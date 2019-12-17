#!/bin/bash

set -e

[ -z "${DEVICE_TYPE}" ] && exit 0

# disable job submission
#export SKIP_LAVA=1

# Send to LAVA
rm -rf pbl post_build_reports_parameters
git clone https://git.trustedfirmware.org/ci/tf-a-job-configs.git pbl
echo "Device type: ${DEVICE_TYPE}"
python pbl/post-build-lava/post-build-lava.py
