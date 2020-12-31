#!/bin/bash -eE
# (C) Sergey Tyurin  2020-12-31 20:00:00

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
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

set -o pipefail
# set -u
# set -x

##############################################################################
# Set Accounts low threshold and topup amounts
DPL_LOW_THRESHOLD=45
DPL_TOPUP_AMOUNT=10

PRX_LOW_THRESHOLD=2
PRX__TOPUP_AMOUNT=3

VAL_LOW_THRESHOLD=60

TIK_LOW_THRESHOLD=3
TIK_TOPUP_AMOUNT=5

##############################################################################
# service variables
TIMEOUT_BEFORE_SIGN=15

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    CALL_BC="bc"
else
    CALL_BC="bc -l"
fi

NormText="\e[0m"
RedBlink="\e[5;101m"
GreeBack="\e[42m"
BlueBack="\e[44m"
RedBack="\e[41m"
YellowBack="\e[43m"
BoldText="\e[1m"

echo
echo "######################## DePool accounts low balance watchdog script ###########################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date  +'%F %T %Z')"
echo

function SendTokens(){
    SRC_NAME=$1
    DST_NAME=$2
    TRANSF_AMOUNT="$3"
    NANO_AMOUNT=`$CALL_TC convert tokens $TRANSF_AMOUNT| grep "[0-9]"`
    BOUNCE="true"

    SRC_ACCOUNT=`cat ${KEYS_DIR}/${SRC_NAME}.addr`
    DST_ACCOUNT=`cat ${KEYS_DIR}/${DST_NAME}.addr`
    SRC_KEY_FILE="${KEYS_DIR}/${1}.keys.json"
    #================================================================
    # Check Keys
    Calc_Addr=$($CALL_TC genaddr ${SafeSCs_DIR}/SafeMultisigWallet.tvc ${SafeC_Wallet_ABI} --setkey $SRC_KEY_FILE --wc "0" | grep "Raw address:" | awk '{print $3}')
    if [[ ! "$SRC_ACCOUNT" == "$Calc_Addr" ]];then
        echo "###-ERROR(line $LINENO): Given account address and calculated address is different. Wrong keys. Can't continue. "
        echo "Given addr: $SRC_ACCOUNT"
        echo "Calc  addr: $Calc_Addr"
        echo 
        exit 1
    fi
    #================================================================
    # 
    ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${SRC_ACCOUNT}" -rc "quit" 2>/dev/null `
    SRC_AMOUNT=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`

    echo "Check DST $DST_NAME account.."
    ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${DST_ACCOUNT}" -rc "quit" 2>/dev/null `
    DST_AMOUNT=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`

    echo "TRANFER FROM ${SRC_NAME} :"
    echo "SRC Account: $SRC_ACCOUNT"
    echo "Has balance : $((SRC_AMOUNT/1000000000)) tokens"
    echo
    echo "TRANFER TO ${DST_NAME} :"
    echo "DST Account: $DST_ACCOUNT"
    echo "Has balance : $((DST_AMOUNT/1000000000)) tokens"
    echo
    echo "Transferring $TRANSF_AMOUNT ($NANO_AMOUNT) from ${SRC_NAME} to ${DST_NAME} ..." 

    $CALL_TC message $SRC_ACCOUNT submitTransaction \
        "{\"dest\":\"${DST_ACCOUNT}\",\"value\":\"${NANO_AMOUNT}\",\"bounce\":$BOUNCE,\"allBalance\":false,\"payload\":\"\"}" \
        --abi ${SafeC_Wallet_ABI} \
        --sign ${KEYS_DIR}/${SRC_NAME}.keys.json \
        --raw \
        --output ${SRC_NAME}-SendTokens-msg.boc

    $CALL_LC -rc "sendfile ${SRC_NAME}-SendTokens-msg.boc" -rc 'quit' &> ${SRC_NAME}-SendTokens-result.log
}

##############################################################################
# show in which network we are
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

##############################################################################
# Get the addresses required for DePool to work 
# be careful: adresses of proxies is renewed by dlt-validaor_depool.sh only
#             dinfo.sh will write new proxies to ton-keys if they absent only
Depool_addr=`cat ${KEYS_DIR}/depool.addr`
Proxy0_addr=`cat ${KEYS_DIR}/proxy0.addr`
Proxy1_addr=`cat ${KEYS_DIR}/proxy1.addr`
Validator_addr=`cat ${KEYS_DIR}/${HOSTNAME}.addr`
Tik_addr=`cat ${KEYS_DIR}/Tik.addr`

##############################################################################
# Get info of addresses
Tik_INFO=`$CALL_LC -rc "getaccount ${Tik_addr}" -t "3" -rc "quit" 2>/dev/null `
Depool_INFO=`$CALL_LC -rc "getaccount ${Depool_addr}" -t "3" -rc "quit" 2>/dev/null `
Proxy0_INFO=`$CALL_LC -rc "getaccount ${Proxy0_addr}" -t "3" -rc "quit" 2>/dev/null `
Proxy1_INFO=`$CALL_LC -rc "getaccount ${Proxy1_addr}" -t "3" -rc "quit" 2>/dev/null `
Validator_INFO=`$CALL_LC -rc "getaccount ${Validator_addr}" -t "3" -rc "quit" 2>/dev/null `

Tik_AMOUNT_nt=`echo "$Tik_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`

Tik_LAST_TR_TIME=`echo "$Tik_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Tik_Status=`echo "$Tik_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Depool_AMOUNT_nt=`echo "$Depool_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Depool_LAST_TR_TIME=`echo "$Depool_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Depool_Status=`echo "$Depool_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Proxy0_AMOUNT_nt=`echo "$Proxy0_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Proxy0_LAST_TR_TIME=`echo "$Proxy0_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Proxy0_Status=`echo "$Proxy0_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Proxy1_AMOUNT_nt=`echo "$Proxy1_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Proxy1_LAST_TR_TIME=`echo "$Proxy1_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Proxy1_Status=`echo "$Proxy1_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Validator_AMOUNT_nt=`echo "$Validator_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Validator_LAST_TR_TIME=`echo "$Validator_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Validator_Status=`echo "$Validator_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

##############################################################################
# check and topup balances if necessary

#=======================
# DePool account
if [[ ! "$Depool_Status" == "account_active" ]];then
    echo "###-ERROR(line $LINENO): Depool account does not deployed"
#    exit 1
else
    if [[ $Depool_AMOUNT_nt -lt $((DPL_LOW_THRESHOLD * 1000000000)) ]];then
        echo '$$$-WARN: We need to REPLANISH DePool account! Let`s do it!'
        $CALL_TC depool --addr $(cat ${KEYS_DIR}/depool.addr) replenish \
            --wallet $(cat ${KEYS_DIR}/${VALIDATOR_NAME}.addr) \
            --sign ${KEYS_DIR}/${VALIDATOR_NAME}.keys.json \
            --value $DPL_TOPUP_AMOUNT
        sleep $TIMEOUT_BEFORE_SIGN
        ${SCRIPT_DIR}/Sign_Val_Trans.sh
    fi
    echo "Depool: $Depool_addr"
    echo "Balance : $(echo "scale=3; $((Depool_AMOUNT_nt)) / 1000000000" | $CALL_BC) tokens | Last op: $Depool_LAST_TR_TIME"
    echo
fi
#=======================
# proxy0 account
if [[ ! "$Proxy0_Status" == "account_active" ]];then
    echo "###-ERROR(line $LINENO): Proxy0 account does not deployed"
#    exit 1
else
    if [[ $Proxy0_AMOUNT_nt -lt $((PRX_LOW_THRESHOLD * 1000000000)) ]];then
        echo '$$$-WARN: We need to topup proxy0 account! Let`s do it!'
        SendTokens "${VALIDATOR_NAME}" "proxy0" "${PRX__TOPUP_AMOUNT}"
        sleep $TIMEOUT_BEFORE_SIGN
        ${SCRIPT_DIR}/Sign_Val_Trans.sh
    fi
    echo "Proxy0_addr: $Proxy0_addr"
    echo "Balance : $(echo "scale=3; $((Proxy0_AMOUNT_nt)) / 1000000000" | $CALL_BC) tokens | Last op: $Proxy0_LAST_TR_TIME"
    echo
fi
#=======================
# proxy1 account
if [[ ! "$Proxy1_Status" == "account_active" ]];then
    echo "###-ERROR(line $LINENO): Proxy1 account does not deployed"
#    exit 1
else
    if [[ $Proxy1_AMOUNT_nt -lt $((PRX_LOW_THRESHOLD * 1000000000)) ]];then
        echo '$$$-WARN: We need to topup proxy1 account! Let`s do it!'
        SendTokens "${VALIDATOR_NAME}" "proxy1" "${PRX__TOPUP_AMOUNT}"
        sleep $TIMEOUT_BEFORE_SIGN
        ${SCRIPT_DIR}/Sign_Val_Trans.sh
    fi
    echo "Proxy1_addr: $Proxy1_addr"
    echo "Balance : $(echo "scale=3; $((Proxy1_AMOUNT_nt)) / 1000000000" | $CALL_BC) tokens | Last op: $Proxy0_LAST_TR_TIME"
    echo
fi
#=======================
# Tik account
if [[ ! "$Tik_Status" == "account_active" ]];then
    echo "###-ERROR(line $LINENO): Tik account does not deployed"
#    exit 1
else
    if [[ $Tik_AMOUNT_nt -lt $((TIK_LOW_THRESHOLD * 1000000000)) ]];then
        echo '$$$-WARN: We need to topup Tik account! Let`s do it!'
        SendTokens "${VALIDATOR_NAME}" "Tik" "${PRX__TOPUP_AMOUNT}"
        sleep $TIMEOUT_BEFORE_SIGN
        ${SCRIPT_DIR}/Sign_Val_Trans.sh
    fi
    echo "Tik_addr: $Tik_addr"
    echo "Balance : $(echo "scale=3; $((Tik_AMOUNT_nt)) / 1000000000" | $CALL_BC) tokens | Last op: $Tik_LAST_TR_TIME"
    echo
fi

echo "Validator_addr: $Validator_addr"
echo "Has Status: $Validator_Status,  balance : $(echo "scale=3; $((Validator_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Validator_LAST_TR_TIME"
echo

# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Current balance: $((AMOUNT/1000000000))" 2>&1 > /dev/null
echo "=================================================================================================="

exit 0
