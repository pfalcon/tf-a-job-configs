#!/bin/bash

set -xe

if [ -f "${WORKSPACE}/lava-raw.log" ]; then

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
                        git clone ${QA_TOOLS_REPO} -b ${QA_TOOLS_BRANCH:-master} ${WORKSPACE}/qa-tools
                    fi
                    cd ${WORKSPACE}/qa-tools/coverage-tool/coverage-reporting
                    ./branch_coverage.sh \
                                --config ${WORKSPACE}/config_file.json \
                                --workspace ${WORKSPACE}/trusted-firmware-a \
                                --outdir ${WORKSPACE}/trace_report
                    find ${WORKSPACE}/trace_report
                fi

fi
