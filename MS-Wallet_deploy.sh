#!/bin/bash

# (C) Sergey Tyurin  2020-11-29 15:00:00

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
#
# You have to have 'tonos-cli' installed in $HOME/bin:
#   

echo

function show_usage(){
echo
echo " Use: MS-Wallet_deploy.sh <Wallet name> <'Safe' or 'SetCode'> <Num of custodians> <Min Num of signatures>"
echo " All fields are required "
echo " If the wallet name is equal HOSTAME than files msig[1..31].keys.json will be used"
echo "   first signature file is used to sign deploy message"
echo " <Min Num of signatures> must be less or equal of <Num of custodians> and min - 2"
echo
echo " Example: MS-Wallet_deploy.sh MyWal Safe 5 3"
echo
exit 0
}

[[ $# -le 3 ]] && show_usage

#==================================================
# Check input parametrs
WAL_NAMEi=$1
CodeOfWallet=$2
if [[ ! $CodeOfWallet == "Safe" ]] && [[ ! $CodeOfWallet == "SetCode" ]];then
    echo "###-ERROR(line $LINENO): Wrong code of wallet. Choose 'Safe' or 'SetCode'"
    show_usage
    exit 1
fi
Cust_QTY=$3
if [[ $Cust_QTY -lt 3 ]] || [[ $Cust_QTY -gt 32 ]];then
    echo "###-ERROR(line $LINENO): Wrong Num of custodians must be >= 3 and <= 31"  
    show_usage
    exit 1
fi
ReqConfirms=$4
if [[ $ReqConfirms -gt $Cust_QTY ]] || [[ $ReqConfirms -lt 2 ]];then
    echo "###-ERROR(line $LINENO): Wrong Required num of signatures."
    show_usage
    exit 1
fi


#==================================================
# Set environment
SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

KEY_FILES_DIR=${KEYS_DIR}

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    CALL_BC="bc"
else
    CALL_BC="bc -l"
fi

#==================================================
# Get Wallet address for deploy
WAL_NAMEi=$1
WAL_NAME=${WAL_NAMEi:-"$HOSTNAME"}
echo "Wallet Name: $WAL_NAME"
WALL_ADDR=`cat "${KEY_FILES_DIR}/${WAL_NAME}.addr"`
if [[ -z $WALL_ADDR ]];then
    echo
    echo "###-ERROR(line $LINENO): Cannot find wallet address in file  ${KEY_FILES_DIR}/${WAL_NAME}.addr"
    echo
    exit 1
fi
echo "Wallet addr for deploy : $WALL_ADDR"
Work_Chain=`echo "${WALL_ADDR}" | cut -d ':' -f 1`

#=================================================
# Check deployed already
ACCOUNT_INFO=`$CALL_TC account ${WALL_ADDR}`
AMOUNT=`echo "$ACCOUNT_INFO" |grep "balance:" |awk '{print $2}'`
ACTUAL_BALANCE=$(echo "scale=3; $((AMOUNT)) / 1000000000" | $CALL_BC)
ACC_STATUS=`echo "$ACCOUNT_INFO" | grep 'acc_type:'|awk '{print $2}'`
if [[ "$ACC_STATUS" == "Active" ]];then
    echo
    echo "###-ERROR(line $LINENO): Wallet deployed already. Status: \"$ACC_STATUS\"; Balance: $ACTUAL_BALANCE"
    echo
    exit 1
fi
echo "Wallet status : \"$ACC_STATUS\""

#=================================================
# Check wallet balance
if [[ $((AMOUNT / 100000000)) -lt 9 ]];then
    echo "###-ERROR(line $LINENO): You haven't enough tokens to deploy wallet. Current balance: $ACTUAL_BALANCE tokens. You need 0.9 at least. Exit."
    exit 1
fi
echo "Wallet balance: $ACTUAL_BALANCE"

#=================================================
# Set sign files name wallet code
if [[ "$WAL_NAMEi" == "$HOSTNAME" ]];then
    SignFileName="msig"
else
    SignFileName="$WAL_NAMEi"
fi
Wallet_Code=${SafeSCs_DIR}/SafeMultisigWallet.tvc
Wallet_ABI=${SafeSCs_DIR}/SafeMultisigWallet.abi.json
if [[ "$CodeOfWallet" == "SetCode" ]];then
    Wallet_Code=${SetSCs_DIR}/SetcodeMultisigWallet.tvc
    Wallet_ABI=${SetSCs_DIR}/SetcodeMultisigWallet.abi.json
fi
if [[ ! -f $Wallet_Code ]] || [[ ! -f $Wallet_ABI ]];then
    echo "###-ERROR(line $LINENO): Can not find Wallet code or ABI. Check contracts folder."  
    show_usage
    exit 1
fi
echo "Wallet Code: $Wallet_Code"
echo "ABI for wallet: $Wallet_ABI"
#=================================================
# Read all pubkeys and make a string
Custodians_PubKeys=""
for (( i=1; i<=$Cust_QTY; i++))
do
    PubKey="0x$(cat $KEY_FILES_DIR/${SignFileName}${i}.keys.json | jq '.public'| tr -d '\"')"
    SecKey="0x$(cat $KEY_FILES_DIR/${SignFileName}${i}.keys.json | jq '.secret'| tr -d '\"')"
    if [[ "$PubKey" == "0x" ]] || [[ "$SecKey" == "0x" ]];then
        echo
        echo "###-ERROR(line $LINENO): Can't find wallet public and/or secret key No: $i !"
        echo
        exit 1
    fi

    Custodians_PubKeys+="\"${PubKey}\","
done

Custodians_PubKeys=${Custodians_PubKeys::-1}
echo "Custodians_PubKeys: '$Custodians_PubKeys'"
echo "Custodians QTY: $Cust_QTY; Required signs: $ReqConfirms"
echo

#=================================================
read -p "### CHECK INFO TWICE!!! Is this a right deploy info?  (y/n)? " answer
case ${answer:0:1} in
    y|Y )
        echo "Processing....."
    ;;
    * )
        echo "Cancelled."
        exit 1
    ;;
esac

#=================================================
# Deploy wallet

$CALL_TC deploy $Wallet_Code --abi $Wallet_ABI \
"{\"owners\":[$Custodians_PubKeys],\"reqConfirms\":$ReqConfirms}" \
--sign $KEY_FILES_DIR/${SignFileName}1.keys.json \
--wc $Work_Chain \
| tee $KEY_FILES_DIR/${WAL_NAME}_deploy_wallet.log

exit 0

