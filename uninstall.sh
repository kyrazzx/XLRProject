#!/bin/bash





DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "$DEFAULT_DIR/.config/config.sh"
source "$DEFAULT_DIR/.config/function.sh" --debug

if [[ $UID != 0 ]]; then
    echo "Please run this script with sudo:"
    echo "sudo $0 $*"
    exit 1
fi

showLogo

selectLanguage
showLogo

confirmUninstall

uninstallXLR
uninstallGameBinaries   # Removes game files and directories
uninstallDotnet         # Uninstalls .NET framework
uninstallWine           # Removes Wine
remove_firewall         # Reverts firewall changes made during installation

{
    apt-get autoremove -y
    apt-get clean
} > /dev/null 2>&1 &
showProgressIndicator "$(getMessage "cleanup")"

finishUninstallation

stty -igncr
exit