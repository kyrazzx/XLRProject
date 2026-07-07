#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

setupDdosProtection() {
    local config_file="${1:-$WORKDIR/Plutonium/server_config.json}"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local enabled
    enabled=$(jq -r '.security_hardening.enabled // true' "$config_file")
    if [ "$enabled" != "true" ]; then
        return 0
    fi

    if [ "$(jq -r '.security_hardening.sysctl_tuning // true' "$config_file")" = "true" ]; then
        cat > /etc/sysctl.d/99-xlr-network.conf << 'EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 8192
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.conf.all.rp_filter = 1
EOF
        sysctl -p /etc/sysctl.d/99-xlr-network.conf 2>/dev/null || true
    fi

    if [ "$(jq -r '.security_hardening.rate_limit_enabled // true' "$config_file")" != "true" ]; then
        return 0
    fi

    checkAndInstallCommand nft nftables

    local pps burst nft_ports
    pps=$(jq -r '.security_hardening.rate_limit_pps // 800' "$config_file")
    burst=$(jq -r '.security_hardening.rate_limit_burst // 400' "$config_file")
    nft_ports=$(jq -r '.servers[] | select(.enabled == true) | .port' "$config_file" | paste -sd, -)

    if [ -z "$nft_ports" ]; then
        return 0
    fi

    mkdir -p /etc/nftables.d
    cat > /etc/nftables.d/xlr-game.conf << EOF
table inet xlr {
    set banned_ips {
        type ipv4_addr
        flags timeout
        timeout 30d
    }

    chain input {
        type filter hook input priority filter; policy accept;

        ip saddr @banned_ips udp dport { $nft_ports } drop

        udp dport { $nft_ports } limit rate over ${pps}/second burst ${burst} packets drop
    }
}
EOF

    if [ -f /etc/nftables.conf ] && ! grep -q 'xlr-game.conf' /etc/nftables.conf; then
        echo 'include "/etc/nftables.d/xlr-game.conf"' >> /etc/nftables.conf
    fi

    nft list table inet xlr >/dev/null 2>&1 && nft delete table inet xlr 2>/dev/null || true
    nft -f /etc/nftables.d/xlr-game.conf 2>/dev/null || true
    systemctl enable nftables 2>/dev/null || true
    systemctl restart nftables 2>/dev/null || true
}

xlr_ban_ip_nft() {
    local ip="$1"
    if [ -z "$ip" ] || ! command -v nft &>/dev/null; then
        return 1
    fi
    nft add element inet xlr banned_ips "{ $ip }" 2>/dev/null || true
}

xlr_unban_ip_nft() {
    local ip="$1"
    if [ -z "$ip" ] || ! command -v nft &>/dev/null; then
        return 1
    fi
    nft delete element inet xlr banned_ips "{ $ip }" 2>/dev/null || true
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupDdosProtection
else
    echo "Usage: $0 [--install] | [--import]"
fi
