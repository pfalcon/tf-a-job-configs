#!/bin/bash

set -ex

sudo apt update -q=2
sudo apt install -q=2 --yes --no-install-recommends build-essential device-tree-compiler git libssl-dev

# FIXME workaround clone_repos.sh script when using gerrit
unset GERRIT_PROJECT
unset GERRIT_BRANCH
unset GERRIT_REFSPEC

if [ -z "${WORKSPACE}" ]; then
  ## Local build
  export WORKSPACE=${PWD}
fi

# Toolchain from Arm Developer page: https://developer.arm.com/open-source/gnu-toolchain/gnu-a/downloads
TC_VERSION="9.2-2019.12"
TC_URL="https://developer.arm.com/-/media/Files/downloads/gnu-a/${TC_VERSION}/binrel"
TC_AARCH64="gcc-arm-${TC_VERSION}-x86_64-aarch64-none-elf.tar.xz"
TC_ARM="gcc-arm-${TC_VERSION}-x86_64-arm-none-eabi.tar.xz"

# install toolchains
for TC in ${TC_AARCH64} ${TC_ARM}; do
    cd ${WORKSPACE}
    curl -sLSO -C - ${TC_URL}/${TC}
    tar -Jxf ${TC}
    cd ${WORKSPACE}/${TC%.tar.xz}/bin
    export PATH=${PWD}:${PATH}
done

# Basic TC checks
for param in -dumpmachine --version -v; do
    aarch64-none-elf-gcc ${param}
    arm-none-eabi-gcc ${param}
done

# Additional binaries required (rootfs, etc...)
LINARO_VERSION=19.06
mkdir -p \
  ${WORKSPACE}/nfs/downloads/linaro/${LINARO_VERSION} \
  ${WORKSPACE}/nfs/downloads/mbedtls

cd ${WORKSPACE}/nfs/downloads/linaro/${LINARO_VERSION}
wget -q -c -m -A .zip -np -nd https://releases.linaro.org/members/arm/platforms/${LINARO_VERSION}/
for file in *.zip; do
  unzip -q ${file} -d $(basename ${file} .zip)
done

cd ${WORKSPACE}/nfs/downloads/mbedtls
curl -sLSO -k -C - https://tls.mbed.org/download/start/mbedtls-2.16.0-apache.tgz
cp -a mbedtls-2.16.0-apache.tgz mbedtls-2.16.0.tar.gz

cd ${WORKSPACE}

# Path to root of CI repository
ci_root="${WORKSPACE}/tf-a-ci-scripts"

export nfs_volume="${WORKSPACE}/nfs"
export tfa_downloads="file://${nfs_volume}/downloads"

# Mandatory workspace
export workspace="${workspace:-${WORKSPACE}/workspace}"

# During feature development, we need incremental build, so don't run
# 'distlcean' on every invocation.
export dont_clean="${dont_clean:-1}"

# During feature development, we typically only build in debug mode.
export bin_mode="${bin_mode:-debug}"

# Local paths to TF and TFTF repositories
export tf_root="${tf_root:-${WORKSPACE}/trusted-firmware-a}"
export tftf_root="${tftf_root:-${WORKSPACE}/tf-a-tests}"

# We'd need to see the terminals during development runs, so no need for
# automation.
export test_run="${test_run:-1}"

# Run this script bash -x, and it gets passed downstream for debugging
if echo "$-" | grep -q "x"; then
  bash_opts="-x"
fi

bash $bash_opts "$ci_root/script/run_local_ci.sh"

cp -a $(find ${workspace} -type d -name artefacts) ${WORKSPACE}/
