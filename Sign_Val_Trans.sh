#!/bin/bash

# (C) Sergey Tyurin  2020-11-19 15:00:00

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
# You have to have installed :
#   'xxd' - is a part of vim-commons ( [apt/dnf/pkg] install vim[-common] )
#   'jq'
#   'bc' for Linux
#   'dc' for FreeBSD
#   'tvm_linker' compiled binary from https://github.com/tonlabs/TVM-linker.git to $HOME/bin (must be in $PATH)
#   'lite-client'                                               
# ------------------------------------------------------------------------
# Script assumes that: 
#   - all keypairs are in ${KEYS_DIR} folder
#   use: SignVal_Trans.sh [AccName]
#      AccName - filename of separate acc with AccName{n}.keys.json keys files
#      If AccName omitted - will use $HOSTNAME & msig{n}.keys.json
# ------------------------------------------------------------------------

set -o pipefail

if [ "$DEBUG" = "yes" ]; then
    set -x
fi

####################
TIMEDIFF_MAX=100
SLEEP_TIMEOUT=10
SEND_ATTEMPTS=10
###################
function sgn_usage(){
echo
echo " use: SignVal_Trans.sh [AccName]"
echo " AccName - filename of separate acc with AccName{n}.keys.json keys files"
echo " If AccName omitted - will use $HOSTNAME & msig{n}.keys.json"
echo
exit 0
}

echo "######################################## Signing script ########################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

#==================================================
# Acc by name or default 
AccName=$1
if [[ -z $AccName ]];then
    MSIG_ADDR=`cat "${KEYS_DIR}/${HOSTNAME}.addr"`
    KeyFileName="msig"
    if [[ -z $MSIG_ADDR ]];then
        echo " Can't find ${KEYS_DIR}/${HOSTNAME}.addr" && sgn_usage
        exit 1
    fi
else
    MSIG_ADDR=`cat "${KEYS_DIR}/${AccName}.addr"`
    KeyFileName="${AccName}"
    if [[ -z $MSIG_ADDR ]];then
        echo " Can't find ${KEYS_DIR}/${AccName}.addr" && sgn_usage
        exit 1
    fi
fi

#=================================================
# function Get_SC_current_state() { 
#     rm -f ${val_acc_addr}.tvc
#     trap 'echo LC TIMEOUT EXIT' EXIT
#     local LC_OUTPUT=`$CALL_LC -rc "saveaccount ${val_acc_addr}.tvc ${MSIG_ADDR}" -rc "quit" 2>/dev/null | tee ${ELECTIONS_WORK_DIR}/get-acc-state.log`
#     trap - EXIT
#     local result=`echo $LC_OUTPUT | grep "written StateInit of account"`
#     if [[ -z  $result ]];then
#         echo "###-ERROR: Cannot get account state. Can't continue. Sorry."
#         exit 1
#     fi
#     echo "$LC_OUTPUT"
# }
# Get Smart Contract current state by dowloading it & save to file
function Get_SC_current_state() { 
    # Input: acc in form x:xxx...xxx
    # result: file named xxx...xxx.tvc
    # return: Output of lite-client executing
    local w_acc="$1" 
    [[ -z $w_acc ]] && echo "###-ERROR(line $LINENO): func Get_SC_current_state: empty address" && exit 1
    local s_acc=`echo "${w_acc}" | cut -d ':' -f 2`
    rm -f ${s_acc}.tvc
    trap 'echo LC TIMEOUT EXIT' EXIT
    local LC_OUTPUT=`$CALL_LC -rc "saveaccount ${s_acc}.tvc ${w_acc}" -rc "quit" 2>/dev/null`
    trap - EXIT
    local result=`echo $LC_OUTPUT | grep "written StateInit of account"`
    if [[ -z  $result ]];then
        echo "###-ERROR(line $LINENO): Cannot get account state. Can't continue. Sorry."
        exit 1
    fi
    echo "$LC_OUTPUT"
}
#=================================================
# Test binaries
if [[ -z $($HOME/bin/tvm_linker -V | grep "TVM linker") ]];then
    echo "###-ERROR: TVM linker not installed in PATH"
    exit 1
fi

if [[ -z $(xxd -v 2>&1 | grep "Juergen Weigert") ]];then
    echo "###-ERROR: 'xxd' not installed in PATH"
    exit 1
fi

if [[ -z $(jq --help 2>/dev/null |grep -i "Usage"|cut -d ":" -f 1) ]];then
    echo "###-ERROR: 'jq' not installed in PATH"
    exit 1
fi

#=================================================
# Call defines
# CALL_LC="${TON_BUILD_DIR}/lite-client/lite-client -p ${KEYS_DIR}/liteserver.pub -a 127.0.0.1:3031 -t 5"
# CALL_VC="${TON_BUILD_DIR}/validator-engine-console/validator-engine-console -k ${KEYS_DIR}/client -p ${KEYS_DIR}/server.pub -a 127.0.0.1:3030 -t 5"
# CALL_FIFT="${TON_BUILD_DIR}/crypto/fift -I ${TON_SRC_DIR}/crypto/fift/lib:${TON_SRC_DIR}/crypto/smartcont"

#=================================================
# MSIG_ADDR=`cat "${KEYS_DIR}/${VALIDATOR_NAME}.addr"`
# if [[ -z $MSIG_ADDR ]];then
#     echo "###-ERROR: Can't find validator account address!"
#     exit 1
# fi

val_acc_addr=`echo "${MSIG_ADDR}" | cut -d ':' -f 2`
workchain=`echo "${MSIG_ADDR}" | cut -d ':' -f 1`
echo "INFO: MSIG_ADDR = ${MSIG_ADDR} / $val_acc_addr"
echo "WorkChain: $workchain"

ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"
[[ ! -d ${ELECTIONS_WORK_DIR} ]] && mkdir -p ${ELECTIONS_WORK_DIR}
chmod +x ${ELECTIONS_WORK_DIR}

##############################################################################
# Check node sync
trap 'echo VC EXIT' EXIT
VEC_OUTPUT=`$CALL_VC -c "getstats" -c "quit"`
trap - EXIT

CURR_TD_NOW=`echo "${VEC_OUTPUT}" | grep unixtime | awk '{print $2}'`
CHAIN_TD=`echo "${VEC_OUTPUT}" | grep masterchainblocktime | awk '{print $2}'`
TIME_DIFF=$((CURR_TD_NOW - CHAIN_TD))
if [[ $TIME_DIFF -gt $TIMEDIFF_MAX ]];then
    echo "###-ERROR: Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF"
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "###-ERROR: Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF" 2>&1 > /dev/null
    exit 1
fi
echo "INFO: Current TimeDiff: $TIME_DIFF"

##############################################################################
# get elector address
trap 'echo LC TIMEOUT EXIT' EXIT
elector_addr=`$CALL_LC -rc "getconfig 1" -rc "quit" 2>/dev/null | grep -i 'ConfigParam(1)' | awk '{print substr($4,15,64)}'`
trap - EXIT
elector_addr=`echo "-1:"$elector_addr | tee ${ELECTIONS_WORK_DIR}/elector-addr-base64`
echo "INFO: Elector Address: $elector_addr"

##############################################################################
# get elections ID
trap 'echo LC TIMEOUT EXIT' EXIT
election_id=`$CALL_LC -rc "runmethod $elector_addr active_election_id" -rc "quit" 2>/dev/null | grep "result:" | awk '{print $3}'`
trap - EXIT
echo "INFO: Election ID: $election_id"

if [[ ! -z $election_id ]] && [[ ! -f ${ELECTIONS_WORK_DIR}/$election_id ]];then
  touch ${ELECTIONS_WORK_DIR}/$election_id
  echo "Election ID: $election_id" >> ${ELECTIONS_WORK_DIR}/$election_id
  echo "Elector address: $elector_addr" >> ${ELECTIONS_WORK_DIR}/$election_id
fi

##############################################################################
# Get SC current state to file ${ELECTIONS_WORK_DIR}/$val_acc_addr.tvc
echo -n "Get SC state of acc: $MSIG_ADDR ... "    
LC_OUTPUT="$(Get_SC_current_state "$MSIG_ADDR")"
result=`echo $LC_OUTPUT | grep "written StateInit of account"`
if [[ -z  $result ]];then
    echo "###-ERROR: Cannot get account state. Can't continue. Sorry."
    exit 1
fi
echo "Done."

##############################################################################
# Get custodians number
Custod_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getCustodians -p '{}' --decode-c6 $val_acc_addr | grep '"custodians":'| jq ".custodians|length"|tr -d '"'`
Custod_QTY=$((Custod_QTY))
# Get Required number of confirmations
Confirms_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getParameters -p '{}' --decode-c6 $val_acc_addr | grep "requiredTxnConfirms" | jq '.requiredTxnConfirms'|tr -d '"'`
Confirms_QTY=$((Confirms_QTY))
echo "******************************"
echo "INFO: Number of custodians: $Custod_QTY. Required number of confirmations: $Confirms_QTY"

##############################################################################
# Get Transaction ID to sign
Trans_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getTransactions -p '{}' --decode-c6 $val_acc_addr | grep '"transactions":'| jq ".transactions|length"|tr -d '"'`
Trans_QTY=$((Trans_QTY))
if [[ $Trans_QTY -eq 0 ]];then
    echo
    echo "###-ERROR: Trans_QTY=$Trans_QTY. NO transactions to sign. Exit."
    echo
    exit 1
fi
if [[ $Trans_QTY -gt 1 ]];then
    echo
    echo "###-ERROR: Trans_QTY=$Trans_QTY. Multitransaction signing not implemented yet! Exit."
    echo
    exit 1
fi

Trans_ID=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getTransactions -p '{}' --decode-c6 $val_acc_addr | grep '"transactions":'| jq '.transactions[].id'`
echo "INFO: Found $Trans_QTY transaction to sign with ID: $Trans_ID"

signsReceived=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getTransactions -p '{}' --decode-c6 $val_acc_addr | grep '"transactions":'| jq '.transactions[].signsReceived'|tr -d '"'`
signsReceived=$((signsReceived))
echo "signsReceived: $signsReceived"
##############################################################################
# Send signatures one by one with checks 
# Assume that transaction was made and already signed by custodian with pubkey index # 0x0
# other custodians has keys in files 

for i in `seq -s " " 2 "${Custod_QTY}"`
do
    echo "----------------------------------------------------------------------"
    echo "INFO: Make boc for signature No: ${i}"
    Signed_Flag=false
    #======================================================================
    # prepare user signatures
    msig_public=`cat ${KEYS_DIR}/${KeyFileName}${i}.keys.json | jq ".public" | tr -d '"'`
    msig_secret=`cat ${KEYS_DIR}/${KeyFileName}${i}.keys.json | jq ".secret" | tr -d '"'`

    if [[ -z $msig_public ]] || [[ -z $msig_secret ]];then
        echo "###-ERROR: Can't find validator ${i} public and/or secret key!"
        exit 1
    fi
    
    echo "${msig_secret}${msig_public}" > ${KEYS_DIR}/${KeyFileName}${i}.keys.txt
    rm -f ${KEYS_DIR}/${KeyFileName}${i}.keys.bin
    xxd -r -p ${KEYS_DIR}/${KeyFileName}${i}.keys.txt ${KEYS_DIR}/${KeyFileName}${i}.keys.bin

    #======================================================================
    # make boc for lite-client
    TVM_OUTPUT=$($HOME/bin/tvm_linker message $val_acc_addr \
        -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json \
        -m confirmTransaction \
        -p "{\"transactionId\":$Trans_ID}" \
        -w $workchain --setkey ${KEYS_DIR}/${KeyFileName}${i}.keys.bin| tee ${ELECTIONS_WORK_DIR}/TVM_linker-${i}-signing.log)

    if [[ -z $(echo "$TVM_OUTPUT" | grep "boc file created") ]];then
        echo "###-ERROR: TVM linker CANNOT create boc file for ${i} signature!!! Can't continue. Exit."
        echo "$TVM_OUTPUT"
        exit 2
    fi
    mv -f "$(echo "$val_acc_addr"| cut -c 1-8)-msg-body.boc" "${ELECTIONS_WORK_DIR}/vaidator-${i}-msg.boc"
    echo "INFO: Make ${i} boc for lite-client ... DONE"

    ########################################
    Attempts_to_send=$SEND_ATTEMPTS
    while [[ $Attempts_to_send -gt 0 ]]; do
        #======================================================================
        # Send confirmations signature by lite-client
        echo "INFO: Send confirmations signature # ${i} by lite-client ..."

        trap 'echo LC TIMEOUT EXIT' EXIT
        $CALL_LC -rc "sendfile ${ELECTIONS_WORK_DIR}/vaidator-${i}-msg.boc" -rc 'quit' &> ${ELECTIONS_WORK_DIR}/validator-sig-${i}-result.log
        trap - EXIT
        vr_result=`cat ${ELECTIONS_WORK_DIR}/validator-sig-${i}-result.log | grep "external message status is 1"`

        if [[ -z $vr_result ]]; then
            echo "###-ERROR: Send message for confirmation ${i} FAILED!!!"
            exit 3
        fi
        sleep $SLEEP_TIMEOUT
    
        #======================================================================
        # Get SC current state to file ${ELECTIONS_WORK_DIR}/$val_acc_addr.tvc
        echo -n "Get SC state of acc: $MSIG_ADDR ... "    
        LC_OUTPUT="$(Get_SC_current_state "$MSIG_ADDR")"
        result=`echo $LC_OUTPUT | grep "written StateInit of account"`
        if [[ -z  $result ]];then
            echo "###-ERROR: Cannot get account state. Can't continue. Sorry."
            exit 4
        fi
        echo "Done."

        #======================================================================
        # Chech transaction signed and leaved
        Trans_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getTransactions -p '{}' --decode-c6 $val_acc_addr | grep '"transactions":'| jq ".transactions|length"|tr -d '"'`
        Trans_QTY=$((Trans_QTY))
        if [[ $Trans_QTY -eq 0 ]];then
            Attempts_to_send=0
            Signed_Flag=true
            echo "\$\$\$-SUCCESS: Transaction # $Trans_ID signed and send"
            break
        fi

        #======================================================================
        # Check signing success by get num of signatures
       Signed_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getTransactions -p '{}' --decode-c6 $val_acc_addr | grep '"transactions":'| jq '.transactions[].signsReceived'|tr -d '"'`
       Signed_QTY=$((Signed_QTY))
       echo "Signed_QTY: $Signed_QTY | signsReceived: $signsReceived"
        if [[ $signsReceived -ge $Signed_QTY ]];then
            echo "+++-WARNING: Attempt # $((SEND_ATTEMPTS + 1 - Attempts_to_send))/$SEND_ATTEMPTS to send signature # ${i} failed. Will try again.."
            Attempts_to_send=$((Attempts_to_send - 1))
        else
            Attempts_to_send=0
            signsReceived=$Signed_QTY
        fi

    done
    ########################################

    if [[ ! Signed_Flag ]] ;then
        echo "###-ERROR: CANNOT sign transaction $Trans_ID by key # ${i} with pubkey: $msig_public from file: ${KEYS_DIR}/msig${i}.keys.json"
        "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Signing transaction $Trans_ID for election FAILED!!!" 2>&1 > /dev/null
        exit 5
    fi
    echo "INFO: Signing transaction $Trans_ID by custodian ${i} was done SUCCESSFULLY!"
done

# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Transaction $Trans_ID for election confirmed." 2>&1 > /dev/null

echo "INFO: $(basename "$0") FINISHED $(date +%s) / $(date)"

trap - EXIT
exit 0




