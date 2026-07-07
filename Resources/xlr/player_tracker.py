#!/usr/bin/env python3

import time
from pathlib import Path

from xlr_lib import (
    AUTH_RE,
    CONNECT_RE,
    REPORT_CHAT_RE,
    STEAM_RE,
    create_report,
    guess_locale,
    init_db,
    is_banned,
    load_config,
    connect_db,
    parse_status_clients,
    rcon_query,
    upsert_player,
    welcome_message,
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


def process_server(conn, config, server, state):
    sid = server["id"]
    session = state.setdefault(sid, {"sessions": {}, "offsets": {}, "welcomed": set()})

    for path_key in ("stdout_log", "game_log"):
        offset = session["offsets"].get(path_key, 0)
        offset, lines = tail_file(server[path_key], offset)
        session["offsets"][path_key] = offset
        for line in lines:
            auth = AUTH_RE.search(line)
            if auth:
                pid = auth.group(1)
                session["sessions"].setdefault(pid, {"plutonium_id": pid, "name": "", "steam_id": None})

            connect = CONNECT_RE.search(line)
            if connect:
                name = connect.group(1)
                for entry in session["sessions"].values():
                    if not entry.get("name"):
                        entry["name"] = name
                        break
                else:
                    session["sessions"][f"tmp:{name}"] = {"plutonium_id": "", "name": name, "steam_id": None}

            steam = STEAM_RE.search(line)
            if steam:
                for entry in session["sessions"].values():
                    if not entry.get("steam_id"):
                        entry["steam_id"] = steam.group(1)

            if handle_report_line(conn, sid, line):
                print(f"[report] new in-game report on {sid}")

    status = rcon_query(server["host"], server["port"], server["password"], "status")
    for client in parse_status_clients(status):
        guid = client["guid"]
        name = client["name"]
        ip = client["ip"]
        if not guid:
            continue
        if is_banned(conn, plutonium_id=guid, ip=ip):
            rcon_query(
                server["host"],
                server["port"],
                server["password"],
                f"clientkick {client['client_num']} banned",
            )
            continue
        upsert_player(conn, guid, name, ip)
        welcome_key = f"{sid}:{guid}"
        if welcome_key in session["welcomed"]:
            continue
        session["welcomed"].add(welcome_key)
        locale = guess_locale(ip)
        message = welcome_message(config, locale, name)
        rcon_query(
            server["host"],
            server["port"],
            server["password"],
            f'tell {client["client_num"]} {message}',
        )


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
