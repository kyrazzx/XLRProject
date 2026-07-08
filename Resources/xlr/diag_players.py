#!/usr/bin/env python3
"""Diagnostic for player counting / RCON connectivity.

Usage:
    python3 Resources/xlr/diag_players.py [server_id]

It compares the RCON password the bot uses (server_config.json) with the one
actually set in the server's dedicated_*.cfg, then tries an RCON `status` with
each so we can see which password (if any) the server accepts. Paste the full
output back.
"""

import re
import socket
import sys
from pathlib import Path

from xlr_lib import WORKROOT, load_config


def raw_rcon(host, port, password, command="status", timeout=2.5):
    payload = f"\xff\xff\xff\xffrcon {password} {command}".encode("latin-1", errors="ignore")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    chunks = []
    try:
        sock.sendto(payload, (host, int(port)))
        while True:
            try:
                data, _ = sock.recvfrom(16384)
            except OSError:
                break
            if len(data) > 4:
                chunks.append(data[4:].decode("latin-1", errors="ignore"))
            sock.settimeout(0.5)
    finally:
        sock.close()
    return "".join(chunks)


def cfg_rcon_password(config, server):
    cfg_name = server.get("config", "")
    candidates = [
        WORKROOT / "Server" / "Multiplayer" / "main" / cfg_name,
        WORKROOT / "Server" / "Multiplayer" / "main" / "dedicated.cfg",
    ]
    for path in candidates:
        if path.is_file():
            text = path.read_text(encoding="latin-1", errors="ignore")
            match = re.search(r'^\s*rcon_password\s+"?([^"\r\n]+)"?', text, re.M)
            if match:
                return path, match.group(1).strip()
            return path, "(no rcon_password line)"
    return None, "(cfg file not found)"


def main():
    config = load_config()
    host = config.get("general_config", {}).get("rcon_ip", "127.0.0.1")
    target = sys.argv[1] if len(sys.argv) > 1 else None
    for server in config.get("servers", []):
        if not server.get("enabled", True):
            continue
        sid = server.get("id")
        if target and sid != target:
            continue
        port = server.get("port")
        json_pass = server.get("rcon_password") or server.get("key", "")
        cfg_path, cfg_pass = cfg_rcon_password(config, server)

        print("\n########################################")
        print(f"# SERVER {sid}  host={host} port={port}")
        print("########################################")
        print(f"server_config.json rcon_password/key : {json_pass!r}")
        print(f"cfg file                             : {cfg_path}")
        print(f"cfg rcon_password                    : {cfg_pass!r}")

        tried = []
        for label, pw in (("json", json_pass), ("cfg", cfg_pass)):
            if not pw or pw in tried or pw.startswith("("):
                continue
            tried.append(pw)
            resp = raw_rcon(host, port, pw)
            print(f"\n----- RCON status using {label} password ({pw!r}) -----")
            print(f"[{len(resp)} chars]")
            print(resp[:2000] if resp else "(empty response)")


if __name__ == "__main__":
    main()
