#!/bin/bash -eE


VAL_PID=`ps -ax | grep "validator\-engine" | awk '{print $1}'`
# echo "Engine PID: $VAL_PID"

if [[ ! -z $VAL_PID ]]; then
    exit 0
fi

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

verb="${1:-1}"

# $SCRIPT_DIR/nets_config_update.sh
echo "############## - !!! Restart NODE !!! - ##############"
echo "$(date)"
./run.sh $verb

VAL_PID=`ps -ax | grep "validator\-engine" | awk '{print $1}'`
if [[ -z $VAL_PID ]]; then
  while true
  do
    ./run.sh $verb
    VAL_PID=`ps -ax | grep "validator\-engine" | awk '{print $1}'`
    [[ ! -z $VAL_PID ]] && break
    echo "### - ALARM !!! Can't start engine."
    ${SCRIPT_DIR}/Send_msg_toTelBot.sh "$HOSTNAME Server" "### - ALARM !!! Can't start engine." 2>&1 > /dev/null
  done
fi
echo "=================================================================================================="

