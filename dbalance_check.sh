#!/bin/bash -eE

set -o pipefail
# set -u
# set -x


SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    CALL_BC="bc"
else
    CALL_BC="bc -l"
fi

Tik_addr=`cat ${KEYS_DIR}/Tik.addr`
Depool_addr=`cat ${KEYS_DIR}/depool.addr`
# Helper_addr=`cat ${KEYS_DIR}/helper.addr`
Proxy0_addr=`cat ${KEYS_DIR}/proxy0.addr`
Proxy1_addr=`cat ${KEYS_DIR}/proxy1.addr`
Validator_addr=`cat ${KEYS_DIR}/${HOSTNAME}.addr`

CALL_LC="${TON_BUILD_DIR}/lite-client/lite-client -p ${KEYS_DIR}/liteserver.pub -a 127.0.0.1:3031 -t 5"

Tik_INFO=`$CALL_LC -rc "getaccount ${Tik_addr}" -t "3" -rc "quit" 2>/dev/null `
Depool_INFO=`$CALL_LC -rc "getaccount ${Depool_addr}" -t "3" -rc "quit" 2>/dev/null `
# Helper_INFO=`$CALL_LC -rc "getaccount ${Helper_addr}" -t "3" -rc "quit" 2>/dev/null `
Proxy0_INFO=`$CALL_LC -rc "getaccount ${Proxy0_addr}" -t "3" -rc "quit" 2>/dev/null `
Proxy1_INFO=`$CALL_LC -rc "getaccount ${Proxy1_addr}" -t "3" -rc "quit" 2>/dev/null `
Validator_INFO=`$CALL_LC -rc "getaccount ${Validator_addr}" -t "3" -rc "quit" 2>/dev/null `

#ACC_STATUS=`echo "$ACCOUNT_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`
Tik_AMOUNT=`echo "$Tik_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Tik_LAST_TR_TIME=`echo "$Tik_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Tik_Status=`echo "$Tik_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Depool_AMOUNT=`echo "$Depool_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Depool_LAST_TR_TIME=`echo "$Depool_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Depool_Status=`echo "$Depool_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

# Helper_AMOUNT=`echo "$Helper_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
# Helper_LAST_TR_TIME=`echo "$Helper_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
# Helper_Status=`echo "$Helper_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Proxy0_AMOUNT=`echo "$Proxy0_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Proxy0_LAST_TR_TIME=`echo "$Proxy0_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Proxy0_Status=`echo "$Proxy0_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Proxy1_AMOUNT=`echo "$Proxy1_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Proxy1_LAST_TR_TIME=`echo "$Proxy1_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Proxy1_Status=`echo "$Proxy1_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`

Validator_AMOUNT=`echo "$Validator_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
Validator_LAST_TR_TIME=`echo "$Validator_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`
Validator_Status=`echo "$Validator_INFO" | grep "state:" | awk -F "(" '{ print $2 }'`


echo
echo "Time Now: $(date  +'%Y-%m-%d %H:%M:%S')"
echo
echo "Tik_addr: $Tik_addr"
echo "Has Status: $Tik_Status,  balance : $(echo "scale=3; $((Tik_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Tik_LAST_TR_TIME"
echo
echo "Depool: $Depool_addr"
echo "Has Status: $Depool_Status,  balance : $(echo "scale=3; $((Depool_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Depool_LAST_TR_TIME"
# echo
# echo "Helper_addr: $Helper_addr"
# echo "Has Status: $Helper_Status,  balance : $(echo "scale=3; $((Helper_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Helper_LAST_TR_TIME"
echo
echo "Proxy0_addr: $Proxy0_addr"
echo "Has Status: $Proxy0_Status,  balance : $(echo "scale=3; $((Proxy0_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Proxy0_LAST_TR_TIME"
echo
echo "Proxy1_addr: $Proxy1_addr"
echo "Has Status: $Proxy1_Status,  balance : $(echo "scale=3; $((Proxy1_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Proxy1_LAST_TR_TIME"
echo
echo "Validator_addr: $Validator_addr"
echo "Has Status: $Validator_Status,  balance : $(echo "scale=3; $((Validator_AMOUNT)) / 1000000000" | $CALL_BC) tokens | Last op: $Validator_LAST_TR_TIME"
echo
# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Current balance: $((AMOUNT/1000000000))" 2>&1 > /dev/null
echo "=================================================================================================="

exit 0
