#!/bin/bash 

# (C) Sergey Tyurin  2020-11-11 15:00:00

# Disclaimer
##################################################################################################################
# You running this script/function means you will not blame the author(s)
# if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. 
# Author(s) disclaim all implied warranties including, without limitation, 
# any implied warranties of merchantability or of fitness for a particular purpose. 
# The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.
# In no event shall author(s) be held liable for any damages whatsoever 
# (including, without limitation, damages for loss of business profits, business interruption, 
# loss of business information, or other pecuniary loss) arising out of the use of or inability 
# to use the script or documentation. Neither this script/function, 
# nor any part of it other than those parts that are explicitly copied from others, 
# may be republished without author(s) express written permission. 
# Author(s) retain the right to alter this disclaimer at any time.
##################################################################################################################
 
SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`

echo "cd to $SCRIPT_DIR"
cd $SCRIPT_DIR
. "${SCRIPT_DIR}/env.sh"

[[ ! -d $HOME/bin ]] && mkdir -p $HOME/bin

if [ "${INSTALL_DEPENDENCIES}" = "yes" ]; then
    echo "INFO: install dependencies..."
    sudo dnf -y update && sudo dnf upgrade && sudo dnf clean all
    sudo dnf -y group list ids 
    sudo dnf -y group install "Development Tools"
    sudo dnf -y config-manager --set-enabled powertools
    sudo dnf -y install cargo
    sudo dnf -y install curl jq wget bc vim logrotate
    sudo dnf -y install gperf
    sudo dnf -y install snappy snappy-devel
    sudo dnf -y install zlib zlib-devel
    sudo dnf -y install bzip2 bzip2-devel
    sudo dnf -y install lz4-devel
    sudo dnf -y install libmicrohttpd-devel
    sudo dnf -y install readline-devel openssl-devel zlib-devel
    sudo dnf -y install ninja-build
#------------------------------------------------------
    echo "INFO: Install gflags"
    if [[ ! -d "/usr/local/include/gflags" ]];then
    rm -rf ${SCRIPT_DIR}/src
    mkdir -p ${SCRIPT_DIR}/src && cd ${SCRIPT_DIR}/src
    git clone https://github.com/gflags/gflags.git
    cd gflags
    git checkout v2.0
    ./configure && make && sudo make install
    rm -rf ${SCRIPT_DIR}/src
    fi
#-------------------------------------------------------
    echo "INFO: Install epel"
    if [[ -z `dnf info epel-release | grep "Release"|awk -F ":" '{print $2}'` ]];then
    rm -rf ${SCRIPT_DIR}/src
    mkdir -p ${SCRIPT_DIR}/src && cd ${SCRIPT_DIR}/src
    wget https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/e/epel-release-8-8.el8.noarch.rpm
    sudo rpm -Uvh epel-release*rpm
    sudo dnf -y install ccache
    rm -rf ${SCRIPT_DIR}/src
    fi
#-------------------------------------------------------
    sudo dnf -y install cmake

    cd ${SCRIPT_DIR}


    curl https://sh.rustup.rs -sSf | sh -s -- -y
    #shellcheck source=$HOME/.cargo/env
    . "$HOME/.cargo/env"
    rustup update
    echo "INFO: install dependencies... DONE"
fi
#######################################################################################################
[[ ! -z ${TON_SRC_DIR} ]] && rm -rf "${TON_SRC_DIR}"

echo "INFO: clone ${TON_GITHUB_REPO} (${TON_STABLE_GITHUB_COMMIT_ID})..."
git clone --recursive "${TON_GITHUB_REPO}" "${TON_SRC_DIR}"
cd "${TON_SRC_DIR}" && git checkout "${TON_STABLE_GITHUB_COMMIT_ID}"
echo "INFO: clone ${TON_GITHUB_REPO} (${TON_STABLE_GITHUB_COMMIT_ID})... DONE"

#=====================================================
echo "INFO: build a node..."
mkdir -p "${TON_BUILD_DIR}"
cd "${TON_BUILD_DIR}"
#cmake -DCMAKE_BUILD_TYPE=Release ..
#cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
#cmake --build .
#cmake .. -G "Ninja" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPORTABLE=ON
cmake .. -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DPORTABLE=ON
ninja
echo "INFO: build a node... DONE"

#=====================================================
echo "INFO: build utils (convert_address)..."
cd "${NET_TON_DEV_SRC_TOP_DIR}/utils/convert_address"
cargo update
cargo build --release
cp "${NET_TON_DEV_SRC_TOP_DIR}/utils/convert_address/target/release/convert_address" "${UTILS_DIR}/"
echo "INFO: build utils (convert_address)... DONE"

#=====================================================
echo "INFO: build utils (tonos-cli)..."
rm -rf "${TONOS_CLI_SRC_DIR}"
git clone https://github.com/tonlabs/tonos-cli.git "${TONOS_CLI_SRC_DIR}"
cd "${TONOS_CLI_SRC_DIR}"
cargo update
cargo build --release
cp "${TONOS_CLI_SRC_DIR}/target/release/tonos-cli" "${UTILS_DIR}/"
echo "INFO: build utils (tonos-cli)... DONE"

#=====================================================
rm -rf "${NET_TON_DEV_SRC_TOP_DIR}/ton-labs-contracts"
git clone https://github.com/tonlabs/ton-labs-contracts.git "${NET_TON_DEV_SRC_TOP_DIR}/ton-labs-contracts"
rm -f "${CONFIGS_DIR}/SafeMultisigWallet.tvc"
rm -f "${CONFIGS_DIR}/SafeMultisigWallet.abi.json"
cp "${NET_TON_DEV_SRC_TOP_DIR}/ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.tvc" "${CONFIGS_DIR}"
cp "${NET_TON_DEV_SRC_TOP_DIR}/ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.abi.json" "${CONFIGS_DIR}"

cp -f $TON_BUILD_DIR/lite-client/lite-client $HOME/bin
cp -f $TON_BUILD_DIR/utils/tonos-cli $HOME/bin
cp -f $TON_BUILD_DIR/validator-engine/validator-engine $HOME/bin
cp -f $TON_BUILD_DIR/validator-engine-console/validator-engine-console $HOME/bin

#=========================================================
# build TVM-linker
echo "INFO: build TVM-linker ..."
cd $HOME
rm -rf $HOME/TVM-linker
git clone https://github.com/tonlabs/TVM-linker.git
cd $HOME/TVM-linker/tvm_linker/
cargo build --release
cp -f $HOME/TVM-linker/tvm_linker/target/release/tvm_linker $HOME/bin/
echo "INFO: build TVM-linker DONE."



