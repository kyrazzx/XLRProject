#!/bin/bash

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEFAULT_DIR/.config/config.sh"
source "$DEFAULT_DIR/.config/function.sh"

if [[ $UID != 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

promptServerCredentials
generateServerConfig
applyServerCredentials
setupSecurityConfig 2>/dev/null || true
setupDdosProtection "$DEFAULT_DIR/Plutonium/server_config.json" 2>/dev/null || true
setupCustomization
source "$DEFAULT_DIR/.config/xlr/setupBotWarfare.sh" --import
setupBotWarfare
source "$DEFAULT_DIR/.config/xlr/setupResxtScripts.sh" --import
setupResxtScripts
installXlrPython
configureIW4MAdmin
setupSystemdServices

echo "XLR configuration updated."
