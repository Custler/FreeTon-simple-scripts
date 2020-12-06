#!/bin/bash 

# (C) Sergey Tyurin  2020-09-05 15:00:00

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

echo "INFO: setup TON node..."

if [[ -z $TON_LOG_DIR ]];then
    echo "###-ERROR: 'TON_LOG_DIR' variable cannot be empty!"
    exit 1
fi
if [[ -z $TON_WORK_DIR ]];then
    echo "###-ERROR: 'TON_WORK_DIR' variable cannot be empty!"
    exit 1
fi

SETUP_USER="$(id -un)"
SETUP_GROUP="$(id -gn)"

echo "INFO: Getting my public IP..."
until [ "$(echo "${MY_ADDR}" | grep "\." -o | wc -l)" -eq 3 ] ; do
    set +e
    MY_ADDR="$(curl -sS ipv4bot.whatismyipaddress.com)":${ADNL_PORT}
    set -e
done
echo "INFO: MY_ADDR = ${MY_ADDR}"

#============================================
# we can't delete TON_WORK_DIR if it has been mounted on separate disk
sudo rm -rf "${TON_WORK_DIR}/db"

sudo mkdir -p "${TON_WORK_DIR}"
sudo chown "${SETUP_USER}:${SETUP_GROUP}" "${TON_WORK_DIR}"
mkdir -p "${TON_WORK_DIR}/etc"
mkdir -p "${TON_WORK_DIR}/db"

mkdir -p $TON_LOG_DIR

#============================================
# set log rotate
# NB! - should be >> in run.sh
NODE_LOG_ROT=$(cat <<-_ENDNLR_
$TON_LOG_DIR/node.log {
    daily
    copytruncate
    dateext
    dateyesterday
    missingok
    rotate 14
    maxage 30
    compress
    delaycompress
    notifempty
    sharedscripts
}
_ENDNLR_
)
sudo echo $NODE_LOG_ROT > tonnode
sudo mv -f tonnode /usr/local/etc/logrotate.d/

#============================================
# set global config according to NETWORK_TYPE
curl -o ${CONFIGS_DIR}/${NETWORK_TYPE}/ton-global.config.json https://raw.githubusercontent.com/FreeTON-Network/fld.ton.dev/main/configs/${NETWORK_TYPE}/ton-global.config.json
cp -f "${CONFIGS_DIR}/${NETWORK_TYPE}/ton-global.config.json" "${TON_WORK_DIR}/etc/ton-global.config.json"

#===========================================
echo "INFO: generate initial ${TON_WORK_DIR}/db/config.json..."
"${TON_BUILD_DIR}/validator-engine/validator-engine" -C "${TON_WORK_DIR}/etc/ton-global.config.json" --db "${TON_WORK_DIR}/db" --ip "${MY_ADDR}"

sudo mkdir -p "${KEYS_DIR}"
sudo chown "${SETUP_USER}:${SETUP_GROUP}" "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

cd "${KEYS_DIR}"

"${UTILS_DIR}/generate-random-id" -m keys -n server > "${KEYS_DIR}/keys_s"
"${UTILS_DIR}/generate-random-id" -m keys -n liteserver > "${KEYS_DIR}/keys_l"
"${UTILS_DIR}/generate-random-id" -m keys -n client > "${KEYS_DIR}/keys_c"
chmod 600 "${KEYS_DIR}"/*
chmod 700 "${KEYS_DIR}"
find "${KEYS_DIR}"

mv "${KEYS_DIR}/server" "${TON_WORK_DIR}/db/keyring/$(awk '{print $1}' "${KEYS_DIR}/keys_s")"
mv "${KEYS_DIR}/liteserver" "${TON_WORK_DIR}/db/keyring/$(awk '{print $1}' "${KEYS_DIR}/keys_l")"

awk '{
    if (NR == 1) {
        server_id = $2
    } else if (NR == 2) {
        client_id = $2
    } else if (NR == 3) {
        liteserver_id = $2
    } else {
        print $0;
        if ($1 == "\"control\"") {
            print "      {";
            print "         \"id\": \"" server_id "\","
            print "         \"port\": 3030,"
            print "         \"allowed\": ["
            print "            {";
            print "               \"id\": \"" client_id "\","
            print "               \"permissions\": 15"
            print "            }";
            print "         ]"
            print "      }";
        } else if ($1 == "\"liteservers\"") {
            print "      {";
            print "         \"id\": \"" liteserver_id "\","
            print "         \"port\": 3031"
            print "      }";
        }
    }
}' "${KEYS_DIR}/keys_s" "${KEYS_DIR}/keys_c" "${KEYS_DIR}/keys_l" "${TON_WORK_DIR}/db/config.json" > "${TON_WORK_DIR}/db/config.json.tmp"

mv "${TON_WORK_DIR}/db/config.json.tmp" "${TON_WORK_DIR}/db/config.json"

find "${TON_WORK_DIR}"

echo "INFO: setup TON node... DONE"
