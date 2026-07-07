#!/usr/bin/env python3

import json
import os
import re
import socket
import sqlite3
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

WORKROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKROOT / "Plutonium" / "server_config.json"
SECRETS_PATH = Path("/etc/xlr/secrets.env")
DEFAULT_DB_DIR = WORKROOT / "Plutonium" / "storage" / "xlr"

FR_COUNTRIES = frozenset(
    {"FR", "BE", "CH", "LU", "MC", "RE", "GP", "MQ", "GF", "YT", "PM", "WF", "NC", "PF"}
)


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_secrets():
    secrets = {}
    if SECRETS_PATH.is_file():
        for line in SECRETS_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            secrets[key.strip()] = value.strip().strip('"').strip("'")
    return secrets


def discord_token():
    secrets = load_secrets()
    if secrets.get("DISCORD_TOKEN"):
        return secrets["DISCORD_TOKEN"]
    config = load_config()
    token = config.get("discord_config", {}).get("token", "")
    if token and token != "YOUR_DISCORD_TOKEN":
        return token
    return os.environ.get("XLR_DISCORD_TOKEN", "")


def db_path():
    config = load_config()
    rel = config.get("moderation", {}).get("players_db", "Plutonium/storage/xlr/players.db")
    path = WORKROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def connect_db():
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    return conn


def init_db(conn):
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS players (
            plutonium_id TEXT PRIMARY KEY,
            steam_id TEXT,
            current_name TEXT,
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS player_ips (
            plutonium_id TEXT NOT NULL,
            ip TEXT NOT NULL,
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            PRIMARY KEY (plutonium_id, ip)
        );
        CREATE TABLE IF NOT EXISTS player_names (
            plutonium_id TEXT NOT NULL,
            name TEXT NOT NULL,
            first_seen TEXT NOT NULL,
            PRIMARY KEY (plutonium_id, name)
        );
        CREATE TABLE IF NOT EXISTS bans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plutonium_id TEXT,
            ip TEXT,
            reason TEXT,
            banned_by TEXT,
            banned_at TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reporter_name TEXT,
            reporter_id TEXT,
            target_name TEXT,
            target_id TEXT,
            reason TEXT,
            server_id TEXT,
            source TEXT,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            discord_message_id TEXT
        );
        """
    )
    conn.commit()


def rcon_query(host, port, password, command):
    payload = f"\xff\xff\xff\xffrcon {password} {command}".encode("latin-1", errors="ignore")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.4)
    chunks = []
    try:
        sock.sendto(payload, (host, int(port)))
        deadline = time.time() + 2.5
        while time.time() < deadline:
            try:
                data, _ = sock.recvfrom(8192)
            except OSError:
                break
            if len(data) > 4:
                chunks.append(data[4:].decode("latin-1", errors="ignore"))
    finally:
        sock.close()
    return "".join(chunks)


def parse_status_clients(status_text):
    clients = []
    for line in status_text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("num ") or line.startswith("--"):
            continue
        if not re.match(r"^\d+\s+", line):
            continue
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            client_num = int(parts[0])
        except ValueError:
            continue
        guid = parts[3].replace("^7", "").replace("'", "").strip()
        name = parts[4].replace("^7", "").replace("'", "").strip()
        ip = ""
        for part in reversed(parts[5:]):
            if ":" in part:
                ip = part.split(":")[0].strip()
                break
        clients.append(
            {
                "client_num": client_num,
                "guid": guid,
                "name": name,
                "ip": ip,
            }
        )
    return clients


def resolve_ips_from_conntrack(port):
    ips = []
    commands = (
        ["conntrack", "-L", "-p", "udp", "--dport", str(port)],
        ["conntrack", "-L", "-p", "udp", "--sport", str(port)],
    )
    for cmd in commands:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
        if result.returncode != 0:
            continue
        for line in (result.stdout or "").splitlines():
            match = re.search(r"src=(\d+\.\d+\.\d+\.\d+)", line)
            if not match:
                continue
            ip = match.group(1)
            if ip not in ips:
                ips.append(ip)
    if ips:
        return ips
    proc_path = Path("/proc/net/nf_conntrack")
    if not proc_path.is_file():
        return ips
    port_token = f"dport={int(port)}"
    try:
        for line in proc_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if port_token not in line:
                continue
            match = re.search(r"src=(\d+\.\d+\.\d+\.\d+)", line)
            if match:
                ip = match.group(1)
                if ip not in ips:
                    ips.append(ip)
    except OSError:
        pass
    return ips


def guess_locale(ip):
    if not ip or ip.startswith(("10.", "192.168.", "127.")) or ip.startswith("172."):
        return "en"
    try:
        with urllib.request.urlopen(
            f"http://ip-api.com/json/{ip}?fields=countryCode",
            timeout=2,
        ) as response:
            data = json.loads(response.read().decode("utf-8"))
            if data.get("countryCode") in FR_COUNTRIES:
                return "fr"
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    return "en"


def rcon_say(host, port, password, message):
    return rcon_query(host, port, password, f"say {message}")


def rcon_tell(host, port, password, client_num, message):
    return rcon_query(host, port, password, f"tell {client_num} {message}")


def send_player_welcome(server, client, config):
    locale = guess_locale(client.get("ip", ""))
    message = welcome_message(config, locale, client["name"])
    host = server["host"]
    port = server["port"]
    password = server["password"]
    client_num = client["client_num"]
    mode = config.get("customization", {}).get("welcome_mode", "both")
    if mode in ("say", "both"):
        rcon_say(host, port, password, message)
    if mode in ("tell", "both"):
        rcon_tell(host, port, password, client_num, message)


def pick_auto_message(config, locale):
    custom = config.get("customization", {})
    if locale == "fr":
        messages = custom.get("auto_messages_fr") or []
    else:
        messages = custom.get("auto_messages_en") or []
    if not messages:
        messages = custom.get("auto_messages_en") or custom.get("auto_messages_fr") or []
    if not messages:
        return ""
    import random
    return random.choice(messages)


def welcome_message(config, locale, player_name):
    custom = config.get("customization", {})
    invite = custom.get("discord_invite", "discord.gg/63FAj2ZMrN")
    if locale == "fr":
        template = custom.get(
            "welcome_chat_fr",
            "^5[XLR]^7 Bienvenue {player} ! Discord : {discord}",
        )
    else:
        template = custom.get(
            "welcome_chat_en",
            "^5[XLR]^7 Welcome {player}! Discord: {discord}",
        )
    return template.format(player=player_name, discord=invite)


def upsert_player(conn, plutonium_id, name, ip, steam_id=None):
    now = utc_now()
    row = conn.execute(
        "SELECT plutonium_id FROM players WHERE plutonium_id = ?",
        (plutonium_id,),
    ).fetchone()
    if row:
        conn.execute(
            "UPDATE players SET current_name = ?, last_seen = ?, steam_id = COALESCE(?, steam_id) WHERE plutonium_id = ?",
            (name, now, steam_id, plutonium_id),
        )
    else:
        conn.execute(
            "INSERT INTO players (plutonium_id, steam_id, current_name, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)",
            (plutonium_id, steam_id, name, now, now),
        )

    if name:
        conn.execute(
            "INSERT OR IGNORE INTO player_names (plutonium_id, name, first_seen) VALUES (?, ?, ?)",
            (plutonium_id, name, now),
        )

    if ip:
        conn.execute(
            """
            INSERT INTO player_ips (plutonium_id, ip, first_seen, last_seen)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(plutonium_id, ip) DO UPDATE SET last_seen = excluded.last_seen
            """,
            (plutonium_id, ip, now, now),
        )
    conn.commit()


def is_banned(conn, plutonium_id=None, ip=None):
    if ip:
        row = conn.execute(
            "SELECT 1 FROM bans WHERE active = 1 AND ip = ? LIMIT 1",
            (ip,),
        ).fetchone()
        if row:
            return True
    if plutonium_id:
        row = conn.execute(
            "SELECT 1 FROM bans WHERE active = 1 AND plutonium_id = ? LIMIT 1",
            (plutonium_id,),
        ).fetchone()
        if row:
            return True
    return False


def nft_ban_ip(ip):
    if not ip:
        return
    subprocess.run(
        ["nft", "add", "element", "inet", "xlr", "banned_ips", "{" + ip + "}"],
        capture_output=True,
        text=True,
    )


def nft_unban_ip(ip):
    if not ip:
        return
    subprocess.run(
        ["nft", "delete", "element", "inet", "xlr", "banned_ips", "{" + ip + "}"],
        capture_output=True,
        text=True,
    )


def add_ban(conn, ip=None, plutonium_id=None, reason="", banned_by="system"):
    now = utc_now()
    conn.execute(
        "INSERT INTO bans (plutonium_id, ip, reason, banned_by, banned_at, active) VALUES (?, ?, ?, ?, ?, 1)",
        (plutonium_id, ip, reason, banned_by, now),
    )
    conn.commit()
    if ip:
        nft_ban_ip(ip)


def remove_ban(conn, ip=None, plutonium_id=None):
    ips_to_unban = set()
    if ip:
        ips_to_unban.add(ip)
    if plutonium_id:
        ban_rows = conn.execute(
            """
            SELECT DISTINCT ip FROM bans
            WHERE active = 1 AND plutonium_id = ? AND ip IS NOT NULL AND ip != ''
            """,
            (plutonium_id,),
        ).fetchall()
        for row in ban_rows:
            ips_to_unban.add(row["ip"])
        player_row = conn.execute(
            "SELECT GROUP_CONCAT(DISTINCT ip) AS ips FROM player_ips WHERE plutonium_id = ?",
            (plutonium_id,),
        ).fetchone()
        if player_row and player_row["ips"]:
            ips_to_unban.update(ip.strip() for ip in player_row["ips"].split(",") if ip.strip())

    clauses = []
    params = []
    if ip:
        clauses.append("ip = ?")
        params.append(ip)
    if plutonium_id:
        clauses.append("plutonium_id = ?")
        params.append(plutonium_id)
    if not clauses:
        return 0

    cur = conn.execute(
        f"UPDATE bans SET active = 0 WHERE active = 1 AND ({' OR '.join(clauses)})",
        params,
    )
    conn.commit()
    for banned_ip in ips_to_unban:
        nft_unban_ip(banned_ip)
    return cur.rowcount


def create_report(conn, reporter_name, reporter_id, target_name, target_id, reason, server_id, source):
    now = utc_now()
    cur = conn.execute(
        """
        INSERT INTO reports (reporter_name, reporter_id, target_name, target_id, reason, server_id, source, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (reporter_name, reporter_id, target_name, target_id, reason, server_id, source, now),
    )
    conn.commit()
    return cur.lastrowid


def lookup_player(conn, query):
    query = query.strip()
    rows = conn.execute(
        """
        SELECT p.*, GROUP_CONCAT(DISTINCT pi.ip) AS ips
        FROM players p
        LEFT JOIN player_ips pi ON pi.plutonium_id = p.plutonium_id
        WHERE p.plutonium_id = ? OR p.current_name LIKE ? OR p.steam_id = ?
        GROUP BY p.plutonium_id
        LIMIT 5
        """,
        (query, f"%{query}%", query),
    ).fetchall()
    return rows


CONNECT_RE = re.compile(r"client\s+'([^']+)'\s+connected", re.I)
AUTH_RE = re.compile(r"User with id\s+(\d+)\s+successfully authenticated", re.I)
LET_PLAYER_RE = re.compile(r"Letting player with userid\s+(\d+)", re.I)
CLIENT_ENDPOINT_RE = re.compile(r"'(\d{1,3}(?:\.\d{1,3}){3}):\d+'")
STEAM_RE = re.compile(r"steam(?:_id)?[:=\s]+(\d+)", re.I)
REPORT_CHAT_RE = re.compile(r"!report\s+(\S+)(?:\s+(.*))?", re.I)
