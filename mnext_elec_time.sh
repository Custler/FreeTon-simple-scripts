#!/bin/bash -eE

# (C) Sergey Tyurin  2020-09-30 15:00:00

# You have to have installed :
#   'xxd' - is a part of vim-commons ( [apt/dnf/pkg] install vim[-common] )
#   'jq'
#   'bc' for Linux
#   'dc' for FreeBSD
#   'tvm_linker' compiled binary from https://github.com/tonlabs/TVM-linker.git to $HOME/bin (must be in $PATH)
#   'lite-client'                                               
#   'validator-engine-console'
#   'fift'

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

set -o pipefail

echo
echo "################################# Set timetable for msig #####################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

TIME_SHIFT=120
SCRPT_USER=$USER

# ===================================================
GET_M_H() {
    OS_SYSTEM=`uname`
    ival="${1}"
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        echo "$(date  +'%M %H' -d @$ival)"
    else
        echo "$(date -r $ival +'%M %H')"
    fi
} 
# ===================================================

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

# ===================================================

if [[ ! -d $KEYS_DIR ]];then
  echo "###-ERROR: Folder $KEYS_DIR not found!"
  echo "Check SCRPT_USER variable in the script!"
  exit 1
fi

ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"
ELECTIONS_HISTORY_DIR="${KEYS_DIR}/elections_hist"
[[  ! -d $ELECTIONS_WORK_DIR ]] && mkdir -p $ELECTIONS_WORK_DIR
[[  ! -d $ELECTIONS_HISTORY_DIR ]] && mkdir -p $ELECTIONS_HISTORY_DIR

CALL_LC="${TON_BUILD_DIR}/lite-client/lite-client -p ${KEYS_DIR}/liteserver.pub -a $LITESERVER_IP:$LITESERVER_PORT -t 5"

#===================================================
# Stake Calculation
ACCOUNT=`cat ${KEYS_DIR}/${HOSTNAME}.addr`
if [[ -z $ACCOUNT ]];then
    echo "###-ERROR: Can't find ${KEYS_DIR}/${HOSTNAME}.addr"
    exit 1
fi

echo "Account: $ACCOUNT"
echo "Time: $(date  +'%Y-%m-%d %H:%M:%S')"

ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${ACCOUNT}" -t "3" -rc "quit" 2>/dev/null `
MY_WALL_BAL=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`

TOKEN_BALANCE=$((MY_WALL_BAL/1000000000))
STAKE_AMNT=$((TOKEN_BALANCE - 1))

#######################################################################################################
#===================================================
# Get current electoin cycle info
# get elector address
trap 'echo LC TIMEOUT EXIT' EXIT
elector_addr=`$CALL_LC -rc "getconfig 1" -rc "quit" 2>/dev/null | grep -i 'ConfigParam(1)' | awk '{print substr($4,15,64)}'`
trap - EXIT
elector_addr=`echo "-1:"$elector_addr`
echo "INFO: Elector Address: $elector_addr"

# Get elections ID 
trap 'echo LC TIMEOUT EXIT' EXIT
election_id=`$CALL_LC -rc "runmethod $elector_addr active_election_id" -rc "quit" 2>/dev/null | grep "result:" | awk '{print $3}' `
trap - EXIT

ELECT_TIME_PAR=`$CALL_LC -rc "getconfig 15" -t "3" -rc "quit" 2>/dev/null`
LIST_CURR_VALS=`$CALL_LC -rc "getconfig 34" -t "3" -rc "quit" 2>/dev/null`
LIST_NEXT_VALS=`$CALL_LC -rc "getconfig 36" -t "3" -rc "quit" 2>/dev/null`

NEXT_VAL__EXIST=`echo "${LIST_NEXT_VALS}"| grep -i "ConfigParam(36)" | grep -i 'null'`                              # Config p36: null
CURR_VAL_UNTIL=`echo "${LIST_CURR_VALS}" | grep -i "cur_validators"  | awk -F ":" '{print $4}'|awk '{print $1}'`	# utime_until
VAL_DUR=`echo "${ELECT_TIME_PAR}"        | grep -i "ConfigParam(15)" | awk -F ":" '{print $2}' |awk '{print $1}'`	# validators_elected_for
STRT_BEFORE=`echo "${ELECT_TIME_PAR}"    | grep -i "ConfigParam(15)" | awk -F ":" '{print $3}' |awk '{print $1}'`	# elections_start_before
EEND_BEFORE=`echo "${ELECT_TIME_PAR}"    | grep -i "ConfigParam(15)" | awk -F ":" '{print $4}' |awk '{print $1}'`	# elections_end_before

END_OF_ELECTIONS_TIME=$((election_id - EEND_BEFORE))
END_OF_ELECTIONS=$(GET_M_H "$END_OF_ELECTIONS_TIME")
#===================================================
# for new script it need to run msig script twice
CRR_ELECTION_TIME=$((CURR_VAL_UNTIL - STRT_BEFORE + TIME_SHIFT))
CRR_ELECTION_SECOND_TIME=$(($CRR_ELECTION_TIME + $TIME_SHIFT))
CRR_ADNL_TIME=$(($CRR_ELECTION_SECOND_TIME + $TIME_SHIFT))
CRR_BAL_TIME=$(($CRR_ADNL_TIME + $TIME_SHIFT))
CRR_CHG_TIME=$(($CRR_BAL_TIME + $TIME_SHIFT))

CUR_ELECT_1=$(GET_M_H "$CRR_ELECTION_TIME")
CUR_ELECT_2=$(GET_M_H "$CRR_ELECTION_SECOND_TIME")
CUR_ELECT_3=$(GET_M_H "$CRR_ADNL_TIME")
CUR_ELECT_4=$(GET_M_H "$CRR_BAL_TIME")
CUR_ELECT_5=$(GET_M_H "$CRR_CHG_TIME")

#===================================================
# for new script it need to run msig script twice
NEXT_ELECTION_TIME=$((CURR_VAL_UNTIL + VAL_DUR - STRT_BEFORE + $TIME_SHIFT))
NEXT_ELECTION_SECOND_TIME=$(($NEXT_ELECTION_TIME + $TIME_SHIFT))
NEXT_ADNL_TIME=$(($NEXT_ELECTION_SECOND_TIME + $TIME_SHIFT))
NEXT_BAL_TIME=$(($NEXT_ADNL_TIME + $TIME_SHIFT))
NEXT_CHG_TIME=$(($NEXT_BAL_TIME + $TIME_SHIFT))


NXT_ELECT_1=$(GET_M_H "$NEXT_ELECTION_TIME")
NXT_ELECT_2=$(GET_M_H "$NEXT_ELECTION_SECOND_TIME")
NXT_ELECT_3=$(GET_M_H "$NEXT_ADNL_TIME")
NXT_ELECT_4=$(GET_M_H "$NEXT_BAL_TIME")
NXT_ELECT_5=$(GET_M_H "$NEXT_CHG_TIME")

#===================================================

CURRENT_CHG_TIME=`crontab -l |tail -n 1 | awk '{print $1 " " $2}'`

GET_F_T(){
    OS_SYSTEM=`uname`
    ival="${1}"
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        echo "$(date  +'%Y-%m-%d %H:%M:%S' -d @$ival)"
    else
        echo "$(date -r $ival +'%Y-%m-%d %H:%M:%S')"
    fi
}

echo
echo "Current elections time start: $CRR_ELECTION_TIME / $(GET_F_T "$CRR_ELECTION_TIME")"
echo "Next elections time start: $NEXT_ELECTION_TIME / $(GET_F_T "$NEXT_ELECTION_TIME")"
echo "-------------------------------------------------------------------"

if [[ ! -z $NEXT_VAL__EXIST ]] && [[ "$election_id" == "0" ]];then
    NXT_ELECT_1=$CUR_ELECT_1
    NXT_ELECT_2=$CUR_ELECT_2
fi

#####################
# STAKE_AMNT=100000
#####################
#===================================================
# sudo crontab -u $SCRPT_USER -r
# Make crontab content depend of OS
OS_SYSTEM=`uname`
FB_CT_HEADER=""
if [[ "$OS_SYSTEM" == "FreeBSD" ]];then

CRONT_JOBS=$(cat <<-_ENDCRN_
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/home/$SCRPT_USER/bin
HOME=/home/$SCRPT_USER
$NXT_ELECT_1 * * *    cd ${SCRIPT_DIR} && ./lt-validator_msig.sh 1 >> ${TON_LOG_DIR}/validator_msig.log
$NXT_ELECT_2 * * *    cd ${SCRIPT_DIR} && ./mnext_elec_time.sh >> /var/ton-work/validator_msig.log && ./balance_check.sh >> ${TON_LOG_DIR}/validator_msig.log
$CUR_ELECT_3 * * *    cd ${SCRIPT_DIR} && ./lt-validator_msig.sh $STAKE_AMNT >> ${TON_LOG_DIR}/validator_msig.log
$CUR_ELECT_4 * * *    cd ${SCRIPT_DIR} && ./participant_list.sh >> ${TON_LOG_DIR}/validator_msig.log && ./balance_check.sh >> ${TON_LOG_DIR}/validator_msig.log
$END_OF_ELECTIONS * * *    cd ${SCRIPT_DIR} && ./get_participant_list.sh > $END_OF_ELECTIONS/${election_id}_parts.lst && chmod 444 $END_OF_ELECTIONS/${election_id}_parts.lst
_ENDCRN_
)

else

CRONT_JOBS=$(cat <<-_ENDCRN_
$NXT_ELECT_1 * * *    script --return --quiet --append --command "cd ${SCRIPT_DIR} && ./lt-validator_msig.sh 1 >> ${TON_LOG_DIR}/validator_msig.log"
$NXT_ELECT_2 * * *    script --return --quiet --append --command "cd ${SCRIPT_DIR} && ./mnext_elec_time.sh >> ${TON_LOG_DIR}/validator_msig.log && ./balance_check.sh >> ${TON_LOG_DIR}/validator_msig.log"
$CUR_ELECT_3 * * *    script --return --quiet --append --command "cd ${SCRIPT_DIR} && ./lt-validator_msig.sh $STAKE_AMNT >> ${TON_LOG_DIR}/validator_msig.log"
$CUR_ELECT_4 * * *    script --return --quiet --append --command "cd ${SCRIPT_DIR} && ./participant_list.sh >> ${TON_LOG_DIR}/validator_msig.log && ./balance_check.sh >> ${TON_LOG_DIR}/validator_msig.log"
$END_OF_ELECTIONS * * *    script --return --quiet --append --command "cd ${SCRIPT_DIR} && ./get_participant_list.sh > $ELECTIONS_HISTORY_DIR/${election_id}_parts.lst && chmod 444 $ELECTIONS_HISTORY_DIR/${election_id}_parts.lst"
_ENDCRN_
)

fi

#===================================================
# Write to crontab
[[ "$1" == "show" ]] && echo "$CRONT_JOBS"&& exit 0

echo "$CRONT_JOBS" | sudo crontab -u $SCRPT_USER -

sudo crontab -l -u $SCRPT_USER | tail -n 5

exit 0
