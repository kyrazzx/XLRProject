#!/bin/bash
#
# analyze_attack.sh - Capture and characterize traffic hitting the XLR game
# ports, to tell apart spoofed floods vs proxy/botnet vs a few repeat IPs.
#
# Usage:  sudo bash Resources/xlr/analyze_attack.sh [duration_seconds]
# Default duration: 30s. Run it WHILE the lag/attack is happening.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKROOT="$(cd "$DIR/../.." && pwd)"
CONFIG="$WORKROOT/Plutonium/server_config.json"
DURATION="${1:-30}"
PCAP="/tmp/xlr_attack_$(date +%s).pcap"

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo." >&2
    exit 1
fi
for bin in tcpdump jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "Missing '$bin' (apt install $bin)"; exit 1; }
done

# Safety caps to keep the capture cheap even under a heavy flood:
#  -s 96  : headers only (we only need src IP / TTL / length / frag flags)
#  -c CAP : stop after CAP packets no matter what (bounds CPU + disk I/O)
SNAPLEN=96
MAX_PACKETS="${2:-200000}"

ports=$(jq -r '.servers[] | select(.enabled==true) | .port' "$CONFIG" | paste -sd, -)
filter=$(jq -r '.servers[] | select(.enabled==true) | "udp port " + (.port|tostring)' "$CONFIG" | paste -sd " or " -)
echo "Capturing up to ${DURATION}s / ${MAX_PACKETS} pkts of UDP on ports: ${ports} ..."
echo "(headers-only, low impact; run during the lag spikes for best results)"
timeout "$DURATION" tcpdump -ni any -s "$SNAPLEN" -c "$MAX_PACKETS" -w "$PCAP" "$filter" 2>/dev/null || true

src_ips() {
    tcpdump -nr "$PCAP" 2>/dev/null \
        | grep -oE 'IP6?[[:space:]][0-9a-fA-F:.]+\.[0-9]+ >' \
        | awk '{print $2}' | sed -E 's/\.[0-9]+$//'
}

total=$(tcpdump -nr "$PCAP" 2>/dev/null | wc -l)
echo ""
echo "Total packets captured: ${total}"
if [ "${total}" -eq 0 ]; then
    echo "No packets seen. Either no attack right now, or OVH is scrubbing it"
    echo "upstream (spoofed volumetric attacks never reach the box)."
    exit 0
fi

echo ""
echo "=== Top 30 source IPs (count) ==="
src_ips | sort | uniq -c | sort -rn | head -30

distinct=$(src_ips | sort -u | wc -l)
echo ""
echo "Distinct source IPs: ${distinct}"

echo ""
echo "=== TTL distribution (varied TTL from 'same' sources hints spoofing) ==="
tcpdump -nvr "$PCAP" 2>/dev/null | grep -oE 'ttl [0-9]+' | sort | uniq -c | sort -rn | head

echo ""
echo "=== Packet length distribution ==="
tcpdump -nvr "$PCAP" 2>/dev/null | grep -oE 'length [0-9]+' | awk '{print $2}' \
    | sort -n | uniq -c | sort -rn | head

frag=$(tcpdump -nvr "$PCAP" 2>/dev/null | grep -cE 'flags \[\+\]|offset [0-9]' || true)
echo ""
echo "Fragmented packets: ~${frag} / ${total}"

echo ""
echo "=== Heuristic verdict ==="
avg_per_ip=$(( total / (distinct>0 ? distinct : 1) ))
if [ "${distinct}" -gt 500 ] && [ "${avg_per_ip}" -le 5 ]; then
    echo "-> MANY source IPs, few packets each => likely SPOOFED / reflection."
    echo "   You cannot ban these. Only upstream scrubbing (OVH permanent"
    echo "   mitigation / Game protection) helps."
elif [ "${distinct}" -le 200 ] && [ "${avg_per_ip}" -ge 20 ]; then
    echo "-> FEW source IPs, high packets each => likely PROXY/BOTNET (real IPs)."
    echo "   These are bannable. Add the worst offenders to nftables:"
    echo "     sudo nft add element inet xlr banned_ips '{ <IP> }'"
else
    echo "-> Mixed pattern. Inspect the top IPs above: datacenter/proxy ranges"
    echo "   that repeat = bannable; huge random spread = spoofed."
fi

echo ""
echo "pcap saved at: ${PCAP} (open with: tcpdump -nvr ${PCAP} | less)"
