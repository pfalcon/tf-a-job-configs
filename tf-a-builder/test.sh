#!/bin/bash

set -e

ls -l ${WORKSPACE}

if [ -n ${QA_SERVER_VERSION} ]; then
    if [ -n ${GERRIT_CHANGE_NUMBER} ] && [ -n ${GERRIT_PATCHSET_NUMBER} ]; then
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
    if [ -n ${TESTJOB_ID} ]; then
        echo "TEST JOB URL: ${QA_SERVER}/testjob/${TESTJOB_ID} TEST JOB ID: ${TESTJOB_ID}"
    fi
fi
