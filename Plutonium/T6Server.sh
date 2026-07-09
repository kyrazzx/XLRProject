#!/bin/bash






readonly SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
readonly SERVER_NAME="SERVER_NAME"

readonly GAME_PATH="/opt/T6Server/Server/Multiplayer"

readonly SERVER_KEY="YOURKEY"

readonly CONFIG_FILE="dedicated.cfg"

readonly SERVER_PORT=21889

readonly GAME_MODE="t6mp"

readonly INSTALL_DIR="/opt/T6Server/Plutonium"

readonly MOD=""


readonly ADDITIONAL_PARAMS=""


update_server() {
    ./plutonium-updater -d "$INSTALL_DIR"
}

start_server() {
    local timestamp
    printf -v timestamp '%(%F_%H:%M:%S)T' -1
    
    echo -e '\033]2;Plutonium - '"$SERVER_NAME"' - Server restart\007'
    
    echo "Visit plutonium.pw | Join the Discord (plutonium) for NEWS and Updates!"
    echo "Server $SERVER_NAME will load $CONFIG_FILE and listen on port $SERVER_PORT UDP!"
    echo "To shut down the server close this window first!"
    echo "$timestamp $SERVER_NAME server started."

    while true; do
        nice -n -10 wine ./bin/plutonium-bootstrapper-win32.exe $GAME_MODE $GAME_PATH -dedicated \
            +set key $SERVER_KEY \
            +set fs_game $MOD \
            +set net_port $SERVER_PORT \
            +exec $CONFIG_FILE \
            $ADDITIONAL_PARAMS \
            +map_rotate \
            2>/dev/null
        
        printf -v timestamp '%(%F_%H:%M:%S)T' -1
        echo "$timestamp WARNING: $SERVER_NAME server closed or dropped... server restarting."
        sleep 1
    done
}

update_server
start_server
