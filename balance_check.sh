#!/bin/bash -eE

set -o pipefail
# set -u
# set -x
SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

NormText="\e[0m"
RedBlink="\e[5;101m"
GreeBack="\e[42m"
BlueBack="\e[44m"
RedBack="\e[41m"
YellowBack="\e[43m"
BoldText="\e[1m"

function not_found(){
    if [[ -z $ACC_STATUS ]];then
    echo
    echo "Account not found!"
    echo
    fi
}
OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    CALL_BC="bc"
else
    CALL_BC="bc -l"
fi
trap not_found EXIT
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

echo

CURR_NET_ID=`$CALL_LC -rc "time" -rc "quit" 2>&1 |grep 'zerostate id'|awk -F '': '{print $3}'|cut -c 1-16`
if [[ "$CURR_NET_ID" == "$MAIN_NET_ID" ]];then
    CurrNetInfo="${BoldText}${BlueBack}You are in MAIN network${NormText}"
elif [[ "$CURR_NET_ID" == "$DEV_NET_ID" ]];then
    CurrNetInfo="${BoldText}${RedBack}You are in DEVNET network${NormText}"
elif [[ "$CURR_NET_ID" == "$FLD_NET_ID" ]];then
    CurrNetInfo="${BoldText}${YellowBack}You are in FLD network${NormText}"
else
    CurrNetInfo="${BoldText}${RedBlink}You are in UNKNOWN network${NormText} or you need to update 'env.sh'"
fi
echo -e "$CurrNetInfo"
#=================================================
echo
echo "Time Now: $(date  +'%Y-%m-%d %H:%M:%S')"

ACCOUNT=$1
if [[ -z $ACCOUNT ]];then
    MY_ACCOUNT=`cat "${KEYS_DIR}/${HOSTNAME}.addr"`
    if [[ -z $MY_ACCOUNT ]];then
        echo " Can't find ${KEYS_DIR}/${HOSTNAME}.addr"
        exit 1
    else
        ACCOUNT=$MY_ACCOUNT
    fi
else
    acc_fmt="$(echo "$ACCOUNT" |  awk -F ':' '{print $2}')"
    [[ -z $acc_fmt ]] && ACCOUNT=`cat "${KEYS_DIR}/${ACCOUNT}.addr"`
fi
echo "Account: $ACCOUNT"

ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${ACCOUNT}" -rc "quit" 2>/dev/null`

ACC_STATUS=`echo "$ACCOUNT_INFO" | grep 'state:'|tr -d ')'|tr -d '('|cut -d ':' -f 2`
echo "Status: $ACC_STATUS"
AMOUNT=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
echo "Has balance : $(echo "scale=3; $((AMOUNT)) / 1000000000" | $CALL_BC) tokens"
LAST_TR_TIME=`echo "$ACCOUNT_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
echo "Last operation time: $LAST_TR_TIME"

# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Current balance: $((AMOUNT/1000000000))" 2>&1 > /dev/null

#=========================================================================
# Get custodians number
val_acc_addr=`echo "${ACCOUNT}" | cut -d ':' -f 2`
LC_OUTPUT="$(Get_SC_current_state "$ACCOUNT")"
result=`echo $LC_OUTPUT | grep "written StateInit of account"`
if [[ -z  $result ]];then
    echo "###-ERROR: Cannot get account state. Can't continue. Sorry."
    exit 1
fi

Custod_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getCustodians -p '{}' --decode-c6 $val_acc_addr | grep '"custodians":'| jq ".custodians|length"|tr -d '"'`
Custod_QTY=$((Custod_QTY))
# Get Required number of confirmations
Confirms_QTY=`$HOME/bin/tvm_linker test -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json -m getParameters -p '{}' --decode-c6 $val_acc_addr | grep "requiredTxnConfirms" | jq '.requiredTxnConfirms'|tr -d '"'`
Confirms_QTY=$((Confirms_QTY))

#=========================================================================
echo "Number of custodians: $Custod_QTY. Required number of confirmations: $Confirms_QTY"
echo "=================================================================================================="
exit 0
