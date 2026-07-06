#!/bin/bash

isUbuntu() {
    [ "${DISTRO:-}" = "ubuntu" ]
}

isDebian() {
    [ "${DISTRO:-}" = "debian" ]
}

resolveWineSuite() {
    if isUbuntu; then
        case "${VERSION:-}" in
            24.04) echo "noble" ;;
            22.04) echo "jammy" ;;
            20.04) echo "focal" ;;
            *) echo "noble" ;;
        esac
    else
        case "${VERSION:-}" in
            12) echo "bookworm" ;;
            11) echo "bullseye" ;;
            10) echo "buster" ;;
            *) echo "bookworm" ;;
        esac
    fi
}

resolveWineRepoFamily() {
    if isUbuntu; then
        echo "ubuntu"
    else
        echo "debian"
    fi
}

usesAspnet8Runtime() {
    if isUbuntu; then
        case "${VERSION:-}" in
            24.04|22.04) return 0 ;;
        esac
        return 1
    fi
    case "${VERSION:-}" in
        12|11) return 0 ;;
    esac
    return 1
}

usesAspnet7Runtime() {
    if isDebian && [ "${VERSION:-}" = "10" ]; then
        return 0
    fi
    return 1
}

installPlatformLibraries() {
    if isUbuntu && [ "${VERSION:-}" = "24.04" ]; then
        apt-get install -y libssl3 libcurl4t64 libc6:i386 libstdc++6:i386 2>/dev/null \
            || apt-get install -y libssl3 libcurl4 libc6:i386 libstdc++6:i386
        return
    fi
    if isUbuntu && [ "${VERSION:-}" = "22.04" ]; then
        apt-get install -y libssl3 libcurl4 libc6:i386 libstdc++6:i386
        return
    fi
    if apt-cache show libssl1.1 &>/dev/null; then
        apt-get install -y libssl1.1 libcurl4 libc6:i386 libstdc++6:i386
    else
        apt-get install -y libssl3 libcurl4 libc6:i386 libstdc++6:i386
    fi
}

installMicrosoftDotnetRepo() {
    local pkg_url="https://packages.microsoft.com/config/${DISTRO}/${VERSION}/packages-microsoft-prod.deb"
    local tmp_deb="/tmp/packages-microsoft-prod.deb"

    if ! wget -q --method=HEAD "$pkg_url" 2>/dev/null; then
        if isUbuntu; then
            pkg_url="https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb"
        else
            pkg_url="https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb"
        fi
    fi

    wget -q -O "$tmp_deb" "$pkg_url"
    dpkg -i "$tmp_deb" >/dev/null 2>&1 || true
    rm -f "$tmp_deb"
    apt-get update -y
}

getAspnetRuntimePackage() {
    if usesAspnet8Runtime; then
        echo "aspnetcore-runtime-8.0"
    elif usesAspnet7Runtime; then
        echo "aspnetcore-runtime-7.0"
    else
        echo ""
    fi
}
