#!/bin/bash

set -xe

# Wait for the LAVA job to finished
# By default, timeout at 5400 secs (1.5 hours) and monitor every 60 seconds
wait_lava_job() {
    local id=$1
    local timeout="${2:-5400}"
    local interval="${3:-60}"

    (( t = timeout ))

    while ((t > 0)); do
        sleep $interval
        resilient_cmd lavacli jobs show $id | tee "${WORKSPACE}/lava-progress.show"
        if grep 'state.*: Finished' "${WORKSPACE}/lava-progress.show"; then
            echo finished
            return
        fi
        ((t -= interval))
    done
    echo timeout
}

# Run the given command passed through parameters, if fails, try
# at most more N-times with a pause of M-seconds until success.
resilient_cmd() {
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
            return 1
        fi
    done
    return 0
}

ls -l ${WORKSPACE}

if [ -n "${QA_SERVER_VERSION}" ]; then
    if [ -n "${GERRIT_CHANGE_NUMBER}" ] && [ -n "${GERRIT_PATCHSET_NUMBER}" ]; then
        curl \
            --retry 4 \
            -X POST \
            --header "Auth-Token: ${QA_REPORTS_TOKEN}" \
            -d patch_source=${GERRIT_HOST} \
            -d patch_id=${GERRIT_CHANGE_NUMBER},${GERRIT_PATCHSET_NUMBER} \
            ${QA_SERVER}/api/createbuild/${QA_SERVER_TEAM}/${QA_SERVER_PROJECT}/${QA_SERVER_VERSION}
    fi

    TESTJOB_ID=$(curl \
        --retry 4 \
        -X POST \
        --header "Auth-Token: ${QA_REPORTS_TOKEN}" \
        --form backend=${LAVA_SERVER} \
        --form definition=@artefacts/debug/job.yaml \
        ${QA_SERVER}/api/submitjob/${QA_SERVER_TEAM}/${QA_SERVER_PROJECT}/${QA_SERVER_VERSION}/${DEVICE_TYPE})

    if [ -n "${TESTJOB_ID}" ]; then
        echo "TEST JOB URL: ${QA_SERVER}/testjob/${TESTJOB_ID} TEST JOB ID: ${TESTJOB_ID}"


        # The below loop with a sleep is intentional: LAVA could be under heavy load so previous job creation can
        # take 'some' time to get the right numeric LAVA JOB ID
        renumber='^[0-9]+$'
        LAVAJOB_ID="null"
        iter=0
        max_tries=10
        while ! [[ $LAVAJOB_ID =~ $renumber ]]; do
            if [ $iter -eq $max_tries ] ; then
                LAVAJOB_ID=''
                break
            fi
            sleep 2
            LAVAJOB_ID=$(curl --retry 4 ${QA_SERVER}/api/testjobs/${TESTJOB_ID}/?fields=job_id)

            # Get the job_id value (whatever it is)
            LAVAJOB_ID=$(echo ${LAVAJOB_ID} | jq '.job_id')
            LAVAJOB_ID="${LAVAJOB_ID//\"/}"

            iter=$(( iter + 1 ))
        done

        # check that rest query at least get non-empty value
        if [ -n "${LAVAJOB_ID}" ]; then

            echo "LAVA URL: https://${LAVA_SERVER}/scheduler/job/${LAVAJOB_ID} LAVA JOB ID: ${LAVAJOB_ID}"

            resilient_cmd lavacli identities add --username ${LAVA_USER} --token ${LAVA_TOKEN} --uri "https://${LAVA_SERVER}/RPC2" default

	    wait_status="$(wait_lava_job ${LAVAJOB_ID})"

            # if timeout on waiting for LAVA to complete, create an 'artificial' lava.log indicating
            # job ID and timeout seconds
            if [ "${wait_status}" == "timeout" ]; then
                echo "Stopped monitoring LAVA JOB ${LAVAJOB_ID}, likely stuck or timeout too short?" > "${WORKSPACE}/lava.log"
                echo "LAVA JOB RESULT: 1"
            else
                # Retrieve the test job plain log which is a yaml format file from LAVA
                resilient_cmd lavacli jobs logs --raw ${LAVAJOB_ID} > "${WORKSPACE}/lava-raw.log"

                # Split the UART messages to the corresponding log files
                ${WORKSPACE}/tf-a-job-configs/tf-a-builder/log-splitter.py "${WORKSPACE}/lava-raw.log" 

                # Fetch and store LAVA job result (1 failure, 0 success)
                resilient_cmd lavacli jobs show ${LAVAJOB_ID} | tee "${WORKSPACE}/lava.show"
                if grep 'state.*: Finished' "${WORKSPACE}/lava.show"; then
                    if grep 'Health.*: Complete' "${WORKSPACE}/lava.show"; then
                        echo "LAVA JOB RESULT: 0"
                    else
                        echo "LAVA JOB RESULT: 1"
                    fi
                else
                    echo "LAVA JOB RESULT: 1"
                fi
            fi
        else
            echo "LAVA Job ID could not be obtained"
        fi
    fi
fi
