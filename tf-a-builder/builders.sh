#!/bin/bash

sudo apt update -q=2
sudo apt install -q=2 --yes --no-install-recommends build-essential device-tree-compiler git libssl-dev

# FIXME workaround clone_repos.sh script when using gerrit
unset GERRIT_PROJECT
unset GERRIT_BRANCH
unset GERRIT_REFSPEC

set -ex

if [ -z "${WORKSPACE}" ]; then
  ## Local build
  export WORKSPACE=${PWD}
fi

# Toolchain from Arm Developer page: https://developer.arm.com/open-source/gnu-toolchain/gnu-a/downloads
TC_URL="https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/8.3-2019.03/binrel"
# Toolchain from Linaro Releases: https://releases.linaro.org/components/toolchain/binaries
#TC_URL="https://releases.linaro.org/components/toolchain/binaries/6.2-2016.11/aarch64-linux-gnu/gcc-linaro-6.2.1-2016.11-x86_64_aarch64-linux-gnu.tar.xz"
#TC_URL="https://releases.linaro.org/components/toolchain/binaries/6.2-2016.11/arm-linux-gnueabihf/gcc-linaro-6.2.1-2016.11-x86_64_arm-linux-gnueabihf.tar.xz"

# AArch64 little-endian (aarch64-linux-gnu) compiler
cd ${WORKSPACE}
curl -sLSO -C - ${TC_URL}/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz
tar -Jxf gcc-arm-*-x86_64-aarch64-linux-gnu.tar.xz
cd ${WORKSPACE}/gcc-arm-*-x86_64-aarch64-linux-gnu/bin
export PATH=${PWD}:${PATH}
aarch64-linux-gnu-gcc --version

# AArch32 bare-metal (arm-eabi) compiler
cd ${WORKSPACE}
curl -sLSO -C - ${TC_URL}/gcc-arm-8.3-2019.03-x86_64-arm-eabi.tar.xz
tar -Jxf gcc-arm-*-x86_64-arm-eabi.tar.xz
cd ${WORKSPACE}/gcc-arm-*-x86_64-arm-eabi/bin
export PATH=${PWD}:${PATH}
arm-eabi-gcc --version

# Additional binaries required (rootfs, etc...)
mkdir -p \
  ${WORKSPACE}/nfs/downloads/linaro/18.04 \
  ${WORKSPACE}/nfs/downloads/mbedtls
cd ${WORKSPACE}/nfs/downloads/linaro/18.04
#curl -sLSO -C - https://releases.linaro.org/openembedded/juno-lsk/15.09/lt-vexpress64-openembedded_minimal-armv8-gcc-4.9_20150912-729.img.gz
#curl -sLSO -C - https://releases.linaro.org/openembedded/aarch64/17.01/linaro-image-minimal-genericarmv8-20170127-888.rootfs.tar.gz
wget -q -c -m -A .zip -np -nd https://releases.linaro.org/members/arm/platforms/19.06/
for file in $(ls *.zip); do
  unzip -q ${file} -d $(basename ${file} .zip)
done
cd ${WORKSPACE}/nfs/downloads/mbedtls
curl -sLSO -C - https://tls.mbed.org/download/start/mbedtls-2.16.0-apache.tgz
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
