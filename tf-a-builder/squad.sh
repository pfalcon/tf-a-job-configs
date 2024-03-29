#!/bin/bash

set -xe

# Wait for the LAVA job to finished
# By default, timeout at 5400 secs (1.5 hours) and monitor every 60 seconds
wait_lava_job() {
    set +x
    local id=$1
    local timeout="${2:-5400}"
    local interval="${3:-60}"

    (( t = timeout ))

    while ((t > 0)); do
        sleep $interval
        resilient_cmd lavacli jobs show $id | tee "${WORKSPACE}/lava-progress.show" | grep 'state *:'
        set +x
        if grep 'state.*: Finished' "${WORKSPACE}/lava-progress.show"; then
            set -x
            cat "${WORKSPACE}/lava-progress.show"
            # finished
            return 0
        fi
        ((t -= interval))
    done
    set -x
    cat "${WORKSPACE}/lava-progress.show"
    # timeout
    return 1
}

# Run the given command passed through parameters, if fails, try
# at most more N-times with a pause of M-seconds until success.
resilient_cmd() {
    set +x
    local cmd="$*"
    local max_wait=10
    local sleep_body=2
    local iter=0

    while true; do
        if ${cmd}; then
            break
        fi

        sleep ${sleep_body}

        iter=$(( iter + 1 ))
        if [ ${iter} -ge ${max_wait} ]; then
            set -x
            return 1
        fi
    done
    set -x
    return 0
}

ls -l ${WORKSPACE}

if [ -n "${QA_SERVER_VERSION}" ]; then
    if [ -n "${GERRIT_CHANGE_NUMBER}" ] && [ -n "${GERRIT_PATCHSET_NUMBER}" ]; then
        curl \
            --fail \
            --retry 4 \
            -X POST \
            --header "Auth-Token: ${QA_REPORTS_TOKEN}" \
            ${QA_SERVER}/api/createbuild/${QA_SERVER_TEAM}/${QA_SERVER_PROJECT}/${QA_SERVER_VERSION}
    fi

    TESTJOB_ID=$(curl \
        --fail \
        --retry 4 \
        -X POST \
        --header "Auth-Token: ${QA_REPORTS_TOKEN}" \
        --form backend=${LAVA_SERVER} \
        --form definition=@artefacts-lava/job.yaml \
        ${QA_SERVER}/api/submitjob/${QA_SERVER_TEAM}/${QA_SERVER_PROJECT}/${QA_SERVER_VERSION}/${DEVICE_TYPE})

    # SQUAD will send 400, curl error code 22, on bad test definition
    if [ "$?" = "22" ]; then
        echo "Bad test definition!!"
        exit 1
    fi

    if [ -n "${TESTJOB_ID}" ]; then
        echo "TEST JOB URL: ${QA_SERVER}/testjob/${TESTJOB_ID} TEST JOB ID: ${TESTJOB_ID}"


        # The below loop with a sleep is intentional: LAVA could be under heavy load so previous job creation can
        # take 'some' time to get the right numeric LAVA JOB ID
        renumber='^[0-9]+$'
        LAVAJOB_ID="null"
        iter=0
        max_tries=120 # run retries for an hour
        while ! [[ $LAVAJOB_ID =~ $renumber ]]; do
            if [ $iter -eq $max_tries ] ; then
                LAVAJOB_ID=''
                break
            fi
            sleep 30
            LAVAJOB_ID=$(curl --fail --retry 4 ${QA_SERVER}/api/testjobs/${TESTJOB_ID}/?fields=job_id)

            # Get the job_id value (whatever it is)
            LAVAJOB_ID=$(echo ${LAVAJOB_ID} | jq '.job_id')
            LAVAJOB_ID="${LAVAJOB_ID//\"/}"

            iter=$(( iter + 1 ))
        done

        # check that rest query at least get non-empty value
        if [ -n "${LAVAJOB_ID}" ]; then

            echo "LAVA URL: https://${LAVA_SERVER}/scheduler/job/${LAVAJOB_ID} LAVA JOB ID: ${LAVAJOB_ID}"

            resilient_cmd lavacli identities add --username ${LAVA_USER} --token ${LAVA_TOKEN} --uri "https://${LAVA_SERVER}/RPC2" default

            # if timeout on waiting for LAVA to complete, create an 'artificial' lava.log indicating
            # job ID and timeout seconds
            if ! wait_lava_job ${LAVAJOB_ID}; then
                echo "Stopped monitoring LAVA JOB ${LAVAJOB_ID}, likely stuck or timeout too short?" | tee "${WORKSPACE}/lava.log"
                exit 1
            else
                # Retrieve the test job plain log which is a yaml format file from LAVA
                resilient_cmd lavacli jobs logs --raw ${LAVAJOB_ID} > "${WORKSPACE}/lava-raw.log"

                # Split the UART messages to the corresponding log files
                ${WORKSPACE}/tf-a-job-configs/tf-a-builder/log-splitter.py "${WORKSPACE}/lava-raw.log"

                # Take possible code coverage trace data from the LAVA log
                ${WORKSPACE}/tf-a-job-configs/tf-a-builder/feedback-trace-splitter.sh \
                            ${WORKSPACE}/trusted-firmware-a \
                            ${WORKSPACE} \
                            ${WORKSPACE}/artefacts-lava/ \
                            ${TF_GERRIT_REFSPEC}

                # Generate Code Coverate Report in case there are traces available
                if find covtrace-*.log; then
                    if [ ! -d "${WORKSPACE}/qa-tools" ]; then
                        git clone ${QA_TOOLS_REPO} ${WORKSPACE}/qa-tools
                    fi
                    cd ${WORKSPACE}/qa-tools/coverage-tool/coverage-reporting
                    ./branch_coverage.sh \
                                --config ${WORKSPACE}/config_file.json \
                                --workspace ${WORKSPACE}/trusted-firmware-a \
                                --outdir ${WORKSPACE}/trace_report
                    find ${WORKSPACE}/trace_report
                fi

                # Fetch and store LAVA job result (1 failure, 0 success)
                resilient_cmd lavacli results ${LAVAJOB_ID} | tee "${WORKSPACE}/lava.results"
                if grep -q '\[fail\]' "${WORKSPACE}/lava.results"; then
                    exit 1
                else
                    exit 0
                fi
            fi
        else
            echo "LAVA Job ID could not be obtained"
	    exit 1
        fi
    fi
fi
