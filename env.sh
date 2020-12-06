#!/bin/bash 

export NETWORK_TYPE="fld.ton.dev"
export MAIN_NET_ID="58FFCA1A178DAFF7"
export DEV_NET_ID="3540FA79BD97390D"
export FLD_NET_ID="101FED41A989FE77"

export MASTER_NODE="fld0"
export NODE_IP_ADDR="$(curl -sS ipv4bot.whatismyipaddress.com)"
export ADNL_PORT="30310"
export NODE_ADDRESS="${NODE_IP_ADDR}:${ADNL_PORT}"

export INSTALL_DEPENDENCIES="yes"
SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
export NET_TON_DEV_SRC_TOP_DIR=$(cd "${SCRIPT_DIR}/../" && pwd -P)
export TON_GITHUB_REPO="https://github.com/FreeTON-Network/FreeTON-Node.git"
export TON_STABLE_GITHUB_COMMIT_ID="cdfd7ce654bf6afe4e8de962c7f68abe1011b8a0"
export TON_SRC_DIR="${NET_TON_DEV_SRC_TOP_DIR}/ton"
export TON_BUILD_DIR="${TON_SRC_DIR}/build"
export TONOS_CLI_SRC_DIR="${NET_TON_DEV_SRC_TOP_DIR}/tonos-cli"
export UTILS_DIR="${TON_BUILD_DIR}/utils"

#WRK_DIR=/dev/shm
WRK_DIR=/var

export TON_WORK_DIR="$WRK_DIR/ton-work"
export TON_LOG_DIR="$WRK_DIR/ton-work"

export KEYS_DIR="$HOME/ton-keys"
export ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"

export CONFIGS_DIR="${NET_TON_DEV_SRC_TOP_DIR}/configs"
export HOSTNAME=$(hostname -s)
export VALIDATOR_NAME="$HOSTNAME"
export PATH="${UTILS_DIR}:$PATH"
export LITESERVER_IP="127.0.0.1"
export LITESERVER_PORT="3031"
export VAL_ENGINE_CONSOLE_IP="127.0.0.1"
export VAL_ENGINE_CONSOLE_PORT="3030"
export ENGINE_ADDITIONAL_PARAMS=""

export SafeSCs_DIR=$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/safemultisig
export SetSCs_DIR=$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/safemultisig
export DSCs_DIR=$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/depool
export CRYPTO_DIR=$TON_SRC_DIR/crypto
export FSCs_DIR=$CRYPTO_DIR/smartcont
export FIFT_LIB=$CRYPTO_DIR/fift/lib

export SetC_Wallet_ABI="$SCRIPT_DIR/../ton-labs-contracts/solidity/setcodemultisig/SetcodeMultisigWallet.abi.json"
export SafeC_Wallet_ABI="$SCRIPT_DIR/../ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.abi.json"

export CALL_LC="$HOME/bin/lite-client -p ${KEYS_DIR}/liteserver.pub -a ${LITESERVER_IP}:${LITESERVER_PORT} -t 5"
export CALL_VC="$HOME/bin/validator-engine-console -k ${KEYS_DIR}/client -p ${KEYS_DIR}/server.pub -a ${VAL_ENGINE_CONSOLE_IP}:${VAL_ENGINE_CONSOLE_PORT} -t 5"
export CALL_VE="$HOME/bin/validator-engine"
export CALL_TL="$HOME/bin/tvm_linker"
export CALL_TC="$HOME/bin/tonos-cli"
export CALL_FIFT="${TON_BUILD_DIR}/crypto/fift -I ${FIFT_LIB}:${FSCs_DIR}"
