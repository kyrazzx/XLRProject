#!/bin/bash





DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$DEFAULT_DIR/.config/config.sh"
source "$DEFAULT_DIR/.config/function.sh"

if [[ $UID != 0 ]]; then
    echo "Please run this script with sudo:"
    echo "sudo $0 $*"
    exit 1
fi

showLogo
selectLanguage

showLogo
confirmInstallations

promptServerCredentials

showLogo

updateSystem

installDependencies

if [[ "$firewall" =~ ^[yYoO]$ ]] || [[ -z "$firewall" ]]; then
    installFirewall "$ssh_port"
fi

enable32BitPackages

installWine

if [[ "$dotnet" =~ ^[yYoO]$ ]] || [[ -z "$dotnet" ]]; then
    installDotnet
fi

installGameBinaries 

installXLRStack

finishInstallation

stty -igncr
exit