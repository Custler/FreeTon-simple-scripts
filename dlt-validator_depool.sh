#!/bin/bash

# (C) Sergey Tyurin  2020-11-16 15:00:00

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

if [ "$DEBUG" = "yes" ]; then
    set -x
fi

####################################
# we can't work on desynced node
TIMEDIFF_MAX=100
MAX_FACTOR=${MAX_FACTOR:-3}
####################################

echo
echo "#################################### Participate script ########################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

#=================================================
# Test binaries
if [[ -z $($HOME/bin/tvm_linker -V | grep "TVM linker") ]];then
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
# NOTE: Avoid double quoting  - ""0xXXXXX"" in input var
function hex2dec() {
    local OS_SYSTEM=`uname`
    local ival="$(echo ${1^^}|tr -d '"')"
    if [[ -z $ival ]]; then
        printf ""
        return
    fi
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
        echo "###-ERROR(line $LINENO):
 Cannot get account state. Can't continue. Sorry."
        exit 1
    fi
    echo "$LC_OUTPUT"
}

#=================================================
# Load addresses and set variables
Depool_addr=`cat ${KEYS_DIR}/depool.addr`
dpc_addr=`echo $Depool_addr | cut -d ':' -f 2`

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
echo "INFO: validator account address: $Validator_addr / $val_acc_addr"
echo "INFO: depool   contract address: $Depool_addr / $dpc_addr"
ELECTIONS_WORK_DIR="${KEYS_DIR}/elections"
[[ ! -d ${ELECTIONS_WORK_DIR} ]] && mkdir -p ${ELECTIONS_WORK_DIR}
chmod +x ${ELECTIONS_WORK_DIR}

# ~/net.ton.dev/ton-labs-contracts/solidity/depool/DePool.abi.json
DSCs_DIR="$NET_TON_DEV_SRC_TOP_DIR/ton-labs-contracts/solidity/depool"

CALL_LC="${TON_BUILD_DIR}/lite-client/lite-client -p ${KEYS_DIR}/liteserver.pub -a 127.0.0.1:3031 -t 5"
CALL_VC="${TON_BUILD_DIR}/validator-engine-console/validator-engine-console -k ${KEYS_DIR}/client -p ${KEYS_DIR}/server.pub -a 127.0.0.1:3030 -t 5"
CALL_FIFT="${TON_BUILD_DIR}/crypto/fift -I ${TON_SRC_DIR}/crypto/fift/lib:${TON_SRC_DIR}/crypto/smartcont"

##############################################################################
# prepare user signature for lt
touch $val_acc_addr
msig_public=`cat ${KEYS_DIR}/msig.keys.json | jq ".public" | tr -d '"'`
msig_secret=`cat ${KEYS_DIR}/msig.keys.json | jq ".secret" | tr -d '"'`
if [[ -z $msig_public ]] || [[ -z $msig_secret ]];then
    echo "###-ERROR(line $LINENO): Can't find validator public and/or secret key!"
    exit 1
fi
echo "${msig_secret}${msig_public}" > ${KEYS_DIR}/msig.keys.txt
rm -f ${KEYS_DIR}/msig.keys.bin
xxd -r -p ${KEYS_DIR}/msig.keys.txt ${KEYS_DIR}/msig.keys.bin

##############################################################################
# Check node sync
trap 'echo VC EXIT' EXIT
VEC_OUTPUT=`$CALL_VC -c "getstats" -c "quit"`
trap - EXIT

CURR_TD_NOW=`echo "${VEC_OUTPUT}" | grep unixtime | awk '{print $2}'`
CHAIN_TD=`echo "${VEC_OUTPUT}" | grep masterchainblocktime | awk '{print $2}'`
TIME_DIFF=$((CURR_TD_NOW - CHAIN_TD))
if [[ $TIME_DIFF -gt $TIMEDIFF_MAX ]];then
    echo "###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF"
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF" 2>&1 > /dev/null
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
# get elections ID from elector
trap 'echo LC TIMEOUT EXIT' EXIT
election_id=`$CALL_LC -rc "runmethod $elector_addr active_election_id" -rc "quit" 2>/dev/null | grep "result:" | awk '{print $3}' | tee ${ELECTIONS_WORK_DIR}/election-id`
trap - EXIT
echo "INFO:      Election ID: $election_id"

if [[ ! -z $election_id ]] && [[ ! -f ${ELECTIONS_WORK_DIR}/$election_id ]];then
  touch ${ELECTIONS_WORK_DIR}/$election_id
  echo "Election ID: $election_id" >> ${ELECTIONS_WORK_DIR}/$election_id
  echo "Elector address: $elector_addr" >> ${ELECTIONS_WORK_DIR}/$election_id
fi

##############################################################################
# Save DePool contract state to file
echo -n "Get SC state of depool: $Depool_addr ... "    
LC_OUTPUT="$(Get_SC_current_state "$Depool_addr")"
result=`echo $LC_OUTPUT | grep "written StateInit of account"`
if [[ -z  $result ]];then
    echo "###-ERROR(line $LINENO): Cannot get account state. Can't continue. Sorry."
    exit 1
fi
echo "Done."

##############################################################################
# Get proxy adrrs from depool
Current_Depool_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getDePoolInfo -p "{}" --decode-c6 $dpc_addr|grep -i 'validatorWallet')
dp_val_wal=$(echo "$Current_Depool_Info" | jq ".validatorWallet")
dp_proxy0=$(echo "$Current_Depool_Info" | jq "[.proxies[]]|.[0]"|tr -d '"')
dp_proxy1=$(echo "$Current_Depool_Info" | jq "[.proxies[]]|.[1]"|tr -d '"')

if [[ -z $dp_proxy0 ]] || [[ -z $dp_proxy1 ]];then
    echo "###-ERROR(line $LINENO): Cannot get proxies from depool contract. Can't continue. Exit" 
    exit 1
fi

echo "$dp_proxy0" > ${KEYS_DIR}/proxy0.addr
echo "$dp_proxy1" > ${KEYS_DIR}/proxy1.addr

##############################################################################
# get info from DePool contract state
Curr_Rounds_Info=$($CALL_TL test -a ${DSCs_DIR}/DePool.abi.json -m getRounds -p "{}" --decode-c6 $dpc_addr | grep -i 'rounds')

Round_0_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[0].id"|tr -d '"'| xargs printf "%d\n")
Round_1_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[1].id"|tr -d '"'| xargs printf "%d\n")
Round_2_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[2].id"|tr -d '"'| xargs printf "%d\n")
Round_3_ID=$(echo "$Curr_Rounds_Info" | jq "[.rounds[]]|.[3].id"|tr -d '"'| xargs printf "%d\n")

declare -a rounds=($(($Round_0_ID)) $(($Round_1_ID)) $(($Round_2_ID)) $(($Round_3_ID)))
IFS=$'\n' Rounds_Sorted=($(sort <<<"${rounds[*]}")); unset IFS

Mid_Round_ID=${Rounds_Sorted[1]}
Curr_Round_Num=$((Mid_Round_ID - Round_0_ID))

Curr_DP_Elec_ID=$($HOME/bin/tvm_linker test -a ${DSCs_DIR}/DePool.abi.json -m getRounds -p "{}" --decode-c6 $dpc_addr|grep rounds|jq "[.rounds[]]|.[$Curr_Round_Num].supposedElectedAt"|tr -d '"'| xargs printf "%d\n")
echo "Elections ID in depool: $Curr_DP_Elec_ID"

echo "  Round ID from depool: $Mid_Round_ID"

Proxy_ID=$((Mid_Round_ID % 2))

File_Round_Proxy="`cat ${KEYS_DIR}/proxy${Proxy_ID}.addr`"
echo "Proxy addr   from file: $File_Round_Proxy"
[[ -z $File_Round_Proxy ]] && echo "###-ERROR(line $LINENO) Cannot get proxy for this round from file. Can't continue. Exit" && exit 1

DP_Round_Proxy=$($HOME/bin/tvm_linker test -a ${DSCs_DIR}/DePool.abi.json -m getDePoolInfo -p "{}" --decode-c6 $dpc_addr|grep "proxies"|jq ".proxies[$Proxy_ID]"|tr -d '"')
echo "Proxy addr from depool: $DP_Round_Proxy"
[[ -z $DP_Round_Proxy ]] && echo "###-ERROR(line $LINENO) Cannot get proxy for this round from depool contract. Can't continue. Exit" && exit 1

########################################################################################
# Check election conditions

if [[ $election_id == 0 ]]; then
    date +"INFO: %F %T No current elections"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit 1
fi

if [[ -f "${ELECTIONS_WORK_DIR}/stop-election" ]]; then
    date +"INFO: %F %T Election stopped"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit 1
fi

if [[ $election_id -ne $Curr_DP_Elec_ID ]]; then
    echo "###-ERROR(line $LINENO): Current elections ID from elector $election_id ($(TD_unix2human "$election_id")) is not equal elections ID from DP: $Curr_DP_Elec_ID ($(TD_unix2human "$Curr_DP_Elec_ID"))"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit 1
fi

#####################################################################################
# Check in participant list
# public key : [ stake, max_factor, wallet (addr), adnl (adnl_addr) ]
echo "INFO: Check you participate already ... "
Curr_ADNL_Key=`cat ${ELECTIONS_WORK_DIR}/$election_id | grep "ADNL key:" | awk '{print $3}'`
Dec_Curr_ADNL_Key=$(hex2dec "$Curr_ADNL_Key")
dec_val_acc_addr=$(hex2dec "$val_acc_addr")
h_dprp=$(echo $DP_Round_Proxy | cut -d ":" -f 2)
dec_proxy_addr=$(hex2dec "$h_dprp")

# check in participant list by proxy account address
trap 'echo LC TIMEOUT EXIT' EXIT
LC_OUTPUT="$($CALL_LC -rc "runmethodfull $elector_addr participant_list_extended" -rc "quit" 2>/dev/null | grep 'result:' | tr "]]" "\n" | tr '[' '\n' | awk 'NF > 0'| tee ${ELECTIONS_WORK_DIR}/Curr-Validator.lst)"
trap - EXIT

ADDR_FOUND=`echo "${LC_OUTPUT}"  | grep "$dec_proxy_addr" | awk '{print $3}'`

if [[ ! -z $ADDR_FOUND ]];then
    echo
    echo "INFO: You participate already in this elections ($election_id)"
    Your_Stake=`echo "${LC_OUTPUT}" | grep "$dec_proxy_addr" | awk '{print $1 / 1000000000}'`
    Your_ADNL=`echo "${LC_OUTPUT}"  | grep "$dec_proxy_addr" | awk '{print $4}'`
    echo "---INFO: Your stake: $Your_Stake with ADNL: $(echo "$Curr_ADNL_Key" | tr "[:upper:]" "[:lower:]")"
    echo
    exit 1
fi

# check in participant list by ADNL key
if [[ ! -z $Curr_ADNL_Key ]];then
    trap 'echo LC TIMEOUT EXIT' EXIT
    LC_OUTPUT="$($CALL_LC -rc "runmethodfull $elector_addr participant_list_extended" -rc "quit" 2>/dev/null | grep 'result:' | tr "]]" "\n" | tr '[' '\n' | awk 'NF > 0')"
    trap - EXIT
    Found_ADNL=`echo "${LC_OUTPUT}" | grep "$Dec_Curr_ADNL_Key" | awk '{print $4}'`
    if [[ -z $Found_ADNL ]];then
        echo "INFO: Current ADNL: $Curr_ADNL_Key / $Dec_Curr_ADNL_Key"
        echo "INFO: You ADNL not found in curreent participant list. Let's go to elections..."
    else
        Your_Stake=`echo "${LC_OUTPUT}" | grep "$Dec_Curr_ADNL_Key" | awk '{print $1 / 1000000000}'`
    echo
    echo "INFO: You are already participating in this elections ($election_id)"
        echo "---INFO: Your stake: $Your_Stake and ADNL: $(echo "$Curr_ADNL_Key" | tr "[:upper:]" "[:lower:]")"
        exit 1
    fi
else
    echo "INFO: This is your first try for elections ID: $election_id ..."
fi

#=================================================
# Check keys in the engine

VC_OUTPUT=`$CALL_VC -c "getvalidators" -c "quit" 2>/dev/null | tee "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-current-engine-keys"`
Engine_elecID=$(echo "$VC_OUTPUT" | grep "validator0" | grep -i "adnl" | cut -d " " -f 2)

if [[ -z $Engine_elecID ]];then
    echo "$VC_OUTPUT"
fi

#if [[ $Engine_elecID -eq  $election_id]];then
#fi

#Engine_ADNL="$(echo "$VC_OUTPUT"  | grep "validator0" | grep -i "adnl" | cut -d " " -f 4)"

########################################################################################
# Prepare for elections
date +"INFO: %F %T Current elections ID: $election_id"
cp "${ELECTIONS_WORK_DIR}/election-id" "${ELECTIONS_WORK_DIR}/active-election-id"

#=================================================
# Get Elections parametrs (p15)
echo "INFO: Get elections parametrs (p15)"
trap 'echo LC TIMEOUT EXIT' EXIT
CONFIG_PAR_15=`$CALL_LC -rc "getconfig 15" -rc "quit" 2>/dev/null |tee "${ELECTIONS_WORK_DIR}/elector-params" | grep -i "ConfigParam(15)"`
trap - EXIT
validators_elected_for=`echo $CONFIG_PAR_15 | awk '{print $4}'| awk -F ":" '{print $2}'`
elections_start_before=`echo $CONFIG_PAR_15 | awk '{print $5}'| awk -F ":" '{print $2}'`
elections_end_before=`echo $CONFIG_PAR_15   | awk '{print $6}'| awk -F ":" '{print $2}'`
stake_held_for=`echo $CONFIG_PAR_15         | awk '{print $7}'| awk -F ":" '{print $2}' | tr -d ')'`
if [[ -z $validators_elected_for ]] || [[ -z $elections_start_before ]] || [[ -z $elections_end_before ]] || [[ -z $stake_held_for ]];then
    echo "###-ERROR(line $LINENO): Get network election params (p15) FAILED!!!"
    exit 1
fi
#=================================================
# Generate node new pubkey for next elections
echo "INFO: Generate new elections key ..."
NewElectionKey=`cat ${ELECTIONS_WORK_DIR}/$election_id | grep "Elections key:" | awk '{print $3}'` 
if [[ -z $NewElectionKey ]];then
    trap 'echo VC TIMEOUT EXIT' EXIT
    NewElectionKey=`$CALL_VC -c "newkey" -c "quit" 2>/dev/null | tee "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-key" | grep "created new key" | awk '{print $4}'`
    trap - EXIT
    if [[ -z $NewElectionKey ]];then
        echo "###-E RROR: Generate new election key FAILED!!!"
        exit 1
    fi
    echo "Elections key: $NewElectionKey" >> ${ELECTIONS_WORK_DIR}/$election_id
else
    echo "INFO: New election key generated alredy."
fi
echo "INFO: New election key: $NewElectionKey"
NewElectionKey=`cat ${ELECTIONS_WORK_DIR}/$election_id | grep "Elections key:" | awk '{print $3}'`
#=================================================
# Generate node new ADNL for next elections
echo "INFO: Generate new ADNL key ..."
New_ADNL_Key=`cat ${ELECTIONS_WORK_DIR}/$election_id | grep "ADNL key:" | awk '{print $3}'` 
if [[ -z $New_ADNL_Key ]];then
    trap 'echo VC TIMEOUT EXIT' EXIT
    New_ADNL_Key=`$CALL_VC -c "newkey" -c "quit" 2>/dev/null | tee "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-adnl-key" | grep "created new key" | awk '{print $4}'`
    trap - EXIT
    if [[ -z $New_ADNL_Key ]];then
        echo "###-ERROR(line $LINENO): Generate new ADNL key FAILED!!!"
        exit 1
    fi
    echo "ADNL key: $New_ADNL_Key" >> ${ELECTIONS_WORK_DIR}/$election_id
else
    echo "INFO: New ADNL key generated alredy."
fi
echo "INFO: New ADNL key: $New_ADNL_Key"


#=================================================
# run1.1
# Add new keys to engine
echo "INFO: Add new keys to engine ..."
Validating_Start=${election_id}
Validating_Stop=$(( ${Validating_Start} + 1000 + ${validators_elected_for} + ${elections_start_before} + ${elections_end_before} + ${stake_held_for} ))
echo "Validating_Start: $Validating_Start | Validating_Stop: $Validating_Stop"

trap 'echo VC TIMEOUT EXIT' EXIT
VC_OUTPUT=`$CALL_VC \
    -c "addpermkey $NewElectionKey $Validating_Start $Validating_Stop" \
    -c "addtempkey $NewElectionKey $NewElectionKey $Validating_Stop" \
    -c "addadnl $New_ADNL_Key 0" \
    -c "addvalidatoraddr $NewElectionKey $New_ADNL_Key $Validating_Stop" \
    -c "quit"` | tee ${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-engine-add-keys-log
trap - EXIT

if [[ ! -z $(echo "$VC_OUTPUT" | grep "duplicate election date") ]];then
    echo "###-WARNING(line $LINENO): New keys was added to engine already !!!"
fi
echo "INFO: Add new keys to engine ... DONE"
#=================================================
# run1.2
# make request SC signature
SC_Signature=$($CALL_FIFT -s validator-elect-req.fif $DP_Round_Proxy $Validating_Start $MAX_FACTOR $New_ADNL_Key \
        ${ELECTIONS_WORK_DIR}/validator-to-sign.bin \
        | tee "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-lt-request-dump" \
        | sed -n 2p)

if [[ -z $SC_Signature ]];then
    echo "###-ERROR(line $LINENO): validator-elect-req.fif NOT processed !!! Can't continue."
    exit 1
else
    echo "INFO: validator-elect-req.fif: $SC_Signature "
fi

#=================================================
# run2
# Signing New Public_Key
echo "INFO: Signing New Public_Key ..."
trap 'echo VC TIMEOUT EXIT' EXIT
VC_OUTPUT=$($CALL_VC \
    -c "exportpub $NewElectionKey" \
    -c "sign $NewElectionKey $SC_Signature" \
    -c "quit" \
    | tee  "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-lt-request-dump1")
trap - EXIT
Public_Key=`echo "${VC_OUTPUT}" | grep "got public key" | awk '{print $4}'`
Signature=`echo "${VC_OUTPUT}" | grep "got signature" | awk '{print $3}'`

if [[ -z $Public_Key ]] || [[ -z $Signature ]];then
    echo "###-ERROR(line $LINENO): Signing  NewElectionKey FAILED!!! Can't continue."
    exit 1
fi

echo "INFO: Public_Key: $Public_Key"
echo "INFO: Signature:  $Signature"
echo "INFO: Signing New Public_Key ... DONE "

#=================================================
# run3
# Create validator-query.boc
echo "INFO: Create validator-query.boc ..."
FIFT_OUTPUT=$($CALL_FIFT -s validator-elect-signed.fif $DP_Round_Proxy $Validating_Start $MAX_FACTOR $New_ADNL_Key $Public_Key $Signature \
    ${ELECTIONS_WORK_DIR}/validator-query.boc \
    | tee "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-lt-request-dump2" )


if [[ -z $(echo "$FIFT_OUTPUT" | grep "Message body is" | awk '{print $4}') ]];then
    echo "###-ERROR(line $LINENO): ${ELECTIONS_WORK_DIR}/validator-query.boc NOT created!!! Can't continue"
    exit 1
else
    echo "INFO: ${ELECTIONS_WORK_DIR}/validator-query.boc Created"
fi

######################################################################################################
# prepare validator query to elector contract using multisig for lite-client

validator_query_payload=$(base64 "${ELECTIONS_WORK_DIR}/validator-query.boc" |tr -d "\n")
# ===============================================================
# parameters checks
if [[ -z $validator_query_payload ]];then
    echo "###-ERROR(line $LINENO): Payload is empty! It is unasseptable!"
    echo "did you have right validator-query.boc ?"
    exit 2
fi

if [[ -z $val_acc_addr ]];then
    echo "###-ERROR(line $LINENO): Validator Address empty! It is unasseptable!"
    echo "Check keys files."
    exit 2
fi

if [[ -z $Depool_addr ]];then
    echo "###-ERROR(line $LINENO): Depool Address empty! It is unasseptable!"
    exit 2
fi

if [[ ! -f ${KEYS_DIR}/msig.keys.bin ]];then
    echo "###-ERROR(line $LINENO): ${KEYS_DIR}/msig.keys.bin NOT FOUND! Can't continue"
    exit 2
fi

if [[ ! -f ${CONFIGS_DIR}/SafeMultisigWallet.abi.json ]];then
    echo "###-ERROR(line $LINENO): ${CONFIGS_DIR}/SafeMultisigWallet.abi.json NOT FOUND! Can't continue"
    exit 2
fi

# ===============================================================
# make boc for lite-client
NANOSTAKE=$((1 * 1000000000))
echo "INFO: Make boc for lite-client ..."
TVM_OUTPUT=$($HOME/bin/tvm_linker message $val_acc_addr \
    -a ${CONFIGS_DIR}/SafeMultisigWallet.abi.json \
    -m submitTransaction \
    -p "{\"dest\":\"$Depool_addr\",\"value\":$NANOSTAKE,\"bounce\":true,\"allBalance\":false,\"payload\":\"$validator_query_payload\"}" \
    -w $Work_Chain --setkey ${KEYS_DIR}/msig.keys.bin | tee ${ELECTIONS_WORK_DIR}/TVM_linker-valquery.log)

if [[ -z $(echo $TVM_OUTPUT | grep "boc file created") ]];then
    echo "###-ERROR(line $LINENO): TVM linker CANNOT create boc file!!! Can't continue."
    exit 3
fi

mv "$(echo "$val_acc_addr"| cut -c 1-8)-msg-body.boc" "${ELECTIONS_WORK_DIR}/vaidator-msg.boc"
echo "INFO: Make boc for lite-client ... DONE"

#####################################################################################################
###############  Send query by lite-client ##########################################################
#####################################################################################################

echo "INFO: Send query to Elector by lite-client ..."

trap 'echo LC TIMEOUT EXIT' EXIT
$CALL_LC -rc "sendfile ${ELECTIONS_WORK_DIR}/vaidator-msg.boc" -rc 'quit' &> ${ELECTIONS_WORK_DIR}/validator-req-result.log
trap - EXIT

vr_result=`cat ${ELECTIONS_WORK_DIR}/validator-req-result.log | grep "external message status is 1"`

if [[ -z $vr_result ]]; then
    echo "###-ERROR(line $LINENO): Send message for eletction FAILED!!!"
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "###-ERROR(line $LINENO): Send message for eletction FAILED!!!" 2>&1 > /dev/null
    exit 4
fi

echo "INFO: Submit transaction for elections was done SUCCESSFULLY!"

FUTURE_CYCLE_ADNL=`echo $New_ADNL_Key | tr "[:upper:]" "[:lower:]"`
echo "INFO: Sent $STAKE for elections. ADNL: $FUTURE_CYCLE_ADNL"

# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Sent $STAKE for elections. ADNL: $FUTURE_CYCLE_ADNL" 2>&1 > /dev/null

date +"INFO: %F %T prepared for elections"
echo "INFO: $(basename "$0") FINISHED $(date +%s) / $(date)"

trap - EXIT
exit 0

