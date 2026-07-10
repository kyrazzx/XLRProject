#!/bin/bash

XLR_SECURITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XLR_WORKDIR="$(cd "$XLR_SECURITY_DIR/../.." && pwd)"

if [ -f "$XLR_WORKDIR/.config/config.sh" ]; then
    source "$XLR_WORKDIR/.config/config.sh"
fi

xlr_apply_anti_spoof_sysctl() {
    local config_file="$1"
    local anti_spoof
    anti_spoof=$(jq -r '.security_hardening.anti_spoof_enabled // true' "$config_file")

    cat > /etc/sysctl.d/99-xlr-network.conf << 'EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 16384
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

    if [ "$anti_spoof" = "true" ]; then
        cat >> /etc/sysctl.d/99-xlr-network.conf << 'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 0
EOF
    fi

    sysctl -p /etc/sysctl.d/99-xlr-network.conf 2>/dev/null || true

    if [ "$anti_spoof" = "true" ]; then
        local iface_path
        for iface_path in /proc/sys/net/ipv4/conf/*/rp_filter; do
            echo 1 > "$iface_path" 2>/dev/null || true
        done
        echo 0 > /proc/sys/net/ipv4/conf/all/log_martians 2>/dev/null || true
        echo 0 > /proc/sys/net/ipv4/conf/default/log_martians 2>/dev/null || true
    fi
}

setupDdosProtection() {
    local config_file="${1:-${XLR_CONFIG_FILE:-$WORKDIR/Plutonium/server_config.json}}"

    if [ "$(id -u)" -ne 0 ]; then
        echo "[XLR] setupDdosProtection requires root (use: sudo bash .config/security/setupDdosProtection.sh --install)"
        return 1
    fi

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local enabled
    enabled=$(jq -r '.security_hardening.enabled // true' "$config_file")
    if [ "$enabled" != "true" ]; then
        return 0
    fi

    if [ "$(jq -r '.security_hardening.sysctl_tuning // true' "$config_file")" = "true" ]; then
        xlr_apply_anti_spoof_sysctl "$config_file"
    fi

    if [ "$(jq -r '.security_hardening.rate_limit_enabled // true' "$config_file")" != "true" ]; then
        return 0
    fi

    checkAndInstallCommand nft nftables

    local pps burst per_ip_pps per_ip_burst udp_min udp_max drop_fragments nft_ports
    pps=$(jq -r '.security_hardening.rate_limit_pps // 6000' "$config_file")
    burst=$(jq -r '.security_hardening.rate_limit_burst // 1500' "$config_file")
    per_ip_pps=$(jq -r '.security_hardening.rate_limit_per_ip_pps // 150' "$config_file")
    per_ip_burst=$(jq -r '.security_hardening.rate_limit_per_ip_burst // 300' "$config_file")
    udp_min=$(jq -r '.security_hardening.udp_min_size // 24' "$config_file")
    udp_max=$(jq -r '.security_hardening.udp_max_size // 1492' "$config_file")
    drop_fragments=$(jq -r '.security_hardening.drop_fragments // true' "$config_file")
    nft_ports=$(jq -r '.servers[] | select(.enabled == true) | .port' "$config_file" | paste -sd, -)

    if [ -z "$nft_ports" ]; then
        return 0
    fi

    local fragment_rule=""
    if [ "$drop_fragments" = "true" ]; then
        fragment_rule="        udp dport { $nft_ports } ip frag-off != 0 drop"
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
        type filter hook input priority filter - 10; policy accept;

        ip saddr @banned_ips udp dport { $nft_ports } drop

${fragment_rule}

        ip saddr 127.0.0.1 udp dport { $nft_ports } accept

        udp dport { $nft_ports } meta length lt ${udp_min} drop
        udp dport { $nft_ports } meta length gt ${udp_max} drop

        udp dport { $nft_ports } meter game_per_ip { ip saddr limit rate over ${per_ip_pps}/second burst ${per_ip_burst} packets } drop

        udp dport { $nft_ports } limit rate over ${pps}/second burst ${burst} packets drop
    }
}
EOF

    if [ -f /etc/nftables.conf ] && ! grep -q 'xlr-game.conf' /etc/nftables.conf; then
        echo 'include "/etc/nftables.d/xlr-game.conf"' >> /etc/nftables.conf
    fi

    if ! xlr_load_nft_rules; then
        echo "Retrying with simplified nftables rules..."
        cat > /etc/nftables.d/xlr-game.conf << EOF
table inet xlr {
    set banned_ips {
        type ipv4_addr
        flags timeout
        timeout 30d
    }

    chain input {
        type filter hook input priority filter - 10; policy accept;

        ip saddr @banned_ips udp dport { $nft_ports } drop

        ip saddr 127.0.0.1 udp dport { $nft_ports } accept

        udp dport { $nft_ports } meta length lt ${udp_min} drop
        udp dport { $nft_ports } meta length gt ${udp_max} drop

        udp dport { $nft_ports } limit rate over ${pps}/second burst ${burst} packets drop
    }
}
EOF
        xlr_load_nft_rules || return 1
    fi
}

xlr_load_nft_rules() {
    local conf="/etc/nftables.d/xlr-game.conf"
    local err_file
    err_file="$(mktemp)"

    nft list table inet xlr >/dev/null 2>&1 && nft delete table inet xlr 2>/dev/null || true

    if ! nft -f "$conf" >"$err_file" 2>&1; then
        echo "Failed to load nftables rules:"
        cat "$err_file"
        rm -f "$err_file"
        return 1
    fi

    rm -f "$err_file"
    echo "nftables rules loaded: inet xlr"
    return 0
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

xlr_show_ddos_status() {
    if ! command -v nft &>/dev/null; then
        echo "nftables not installed"
        return 1
    fi
    echo "=== sysctl anti-spoof ==="
    sysctl net.ipv4.conf.all.rp_filter 2>/dev/null || true
    echo ""
    echo "=== nft table xlr ==="
    nft list table inet xlr 2>/dev/null || echo "table inet xlr not loaded"
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    setupDdosProtection "${XLR_CONFIG_FILE:-}"
elif [ "$1" = "--status" ]; then
    xlr_show_ddos_status
else
    echo "Usage: $0 [--install] | [--import] | [--status]"
fi
