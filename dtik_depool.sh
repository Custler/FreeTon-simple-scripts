#!/bin/bash -eE

# (C) Sergey Tyurin  2020-11-29 16:00:00

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
#   'tvm_linker' compiled binary from https://github.com/tonlabs/TVM-linker.git to $HOME/bin (must be in $PATH)
#   'lite-client'                                               
# ------------------------------------------------------------------------
# Script assumes that: 
#   - all keypairs are in ${KEYS_DIR} folder
#   - Tik account is SafeMultisigWallet with one custodian
#   - Tik.addr - file with addr of Tik account
#   - Tik.keys.json - keypair of Tik account
#   - Depool address is in depool.addr file
#   - If you want to tik other depool address, the address should be in file <depool name>.addr in KEYS_DIR
#     and usage will ./dtik_depool.sh <depool name>
# ------------------------------------------------------------------------

# set -x

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

###################
TIMEDIFF_MAX=100
SLEEP_TIMEOUT=10
SEND_ATTEMPTS=10
###################

echo
echo "#################################### Tik depool script ########################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

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
# ===================================================
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
# Addresses and vars
Depool_Name=$1
Depool_Name=${Depool_Name:-"depool"}
Depool_addr=`cat ${KEYS_DIR}/${Depool_Name}.addr`
if [[ -z $Depool_addr ]];then
    echo
    echo "###-ERROR(line $LINENO): Cannot find depool address in file  ${KEYS_DIR}/${Depool_Name}.addr"
    echo
    exit 1
fi
dpc_addr=`echo $Depool_addr | cut -d ':' -f 2`


Tik_addr=`cat ${KEYS_DIR}/Tik.addr`
Tik_Keys_File="${KEYS_DIR}/Tik.keys.json"
if [[ -z $Tik_addr ]];then
    echo
    echo "###-ERROR(line $LINENO): Cannot find Tik acc address in file  ${KEYS_DIR}/Tik.addr"
    echo
    exit 1
fi

Work_Chain=`echo "${Tik_addr}" | cut -d ':' -f 1`

ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"
mkdir -p $ELECTIONS_WORK_DIR

Tik_Payload="te6ccgEBAQEABgAACCiAmCM="
NANOSTAKE=$((1 * 1000000000))

#=================================================
# prepare user signature
tik_acc_addr=`echo "${Tik_addr}" | cut -d ':' -f 2`
touch $tik_acc_addr
tik_public=`cat $Tik_Keys_File | jq ".public" | tr -d '"'`
tik_secret=`cat $Tik_Keys_File | jq ".secret" | tr -d '"'`
if [[ -z $tik_public ]] || [[ -z $tik_secret ]];then
    echo "###-ERROR(line $LINENO): Can not find Tik public and/or secret key!"
    exit 1
fi
echo "${tik_secret}${tik_public}" > ${KEYS_DIR}/tik.keys.txt
rm -f ${KEYS_DIR}/tik.keys.bin
xxd -r -p ${KEYS_DIR}/tik.keys.txt ${KEYS_DIR}/tik.keys.bin

#=================================================
# get elector address
trap 'echo LC TIMEOUT EXIT' EXIT
elector_addr=`$CALL_LC -rc "getconfig 1" -rc "quit" 2>/dev/null | grep -i 'ConfigParam(1)' | awk '{print substr($4,15,64)}'`
trap - EXIT
elector_addr=`echo "-1:${elector_addr}"`
echo "INFO: Elector Address: $elector_addr"

#=================================================
# Get elections ID
trap 'echo LC TIMEOUT EXIT' EXIT
elections_id=`$CALL_LC -rc "runmethod $elector_addr active_election_id" -rc "quit" 2>/dev/null | grep "result:" | awk '{print $3}'`
trap - EXIT
echo "INFO:      Election ID: $elections_id"

if [[ -z $elections_id ]];then
    echo "~~~WARN(line $LINENO):There is no elections now!"
    echo "We will just spend tokens"
fi

#=================================================
# make boc for lite-client
echo "INFO: Make boc for lite-client ..."
TVM_OUTPUT=$($CALL_TL message $tik_acc_addr -a $SafeC_Wallet_ABI -m submitTransaction \
    -p "{\"dest\":\"$Depool_addr\",\"value\":$NANOSTAKE,\"bounce\":true,\"allBalance\":false,\"payload\":\"$Tik_Payload\"}" \
    -w $Work_Chain --setkey ${KEYS_DIR}/tik.keys.bin \
    | tee ${ELECTIONS_WORK_DIR}/TVM_linker-tikquery.log)

if [[ -z $(echo $TVM_OUTPUT | grep "boc file created") ]];then
    echo "###-ERROR(line $LINENO): TVM linker CANNOT create boc file!!! Can't continue."
    exit 2
fi

mv "$(echo "$tik_acc_addr"| cut -c 1-8)-msg-body.boc" "${ELECTIONS_WORK_DIR}/tik-msg.boc"
echo "INFO: Make boc for lite-client ... DONE"


##############################################################################
###############  Send query by lite-client ###################################
##############################################################################
Last_Trans_lt=$($CALL_LC -rc "getaccount ${Depool_addr}" -t "3" -rc "quit" 2>/dev/null |grep 'last transaction lt'|awk '{print $5}')

echo "INFO: Send query to Depool by lite-client ..."

Attempts_to_send=$SEND_ATTEMPTS
while [[ $Attempts_to_send -gt 0 ]]; do

    $CALL_LC -rc "sendfile ${ELECTIONS_WORK_DIR}/tik-msg.boc" -rc 'quit' &> ${ELECTIONS_WORK_DIR}/tik-req-result-${Attempts_to_send}.log
    vr_result=`cat ${ELECTIONS_WORK_DIR}/tik-req-result-${Attempts_to_send}.log | grep "external message status is 1"`
    if [[ -z $vr_result ]]; then
        echo "###-ERROR(line $LINENO): Send message for Tik FAILED!!!"
    fi
    echo "INFO: Tik-tok transaction to depool submitted!"

    echo "INFO: Check depool cranked ..."
    sleep $SLEEP_TIMEOUT

    Curr_Trans_lt=$($CALL_LC -rc "getaccount ${Depool_addr}" -rc "quit" 2>/dev/null |grep 'last transaction lt'|awk '{print $5}')
    if [[ $Curr_Trans_lt == $Last_Trans_lt ]];then
        echo "Attempt # $((SEND_ATTEMPTS + 1 - Attempts_to_send))/$SEND_ATTEMPTS"
        echo "+++-WARNING(line $LINENO): Depool does not crank up .. Repeat sending.."
        Attempts_to_send=$((Attempts_to_send - 1))
    else
        echo "INFO: Depool tiked SUCCESSFULLY!"
        break
    fi
done

if [[ Attempts_to_send -eq 0   ]];then
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "ALARM!!! Can't TIK Depool!!!" 2>&1 > /dev/null
    echo "###-=ERROR(line $LINENO): ALARM!!! Depool DOES NOT CRANKED UP!!!"
    echo "INFO: $(basename "$0") FINISHED $(date +%s) / $(date)"
    exit 3
fi

if [[ ! "$elections_id" == "0" ]];then
    #=================================================
    # Save DePool contract state to file
    echo -n "Get SC state of depool: $Depool_addr ... "    
    LC_OUTPUT="$(Get_SC_current_state "$Depool_addr")"
    result=`echo $LC_OUTPUT | grep "written StateInit of account"`
    if [[ -z  $result ]];then
        echo "###-ERROR(line $LINENO): Cannot get account state. Can't continue. Sorry."
        exit 1
    fi
    echo "Done."

    #=================================================
    # get info from DePool contract state
    Curr_Rounds_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getRounds -p "{}" --decode-c6 $dpc_addr | grep -i 'rounds')
    Current_Depool_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getDePoolInfo -p "{}" --decode-c6 $dpc_addr|grep -i 'validatorWallet')
    Round_0_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[0].id"|tr -d '"'| xargs printf "%d\n")
    Round_1_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[1].id"|tr -d '"'| xargs printf "%d\n")
    Round_2_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[2].id"|tr -d '"'| xargs printf "%d\n")
    Round_3_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[3].id"|tr -d '"'| xargs printf "%d\n")

    declare -a rounds=($(($Round_0_ID)) $(($Round_1_ID)) $(($Round_2_ID)) $(($Round_3_ID)))
    IFS=$'\n' Rounds_Sorted=($(sort -g <<<"${rounds[*]}")); unset IFS

    Mid_Round_ID=${Rounds_Sorted[1]}
    Curr_Round_Num=$((Mid_Round_ID - Round_0_ID))

    Curr_DP_Elec_ID=$($HOME/bin/tvm_linker test -a ${DSCs_DIR}/DePool.abi.json -m getRounds -p "{}" --decode-c6 $dpc_addr|grep rounds|jq "[.rounds[]]|.[$Curr_Round_Num].supposedElectedAt"|tr -d '"'| xargs printf "%d\n")
    echo "Elections ID in depool: $Curr_DP_Elec_ID"
    
    if [[ ! "$elections_id" == "$Curr_DP_Elec_ID" ]]; then
        echo "###-ERROR(line $LINENO): Current elections ID from elector $elections_id ($(TD_unix2human "$elections_id")) is not equal elections ID from DP: $Curr_DP_Elec_ID ($(TD_unix2human "$Curr_DP_Elec_ID"))"
        echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
        "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server: Depool Tik:" \
            "ALARM!!! Current elections ID from elector $elections_id ($(TD_unix2human $elections_id)) is not equal elections ID from Depool: $Curr_DP_Elec_ID ($(TD_unix2human $Curr_DP_Elec_ID))" 2>&1 > /dev/null
    fi

    #=================================================
fi 

date +"INFO: %F %T %Z Depool Tiked"
echo "INFO: $(basename "$0") FINISHED $(date +%s) / $(date)"
echo

trap - EXIT
exit 0

