#!/bin/bash
# (C) Sergey Tyurin  2020-12-15 19:00:00

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

NormText="\e[0m"
RedBlink="\e[5;101m"
GreeBack="\e[42m"
BlueBack="\e[44m"
RedBack="\e[41m"
YellowBack="\e[43m"
BoldText="\e[1m"


ValidatorAssuranceT=50000
MinStakeT=10
ParticipantRewardFraction=95
BalanceThresholdT=20

#===========================================================
# DePool_2020_12_08
# Code from commit 94bff38f9826a19a8ae55d5b48528912f21b3919
DP_2020_12_08_MD5='8cca5ef28325e90c46ad9b0e35951d21'
#-----------------------------------------------------------
# DePool_2020_12_08
# Code from commit a49c96de2c22c0047a9c9d04e0d354d3b22d5937 
DP_2020_12_11_MD5='206929ca364fd8fa225937ada19f30a0'
DP_Proxy_2020_12_11_MD5="3b8e08ffc4cff249e1d33ece9587fcc3"
#-----------------------------------------------------------
CurrDP_MD5=$DP_2020_12_11_MD5
CurrProxy_MD5=$DP_Proxy_2020_12_11_MD5

echo
echo "#################################### DePool deploy script ########################################"
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"
echo 
echo "DP_2020_12_11_MD5       = $DP_2020_12_11_MD5"
echo "DP_Proxy_2020_12_11_MD5 = $DP_Proxy_2020_12_11_MD5"
echo

#===========================================================
# NETWORK INFO
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


#===========================================================
# check tonos-cli version
TC_VER="$($CALL_TC deploy --help | grep 'Can be passed via a filename')"
[[ -z $TC_VER ]] && echo "###-ERROR(line $LINENO): You have to Update tonos-cli" && exit 1
echo
$CALL_TC deploy --help | grep 'tonos-cli-deploy'

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
        GetMD5="md5sum --tag"
else
        GetMD5="md5"
fi

#========= Depool Deploy Parametrs ================================
echo 
echo "================= Deploy DePool contract =========================="

MinStake=`$CALL_TC convert tokens ${MinStakeT} | grep "[0-9]"`

ValidatorAssurance=`$CALL_TC convert tokens ${ValidatorAssuranceT} | grep "[0-9]"`

ProxyCode="$($CALL_TL decode --tvc ${DSCs_DIR}/DePoolProxy.tvc |grep 'code: ' | awk '{print $2}')"
[[ -z $ProxyCode ]] && echo "###-ERROR(line $LINENO): DePoolProxy.tvc not found in ${DSCs_DIR}/DePoolProxy.tvc" && exit 1

DepoolCode="$($CALL_TL decode --tvc ${DSCs_DIR}/DePool.tvc |grep 'code: ' | awk '{print $2}')"
[[ -z $DepoolCode ]] && echo "###-ERROR(line $LINENO): DePool.tvc not found in ${DSCs_DIR}/DePool.tvc" && exit 1
VrfDepoolCode=${DepoolCode:0:64}

DePoolMD5=$($GetMD5 ${DSCs_DIR}/DePool.tvc |awk '{print $4}')
if [[ ! "${DePoolMD5}" == "${CurrDP_MD5}" ]];then
    echo "###-ERROR(line $LINENO): DePool.tvc is not right version!! Can't continue"
    exit 1
fi

ProxyMD5=$($GetMD5 ${DSCs_DIR}/DePoolProxy.tvc |awk '{print $4}')
if [[ ! "${ProxyMD5}" == "${CurrProxy_MD5}" ]];then
    echo "###-ERROR(line $LINENO): DePoolProxy.tvc is not right version!! Can't continue"
    exit 1
fi


Validator_addr=`cat ${KEYS_DIR}/${HOSTNAME}.addr`
[[ -z $Validator_addr ]] && echo "###-ERROR(line $LINENO): Validator address not found in ${KEYS_DIR}/${HOSTNAME}.addr" && exit 1


# BalanceThreshold=`$CALL_TC convert tokens ${BalanceThresholdT} | grep "[0-9]"`
# echo "BalanceThreshold $BalanceThresholdT in nanoTon:  $BalanceThreshold"
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
Depoo_Keys=${KEYS_DIR}/${Depool_Name}.keys.json
Depool_Public_Key=`cat $Depoo_Keys | jq ".public" | tr -d '"'`
[[ -z $Depool_Public_Key ]] && echo "###-ERROR(line $LINENO): Depool_Public_Key not found in ${KEYS_DIR}/${Depool_Name}.keys.json" && exit 1

#===========================================================
# Check DePool Address
DP_ADDR_from_Keys=$($CALL_TC genaddr ${DSCs_DIR}/DePool.tvc ${DSCs_DIR}/DePool.abi.json --setkey $Depoo_Keys --wc "0" | grep "Raw address:" | awk '{print $3}')
if [[ ! "$Depool_addr" == "$DP_ADDR_from_Keys" ]];then
    echo "###-ERROR(line $LINENO): Given DePool Address and calculated address is different. Possible you prepared it for another contract. "
    echo "Given addr: $Depool_addr"
    echo "Calc  addr: $DP_ADDR_from_Keys"
    echo 
    exit 1
fi

#===========================================================
# print INFO
echo "Validator_addr:    $Validator_addr"
echo "Depool Address:    $Depool_addr"
echo "Depool_Public_Key: $Depool_Public_Key"
echo
echo "Minimal Stake:                $MinStakeT"
echo "ParticipantRewardFraction:    $ParticipantRewardFraction"
echo "ValidatorAssurance:           $ValidatorAssuranceT"
echo
echo "DePool MD5 sum:                 $DePoolMD5"
echo "DePool Proxy MD5 sum:           $ProxyMD5"
echo "First 64 syms from DePoolCode:  ${VrfDepoolCode}"
echo "First 64 syms from ProxyCode:   ${ProxyCode:0:64}"

#===========================================================


#===========================================================
# check depool balance

Depool_INFO=`$CALL_TC account ${Depool_addr}`
Depool_AMOUNT=`echo "$Depool_INFO" |grep 'balance:' | awk '{print $2}'`
Depool_Status=`echo "$Depool_INFO" | grep 'acc_type:' |awk '{print $2}'`

if [[ $Depool_AMOUNT -lt $((BalanceThreshold * 2  + 5000000000)) ]];then
    echo "###-ERROR(line $LINENO): You have not anought balance on depool address!"
    echo "It should have at least $((BalanceThresholdT * 2  + 5)), but now it has $((Depool_AMOUNT))"
    exit 1
fi

if [[ ! "$Depool_Status" == "Uninit" ]];then
    echo "###-ERROR(line $LINENO): Depool_Status not 'Uninit'. Already deployed?"
    exit 1
fi
echo "Depool balance: $((Depool_AMOUNT/1000000000)) ; status: $Depool_Status"
echo
#===========================================================
read -p "### CHECK INFO TWICE!!! Is this a right Parameters? Think once more!  (yes/n)? " </dev/tty answer
case ${answer:0:3} in
    yes|YES )
        echo
        echo "Processing....."
    ;;
    * )
        echo
        echo "If you absolutely sure, type 'yes' "
        echo "Cancelled."
        exit 1
    ;;
esac
#===========================================================
# exit 0
# from https://docs.ton.dev/86757ecb2/v/0/p/37a848-run-depool/t/019261 :
# tonos-cli deploy DePool.tvc 
#   '{
#     "minStake":*number*
#     "validatorAssurance":*number*,
#     "proxyCode":"<ProxyContractCodeInBase64>",
#     "validatorWallet":"<validatorWalletAddress>",
#     "participantRewardFraction":*number*,
#   }' 
#   --abi DePool.abi.json 
#   --sign depool.json --wc 0

echo "{\"minStake\":$MinStake,\"validatorAssurance\":$ValidatorAssurance,\"proxyCode\":\"$ProxyCode\",\"validatorWallet\":\"$Validator_addr\",\"participantRewardFraction\":$ParticipantRewardFraction}"

tonos-cli deploy ${DSCs_DIR}/DePool.tvc \
    "{\"minStake\":$MinStake,\"validatorAssurance\":$ValidatorAssurance,\"proxyCode\":\"$ProxyCode\",\"validatorWallet\":\"$Validator_addr\",\"participantRewardFraction\":$ParticipantRewardFraction}" \
    --abi ${DSCs_DIR}/DePool.abi.json \
    --sign ${KEYS_DIR}/${Depool_Name}.keys.json --wc 0 | tee ${KEYS_DIR}/${Depool_Name}_depool-deploy.log

echo "================= Deploy Done =========================="
echo 
exit 0
