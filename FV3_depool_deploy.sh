#!/bin/bash

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

ValidatorAssuranceT=100000
MinStakeT=10
ParticipantRewardFraction=95
# BalanceThresholdT=20

#===========================================================
# DePool_2020_12_08
# Code from commit 94bff38f9826a19a8ae55d5b48528912f21b3919
DP_2020_12_08_MD5='8cca5ef28325e90c46ad9b0e35951d21'
#-----------------------------------------------------------
# DePool_2020_12_08
# Code from commit a49c96de2c22c0047a9c9d04e0d354d3b22d5937 
DP_2020_12_11_MD5='206929ca364fd8fa225937ada19f30a0'

#-----------------------------------------------------------
CurrDP_MD5=$DP_2020_12_11_MD5

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
echo "================= Deploy FV1 Depool contract =========================="

MinStake=`$CALL_TC convert tokens ${MinStakeT} | grep "[0-9]"`
echo "MinStake $MinStakeT in nanoTon:  $MinStake"

ValidatorAssurance=`$CALL_TC convert tokens ${ValidatorAssuranceT} | grep "[0-9]"`
echo "ValidatorAssurance $ValidatorAssuranceT in nanoTon: $ValidatorAssurance"

ProxyCode="$($CALL_TL decode --tvc ${DSCs_DIR}/DePoolProxy.tvc |grep 'code: ' | awk '{print $2}')"
[[ -z $ProxyCode ]] && echo "###-ERROR(line $LINENO): DePoolProxy.tvc not found in ${DSCs_DIR}/DePoolProxy.tvc" && exit 1
echo "First 64 syms from ProxyCode:  ${ProxyCode:0:64}"

DepoolCode="$($CALL_TL decode --tvc ${DSCs_DIR}/DePool.tvc |grep 'code: ' | awk '{print $2}')"
[[ -z $DepoolCode ]] && echo "###-ERROR(line $LINENO): DePool.tvc not found in ${DSCs_DIR}/DePool.tvc" && exit 1
VrfDepoolCode=${DepoolCode:0:64}
echo "First 64 syms from DePoolCode:  ${VrfDepoolCode}"
DePoolMD5=$($GetMD5 ${DSCs_DIR}/DePool.tvc |awk '{print $4}')

if [[ ! "${DePoolMD5}" == "${CurrDP_MD5}" ]];then
    echo "###-ERROR(line $LINENO): DePool.tvc is not right version!! Can't continue"
    exit 1
fi

Validator_addr=`cat ${KEYS_DIR}/${HOSTNAME}.addr`
[[ -z $Validator_addr ]] && echo "###-ERROR(line $LINENO): Validator address not found in ${KEYS_DIR}/${HOSTNAME}.addr" && exit 1
echo "Validator_addr:                $Validator_addr"

echo "ParticipantRewardFraction:     $ParticipantRewardFraction"

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
echo "Depool Address:                $Depool_addr"
#===========================================================

Depoo_Keys=${KEYS_DIR}/${Depool_Name}.keys.json
Depool_Public_Key=`cat $Depoo_Keys | jq ".public" | tr -d '"'`
[[ -z $Depool_Public_Key ]] && echo "###-ERROR(line $LINENO): Depool_Public_Key not found in ${KEYS_DIR}/${Depool_Name}.keys.json" && exit 1
echo "Depool_Public_Key:              $Depool_Public_Key"

#===========================================================
# check depool balance

Depool_INFO=`$CALL_TC account ${Depool_addr}`
Depool_AMOUNT=`echo "$Depool_INFO" |grep 'balance:' | awk '{print $2}'`
Depool_Status=`echo "$Depool_INFO" | grep 'acc_type:' |awk '{print $2}'`

if [[ $Depool_AMOUNT -lt $((BalanceThreshold * 2  + 5000000000)) ]];then
    echo "###-ERROR(line $LINENO): You have not anought balance on depool address!"
    echo "You shold have $((BalanceThreshold * 2  + 5000000000)), but now it is $Depool_AMOUNT"
    exit 1
fi

if [[ ! "$Depool_Status" == "Uninit" ]];then
    echo "###-ERROR(line $LINENO): Depool_Status not 'Uninit'. Already deployed?"
    exit 1
fi
echo "Depool balance: $((Depool_AMOUNT/1000000000)) ; status: $Depool_Status"

#===========================================================
read -p "### CHECK INFO TWICE!!! Is this a right Parameters? Think once more!  (yes/n)? " answer
case ${answer:0:3} in
    yes|YES )
        echo "Processing....."
    ;;
    * )
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
