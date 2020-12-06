#!/bin/bash -eE

# usage: tg-check_node_sync_status.sh [T - timeout sec] [alarm to tg if time > N]

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

[[ ! -d $HOME/logs ]] && mkdir -p $HOME/logs

SLEEP_TIMEOUT=$1
SLEEP_TIMEOUT=${SLEEP_TIMEOUT:="60"}
ALARM_TIME_DIFF=$2
ALARM_TIME_DIFF=${ALARM_TIME_DIFF:=100}

# ===================================================
GET_CHAIN_DATE() {
    OS_SYSTEM=`uname`
    ival="${1}"
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        echo "$(date  +'%F %T %Z' -d @$ival)"
    else
        echo "$(date -r $ival +'%F %T %Z')"
    fi
}
# ===================================================


while(true)
do

VEC_OUTPUT=$($CALL_VC -c "getstats" -c "quit" 2>&1 | cat)

NODE_DOWN=$(echo "${VEC_OUTPUT}" | grep 'Connection refused' | cat)
if [[ ! -z $NODE_DOWN ]];then
    echo "${VEC_OUTPUT}"
    # "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "ALARM! NODE IS DOWN." 2>&1 > /dev/null
    sleep $SLEEP_TIMEOUT
    continue
fi
    
# echo "VEC output:"
CURR_TD_NOW=`echo "${VEC_OUTPUT}" | grep 'unixtime' | awk '{print $2}'`
CHAIN_TD=`echo "${VEC_OUTPUT}" | grep 'masterchainblocktime' | awk '{print $2}'`
TIME_DIFF=$((CURR_TD_NOW - CHAIN_TD))
CURR_TD_NOW=`GET_CHAIN_DATE "$CURR_TD_NOW"`

if [[ -z $CHAIN_TD ]];then
    echo "CurrTime: $CURR_TD_NOW --- No masterchain blocks received yet."
    sleep $SLEEP_TIMEOUT
    continue
fi

CHAIN_TD=`GET_CHAIN_DATE "$CHAIN_TD"`

echo "CurrTime: $CURR_TD_NOW TimeDiff: $TIME_DIFF" | tee -a $HOME/logs/time-diff.log

# if [[ $TIME_DIFF -gt $ALARM_TIME_DIFF ]] || [[ -z $CHAIN_TD ]];then
#     "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "ALARM! NODE out of sync. TimeDiff: $TIME_DIFF" 2>&1 > /dev/null
# fi

sleep $SLEEP_TIMEOUT
done

exit 0
