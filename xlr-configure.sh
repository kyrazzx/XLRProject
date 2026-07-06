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
configureIW4MAdmin
setupSystemdServices

echo "XLR configuration updated."
