#!/usr/bin/env python3
"""Diagnostic: dump raw server responses so we can fix player counting.

Usage:
    python3 Resources/xlr/diag_players.py [server_id]

If no server_id is given, every enabled server in server_config.json is probed.
Paste the full output back so the parser can be aligned to the real format.
"""

import socket
import sys

from xlr_lib import load_config, rcon_query


def send_oob(host, port, command, timeout=2.0):
    payload = b"\xff\xff\xff\xff" + command.encode("latin-1") + b"\n"
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
            chunks.append(data)
            sock.settimeout(0.4)
    finally:
        sock.close()
    return b"".join(chunks)


def dump(label, raw):
    print(f"\n===== {label} =====")
    print(f"[{len(raw)} bytes]")
    text = raw[4:].decode("latin-1", errors="ignore") if len(raw) > 4 else raw.decode("latin-1", errors="ignore")
    print(repr(text))
    print("----- readable -----")
    print(text)


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
        password = server.get("rcon_password") or server.get("key", "")
        print("\n\n########################################")
        print(f"# SERVER {sid}  host={host} port={port}")
        print("########################################")
        for cmd in ("getstatus", "getinfo"):
            try:
                dump(f"OOB {cmd}", send_oob(host, port, cmd))
            except Exception as exc:  # noqa: BLE001
                print(f"{cmd} failed: {exc}")
        try:
            status = rcon_query(host, port, password, "status")
            print("\n===== RCON status =====")
            print(repr(status))
            print("----- readable -----")
            print(status)
        except Exception as exc:  # noqa: BLE001
            print(f"rcon status failed: {exc}")


if __name__ == "__main__":
    main()
