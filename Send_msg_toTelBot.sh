#!/bin/bash

# telegram_bot_token=
# telegram_chat_id=""

telegram_bot_token=$(cat TlgChat.json|jq '.telegram_bot_token'|tr -d '"')
telegram_chat_id=$(cat TlgChat.json|jq '.telegram_chat_id'|tr -d '"')


Title="$1"
Message="$2"
URL_to_Val="$3"

if [[ ! -z ${URL_to_Val} ]];then
    MSG_JSON=$(echo "" | awk -v TITLE="$Title" -v MESSAGE="\*${Title}* \n${Message}" -v CHAT_ID="$telegram_chat_id" -v URL="$URL_to_Val"  '{
        print "{";
        print "     \"chat_id\" : " CHAT_ID ","
        print "     \"text\" : \"" MESSAGE "\","
        print "     \"parse_mode\" : \"markdown\","
        print "     \"reply_markup\" : {";
        print "         \"inline_keyboard\" : ["
        print "            ["
        print "                 {";
        print "                     \"text\" : \"Open on tone.live\","
        print "                     \"url\" : \"" URL "\""
        print "                 }";
        print "             ]"
        print "         ]"
        print "         }";
        print "}";

    }')
    
    # echo $MSG_JSON
    curl -d "$MSG_JSON" \
     -H "Content-Type: application/json" \
     -X POST https://api.telegram.org/bot${telegram_bot_token}/sendMessage 

else 
    curl -s \
     --data parse_mode=HTML \
     --data chat_id=${telegram_chat_id} \
     --data text="<b>${Title}</b>%0A${Message}" \
     --request POST https://api.telegram.org/bot${telegram_bot_token}/sendMessage 
fi

exit 0
