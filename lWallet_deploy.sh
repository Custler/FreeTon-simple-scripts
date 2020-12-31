#!/bin/bash

echo "SORRY IT IS DOES NOT WORK YET!"
exit 1

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
echo "cd to $SCRIPT_DIR"
cd $SCRIPT_DIR
. "${SCRIPT_DIR}/env.sh"

Contract_TVC="$SCRIPT_DIR/../ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.tvc"
Contract_ABI="$SCRIPT_DIR/../ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.abi.json"

WALL_NAME=$1
MSIG_JSON=${WALL_NAME:-"msig"}
WALL_FILE=${WALL_NAME:-$HOSTNAME}

if [[ ! -f ${KEYS_DIR}/${WALL_FILE}.addr ]];then
    echo "###-ERROR: Can't find address file ${KEYS_DIR}/${WALL_FILE}.addr ! "
    exit 1
fi

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    CALL_BC="bc"
else
    CALL_BC="bc -l"
fi

WALL_ADDR=`cat ${KEYS_DIR}/${WALL_FILE}.addr`
PUB_KEY=`cat ${KEYS_DIR}/${MSIG_JSON}.keys.json | jq ".public" | tr -d '"'`
[[ "$PUB_KEY" == "" ]] && echo "### - ERROR: Empty Public key! Exit." && exit 1

Work_Chain=`echo "${WALL_ADDR}" | cut -d ':' -f 1`
Addr_HEX=`echo "${WALL_ADDR}" | cut -d ':' -f 2`

echo
echo "Wallet Contract:  ${Contract_TVC##*/}"
echo "Deploy wallet:    ${WALL_ADDR}"
echo "Public key:       ${PUB_KEY}"
echo "WorkChain:        ${Work_Chain}"
echo

read -p "Is this a right wallet (yes/n)? " answer
case ${answer:0:3} in
    yes|YES )
     
    ;;
    * )
        echo "If you absolutely sure type 'yes'"
        echo "Cancelled."
        exit 1
    ;;
esac

#==================================================
# prepare signature
PRIV_KEY=`cat ${KEYS_DIR}/${MSIG_JSON}.keys.json | jq ".secret" | tr -d '"'`
if [[ -z $PUB_KEY ]] || [[ -z $PRIV_KEY ]];then
    echo "###-ERROR: Can't find wallet public and/or secret key!"
    exit 1
fi
echo "${PRIV_KEY}${PUB_KEY}" > ${KEYS_DIR}/sign.keys.txt
rm -f ${KEYS_DIR}/sign.keys.bin
xxd -r -p ${KEYS_DIR}/sign.keys.txt ${KEYS_DIR}/sign.keys.bin

#==================================================
# prepare contract code

cp "${Contract_TVC}" ./${Addr_HEX}.tvc

#==================================================
# make deploy message
TVM_OUTPUT=$($CALL_TL message -i \
    -w ${Work_Chain} \
    -a ${Contract_ABI} \
    -m 'constructor' \
    -p "{\"owners\":[\"0x${PUB_KEY}\"],\"reqConfirms\":1}" \
    --setkey ${KEYS_DIR}/sign.keys.bin \
    ${Addr_HEX} \
    | tee ${KEYS_DIR}/${WALL_FILE}-depl-msg.log)

if [[ -z $(echo $TVM_OUTPUT | grep "boc file created") ]];then
    echo "###-ERROR: TVM linker CANNOT create boc file!!! Can't continue."
    exit 1
fi

mv "$(echo "$Addr_HEX"| cut -c 1-8)-msg-init-body.boc" "${KEYS_DIR}/${WALL_FILE}-msg-init-body.boc"
ls -al "${KEYS_DIR}/${WALL_FILE}-msg-init-body.boc"
echo "INFO: Make boc for lite-client ... DONE"

exit 0

#==================================================
# send deploy message by lite-client
$CALL_LC -rc "sendfile ${KEYS_DIR}/${WALL_FILE}-msg-init-body.boc" -rc 'quit' &> ${KEYS_DIR}/${WALL_FILE}-depl-result.log

LC_Result=`cat ${KEYS_DIR}/${WALL_FILE}-depl-result.log | grep "external message status is 1"`

if [[ -z $LC_Result ]]; then
    echo "###-ERROR: Send message for deploy FAILED!!!"
    exit 1
fi

#==================================================
# wait for deploy
while true
do
    ACCOUNT_INFO=`$CALL_LC -rc "getaccount ${ACCOUNT}" -rc "quit" 2>/dev/null`
    ACC_STATUS=`echo "$ACCOUNT_INFO" | grep 'state:'|tr -d ')'|tr -d '('|cut -d ':' -f 2`
    if [[ "$ACC_STATUS" == "account_active" ]];then
        break
    fi
    printf "."
done 

AMOUNT=`echo "$ACCOUNT_INFO" |grep "account balance" | tr -d "ng"|awk '{print $4}'`
LAST_TR_TIME=`echo "$ACCOUNT_INFO" | grep "last_paid" | gawk -F ":" '{print strftime("%Y-%m-%d %H:%M:%S", $5)}'`

echo
echo "Contract Deployed! Last info:"
echo "Account: $ACCOUNT"
echo "Time Now: $(date  +'%Y-%m-%d %H:%M:%S')"
echo "Status: $ACC_STATUS"
echo "Has balance : $(echo "scale=3; $((AMOUNT)) / 1000000000" | $CALL_BC) tokens"
echo "Last operation time: $LAST_TR_TIME"
# "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "Current balance: $((AMOUNT/1000000000))" 2>&1 > /dev/null
echo "=================================================================================================="
echo

exit 0
