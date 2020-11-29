#!/bin/bash -eE


SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

[[ ! -d $HOME/logs ]] && mkdir -p $HOME/logs

SLEEP_TIMEOUT=$1
SLEEP_TIMEOUT=${SLEEP_TIMEOUT:="60"}

# ===================================================
GET_CHAIN_DATE() {
    OS_SYSTEM=`uname`
    ival="${1}"
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        echo "$(date  +'%Y-%m-%d %H:%M:%S' -d @$ival)"
    else
        echo "$(date -r $ival +'%Y-%m-%d %H:%M:%S')"
    fi
}
# ===================================================


while(true)
do

VEC_OUTPUT=$($CALL_VC -c "getstats" -c "quit")

# echo "VEC output:"
CURR_TD_NOW=`echo "${VEC_OUTPUT}" | grep unixtime | awk '{print $2}'`
CHAIN_TD=`echo "${VEC_OUTPUT}" | grep masterchainblocktime | awk '{print $2}'`
TIME_DIFF=$((CURR_TD_NOW - CHAIN_TD))
CURR_TD_NOW=`GET_CHAIN_DATE "$CURR_TD_NOW"`

if [[ -z $CHAIN_TD ]];then
    echo "CurrTime: $CURR_TD_NOW --- No masterchain blocks received yet."
    sleep $SLEEP_TIMEOUT
    continue
fi

CHAIN_TD=`GET_CHAIN_DATE "$CHAIN_TD"`

echo "CurrTime: $CURR_TD_NOW TimeDiff: $TIME_DIFF" | tee -a ~/logs/time-diff.log

sleep $SLEEP_TIMEOUT
done

exit 0
