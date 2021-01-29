#!/bin/bash

set -xe

# Run the given command passed through parameters, if fails, try
# at most more N-times with a pause of M-seconds until success.
resilient_cmd() {
    local cmd="$*"
    local max_wait=10
    local sleep_body=2
    local iter=0

    echo "Waiting for $cmd to complete"
    while true; do
        if ${cmd}; then
            echo "$cmd job finished"
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

        # The below sleep command is intentional: LAVA could be under heavy load so previous job creation can
        # take 'some' time
        sleep 2

        LAVAJOB_ID=$(curl --retry 4 ${QA_SERVER}/api/testjobs/${TESTJOB_ID}/?fields=job_id)

        # check that rest query at least get non-empty value
        if [ -n "${LAVAJOB_ID}" ]; then

            # Get the numeric ID
            LAVAJOB_ID=$(echo ${LAVAJOB_ID} | jq '.job_id')
            LAVAJOB_ID="${LAVAJOB_ID//\"/}"
            if [ -n "${LAVAJOB_ID}" ]; then
                echo "LAVA URL: https://${LAVA_SERVER}/scheduler/job/${LAVAJOB_ID} LAVA JOB ID: ${LAVAJOB_ID}"

                resilient_cmd lavacli identities add --username ${LAVA_USER} --token ${LAVA_TOKEN} --uri "https://${LAVA_SERVER}/RPC2" default
                resilient_cmd lavacli jobs wait ${LAVAJOB_ID}
                resilient_cmd lavacli jobs logs ${LAVAJOB_ID} > "${WORKSPACE}/lava.log"
            else
                echo "LAVA Job ID could not be obtained"
            fi
        else
            echo "LAVA Job ID could not be obtained"
        fi
    fi
fi
