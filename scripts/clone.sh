#!/usr/bin/env bash
#
# Copyright (c) 2021 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Clones and checkout TF-A related repositories in case these are not present
# under SHARE_FOLDER, otherwise copy the share repositories into current folder
# (workspace)

# The way it works is simple: the top level job sets the SHARE_FOLDER
# parameter based on its name and number on top of the share
# volume (/srv/shared/<job name>/<job number>) then it calls the clone
# script (clone.sh), which in turn it fetches the repositories mentioned
# above. Jobs triggered on behalf of the latter, share the same
# SHARE_FOLDER value, and these in turn also call the clone script, but
# in this case, the script detects that the folder is already populated so
# its role is to simply copy the repositories into the job's
# workspace. As seen, all jobs work with repositories on their own
# workspace, which are just copies of the share folder, so there is no
# change of a race condition, i.e every job works with its own copy. The
# worst case scenario is where the down-level job, tf-a-builder, uses its
# default SHARE_FOLDER value, in this case, it would simply clone its
# own repositories without reusing any file however the current approach
# prevents the latter unless the job is triggered manually from the
# builder job itself.

set -e

# WORKAROUND START
# Install last-minute dependencies. This should not be done like that,
# instead all dependencies should go into the build docker image. But
# to unbreak urgent regressions, some packages may be installed here
# until they're moved to the docker image.
sudo apt update
sudo apt-get install -y python3-venv
# WORKAROUND END

# Global defaults
REFSPEC_MASTER="refs/heads/master"
GIT_REPO="https://git.trustedfirmware.org"
GERRIT_HOST="https://review.trustedfirmware.org"
GIT_CLONE_PARAMS=""

# Defaults Projects
TF_GERRIT_PROJECT="${GERRIT_HOST}/${TF_GERRIT_PROJECT:-TF-A/trusted-firmware-a}"
TFTF_GERRIT_PROJECT="${GERRIT_HOST}/${TFTF_GERRIT_PROJECT:-/TF-A/tf-a-tests}"
CI_PROJECT="${CI_PROJECT:-${GIT_REPO}/ci/tf-a-ci-scripts.git}"
JOBS_PROJECT="${JOB_PROJECT:-${GIT_REPO}/ci/tf-a-job-configs.git}"

# Default Reference specs
TF_GERRIT_REFSPEC="${TF_GERRIT_REFSPEC:-${REFSPEC_MASTER}}"
TFTF_GERRIT_REFSPEC="${TFTF_GERRIT_REFSPEC:-${REFSPEC_MASTER}}"
CI_REFSPEC="${CI_REFSPEC:-${REFSPEC_MASTER}}"
JOBS_REFSPEC="${JOBS_REFSPEC:-${REFSPEC_MASTER}}"

# Array containing "<repo url>;"<repo name>;<refspec>" elements
repos=(
    "${CI_PROJECT};tf-a-ci-scripts;${CI_REFSPEC}"
    "${JOBS_PROJECT};tf-a-job-configs;${JOBS_REFSPEC}"
    "${TF_GERRIT_PROJECT};trusted-firmware-a;${TF_GERRIT_REFSPEC}"
    "${TFTF_GERRIT_PROJECT};tf-a-tests;${TFTF_GERRIT_REFSPEC}"
)

# Take into consideration non-CI runs where SHARE_FOLDER variable
# may not be present
if [ -z "${SHARE_FOLDER}" ]; then
    # Default Jenkins values
    SHARE_VOLUME="${SHARE_VOLUME:-$PWD}"
    JOB_NAME="${JOB_NAME:-local}"
    BUILD_NUMBER="${BUILD_NUMBER:-0}"
    SHARE_FOLDER=${SHARE_VOLUME}/${JOB_NAME}/${BUILD_NUMBER}
fi

# clone git repos
for repo in ${repos[@]}; do

    # parse the repo elements
    REPO_URL="$(echo "${repo}" | awk -F ';' '{print $1}')"
    REPO_NAME="$(echo "${repo}" | awk -F ';' '{print $2}')"
    REPO_REFSPEC="$(echo "${repo}" | awk -F ';' '{print $3}')"

    # clone and checkout in case it does not exit
    if [ ! -d ${SHARE_FOLDER}/${REPO_NAME} ]; then
        git clone ${GIT_CLONE_PARAMS} ${REPO_URL} ${SHARE_FOLDER}/${REPO_NAME}

        # fetch and checkout the corresponding refspec
        cd ${SHARE_FOLDER}/${REPO_NAME}
        git fetch ${REPO_URL} ${REPO_REFSPEC}
        git checkout FETCH_HEAD
        git log -1
        cd $OLDPWD

    else
        # otherwise just show the head's log
        cd ${SHARE_FOLDER}/${REPO_NAME}
        git log -1
        cd $OLDPWD
    fi

    # copy repository into pwd dir (workspace in CI), so each job would work
    # on its own workspace
    cp -a -f ${SHARE_FOLDER}/${REPO_NAME} ${PWD}/${REPO_NAME}

done
