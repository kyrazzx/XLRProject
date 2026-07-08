#!/usr/bin/env python3

import json
import time
from pathlib import Path

from xlr_lib import (
    AUTH_RE,
    CLIENT_ENDPOINT_RE,
    CONNECT_RE,
    LET_PLAYER_RE,
    REPORT_CHAT_RE,
    STEAM_RE,
    ban_announce_message,
    create_report,
    get_active_ban_reason,
    init_db,
    is_banned,
    load_config,
    connect_db,
    parse_status_clients,
    rcon_query,
    rcon_say,
    resolve_ips_from_conntrack,
    record_server_player,
    send_player_welcome,
    sync_server_game_dvars,
    upsert_player,
    WORKROOT,
)

OFFSET_STATE_PATH = WORKROOT / "Plutonium" / "storage" / "xlr" / "tracker_offsets.json"


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


def load_offset_state():
    if not OFFSET_STATE_PATH.is_file():
        return {}
    try:
        return json.loads(OFFSET_STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_offset_state(offsets):
    OFFSET_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    OFFSET_STATE_PATH.write_text(json.dumps(offsets, indent=2), encoding="utf-8")


def resolve_log_offset(path, saved_offset):
    path = Path(path)
    if not path.is_file():
        return 0
    size = path.stat().st_size
    if saved_offset is None:
        return size
    if saved_offset > size:
        return 0
    return saved_offset


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


def maybe_record_server_player(conn, server_id, plutonium_id):
    if plutonium_id and str(plutonium_id).isdigit():
        record_server_player(conn, server_id, str(plutonium_id))


def kick_banned_player(server, client, session, reason=""):
    ban_key = f"{client.get('guid') or ''}:{client.get('ip') or ''}:{client['client_num']}"
    if ban_key in session.get("announced_bans", set()):
        return
    name = client.get("name") or "A player"
    rcon_say(
        server["host"],
        server["port"],
        server["password"],
        ban_announce_message(name, reason),
    )
    rcon_query(
        server["host"],
        server["port"],
        server["password"],
        f"clientkick {client['client_num']} banned",
    )
    session.setdefault("announced_bans", set()).add(ban_key)


def take_pending_ip(session):
    queue = session.get("pending_ips", [])
    assigned = session.setdefault("assigned_ips", set())
    while queue:
        ip = queue.pop(0)
        if ip not in assigned:
            assigned.add(ip)
            return ip
    return ""


def resolve_session_ip(session, server, entry, allow_conntrack=True):
    if entry.get("ip"):
        return entry["ip"]
    ip = take_pending_ip(session)
    if ip:
        entry["ip"] = ip
        return ip
    if not allow_conntrack:
        return ""
    assigned = session.setdefault("assigned_ips", set())
    for candidate in resolve_ips_from_conntrack(server["port"]):
        if candidate not in assigned:
            assigned.add(candidate)
            entry["ip"] = candidate
            return candidate
    return ""


def upsert_session_player(conn, session, server, entry, allow_conntrack=True):
    plutonium_id = entry.get("plutonium_id") or ""
    name = entry.get("name") or ""
    if not plutonium_id or not name:
        return
    ip = resolve_session_ip(session, server, entry, allow_conntrack=allow_conntrack)
    upsert_player(
        conn,
        plutonium_id,
        name,
        ip,
        entry.get("steam_id"),
    )
    maybe_record_server_player(conn, server["id"], plutonium_id)
    upsert_key = f"{plutonium_id}:{name}"
    if upsert_key not in session.get("logged", set()):
        session.setdefault("logged", set()).add(upsert_key)
        ip_note = f" ip={ip}" if ip else ""
        print(f"[player] saved {name} ({plutonium_id}){ip_note}")


def process_server(conn, config, server, state, offset_state):
    sid = server["id"]
    session = state.setdefault(
        sid,
        {
            "sessions": {},
            "welcomed": set(),
            "logged": set(),
            "pending_ips": [],
            "assigned_ips": set(),
            "awaiting_connect": None,
        },
    )

    for path_key in ("stdout_log", "game_log"):
        path = server[path_key]
        state_key = f"{sid}:{path_key}"
        saved_offset = offset_state.get(state_key)
        offset = resolve_log_offset(path, saved_offset)
        offset, lines = tail_file(path, offset)
        offset_state[state_key] = offset
        for line in lines:
            endpoint = CLIENT_ENDPOINT_RE.search(line)
            if endpoint:
                session.setdefault("pending_ips", []).append(endpoint.group(1))

            auth = AUTH_RE.search(line)
            if auth:
                pid = auth.group(1)
                session["sessions"].setdefault(
                    pid,
                    {"plutonium_id": pid, "name": "", "steam_id": None, "ip": ""},
                )
                session["awaiting_connect"] = pid

            let_player = LET_PLAYER_RE.search(line)
            if let_player:
                pid = let_player.group(1)
                session["sessions"].setdefault(
                    pid,
                    {"plutonium_id": pid, "name": "", "steam_id": None, "ip": ""},
                )
                session["awaiting_connect"] = pid
                entry = session["sessions"][pid]
                if not entry.get("ip"):
                    ip = take_pending_ip(session)
                    if ip:
                        entry["ip"] = ip

            connect = CONNECT_RE.search(line)
            if connect:
                name = connect.group(1)
                pid = session.get("awaiting_connect")
                if pid and pid in session["sessions"]:
                    entry = session["sessions"][pid]
                    entry["name"] = name
                    upsert_session_player(conn, session, server, entry, allow_conntrack=True)
                session["awaiting_connect"] = None

            steam = STEAM_RE.search(line)
            if steam:
                steam_id = steam.group(1)
                pid = session.get("awaiting_connect")
                if pid and pid in session["sessions"]:
                    entry = session["sessions"][pid]
                    entry["steam_id"] = steam_id
                    if entry.get("name"):
                        upsert_session_player(
                            conn,
                            session,
                            server,
                            entry,
                            allow_conntrack=False,
                        )

            if handle_report_line(conn, sid, line):
                print(f"[report] new in-game report on {sid}")

    status = rcon_query(server["host"], server["port"], server["password"], "status")
    for client in parse_status_clients(status):
        name = client["name"]
        ip = client["ip"]
        guid = client.get("guid") or ""
        plutonium_id = guid if guid.isdigit() else player_key(client)
        if guid.isdigit():
            entry = session["sessions"].setdefault(
                guid,
                {"plutonium_id": guid, "name": name, "steam_id": None, "ip": ip},
            )
            if ip:
                entry["ip"] = ip
        if is_banned(conn, plutonium_id=plutonium_id if guid.isdigit() else None, ip=ip):
            reason = get_active_ban_reason(
                conn,
                plutonium_id=plutonium_id if guid.isdigit() else None,
                ip=ip,
            )
            kick_banned_player(server, client, session, reason=reason)
            continue
        upsert_player(conn, plutonium_id, name, ip)
        maybe_record_server_player(conn, sid, guid if guid.isdigit() else plutonium_id)
        welcome_key = f"{sid}:{player_key(client)}"
        if welcome_key in session["welcomed"]:
            continue
        session["welcomed"].add(welcome_key)
        send_player_welcome(server, client, config)
        print(f"[welcome] {sid}: {name}")

    sync_server_game_dvars(server, config, conn)


def main():
    conn = connect_db()
    init_db(conn)
    state = {}
    offset_state = load_offset_state()
    while True:
        config = load_config()
        for server in enabled_servers(config):
            try:
                process_server(conn, config, server, state, offset_state)
            except Exception as exc:
                print(f"[player_tracker] {server['id']}: {exc}")
        save_offset_state(offset_state)
        time.sleep(2)


if __name__ == "__main__":
    main()
