#!/bin/bash

set -ex

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

# FIXME workaround clone_repos.sh script when using gerrit
unset GERRIT_PROJECT
unset GERRIT_BRANCH
unset GERRIT_REFSPEC

if [ -z "${WORKSPACE}" ]; then
  ## Local build
  export WORKSPACE=${PWD}
fi

cd ${WORKSPACE}

# Several test descriptions are pending to be included in OpenCI, so for the moment
# blocklist these.
# 1. coverity-tf-misra: https://projects.linaro.org/browse/TFC-10
# 2. fvp-tbb-mbedtls-upcounter,fvp-fwu:fvp-tftf.fwu-aemv8a.invalid_nvcounter-debug: Pending TFC ticket
# 3. Failure at LAVA job https://tf.validation.linaro.org/scheduler/job/142122
#    TFC ticket https://projects.linaro.org/browse/TFC-70
# 4. Failure at LAVA job https://tf.validation.linaro.org/scheduler/job/142101
#    TFC ticket https://projects.linaro.org/browse/TFC-70

blocklist="blocklist.txt"
cat << EOF > "${blocklist}"
coverity-tf-misra
fvp-tbb-mbedtls-upcounter,fvp-fwu,nil,nil,nil:fvp-tftf.fwu-aemv8a.invalid_nvcounter-debug
fvp-mb-256-optee-romlib,nil,nil,nil,nil:fvp-optee.mb-linux.rootfs+ftpm-romlib-fip.ftpm-aemv8a
fvp-linux-as-bl33,nil,nil,nil,nil:fvp-linux.bl33-dtb-aemv8a.linux.bl33-debug
EOF

if echo "${TEST_DESC}" | grep -F -f ${blocklist} - ; then
    echo ${TEST_DESC} is blocklisted
    exit 0
fi

mkdir -p ${WORKSPACE}/nfs/downloads/mbedtls
cd ${WORKSPACE}/nfs/downloads/mbedtls
curl --connect-timeout 5 --retry 5 --retry-delay 1 -sLSO -k -C - ${MBEDTLS_URL}
export mbedtls_archive=${WORKSPACE}/nfs/downloads/mbedtls/$(ls -1 mbedtls-*.tar.gz)

# Path to root of CI repository
ci_root="${WORKSPACE}/tf-a-ci-scripts"

export tf_downloads="https://downloads.trustedfirmware.org"
export tfa_downloads="${tf_downloads}/tf-a"

# Fetch required firmware/binaries and place it at proper location
export nfs_volume="${WORKSPACE}/nfs"
project_filer="${nfs_volume}/projectscratch/ssg/trusted-fw"
for d in spm spm-10-23-2020; do
    mkdir -p ${project_filer}/ci-files/$d
    cd ${project_filer}/ci-files/$d
    resilient_cmd curl --connect-timeout 5 --retry 5 --retry-delay 1 -fsSLo \
	 download.json \
	 ${tfa_downloads}/$d/?export=json
    for f in $(cat download.json | jq .files[].Url | sed s/\"//g); do
        resilient_cmd curl --connect-timeout 5 --retry 5 --retry-delay 1 -fsSLo  $(basename $f) $f
    done
done

# FIXME: place below code in above loop
# fetch https://downloads.trustedfirmware.org/tf-a/dummy-crypto-lib.tar
cd ${project_filer}
resilient_cmd curl --connect-timeout 5 --retry 5 --retry-delay 1 -fsSLo \
     dummy-crypto-lib.tar \
     https://downloads.trustedfirmware.org/tf-a/dummy-crypto-lib.tar
tar xf dummy-crypto-lib.tar

# fetch Juno rootfs, required by fvp
linaro_2001_release="/nfs/downloads/linaro/20.01"
cd ${linaro_2001_release}
resilient_cmd curl --connect-timeout 5 --retry 5 --retry-delay 1 -fsSLo \
     lt-vexpress64-openembedded_minimal-armv8-gcc-5.2_20170127-761.img.gz \
     https://releases.linaro.org/openembedded/juno-lsk/latest/lt-vexpress64-openembedded_minimal-armv8-gcc-5.2_20170127-761.img.gz

# export trace code coverage variable
export coverage_trace_plugin="${tf_downloads}/coverage-plugin/qa-tools/coverage-tool/coverage-plugin/coverage_trace.so"

# FIXME: create temporal /arm softlinks.
# Reason behind is described at
#        https://git.trustedfirmware.org/ci/dockerfiles.git/commit/?id=4e2c2c94e434bc8a9b25f5da7c6018a43db8cb2f

# /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-9-2020-q2-update/bin/arm-none-eabi-gcc
mkdir -p /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-9-2020-q2-update
ln -s \
   ${TOOLS_DIR}/bin \
   /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-9-2020-q2-update/bin

# /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-10-2020-q4-major/bin/arm-none-eabi-gcc
mkdir -p /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-10-2020-q4-major
ln -s \
   ${TOOLS_DIR}/gnu-rm/bin \
   /arm/pdsw/downloads/scp-models/tools/gcc-arm-none-eabi-10-2020-q4-major/bin

# /arm/projectscratch/ssg/trusted-fw/dummy-crypto-lib
mkdir -p /arm/projectscratch/ssg/trusted-fw
ln -s \
   ${project_filer}/dummy-crypto-lib \
   /arm/projectscratch/ssg/trusted-fw/dummy-crypto-lib


# /arm/pdsw/tools/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
mkdir -p /arm/pdsw/tools/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu
ln -s ${TOOLS_DIR}/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu/bin \
   /arm/pdsw/tools/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu/bin

# CC=/arm/warehouse/Distributions/FA/ARMCompiler/6.8/25/standalone-linux-x86_64-rel/bin/armclang
mkdir -p /arm/warehouse/Distributions/FA/ARMCompiler/6.8/25/standalone-linux-x86_64-rel
ln -s ${TOOLS_DIR}/armclang-6.8/bin \
      /arm/warehouse/Distributions/FA/ARMCompiler/6.8/25/standalone-linux-x86_64-rel/bin

# Mandatory workspace
export workspace="${workspace:-${WORKSPACE}/workspace}"

# During feature development, we need incremental build, so don't run
# 'distlcean' on every invocation.
export dont_clean="${dont_clean:-1}"

# Local paths to TF and TFTF repositories
export tf_root="${tf_root:-${WORKSPACE}/trusted-firmware-a}"
export tftf_root="${tftf_root:-${WORKSPACE}/tf-a-tests}"

# We'd need to see the terminals during development runs, so no need for
# automation.
export test_run="${test_run:-1}"

# By default, do not execute any run
export skip_runs="${skip_runs:-1}"

# set linaro platform release folder
export linaro_2001_release="file://${linaro_2001_release}"

export docker_registry="${DOCKER_REGISTRY}"
export armlmd_license_file="${ARMLMD_LICENSE_FILE}"
export juno_rootfs_url="${JUNO_ROOTFS_URL}"

# Parse TEST_DESC and export test_group & tf_config and & run_config
test_desc="${test_desc:-$TEST_DESC}"
test_desc="${test_desc:?}"

# Strip test suffix
test_desc="${test_desc%%.test}"

lhs="$(echo "$test_desc" | awk -F: '{print $1}')"
rhs="$(echo "$test_desc" | awk -F: '{print $2}')"

test_group="$(echo "$lhs" | awk -F% '{print $2}')"
build_config="$(echo "$lhs" | awk -F% '{print $3}')"
run_config="${rhs%.test}"
test_config="$(cat $WORKSPACE/TEST_DESC)"

export BUILD_CONFIG="$build_config"
export RUN_CONFIG="$run_config"
export TEST_CONFIG="$test_config"
export TEST_GROUP="$test_group"

# Run this script bash -x, and it gets passed downstream for debugging
if echo "$-" | grep -q "x"; then
  bash_opts="-x"
fi

mkdir -p "${workspace}"
bash $bash_opts "$ci_root/script/build_package.sh"

# compress rootfs.bin file
for a in $(find ${workspace} -type d -name artefacts); do
    for r in $(find $a -type f -name rootfs.bin -or -name busybox.bin); do
	d=$(dirname $r); b=$(basename $r); cd "$d" && gzip "$b"
    done
done

cp -a $(find ${workspace} -type d -name artefacts) ${WORKSPACE}/
