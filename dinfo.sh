#!/bin/bash

# (C) Sergey Tyurin  2020-12-05 20:00:00

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

####################################
# we can't work on desynced node
TIMEDIFF_MAX=100
MAX_FACTOR=${MAX_FACTOR:-3}
export LC_NUMERIC="C"
####################################

echo
echo "#################################### Depool INFO script ########################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

# DSCs_DIR=$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/depool
# CALL_LC="${TON_BUILD_DIR}/lite-client/lite-client -p ${KEYS_DIR}/liteserver.pub -a 127.0.0.1:3031 -t 5"
# CALL_VC="${TON_BUILD_DIR}/validator-engine-console/validator-engine-console -k ${KEYS_DIR}/client -p ${KEYS_DIR}/server.pub -a 127.0.0.1:3030 -t 5"
# CALL_TL="$HOME/bin/tvm_linker"
# CALL_FT="${TON_BUILD_DIR}/crypto/fift -I ${TON_SRC_DIR}/crypto/fift/lib:${TON_SRC_DIR}/crypto/smartcont"

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

##############################################################################
# Test binaries
if [[ -z $($CALL_LC --help |grep 'Lite Client') ]];then
    echo "###-ERROR(line $LINENO): Lite Client not installed in PATH"
    exit 1
fi

if [[ -z $($CALL_TL -V | grep "TVM linker") ]];then
    echo "###-ERROR(line $LINENO): TVM linker not installed in PATH"
    exit 1
fi

if [[ -z $(xxd -v 2>&1 | grep "Juergen Weigert") ]];then
    echo "###-ERROR(line $LINENO): 'xxd' not installed in PATH"
    exit 1
fi

if [[ -z $(jq --help 2>/dev/null |grep -i "Usage"|cut -d ":" -f 1) ]];then
    echo "###-ERROR(line $LINENO): 'jq' not installed in PATH"
    exit 1
fi
#=================================================
# Check 'getvalidators' command present in engine
Node_Keys=`$CALL_VC -c "getvalidators" -c "quit" 2>/dev/null | grep "unknown command"`

if [[ ! -z $Node_Keys ]];then
    echo "###-ERROR(line $LINENO): You engine hasn't command 'getvalidators'. Get & install new engine from 'https://github.com/FreeTON-Network/FreeTON-Node'"
#    exit 1
fi

##############################################################################
# Functions
# ================================================
function TD_unix2human() {
    local OS_SYSTEM=`uname`
    local ival="$(echo ${1}|tr -d '"')"
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        echo "$(date  +'%F %T %Z' -d @$ival)"
    else
        echo "$(date -r $ival +'%F %T %Z')"
    fi
}
#=================================================
# NOTE: Avoid double quoting  - ""0xXXXXX"" in input var
function hex2dec() {
    local OS_SYSTEM=`uname`
    local ival="$(echo ${1^^}|tr -d '"')"
    local ob=${2:-10}
    local ib=${3:-16}
    if [[ "$OS_SYSTEM" == "Linux" ]];then
        export BC_LINE_LENGTH=0
        # set obase first before ibase -- or weird things happen.
        printf "obase=%d; ibase=%d; %s\n" $ob $ib $ival | bc
    else
        dc -e "${ib}i ${ival} p" | tr -d "\\" | tr -d "\n"
    fi
}
#=================================================
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
        echo "###-ERROR(line $LINENO): Cannot get state of account: $Depool_addr" 
        echo "    Can't continue. Sorry."
        exit 1
    fi
    echo "$LC_OUTPUT"
}

#=================================================
# Get account balance
function get_acc_bal() {
    local ACCOUNT=$1
    local ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${ACCOUNT}" -rc "quit" 2>/dev/null`
    local AMOUNT=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
    echo $AMOUNT
}

##############################################################################
# Load addresses and set variables
# net id - first 16 syms of zerostate id
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
echo

Depool_addr=$1
if [[ -z $Depool_addr ]];then
    MyDepool_addr=`cat "${KEYS_DIR}/depool.addr"`
    if [[ -z $MyDepool_addr ]];then
        echo " Can't find ${KEYS_DIR}/depool.addr"
        exit 1
    else
        Depool_addr=$MyDepool_addr
    fi
else
    acc_fmt="$(echo "$Depool_addr" |  awk -F ':' '{print $2}')"
    [[ -z $acc_fmt ]] && Depool_addr=`cat "${KEYS_DIR}/${Depool_addr}.addr"`
fi

dpc_addr=`echo $Depool_addr | cut -d ':' -f 2`
[[ -f ${KEYS_DIR}/Tik.addr ]] && Tik_addr=`cat ${KEYS_DIR}/Tik.addr`
[[ -f ${KEYS_DIR}/proxy0.addr ]] && Proxy0_addr=`cat ${KEYS_DIR}/proxy0.addr`
[[ -f ${KEYS_DIR}/proxy1.addr ]] && Proxy1_addr=`cat ${KEYS_DIR}/proxy1.addr`
Validator_addr=`cat ${KEYS_DIR}/${VALIDATOR_NAME}.addr`
Work_Chain=`echo "${Validator_addr}" | cut -d ':' -f 1`

if [[ -z $Validator_addr ]];then
    echo "###-ERROR(line $LINENO): Can't find validator address! ${KEYS_DIR}/${VALIDATOR_NAME}.addr"
    exit 1
fi
if [[ -z $Depool_addr ]];then
    echo "###-ERROR(line $LINENO): Can't find depool address! ${KEYS_DIR}/depool.addr"
    exit 1
fi

val_acc_addr=`echo "${Validator_addr}" | cut -d ':' -f 2`
echo "INFO: Local validator account address: $Validator_addr"
ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"
[[ ! -d ${ELECTIONS_WORK_DIR} ]] && mkdir -p ${ELECTIONS_WORK_DIR}
chmod +x ${ELECTIONS_WORK_DIR}

# ~/net.ton.dev/ton-labs-contracts/solidity/depool/DePool.abi.json
DSCs_DIR="$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/depool"

##############################################################################
# Check node sync
VEC_OUTPUT=`$CALL_VC -c "getstats" -c "quit"`

CURR_TD_NOW=`echo "${VEC_OUTPUT}" | grep unixtime | awk '{print $2}'`
CHAIN_TD=`echo "${VEC_OUTPUT}" | grep masterchainblocktime | awk '{print $2}'`
TIME_DIFF=$((CURR_TD_NOW - CHAIN_TD))
if [[ $TIME_DIFF -gt $TIMEDIFF_MAX ]];then
    echo "###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF"
#    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF" 2>&1 > /dev/null
    exit 1
fi
echo "INFO: Current TimeDiff: $TIME_DIFF"

##############################################################################
# get elector address
elector_addr=`$CALL_LC -rc "getconfig 1" -rc "quit" 2>/dev/null | grep -i 'ConfigParam(1)' | awk '{print substr($4,15,64)}'`
elector_addr=`echo "-1:"$elector_addr | tee ${ELECTIONS_WORK_DIR}/elector-addr-base64`
echo "INFO:     Elector Address: $elector_addr"

##############################################################################
# get elections ID from elector
echo
echo "==================== Elections Info ====================================="

election_id=`$CALL_LC -rc "runmethod $elector_addr active_election_id" -rc "quit" 2>/dev/null | grep "result:" | awk '{print $3}'`
echo "   => Elector Elections ID: $election_id / $(echo "$election_id" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
echo 

Node_Keys=`$CALL_VC -c "getvalidators" -c "quit" 2>/dev/null | grep "validator0"`

if [[ ! -z $Node_Keys ]];then
    Node_Keys=`$CALL_VC -c "getvalidators" -c "quit" 2>/dev/null`
    Curr_Engine_Eclec_ID=$(echo "$Node_Keys" | grep "validator0"| grep -i 'tempkey:' | awk '{print $2}')
    Curr_Engine_Pub_Key=$(echo  "$Node_Keys" | grep "validator0"| grep -i 'tempkey:' | awk '{print $4}'|tr "[:upper:]" "[:lower:]")
    Curr_Engine_ADNL_Key=$(echo "$Node_Keys" | grep "validator0"| grep -i 'adnl:'    | awk '{print $4}'|tr "[:upper:]" "[:lower:]")
    if [[ -z $(echo "$Node_Keys"|grep "validator1") ]];then
        echo "       Engine Election ID: $Curr_Engine_Eclec_ID / $(echo "$Curr_Engine_Eclec_ID" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
        echo "Current Engine public key: $Curr_Engine_Pub_Key"
        echo "  Current Engine ADNL key: $Curr_Engine_ADNL_Key"
    else
        Next_Engine_Eclec_ID=$Curr_Engine_Eclec_ID
        Next_Engine_Pub_Key=$Curr_Engine_Pub_Key
        Next_Engine_ADNL_Key=$Curr_Engine_ADNL_Key
        Curr_Engine_Eclec_ID=$(echo "$Node_Keys" | grep "validator1"| grep -i 'tempkey:' | awk '{print $2}')
        Curr_Engine_Pub_Key=$(echo  "$Node_Keys" | grep "validator1"| grep -i 'tempkey:' | awk '{print $4}'|tr "[:upper:]" "[:lower:]")
        Curr_Engine_ADNL_Key=$(echo "$Node_Keys" | grep "validator1"| grep -i 'adnl:'    | awk '{print $4}'|tr "[:upper:]" "[:lower:]")

        echo "Current Engine Election #: $Curr_Engine_Eclec_ID / $(echo "$Curr_Engine_Eclec_ID" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
        echo "Current Engine public key: $Curr_Engine_Pub_Key"
        echo "  Current Engine ADNL key: $Curr_Engine_ADNL_Key"
        echo
        echo "   Next Engine Election #: $Next_Engine_Eclec_ID / $(echo "$Next_Engine_Eclec_ID" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
        echo "   Next Engine public key: $Next_Engine_Pub_Key"
        echo "     Next Engine ADNL key: $Next_Engine_ADNL_Key"
    fi
fi

##############################################################################
# Save DePool contract state to file
# echo -n "   Get SC state of depool: $Depool_addr ... "    
LC_OUTPUT="$(Get_SC_current_state "$Depool_addr")"
result=`echo $LC_OUTPUT | grep "written StateInit of account"`
if [[ -z  $result ]];then
    echo "###-ERROR(line $LINENO): Cannot get state of account: $Depool_addr" 
    echo "    Can't continue. Sorry."
    exit 1
fi
# echo "Done."

##############################################################################
# get info from DePool contract state
Curr_Rounds_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getRounds -p "{}" --decode-c6 $dpc_addr | grep -i 'rounds')
Current_Depool_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getDePoolInfo -p "{}" --decode-c6 $dpc_addr|grep -i 'validatorWallet')

#######################################################################################
# Get Depool Info
# returns (
#    {"name":"poolClosed","type":"bool"},
#    {"name":"minStake","type":"uint64"},
#    {"name":"validatorAssurance","type":"uint64"},
#    {"name":"participantRewardFraction","type":"uint8"},
#    {"name":"validatorRewardFraction","type":"uint8"},
#    {"name":"balanceThreshold","type":"uint64"},
#    {"name":"validatorWallet","type":"address"},
#    {"name":"proxies","type":"address[]"},
#    {"name":"stakeFee","type":"uint64"},
#    {"name":"retOrReinvFee","type":"uint64"},
#    {"name":"proxyFee","type":"uint64"}

echo 
echo "==================== Current Depool State ====================================="

PoolClosed=$(echo  "$Current_Depool_Info"|jq '.poolClosed'|tr -d '"')
if [[ "$PoolClosed" == "false" ]];then
    PoolState="${GreeBack}OPEN for participation!${NormText}"
fi
if [[ "$PoolClosed" == "true" ]];then
    PoolState="${RedBlink}CLOSED!!! all stakes should be return to participants${NormText}"
fi
if [[ "$PoolClosed" == "false" ]] || [[ "$PoolClosed" == "true" ]];then
    echo -e "Pool State: $PoolState"
else
    echo "###-ERROR(line $LINENO): Can't determine the Depool state!! All following data is invalid!!!"
fi
echo
echo "==================== Depool addresses ====================================="

dp_val_wal=$(echo "$Current_Depool_Info" | jq ".validatorWallet"|tr -d '"')
dp_proxy0=$(echo "$Current_Depool_Info" | jq "[.proxies[]]|.[0]"|tr -d '"')
dp_proxy1=$(echo "$Current_Depool_Info" | jq "[.proxies[]]|.[1]"|tr -d '"')

[[ ! -f ${KEYS_DIR}/proxy0.addr ]] && echo "$dp_proxy0" > ${KEYS_DIR}/proxy0.addr
[[ ! -f ${KEYS_DIR}/proxy1.addr ]] && echo "$dp_proxy1" > ${KEYS_DIR}/proxy1.addr

#============================================
# Get balances
Depool_Bal=$(get_acc_bal "$Depool_addr")
Val_Bal=$(get_acc_bal "$dp_val_wal")
prx0_Bal=$(get_acc_bal "$dp_proxy0")
prx1_Bal=$(get_acc_bal "$dp_proxy1")
[[ ! -z $Tik_addr ]] && Tik_Bal=$(get_acc_bal "$Tik_addr")

#============================================
# Get depool fininfo
PoolSelfMinBalance=$(echo "$Current_Depool_Info"|jq '.balanceThreshold'|tr -d '"')
PoolMinStake=$(echo "$Current_Depool_Info"|jq '.minStake'|tr -d '"')
validatorAssurance=$(echo "$Current_Depool_Info"|jq '.validatorAssurance'|tr -d '"')
ValRewardFraction=$(echo "$Current_Depool_Info"|jq '.validatorRewardFraction'|tr -d '"')
PoolValStakeFee=$(echo "$Current_Depool_Info"|jq '.stakeFee'|tr -d '"')
PoolRetOrReinvFee=$(echo "$Current_Depool_Info"|jq '.retOrReinvFee'|tr -d '"')


Round_0_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[0].id"|tr -d '"'| xargs printf "%d\n")
Round_1_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[1].id"|tr -d '"'| xargs printf "%d\n")
Round_2_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[2].id"|tr -d '"'| xargs printf "%d\n")
Round_3_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[3].id"|tr -d '"'| xargs printf "%d\n")

declare -a rounds=($(($Round_0_ID)) $(($Round_1_ID)) $(($Round_2_ID)) $(($Round_3_ID)))
IFS=$'\n' Rounds_Sorted=($(sort -g <<<"${rounds[*]}")); unset IFS

Prev_Round_ID=${Rounds_Sorted[0]}
Curr_Round_ID=${Rounds_Sorted[1]}
Next_Round_ID=${Rounds_Sorted[2]}

Prev_Round_Num=$((Prev_Round_ID - Round_0_ID))
Curr_Round_Num=$((Curr_Round_ID - Round_0_ID))
Next_Round_Num=$((Next_Round_ID - Round_0_ID))
# ------------------------------------------------------------------------------------------------------------------------
Prev_DP_Elec_ID=$(echo   "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].supposedElectedAt"|tr -d '"'| xargs printf "%10d\n")
Prev_DP_Round_ID=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].id"|tr -d '"'| xargs printf "%d\n")
Prev_Round_P_QTY=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].participantQty"|tr -d '"'| xargs printf "%4d\n")
Prev_Round_Stake=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].stake"|tr -d '"'| xargs printf "%d\n")
Prev_Round_Reward=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].rewards"|tr -d '"'| xargs printf "%d\n")
Prev_Round_Stake=$(printf '%12.3f' "$(echo $Prev_Round_Stake / 1000000000 | jq -nf /dev/stdin)")
Prev_Round_Reward=$(printf '%12.3f' "$(echo $Prev_Round_Reward / 1000000000 | jq -nf /dev/stdin)")

Curr_DP_Elec_ID=$(echo   "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].supposedElectedAt"|tr -d '"'| xargs printf "%10d\n")
Curr_Round_P_QTY=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].participantQty"|tr -d '"'| xargs printf "%4d\n")
Curr_DP_Round_ID=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].id"|tr -d '"'| xargs printf "%d\n")
Curr_Round_Stake=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].stake"|tr -d '"'| xargs printf "%d\n")
Curr_Round_Reward=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].rewards"|tr -d '"'| xargs printf "%d\n")
Curr_Round_Stake=$(printf '%12.3f' "$(echo $Curr_Round_Stake / 1000000000 | jq -nf /dev/stdin)")
Curr_Round_Reward=$(printf '%12.3f' "$(echo $Curr_Round_Reward / 1000000000 | jq -nf /dev/stdin)")

Next_DP_Elec_ID=$(echo   "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].supposedElectedAt"|tr -d '"'| xargs printf "%d\n")
Next_DP_Round_ID=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].id"|tr -d '"'| xargs printf "%d\n")
Next_Round_P_QTY=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].participantQty"|tr -d '"'| xargs printf "%4d\n")
Next_Round_StakeNT=$(echo  "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].stake"|tr -d '"'| xargs printf "%d\n")
Next_Round_Reward=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].rewards"|tr -d '"'| xargs printf "%d\n")
Next_Round_Stake=$(printf '%12.3f' "$(echo $Next_Round_StakeNT / 1000000000 | jq -nf /dev/stdin)")
Next_Round_Reward=$(printf '%12.3f' "$(echo $Next_Round_Reward / 1000000000 | jq -nf /dev/stdin)")

echo "Depool contract address:     $Depool_addr  Balance: $(echo "scale=2; $((Depool_Bal - Next_Round_StakeNT)) / 1000000000" | $CALL_BC)"
echo "Depool Owner/validator addr: $dp_val_wal  Balance: $(echo "scale=2; $((Val_Bal)) / 1000000000" | $CALL_BC)"
echo "Depool proxy #0:            $dp_proxy0  Balance: $(echo "scale=2; $((prx0_Bal)) / 1000000000" | $CALL_BC)"
echo "Depool proxy #1:            $dp_proxy1  Balance: $(echo "scale=2; $((prx1_Bal)) / 1000000000" | $CALL_BC)"
[[ ! -z $Tik_addr ]] && \
echo "Tik account:                 $Tik_addr  Balance: $(echo "scale=2; $((Tik_Bal)) / 1000000000" | $CALL_BC)"
echo
echo "================ Finance information for the depool ==========================="

echo "                Pool Min Stake (Tk): $(echo "scale=3; $((PoolMinStake)) / 1000000000" | $CALL_BC)"
echo "            Validator Comission (%): $((ValRewardFraction))"
echo "              Depool stake fee (TK): $(echo "scale=3; $((PoolValStakeFee)) / 1000000000" | $CALL_BC)"
echo " Depool return or reinvest fee (TK): $(echo "scale=3; $((PoolRetOrReinvFee)) / 1000000000" | $CALL_BC)"
echo " Depool min balance to operate (TK): $(echo "scale=3; $((PoolSelfMinBalance)) / 1000000000" | $CALL_BC)"
echo "           Validator Assurance (TK): $((validatorAssurance / 1000000000))"
echo
##################################################################################################################
echo "============================ Depool rounds info ==============================="


echo " --------------------------------------------------------------------------------------------------------------------------"
echo "|                 |              Prev Round          |           Current Round          |              Next Round          |"
echo " --------------------------------------------------------------------------------------------------------------------------"
echo "|        Seq No   |       $(printf '%12d' "$Prev_Round_ID")               |       $(printf '%12d' "$Curr_Round_ID")               |       $(printf '%12d' "$Next_Round_ID")               |"
echo "|            ID   | $Prev_DP_Elec_ID / $(echo "$Prev_DP_Elec_ID" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}') | $Curr_DP_Elec_ID / $(echo "$Curr_DP_Elec_ID" | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}') |                  $Next_DP_Elec_ID               |"
echo "| Participant QTY |               $Prev_Round_P_QTY               |               $Curr_Round_P_QTY               |               $Next_Round_P_QTY               |"
echo "|         Stake   |           $Prev_Round_Stake           |           $Curr_Round_Stake           |           $Next_Round_Stake           |"
echo "|        Reward   |           $Prev_Round_Reward           |           $Curr_Round_Reward           |           $Next_Round_Reward           |"


echo
echo "=================== Current participants info in the depool ==================="

# tonos-cli run --abi ${DSCs_DIR}/DePool.abi.json $Depool_addr getParticipants {} > current_participants.lst
# Num_of_participants=`cat current_participants.lst | grep '"0:'| tr -d ' '|tr -d ',' |tr -d '"'| nl | tail -1 |awk '{print $1}'`
Num_of_participants=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipants -p "{}" --decode-c6 $dpc_addr | grep 'participants' | jq '.participants|length')
echo "Current Number of participants: $Num_of_participants"
echo


Prev_Round_Part_QTY=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Prev_Round_Num].participantQty"|tr -d '"'| xargs printf "%d\n")
Curr_Round_Part_QTY=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Curr_Round_Num].participantQty"|tr -d '"'| xargs printf "%d\n")
Next_Round_Part_QTY=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[$Next_Round_Num].participantQty"|tr -d '"'| xargs printf "%d\n")

echo "===== Current Round participants QTY (prev/curr/next/lock): $((Prev_Round_Part_QTY + 1)) / $((Curr_Round_Part_QTY + 1)) / $((Next_Round_Part_QTY + 1))"
# "outputs": [
# 				{"name":"total","type":"uint64"},
# 				{"name":"withdrawValue","type":"uint64"},
# 				{"name":"reinvest","type":"bool"},
# 				{"name":"reward","type":"uint64"},
# 				{"name":"stakes","type":"map(uint64,uint64)"},
# 				{"components":[{"name":"isActive","type":"bool"},{"name":"amount","type":"uint64"},{"name":"lastWithdrawalTime","type":"uint64"},{"name":"withdrawalPeriod","type":"uint32"},{"name":"withdrawalValue","type":"uint64"},{"name":"owner","type":"address"}],"name":"vestings","type":"map(uint64,tuple)"},
# 				{"components":[{"name":"isActive","type":"bool"},{"name":"amount","type":"uint64"},{"name":"lastWithdrawalTime","type":"uint64"},{"name":"withdrawalPeriod","type":"uint32"},{"name":"withdrawalValue","type":"uint64"},{"name":"owner","type":"address"}],"name":"locks","type":"map(uint64,tuple)"}

Hex_Prev_Round_ID=$(echo "0x$(printf '%x\n' $Prev_Round_ID)")
Hex_Curr_Round_ID=$(echo "0x$(printf '%x\n' $Curr_Round_ID)")
Hex_Next_Round_ID=$(echo "0x$(printf '%x\n' $Next_Round_ID)")

CRP_QTY=$((Curr_Round_Part_QTY - 1))
for (( i=0; i <= $CRP_QTY; i++ ))
do
    Curr_Part_Addr=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipants -p "{}" --decode-c6 $dpc_addr | grep 'participants' | jq ".participants|.[$i]")
    
    Prev_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Prev_Round_ID\""|tr -d '"')
    POS_Info=$(printf "%'9.2f" "$(echo $((Prev_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")
    
    Curr_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Curr_Round_ID\""|tr -d '"')
    COS_Info=$(printf "%'9.2f" "$(echo $((Curr_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")
    
    Next_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Next_Round_ID\""|tr -d '"')
    NOS_Info=$(printf "%'9.2f" "$(echo $((Next_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")
    
    Reward=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".reward"|tr -d '"')
    RWRD_Info=$(printf "%'8.2f" "$(echo $((Reward)) / 1000000000 | jq -nf /dev/stdin)")

    Reinvest=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".reinvest"|tr -d '"')
    REINV_Info=""
    if [[ "${Reinvest}" == "false" ]];then
        REINV_Info="${RedBack}GONE${NormText}"
    elif [[ "${Reinvest}" == "true" ]];then
        REINV_Info="Stay"
    fi

    Wtdr_Val_hex=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".withdrawValue"|tr -d '"')
    Wtdr_Val_Info=""
    if [[ $Wtdr_Val_hex -ne 0 ]];then
        Wtdr_Val_Info="; Next round withdraw: $(echo "scale=3; $((Wtdr_Val_hex)) / 1000000000" | $CALL_BC)"
    fi

    Curr_Lck_Stake=$(($($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".amount" |tr -d '"')))
    if [[ $Curr_Lck_Stake -eq 0 ]];then
        Curr_Lck_Stake=$(($($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".remainingAmount" |tr -d '"')))
    fi
    Lck_Start_Time=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".lastWithdrawalTime" |tr -d '"')
    Lck_Held_For=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".withdrawalPeriod" |tr -d '"')
    Lck_Out_DateTime="$(echo $((Lck_Start_Time + Lck_Held_For)) | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
    LockInfo=""
    if [[ $Curr_Lck_Stake -ne 0 ]];then
        LockInfo="; Lock: $((Curr_Lck_Stake / 1000000000)) will out: $Lck_Out_DateTime"
    fi
    #--------------------------------------------
    echo -e "$(printf '%4d' $(($i + 1))) $Curr_Part_Addr Reward: $RWRD_Info ; Stakes(${REINV_Info}): $POS_Info / $COS_Info / $NOS_Info $LockInfo $Wtdr_Val_Info"
    #--------------------------------------------
done

echo
echo "===== Total Depool participants (prev/curr/next/lock) =============================="

CRP_QTY=$((Num_of_participants - 1))
for (( i=0; i <= $CRP_QTY; i++ ))
do
    Curr_Part_Addr=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipants -p "{}" --decode-c6 $dpc_addr | grep 'participants' | jq ".participants|.[$i]")

    Prev_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Prev_Round_ID\""|tr -d '"')
    POS_Info=$(printf "%'9.2f" "$(echo $((Prev_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")

    Curr_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Curr_Round_ID\""|tr -d '"')
    COS_Info=$(printf "%'9.2f" "$(echo $((Curr_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")

    Next_Ord_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".stakes.\"$Hex_Next_Round_ID\""|tr -d '"')
    NOS_Info=$(printf "%'9.2f" "$(echo $((Next_Ord_Stake)) / 1000000000 | jq -nf /dev/stdin)")

    Reward=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".reward"|tr -d '"')
    RWRD_Info=$(printf "%'8.2f" "$(echo $((Reward)) / 1000000000 | jq -nf /dev/stdin)")

    Reinvest=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".reinvest"|tr -d '"')
    REINV_Info=""
    if [[ "${Reinvest}" == "false" ]];then
        REINV_Info="${RedBack}GONE${NormText}"
    elif [[ "${Reinvest}" == "true" ]];then
        REINV_Info="Stay"
    fi

    Curr_Lck_Stake=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".amount" |tr -d '"')
    
    Wtdr_Val_hex=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".withdrawValue"|tr -d '"')
    Wtdr_Val_Info=""
    if [[ $Wtdr_Val_hex -ne 0 ]];then
        Wtdr_Val_Info="; Next round withdraw: $(echo "scale=3; $((Wtdr_Val_hex)) / 1000000000" | $CALL_BC)"
    fi

    Curr_Lck_Stake=$(($($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".amount" |tr -d '"')))
    if [[ $Curr_Lck_Stake -eq 0 ]];then
        Curr_Lck_Stake=$(($($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".remainingAmount" |tr -d '"')))
    fi
    Lck_Start_Time=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".lastWithdrawalTime" |tr -d '"')
    Lck_Held_For=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getParticipantInfo -p "{\"addr\":$Curr_Part_Addr}" --decode-c6 $dpc_addr|grep -i 'withdrawValue' | jq ".locks.\"$Hex_Curr_Round_ID\".withdrawalPeriod" |tr -d '"')
    Lck_Out_DateTime="$(echo $((Lck_Start_Time + Lck_Held_For)) | gawk '{print strftime("%Y-%m-%d %H:%M:%S", $1)}')"
    LockInfo=""
    if [[ $Curr_Lck_Stake -ne 0 ]];then
        LockInfo="; Lock: $((Curr_Lck_Stake / 1000000000)) will out: $Lck_Out_DateTime"
    fi

    #--------------------------------------------
    echo -e "$(printf '%4d' $(($i + 1))) $Curr_Part_Addr Reward: $RWRD_Info ; Stakes(${REINV_Info}): $POS_Info / $COS_Info / $NOS_Info $LockInfo $Wtdr_Val_Info"
    #--------------------------------------------
done

echo
echo "INFO: $(basename "$0") FINISHED $(date +%s) / $(date)"
echo "============================================================================================"

trap - EXIT
exit 0

