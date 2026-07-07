#!/usr/bin/env python3

import time
from pathlib import Path

from xlr_lib import (
    AUTH_RE,
    CONNECT_RE,
    REPORT_CHAT_RE,
    STEAM_RE,
    create_report,
    init_db,
    is_banned,
    load_config,
    connect_db,
    parse_status_clients,
    pick_auto_message,
    rcon_query,
    rcon_say,
    send_player_welcome,
    upsert_player,
    WORKROOT,
)


def enabled_servers(config):
    general = config.get("general_config", {})
    host = general.get("rcon_ip", "127.0.0.1")
    for server in config.get("servers", []):
        if not server.get("enabled", True):
            continue
        yield {
            "id": server.get("id"),
            "port": server.get("port"),
            "password": server.get("rcon_password") or server.get("key", ""),
            "host": host,
            "stdout_log": WORKROOT
            / "Plutonium"
            / "servers"
            / server.get("id")
            / "logs"
            / "stdout.log",
            "game_log": WORKROOT
            / "Plutonium"
            / "storage"
            / "t6"
            / "logs"
            / server.get("log_file", ""),
        }


def tail_file(path, offset):
    path = Path(path)
    if not path.is_file():
        return offset, []
    size = path.stat().st_size
    if size < offset:
        offset = 0
    with open(path, "rb") as handle:
        handle.seek(offset)
        data = handle.read()
    return size, data.decode("latin-1", errors="ignore").splitlines()


def resolve_target(conn, target):
    row = conn.execute(
        """
        SELECT plutonium_id, current_name FROM players
        WHERE current_name LIKE ? OR plutonium_id = ?
        ORDER BY last_seen DESC LIMIT 1
        """,
        (f"%{target}%", target),
    ).fetchone()
    if row:
        return row["plutonium_id"], row["current_name"]
    return "", target


def handle_report_line(conn, server_id, line):
    match = REPORT_CHAT_RE.search(line)
    if not match:
        return None
    target_name = match.group(1)
    reason = (match.group(2) or "No reason provided").strip()
    target_id, resolved_name = resolve_target(conn, target_name)
    report_id = create_report(
        conn,
        "in-game",
        "",
        resolved_name,
        target_id,
        reason,
        server_id,
        "game_chat",
    )
    return report_id


def player_key(client):
    guid = client.get("guid") or ""
    if guid and guid.isdigit():
        return guid
    return f"{client['client_num']}:{client['name']}"


def maybe_send_auto_message(config, server, state):
    sid = server["id"]
    interval = int(config.get("customization", {}).get("auto_message_interval_seconds", 300))
    now = time.time()
    last = state.setdefault(sid, {}).get("last_auto_message", 0)
    if now - last < interval:
        return
    message = pick_auto_message(config, "en")
    if not message:
        return
    rcon_say(server["host"], server["port"], server["password"], message)
    state[sid]["last_auto_message"] = now


def upsert_session_player(conn, session, entry):
    plutonium_id = entry.get("plutonium_id") or ""
    name = entry.get("name") or ""
    if not plutonium_id or not name:
        return
    upsert_player(
        conn,
        plutonium_id,
        name,
        entry.get("ip") or "",
        entry.get("steam_id"),
    )
    upsert_key = f"{plutonium_id}:{name}"
    if upsert_key not in session.get("logged", set()):
        session.setdefault("logged", set()).add(upsert_key)
        print(f"[player] saved {name} ({plutonium_id})")


def process_server(conn, config, server, state):
    sid = server["id"]
    session = state.setdefault(
        sid,
        {"sessions": {}, "offsets": {}, "welcomed": set(), "logged": set(), "unlinked_names": []},
    )

    for path_key in ("stdout_log", "game_log"):
        offset = session["offsets"].get(path_key, 0)
        offset, lines = tail_file(server[path_key], offset)
        session["offsets"][path_key] = offset
        for line in lines:
            auth = AUTH_RE.search(line)
            if auth:
                pid = auth.group(1)
                entry = session["sessions"].setdefault(
                    pid,
                    {"plutonium_id": pid, "name": "", "steam_id": None, "ip": ""},
                )
                entry["plutonium_id"] = pid
                if session["unlinked_names"]:
                    entry["name"] = session["unlinked_names"].pop(0)
                upsert_session_player(conn, session, entry)

            connect = CONNECT_RE.search(line)
            if connect:
                name = connect.group(1)
                linked = False
                for entry in session["sessions"].values():
                    if entry.get("plutonium_id") and not entry.get("name"):
                        entry["name"] = name
                        upsert_session_player(conn, session, entry)
                        linked = True
                        break
                if not linked:
                    session["unlinked_names"].append(name)

            steam = STEAM_RE.search(line)
            if steam:
                steam_id = steam.group(1)
                for entry in session["sessions"].values():
                    if not entry.get("steam_id"):
                        entry["steam_id"] = steam_id
                        if entry.get("plutonium_id") and entry.get("name"):
                            upsert_session_player(conn, session, entry)

            if handle_report_line(conn, sid, line):
                print(f"[report] new in-game report on {sid}")

    status = rcon_query(server["host"], server["port"], server["password"], "status")
    for client in parse_status_clients(status):
        name = client["name"]
        ip = client["ip"]
        guid = client.get("guid") or ""
        plutonium_id = guid if guid.isdigit() else player_key(client)
        if is_banned(conn, plutonium_id=plutonium_id if guid.isdigit() else None, ip=ip):
            rcon_query(
                server["host"],
                server["port"],
                server["password"],
                f"clientkick {client['client_num']} banned",
            )
            continue
        upsert_player(conn, plutonium_id, name, ip)
        welcome_key = f"{sid}:{player_key(client)}"
        if welcome_key in session["welcomed"]:
            continue
        session["welcomed"].add(welcome_key)
        send_player_welcome(server, client, config)
        print(f"[welcome] {sid}: {name}")

    maybe_send_auto_message(config, server, state)


def main():
    conn = connect_db()
    init_db(conn)
    state = {}
    while True:
        config = load_config()
        for server in enabled_servers(config):
            try:
                process_server(conn, config, server, state)
            except Exception as exc:
                print(f"[player_tracker] {server['id']}: {exc}")
        time.sleep(2)


if __name__ == "__main__":
    main()
