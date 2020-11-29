#!/bin/bash -eE

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

OS_SYSTEM=`uname`
if [[ "$OS_SYSTEM" == "Linux" ]];then
    SETUP_USER="$(id -u)"
    SETUP_GROUP="$(id -g)"
else
    SETUP_USER="$(id -un)"
    SETUP_GROUP="$(id -gn)"
fi

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
if [[ "$OS_SYSTEM" == "Linux" ]];then
    sudo echo "$NODE_LOG_ROT" > tonnode
    sudo mv -f tonnode /etc/logrotate.d/
else
    sudo echo "$NODE_LOG_ROT" > tonnode
    sudo mv -f tonnode /usr/local/etc/logrotate.d/
fi

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
[[ -d ${ELECTIONS_WORK_DIR} ]] && chmod 700 "${ELECTIONS_WORK_DIR}"

find "${KEYS_DIR}"

mv "${KEYS_DIR}/server" "${TON_WORK_DIR}/db/keyring/$(awk '{print $1}' "${KEYS_DIR}/keys_s")"
mv "${KEYS_DIR}/liteserver" "${TON_WORK_DIR}/db/keyring/$(awk '{print $1}' "${KEYS_DIR}/keys_l")"

awk -v VAL_ENGINE_CONSOLE_PORT="$VAL_ENGINE_CONSOLE_PORT" -v LITESERVER_PORT="$LITESERVER_PORT" '{
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
            print "         \"port\": " VAL_ENGINE_CONSOLE_PORT ","
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
            print "         \"port\": " LITESERVER_PORT
            print "      }";
        }
    }
}' "${KEYS_DIR}/keys_s" "${KEYS_DIR}/keys_c" "${KEYS_DIR}/keys_l" "${TON_WORK_DIR}/db/config.json" > "${TON_WORK_DIR}/db/config.json.tmp"

mv "${TON_WORK_DIR}/db/config.json.tmp" "${TON_WORK_DIR}/db/config.json"

find "${TON_WORK_DIR}"

echo "INFO: setup TON node... DONE"

exit 0
