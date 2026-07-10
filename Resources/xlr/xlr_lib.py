import json
import os
import random
import re
import socket
import sqlite3
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
WORKROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKROOT / 'Plutonium' / 'server_config.json'
SECRETS_PATH = Path('/etc/xlr/secrets.env')
DEFAULT_DB_DIR = WORKROOT / 'Plutonium' / 'storage' / 'xlr'

def utc_now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

def load_config():
    with open(CONFIG_PATH, 'r', encoding='utf-8') as handle:
        return json.load(handle)

def load_secrets():
    secrets = {}
    if SECRETS_PATH.is_file():
        for line in SECRETS_PATH.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            (key, value) = line.split('=', 1)
            secrets[key.strip()] = value.strip().strip('"').strip("'")
    return secrets

def discord_token():
    secrets = load_secrets()
    if secrets.get('DISCORD_TOKEN'):
        return secrets['DISCORD_TOKEN']
    config = load_config()
    token = config.get('discord_config', {}).get('token', '')
    if token and token != 'YOUR_DISCORD_TOKEN':
        return token
    return os.environ.get('XLR_DISCORD_TOKEN', '')

def discord_webhook_url():
    secrets = load_secrets()
    url = (secrets.get('DISCORD_WEBHOOK') or '').strip()
    if url:
        return url
    config = load_config()
    return (config.get('monitoring_config', {}).get('discord_webhook') or '').strip()

def db_path():
    config = load_config()
    rel = config.get('moderation', {}).get('players_db', 'Plutonium/storage/xlr/players.db')
    path = WORKROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    return path

def connect_db():
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    return conn

def init_db(conn):
    conn.executescript("\n        CREATE TABLE IF NOT EXISTS players (\n            plutonium_id TEXT PRIMARY KEY,\n            steam_id TEXT,\n            current_name TEXT,\n            first_seen TEXT NOT NULL,\n            last_seen TEXT NOT NULL\n        );\n        CREATE TABLE IF NOT EXISTS player_ips (\n            plutonium_id TEXT NOT NULL,\n            ip TEXT NOT NULL,\n            first_seen TEXT NOT NULL,\n            last_seen TEXT NOT NULL,\n            PRIMARY KEY (plutonium_id, ip)\n        );\n        CREATE TABLE IF NOT EXISTS player_names (\n            plutonium_id TEXT NOT NULL,\n            name TEXT NOT NULL,\n            first_seen TEXT NOT NULL,\n            PRIMARY KEY (plutonium_id, name)\n        );\n        CREATE TABLE IF NOT EXISTS bans (\n            id INTEGER PRIMARY KEY AUTOINCREMENT,\n            plutonium_id TEXT,\n            ip TEXT,\n            reason TEXT,\n            banned_by TEXT,\n            banned_at TEXT NOT NULL,\n            active INTEGER NOT NULL DEFAULT 1\n        );\n        CREATE TABLE IF NOT EXISTS server_players (\n            server_id TEXT NOT NULL,\n            plutonium_id TEXT NOT NULL,\n            first_seen TEXT NOT NULL,\n            PRIMARY KEY (server_id, plutonium_id)\n        );\n        CREATE TABLE IF NOT EXISTS reports (\n            id INTEGER PRIMARY KEY AUTOINCREMENT,\n            reporter_name TEXT,\n            reporter_id TEXT,\n            target_name TEXT,\n            target_id TEXT,\n            reason TEXT,\n            server_id TEXT,\n            source TEXT,\n            created_at TEXT NOT NULL,\n            status TEXT NOT NULL DEFAULT 'pending',\n            discord_message_id TEXT\n        );\n        ")
    purge_bot_records(conn)
    conn.commit()

def purge_bot_records(conn):
    predicate = "plutonium_id IN ('0', '') OR plutonium_id LIKE '%:%'"
    for table in ('players', 'server_players', 'player_ips', 'player_names'):
        conn.execute(f'DELETE FROM {table} WHERE {predicate}')

def rcon_query(host, port, password, command):
    payload = f'ÿÿÿÿrcon {password} {command}'.encode('latin-1', errors='ignore')
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.4)
    chunks = []
    try:
        sock.sendto(payload, (host, int(port)))
        deadline = time.time() + 2.5
        while time.time() < deadline:
            try:
                (data, _) = sock.recvfrom(8192)
            except OSError:
                break
            if len(data) > 4:
                chunks.append(data[4:].decode('latin-1', errors='ignore'))
    finally:
        sock.close()
    return ''.join(chunks)

def _udp_oob_collect(host, port, payload, timeout=3.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    chunks = []
    try:
        sock.sendto(payload, (host, int(port)))
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                sock.settimeout(max(0.1, deadline - time.time()))
                (data, _) = sock.recvfrom(16384)
            except OSError:
                if chunks:
                    break
                return ''
            if len(data) > 4:
                chunks.append(data[4:].decode('latin-1', errors='ignore'))
    finally:
        sock.close()
    return ''.join(chunks)

def _parse_infostring(text):
    info = {}
    tokens = text.strip().split('\\')
    if tokens and tokens[0] == '':
        tokens = tokens[1:]
    for i in range(0, len(tokens) - 1, 2):
        info[tokens[i].lower()] = tokens[i + 1]
    return info

def _strip_player_name(name):
    cleaned = re.sub('\\^[0-9]', '', name or '')
    return cleaned.replace("'", '').replace('^7', '').strip()

def _bot_name_cache():
    if not hasattr(_bot_name_cache, 'payload'):
        _bot_name_cache.payload = {'ts': 0.0, 'names': set()}
    now = time.time()
    if now - _bot_name_cache.payload['ts'] < 60:
        return _bot_name_cache.payload['names']
    names = set()
    if BOTS_TXT_PATH.is_file():
        try:
            for line in BOTS_TXT_PATH.read_text(encoding='utf-8').splitlines():
                base = line.split(',', 1)[0].strip()
                if base:
                    names.add(base.lower())
        except OSError:
            pass
    _bot_name_cache.payload = {'ts': now, 'names': names}
    return names

def server_uses_bot_warfare(config, server_id):
    if not bot_warfare_enabled(config):
        return False
    ids = config.get('bot_warfare', {}).get('server_ids') or []
    return server_id in ids

def _parse_getstatus_player_line(line):
    line = line.strip()
    if not line or line.startswith('\\'):
        return None
    match = re.match('^(\\d+)\\s+(\\d+)\\s+"([^"]*)"(?:\\s+(\\S+))?$', line)
    if not match:
        match = re.match('^(\\d+)\\s+(\\d+)\\s+(\\S+)(?:\\s+(\\S+))?$', line)
    if match:
        address = (match.group(4) or '').strip()
        return {'score': int(match.group(1)), 'ping': int(match.group(2)), 'name': match.group(3), 'address': address, 'guid': ''}
    cod_match = re.match('^(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\S+)\\s+"(.*?)"(?:\\s+(\\S+))?$', line)
    if not cod_match:
        cod_match = re.match('^(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\S+)\\s+(\\S+)(?:\\s+(\\S+))?$', line)
    if cod_match:
        guid = cod_match.group(4).replace('^7', '').replace("'", '').strip()
        name = cod_match.group(5).replace('^7', '').replace("'", '').strip()
        address = ''
        if cod_match.lastindex and cod_match.lastindex >= 6:
            address = (cod_match.group(6) or '').strip()
        if not address and re.search('\\bbot\\b', line, re.I):
            address = 'bot'
        ip_match = re.search('(\\d{1,3}(?:\\.\\d{1,3}){3}):\\d+', line)
        if ip_match:
            address = ip_match.group(0)
        return {'score': int(cod_match.group(2)), 'ping': int(cod_match.group(3)), 'name': name, 'address': address, 'guid': guid}
    return None

def _iter_getstatus_clients(rows, bot_names=None):
    clients = []
    for row in rows[1:]:
        client = _parse_getstatus_player_line(row)
        if client is not None:
            clients.append(client)
    return clients

def _extract_status_info(text):
    info = {}
    if not text:
        return info
    for line in text.replace('\r\n', '\n').split('\n'):
        if '\\' not in line:
            continue
        if any((key in line for key in ('\\hostname\\', '\\clients\\', '\\gamename\\', '\\mapname\\'))):
            info.update(_parse_infostring(line))
    if not info.get('clients'):
        tokens = text.split('\\')
        if tokens and tokens[0] == '':
            tokens = tokens[1:]
        for i in range(0, len(tokens) - 1, 2):
            info[tokens[i].lower()] = tokens[i + 1]
    return info

def _loose_scan_player_lines(text, bot_names=None):
    if bot_names is None:
        bot_names = _bot_name_cache()
    humans = 0
    bots = 0
    for line in text.replace('\r', '\n').split('\n'):
        line = line.strip()
        if not line or '\\hostname\\' in line or '\\clients\\' in line:
            continue
        client = _parse_getstatus_player_line(line)
        if client:
            if is_bot_client(client, bot_names):
                bots += 1
            else:
                humans += 1
            continue
        if not re.match('^\\d', line):
            continue
        if re.search('\\bbot\\b', line, re.I):
            bots += 1
        elif re.search('\\d{1,3}(?:\\.\\d{1,3}){3}:\\d+', line):
            humans += 1
    return (humans, bots)

def _parse_getstatus_text(text, bot_names=None):
    if not text:
        return None
    body = text
    for marker in ('statusResponse', 'infoResponse', 'infoPrint'):
        idx = text.find(marker)
        if idx != -1:
            body = text[idx + len(marker):].lstrip('\r\n')
            break
    if body == text and ('\\hostname\\' in text or '\\clients\\' in text):
        body = text.lstrip('\r\n')
    rows = body.split('\n')
    info = _extract_status_info(text)
    if bot_names is None:
        bot_names = _bot_name_cache()
    clients = _iter_getstatus_clients(rows, bot_names=bot_names)
    if not clients:
        for line in text.replace('\r', '\n').split('\n'):
            client = _parse_getstatus_player_line(line.strip())
            if client is not None:
                clients.append(client)
    if clients:
        real = sum((1 for client in clients if not is_bot_client(client, bot_names)))
        total = len(clients)
        bots = total - real
        max_clients = 0
        for key in ('sv_maxclients', 'sv_privateclients', 'maxclients'):
            if key in info:
                try:
                    max_clients = int(info[key])
                    break
                except ValueError:
                    continue
        return {'total': total, 'bots': bots, 'real': real, 'max_clients': max_clients, 'info': info, 'reliable': True}
    (loose_humans, loose_bots) = _loose_scan_player_lines(text, bot_names=bot_names)
    if loose_humans > 0 or loose_bots > 0:
        return {'total': loose_humans + loose_bots, 'bots': loose_bots, 'real': loose_humans, 'max_clients': 0, 'info': info, 'reliable': True}
    clients_total = _infostring_client_count(info)
    bot_count = _infostring_bot_count(info)
    if clients_total is not None and bot_count is not None:
        real = max(clients_total - bot_count, 0)
        return {'total': clients_total, 'bots': bot_count, 'real': real, 'max_clients': 0, 'info': info, 'reliable': True}
    return None

def fetch_getstatus_raw(host, port, timeout=5.0, public_ip=None):
    payloads = (b'\xff\xff\xff\xffgetstatus\n', b'\xff\xff\xff\xffgetstatus', b'\xff\xff\xff\xffgetinfo\n')
    for target in _player_query_hosts(host, public_ip):
        for payload in payloads:
            text = _udp_oob_collect(target, port, payload, timeout=timeout)
            if text:
                return text
    return ''

def query_server_getstatus(host, port, timeout=5.0, bot_names=None, public_ip=None):
    payloads = (b'\xff\xff\xff\xffgetstatus\n', b'\xff\xff\xff\xffgetstatus', b'\xff\xff\xff\xffgetinfo\n')
    for target in _player_query_hosts(host, public_ip):
        for payload in payloads:
            text = _udp_oob_collect(target, port, payload, timeout=timeout)
            result = _parse_getstatus_text(text, bot_names=bot_names)
            if result is not None:
                return result
    return None

def _infostring_bot_count(info):
    for key in ('bots', 'botclients', 'sv_bots', 'numbots'):
        if key not in info:
            continue
        try:
            return max(int(info[key]), 0)
        except ValueError:
            continue
    return None

def _infostring_client_count(info):
    for key in ('clients', 'numplayers'):
        if key not in info:
            continue
        try:
            return max(int(info[key]), 0)
        except ValueError:
            continue
    return None

PLUTONIUM_API_URL = 'https://plutonium.pw/api/servers'
_PLUTO_CACHE = {'ts': 0.0, 'data': None}
_PLUTO_CACHE_TTL = 10
_PUBLIC_IP_CACHE = None

def detect_public_ip(timeout=4):
    for url in ('https://api.ipify.org', 'https://ifconfig.me/ip'):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'XLR-Bot/1.0'})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                ip = resp.read().decode('utf-8', errors='ignore').strip()
            if re.fullmatch('\\d{1,3}(?:\\.\\d{1,3}){3}', ip):
                return ip
        except Exception:
            continue
    return None

def resolve_public_ip(general=None, allow_detect=True):
    global _PUBLIC_IP_CACHE
    if general is None:
        general = load_config().get('general_config', {})
    ip = (general.get('public_ip') or '').strip()
    if ip:
        return ip
    env_ip = os.environ.get('XLR_PUBLIC_IP', '').strip()
    if env_ip:
        return env_ip
    if _PUBLIC_IP_CACHE:
        return _PUBLIC_IP_CACHE
    if allow_detect:
        detected = detect_public_ip()
        if detected:
            _PUBLIC_IP_CACHE = detected
            return detected
    return None
_PLUTO_HTTP_HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36', 'Accept': 'application/json, text/plain, */*', 'Accept-Language': 'en-US,en;q=0.9', 'Referer': 'https://plutonium.pw/', 'Origin': 'https://plutonium.pw'}

def fetch_plutonium_servers(force=False, timeout=8):
    now = time.time()
    if not force and _PLUTO_CACHE['data'] is not None and (now - _PLUTO_CACHE['ts'] < _PLUTO_CACHE_TTL):
        return _PLUTO_CACHE['data']
    try:
        req = urllib.request.Request(PLUTONIUM_API_URL, headers=_PLUTO_HTTP_HEADERS)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode('utf-8', errors='ignore'))
    except Exception:
        return _PLUTO_CACHE['data']
    if isinstance(data, list):
        _PLUTO_CACHE['data'] = data
        _PLUTO_CACHE['ts'] = now
    return _PLUTO_CACHE['data']

def plutonium_entry_ip(entry):
    for key in ('ip', 'host', 'address'):
        value = str(entry.get(key) or '').strip()
        if not value:
            continue
        if value.count(':') == 1 and value.replace('.', '').replace(':', '').isdigit():
            value = value.split(':', 1)[0]
        return value
    return ''

def match_plutonium_server(server, api_data=None, public_ip=None):
    if api_data is None:
        api_data = fetch_plutonium_servers()
    if not api_data:
        return None
    try:
        port = int(server.get('port'))
    except (TypeError, ValueError):
        return None
    name = (server.get('name') or '').strip()
    port_matches = []
    for entry in api_data:
        try:
            if int(entry.get('port')) != port:
                continue
        except (TypeError, ValueError):
            continue
        port_matches.append(entry)
    if not port_matches:
        return None
    candidates = port_matches
    if public_ip:
        ip_matches = [entry for entry in port_matches if not plutonium_entry_ip(entry) or plutonium_entry_ip(entry) == public_ip]
        if ip_matches:
            candidates = ip_matches
    if not candidates:
        return None
    for entry in candidates:
        hostname = entry.get('hostname') or ''
        if name and (hostname.startswith(name) or name in hostname):
            return entry
    if len(candidates) == 1:
        return candidates[0]
    return None

def plutonium_api_bot_count(entry):
    if not entry:
        return 0
    bots = entry.get('bots')
    return int(bots) if isinstance(bots, (int, float)) else 0

def is_real_api_player(player):
    pid = player.get('id')
    if pid is None:
        return False
    try:
        return int(pid) > 0
    except (TypeError, ValueError):
        return False

def plutonium_api_real_count(entry):
    if not entry:
        return 0
    players = entry.get('players')
    list_count = 0
    if isinstance(players, list):
        list_count = len([player for player in players if is_real_api_player(player)])
    clients = entry.get('clients')
    bots = plutonium_api_bot_count(entry)
    if isinstance(clients, (int, float)):
        derived = max(int(clients) - bots, 0)
        if list_count > 0:
            return min(list_count, derived)
        return derived
    return list_count

def plutonium_real_player_count(server, api_data=None, public_ip=None):
    entry = match_plutonium_server(server, api_data=api_data, public_ip=public_ip)
    if entry is None:
        return (None, None)
    return (plutonium_api_real_count(entry), plutonium_api_bot_count(entry))
SERVER_SHORT_LABELS = {'ffa': 'FFA', 'tdm': 'TDM', 'gungame': 'GG', 'zombies': 'ZM'}

def is_server_running(port):
    port = int(port)
    try:
        result = subprocess.run(['pgrep', '-f', 'plutonium-bootstrapper-win32.exe'], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError, ValueError):
        return False
    for pid in result.stdout.split():
        if not pid.strip():
            continue
        try:
            comm = subprocess.run(['ps', '-p', pid.strip(), '-o', 'comm='], capture_output=True, text=True, timeout=2)
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
        if comm.stdout.strip() in {'bash', 'sh', 'nohup', 'runuser', 'sudo', 'sleep', 'nice'}:
            continue
        cmdline_path = Path(f'/proc/{pid.strip()}/cmdline')
        if not cmdline_path.is_file():
            continue
        cmdline = cmdline_path.read_bytes().replace(b'\x00', b' ').decode('latin-1', errors='ignore')
        if re.search(f'net_port\\s+\\"?{port}\\"?', cmdline):
            return True
    return False

def is_bot_client(client, bot_names=None):
    address = str(client.get('address') or '').strip().lower()
    if address == 'bot':
        return True
    if bot_names is None:
        bot_names = _bot_name_cache()
    if bot_names:
        name = _strip_player_name(client.get('name') or '').lower()
        plain = re.sub('^\\[[^\\]]+\\]', '', name).strip()
        if name in bot_names or plain in bot_names:
            return True
    guid = str(client.get('guid') or '').strip()
    if guid == '0':
        return True
    ping = client.get('ping')
    if ping == 0 and address in ('', 'bot'):
        return True
    return False

def real_clients_only(clients):
    return [client for client in clients if not is_bot_client(client)]

def count_real_status_clients(clients):
    return sum((1 for client in clients if not is_bot_client(client)))

def parse_status_player_count(status_text):
    clients = parse_status_clients(status_text)
    if clients:
        return count_real_status_clients(clients)
    if not status_text:
        return 0
    human_match = re.search('(\\d+)\\s+humans?\\b', status_text, re.I)
    if human_match:
        return int(human_match.group(1))
    players_match = re.search('(\\d+)\\s+players?\\b', status_text, re.I)
    bots_match = re.search('(\\d+)\\s+bots?\\b', status_text, re.I)
    if players_match and bots_match:
        return max(int(players_match.group(1)) - int(bots_match.group(1)), 0)
    return 0

def _stdout_session_lines(lines, port=None):
    session_start = 0
    port_text = str(int(port)) if port is not None else ''
    for (index, line) in enumerate(lines):
        lower = line.lower()
        if 'bound socket to' in lower:
            if port_text and port_text not in line:
                continue
            session_start = index
            continue
        if any((token in lower for token in ('heartbeat successful', 'server initialization', 'started server on port'))):
            session_start = index
    if session_start == 0 and len(lines) > 1200:
        return lines[-1200:]
    return lines[session_start:]

def _disconnect_name(line):
    for pattern in DISCONNECT_PATTERNS:
        match = pattern.search(line)
        if match:
            return _strip_player_name(match.group(1)).lower()
    return ''

def estimate_players_from_stdout(log_path, port=None, max_bytes=524288, bot_names=None):
    path = Path(log_path) if log_path else None
    if not path or not path.is_file():
        return 0
    bot_names = bot_names or set()
    try:
        size = path.stat().st_size
        with open(path, 'rb') as handle:
            handle.seek(max(0, size - max_bytes))
            data = handle.read().decode('latin-1', errors='ignore')
    except OSError:
        return 0
    lines = _stdout_session_lines(data.splitlines(), port)
    online = set()
    for line in lines:
        if 'bound socket to' in line.lower():
            online.clear()
        connect = CONNECT_RE.search(line)
        if connect:
            name = _strip_player_name(connect.group(1)).lower()
            plain = re.sub('^\\[[^\\]]+\\]', '', name).strip()
            if not name or name in bot_names or plain in bot_names:
                continue
            online.add(name)
            continue
        dropped = _disconnect_name(line)
        if dropped:
            online.discard(dropped)
            plain = re.sub('^\\[[^\\]]+\\]', '', dropped).strip()
            online.discard(plain)
    return len(online)

ACTIVE_PLAYERS_PATH = WORKROOT / 'Plutonium' / 'storage' / 'xlr' / 'active_players.json'

def read_tracker_player_count(server_id):
    if not ACTIVE_PLAYERS_PATH.is_file():
        return None
    try:
        data = json.loads(ACTIVE_PLAYERS_PATH.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return None
    entry = data.get(server_id)
    if not entry:
        return None
    try:
        return max(int(entry.get('players', 0)), 0)
    except (TypeError, ValueError):
        return None

def resolve_install_dir(config):
    configured = (config.get('general_config', {}) or {}).get('install_dir', '')
    candidates = []
    if configured:
        candidates.append(Path(configured))
    candidates.append(WORKROOT / 'Plutonium')
    for path in candidates:
        if path.is_file():
            path = path.parent
        if (path / 'bin' / 'plutonium-bootstrapper-win32.exe').is_file():
            return path
    return WORKROOT / 'Plutonium'

def resolve_server_log_paths(config, server):
    install_dir = resolve_install_dir(config)
    servers_root = (config.get('general_config', {}) or {}).get('servers_root', './servers')
    root = Path(servers_root) if str(servers_root).startswith('/') else install_dir / str(servers_root).lstrip('./')
    sid = server.get('id', '')
    stdout_log = root / sid / 'logs' / 'stdout.log'
    game_log = install_dir / 'storage' / 't6' / 'logs' / (server.get('log_file') or '')
    return (stdout_log, game_log)

def estimate_humans_from_logs(config, server, port=None, bot_names=None):
    bot_names = bot_names or set()
    (stdout_log, game_log) = resolve_server_log_paths(config, server)
    total = 0
    for path in (stdout_log, game_log):
        count = estimate_players_from_stdout(path, port=port, bot_names=bot_names)
        if count > total:
            total = count
    return total

def api_human_player_count(server, config, public_ip=None):
    api_data = fetch_plutonium_servers(force=True)
    entry = match_plutonium_server(server, api_data=api_data, public_ip=public_ip)
    if not entry:
        return None
    count = plutonium_api_real_count(entry)
    return count if count >= 0 else None

def _human_player_cap(config, server, max_clients):
    cap = int(max_clients)
    if server and config and server_uses_bot_warfare(config, server.get('id')):
        fill = int(config.get('bot_warfare', {}).get('manage_fill', 12))
        cap = max(cap - fill, 1)
    return cap

def ss_udp_peer_count(port, public_ip=None, max_clients=18):
    skip = {'127.0.0.1', '0.0.0.0'}
    if public_ip:
        skip.add(public_ip)
    ips = []
    try:
        result = subprocess.run(['ss', '-H', '-u', '-n', f'sport = :{int(port)}'], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if result.returncode != 0:
        return None
    for line in (result.stdout or '').splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        peer = parts[4]
        if ':' not in peer:
            continue
        ip = peer.rsplit(':', 1)[0].strip('[]')
        if not re.fullmatch('\\d{1,3}(?:\\.\\d{1,3}){3}', ip):
            continue
        if ip in skip or ip in ips:
            continue
        ips.append(ip)
    if not ips:
        return None
    return min(len(ips), max_clients)

def _player_query_hosts(rcon_host, public_ip=None):
    hosts = []
    for candidate in (rcon_host, '127.0.0.1', public_ip):
        if candidate and candidate not in hosts:
            hosts.append(candidate)
    return hosts

def conntrack_real_player_count(port, public_ip=None, max_clients=18):
    skip = {'127.0.0.1', '0.0.0.0'}
    if public_ip:
        skip.add(public_ip)
    ips = []
    for ip in resolve_ips_from_conntrack(port, public_ip=public_ip):
        if ip in skip:
            continue
        if ip not in ips:
            ips.append(ip)
    if ips:
        return min(len(ips), max_clients)
    return ss_udp_peer_count(port, public_ip=public_ip, max_clients=max_clients)

def _server_stdout_log(config, server_id):
    server = {'id': server_id}
    return resolve_server_log_paths(config, server)[0]

def getstatus_player_count(host, port, public_ip=None, max_clients=18, bot_names=None):
    info = query_server_getstatus(host, port, bot_names=bot_names, public_ip=public_ip)
    if info is not None and info.get('reliable'):
        return min(int(info.get('real', 0)), max_clients)
    return None

def rcon_real_player_count(host, port, password, max_clients=18, public_ip=None, bot_names=None):
    for target in _player_query_hosts(host, public_ip):
        status = rcon_query(target, port, password, 'status')
        clients = parse_status_clients(status)
        if clients:
            count = sum((1 for client in clients if not is_bot_client(client, bot_names)))
            return min(count, max_clients)
        derived = parse_status_player_count(status)
        if derived > 0:
            return min(derived, max_clients)
    return None

def get_server_player_count(host, port, password, stdout_log=None, max_clients=18, public_ip=None, server_id=None, config=None):
    server = {'id': server_id, 'port': port, 'name': server_id}
    if config and server_id:
        for item in config.get('servers', []):
            if item.get('id') == server_id:
                server = item
                break
    bot_names = _bot_name_cache() if server_id and config and server_uses_bot_warfare(config, server_id) else set()
    human_cap = _human_player_cap(config, server, max_clients) if config else max_clients
    tracker_count = read_tracker_player_count(server_id) if server_id else None
    if tracker_count is not None:
        return min(tracker_count, human_cap)
    gs_count = getstatus_player_count(host, port, public_ip=public_ip, max_clients=human_cap, bot_names=bot_names)
    if gs_count is not None:
        return gs_count
    net_count = conntrack_real_player_count(port, public_ip=public_ip, max_clients=human_cap)
    if net_count is not None:
        return net_count
    api_count = api_human_player_count(server, config, public_ip=public_ip) if config else None
    if api_count is not None and api_count <= human_cap:
        return api_count
    if config and server_id:
        log_count = estimate_humans_from_logs(config, server, port=port, bot_names=bot_names)
        if 0 < log_count <= human_cap:
            return log_count
    rcon_count = rcon_real_player_count(host, port, password, max_clients=human_cap, public_ip=public_ip, bot_names=bot_names)
    if rcon_count is not None:
        return rcon_count
    return 0

def probe_server_runtime(host, port, password, public_ip=None, server_id=None, config=None):
    rcon_count = rcon_real_player_count(host, port, password, public_ip=public_ip)
    if rcon_count is not None:
        return (True, rcon_count)
    gs_count = getstatus_player_count(host, port, public_ip=public_ip)
    if gs_count is not None:
        return (True, gs_count)
    return (False, 0)

def collect_server_statuses(config):
    general = config.get('general_config', {})
    host = general.get('rcon_ip', '127.0.0.1')
    public_ip = resolve_public_ip(general)
    statuses = []
    total_players = 0
    online_servers = 0
    for server in config.get('servers', []):
        if not server.get('enabled', True):
            continue
        sid = server.get('id', 'server')
        try:
            port = int(server.get('port'))
        except (TypeError, ValueError):
            continue
        password = server.get('rcon_password') or server.get('key', '')
        name = server.get('name', sid)
        short = SERVER_SHORT_LABELS.get(sid, sid.upper()[:4])
        max_clients = int(server.get('additional_params', {}).get('sv_maxclients', 18))
        online = is_server_running(port)
        players = 0
        if online:
            players = get_server_player_count(host, port, password, max_clients=max_clients, public_ip=public_ip, server_id=sid, config=config)
        else:
            (rcon_online, rcon_players) = probe_server_runtime(host, port, password, public_ip=public_ip, server_id=sid, config=config)
            if rcon_online:
                online = True
                players = min(rcon_players, max_clients)
        if online:
            online_servers += 1
            total_players += players
        statuses.append({'id': sid, 'name': name, 'short': short, 'online': online, 'players': players})
    return (statuses, total_players, online_servers)

def format_discord_presence(statuses, total_players):
    online = [item for item in statuses if item['online']]
    if not online:
        return 'XLR EU | Black Ops II'
    if len(online) == 1:
        item = online[0]
        if total_players:
            return f"{item['short']} — {total_players} online"[:128]
        return f"{item['short']} — online"[:128]
    parts = [f"{item['short']} {item['players']}" for item in online]
    return ' · '.join(parts)[:128]

def format_discord_status_lines(statuses):
    lines = []
    for item in statuses:
        if item['online']:
            lines.append(f"**{item['name']}** — Online — {item['players']} players")
        else:
            lines.append(f"**{item['name']}** — Offline")
    return lines

def parse_status_clients(status_text):
    clients = []
    for line in status_text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith('num ') or line.startswith('--'):
            continue
        if not re.match('^\\d+\\s+', line):
            continue
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            client_num = int(parts[0])
        except ValueError:
            continue
        try:
            ping = int(parts[2])
        except ValueError:
            ping = -1
        guid = parts[3].replace('^7', '').replace("'", '').strip()
        name = parts[4].replace('^7', '').replace("'", '').strip()
        ip = ''
        address = ''
        for part in reversed(parts[5:]):
            token = part.strip()
            if token.lower() == 'bot':
                address = 'bot'
                break
            if ':' in token:
                address = token
                ip = token.split(':')[0].strip()
                break
        clients.append({'client_num': client_num, 'guid': guid, 'name': name, 'ip': ip, 'ping': ping, 'address': address})
    return clients

def resolve_ips_from_conntrack(port, public_ip=None):
    ips = []
    port_n = int(port)
    commands = (['conntrack', '-L', '-p', 'udp', '--dport', str(port_n)],)
    for cmd in commands:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
        if result.returncode != 0:
            continue
        for line in (result.stdout or '').splitlines():
            if public_ip and f'dst={public_ip}' not in line:
                continue
            match = re.search('src=(\\d+\\.\\d+\\.\\d+\\.\\d+)', line)
            if not match:
                continue
            ip = match.group(1)
            if ip not in ips:
                ips.append(ip)
    if ips:
        return ips
    proc_path = Path('/proc/net/nf_conntrack')
    if not proc_path.is_file():
        return ips
    port_token = f'dport={port_n}'
    try:
        for line in proc_path.read_text(encoding='utf-8', errors='ignore').splitlines():
            if port_token not in line:
                continue
            if public_ip and f'dst={public_ip}' not in line:
                continue
            match = re.search('src=(\\d+\\.\\d+\\.\\d+\\.\\d+)', line)
            if match:
                ip = match.group(1)
                if ip not in ips:
                    ips.append(ip)
    except OSError:
        pass
    return ips

def rcon_say(host, port, password, message):
    return rcon_query(host, port, password, f'say {message}')

def rcon_tell(host, port, password, client_num, message):
    return rcon_query(host, port, password, f'tell {client_num} {message}')

def send_player_welcome(server, client, config):
    message = welcome_message(config, client['name'])
    host = server['host']
    port = server['port']
    password = server['password']
    client_num = client['client_num']
    mode = config.get('customization', {}).get('welcome_mode', 'both')
    if mode in ('say', 'both'):
        rcon_say(host, port, password, message)
    if mode in ('tell', 'both'):
        rcon_tell(host, port, password, client_num, message)

def pick_auto_message(config):
    custom = config.get('customization', {})
    messages = custom.get('auto_messages_en') or []
    if not messages:
        return ''
    return random.choice(messages)

def game_tip_pool(config, conn, server_id):
    tips = list(config.get('customization', {}).get('auto_messages_en') or [])
    count = count_unique_players(conn, server_id)
    if count > 0:
        tips.append(f'^6[XLR]^7 Unique players since launch: ^6{count}')
    else:
        tips.append('^6[XLR]^7 Thanks for playing on XLR EU!')
    return tips

def force_random_game_tip(config=None, server_id='all'):
    config = config or load_config()
    target = (server_id or 'all').strip().lower()
    token = int(time.time())
    results = []
    for server in iter_enabled_servers(config):
        sid = server['id']
        if target not in ('all', '', '*') and sid != target:
            continue
        if not is_server_running(server['port']):
            results.append({'server_id': sid, 'sent': False, 'reason': 'offline'})
            continue
        host = server['host']
        port = server['port']
        password = server['password']
        status = rcon_query(host, port, password, 'status')
        players = len(real_clients_only(parse_status_clients(status)))
        rcon_query(host, port, password, f'set xlr_force_tip {token}')
        rcon_query(host, port, password, f'seta xlr_force_tip {token}')
        results.append({'server_id': sid, 'sent': True, 'message': 'In-game tip triggered via GSC', 'players': players})
    return results

def iter_enabled_servers(config):
    general = config.get('general_config', {})
    host = general.get('rcon_ip', '127.0.0.1')
    for server in config.get('servers', []):
        if not server.get('enabled', True):
            continue
        yield {'id': server.get('id'), 'port': server.get('port'), 'password': server.get('rcon_password') or server.get('key', ''), 'host': host}

def get_active_ban_reason(conn, plutonium_id=None, ip=None):
    if ip:
        row = conn.execute('SELECT reason FROM bans WHERE active = 1 AND ip = ? ORDER BY banned_at DESC LIMIT 1', (ip,)).fetchone()
        if row and row['reason']:
            return row['reason']
    if plutonium_id:
        row = conn.execute('SELECT reason FROM bans WHERE active = 1 AND plutonium_id = ? ORDER BY banned_at DESC LIMIT 1', (plutonium_id,)).fetchone()
        if row and row['reason']:
            return row['reason']
    return ''

def ban_announce_message(player_name, reason=''):
    name = player_name or 'A player'
    reason = (reason or '').strip()
    if reason:
        return f'^1[XLR]^7 {name} ^7was banned. Reason: ^1{reason}'
    return f'^1[XLR]^7 {name} ^7was banned.'

def find_online_client(config, plutonium_id=None, ip=None):
    for server in iter_enabled_servers(config):
        status = rcon_query(server['host'], server['port'], server['password'], 'status')
        for client in parse_status_clients(status):
            client_ip = client.get('ip') or ''
            client_guid = client.get('guid') or ''
            if ip and client_ip == ip:
                return (server, client)
            if plutonium_id and client_guid == str(plutonium_id):
                return (server, client)
    return (None, None)

def announce_ban_and_kick(config, plutonium_id=None, ip=None, player_name=None, reason=''):
    (server, client) = find_online_client(config, plutonium_id=plutonium_id, ip=ip)
    if not server or not client:
        return False
    name = client.get('name') or player_name or 'A player'
    message = ban_announce_message(name, reason)
    host = server['host']
    port = server['port']
    password = server['password']
    rcon_say(host, port, password, message)
    rcon_query(host, port, password, f"clientkick {client['client_num']} banned")
    return True

def kick_announce_message(player_name, reason=''):
    name = player_name or 'A player'
    reason = (reason or '').strip()
    if reason:
        return f'^1[XLR]^7 {name} ^7was kicked. Reason: ^1{reason}'
    return f'^1[XLR]^7 {name} ^7was kicked.'

def announce_kick(config, plutonium_id=None, ip=None, player_name=None, reason=''):
    (server, client) = find_online_client(config, plutonium_id=plutonium_id, ip=ip)
    if not server or not client:
        return (False, None)
    name = client.get('name') or player_name or 'A player'
    message = kick_announce_message(name, reason)
    host = server['host']
    port = server['port']
    password = server['password']
    rcon_say(host, port, password, message)
    kick_reason = reason.strip() if (reason or '').strip() else 'kicked by staff'
    rcon_query(host, port, password, f"clientkick {client['client_num']} {kick_reason}")
    return (True, name)

def send_player_tips(config, server, clients, state):
    sid = server['id']
    interval = int(config.get('customization', {}).get('auto_message_interval_seconds', 300))
    now = time.time()
    last = state.setdefault(sid, {}).get('last_auto_message', 0)
    if now - last < interval:
        return
    messages = config.get('customization', {}).get('auto_messages_en') or []
    if not messages or not clients:
        return
    tip_index = state[sid].get('tip_index', 0)
    host = server['host']
    port = server['port']
    password = server['password']
    for (offset, client) in enumerate(clients):
        message = messages[(tip_index + offset) % len(messages)]
        rcon_tell(host, port, password, client['client_num'], message)
    state[sid]['tip_index'] = (tip_index + len(clients)) % len(messages)
    state[sid]['last_auto_message'] = now

def record_server_player(conn, server_id, plutonium_id):
    if not server_id or not plutonium_id:
        return
    conn.execute('INSERT OR IGNORE INTO server_players (server_id, plutonium_id, first_seen) VALUES (?, ?, ?)', (server_id, str(plutonium_id), utc_now()))
    conn.commit()

def count_unique_players(conn, server_id=None):
    if server_id:
        row = conn.execute('SELECT COUNT(*) AS total FROM server_players WHERE server_id = ?', (server_id,)).fetchone()
    else:
        row = conn.execute('SELECT COUNT(*) AS total FROM players').fetchone()
    return int(row['total']) if row else 0

def sync_server_game_dvars(server, config, conn):
    sid = server['id']
    host = server['host']
    port = server['port']
    password = server['password']
    unique_count = count_unique_players(conn, sid)
    tip_interval = int(config.get('customization', {}).get('auto_message_interval_seconds', 240))
    rcon_query(host, port, password, f'set xlr_unique_players {unique_count}')
    rcon_query(host, port, password, f'seta xlr_unique_players {unique_count}')
    rcon_query(host, port, password, f'set xlr_tip_interval {tip_interval}')
    rcon_query(host, port, password, f'seta xlr_tip_interval {tip_interval}')

def collect_platform_stats(conn, config):
    (statuses, total_players, online_servers) = collect_server_statuses(config)
    global_unique = count_unique_players(conn)
    active_bans = conn.execute('SELECT COUNT(*) AS total FROM bans WHERE active = 1').fetchone()['total']
    pending_reports = conn.execute("SELECT COUNT(*) AS total FROM reports WHERE status = 'pending'").fetchone()['total']
    per_server = []
    for item in statuses:
        per_server.append({**item, 'unique_players': count_unique_players(conn, item['id'])})
    return {'servers': per_server, 'total_players': total_players, 'online_servers': online_servers, 'global_unique_players': global_unique, 'active_bans': int(active_bans), 'pending_reports': int(pending_reports)}

def fetch_platform_stats(config=None):
    config = config or load_config()
    conn = connect_db()
    init_db(conn)
    try:
        return collect_platform_stats(conn, config)
    finally:
        conn.close()
BOTS_TXT_PATH = WORKROOT / 'Plutonium' / 'storage' / 't6' / 'bots.txt'
BOT_NAMES_FALLBACK_PATH = Path(__file__).resolve().parent / 'data' / 'bot_names_fallback.txt'

def bot_warfare_enabled(config=None):
    config = config or load_config()
    return bool(config.get('bot_warfare', {}).get('enabled', False))

def bot_name_exclusions(config):
    owner = (config.get('customization', {}).get('owner', {}).get('name') or 'akan3').strip().lower()
    extra = config.get('bot_warfare', {}).get('exclude_names') or []
    exclusions = {owner, 'akan3'}
    for item in extra:
        if item and str(item).strip():
            exclusions.add(str(item).strip().lower())
    return exclusions

def sanitize_bot_name(name):
    name = re.sub('[^\\w\\-\\[\\]]', '', (name or '').strip())
    return name[:15]

def load_fallback_bot_names(exclusions):
    names = []
    if not BOT_NAMES_FALLBACK_PATH.is_file():
        return names
    for line in BOT_NAMES_FALLBACK_PATH.read_text(encoding='utf-8').splitlines():
        name = sanitize_bot_name(line)
        if not name or name.lower() in exclusions:
            continue
        names.append(name)
    return names

def sync_bots_txt(conn=None, config=None):
    config = config or load_config()
    if not bot_warfare_enabled(config):
        return 0
    bw = config.get('bot_warfare', {})
    tag = sanitize_bot_name(bw.get('clan_tag') or 'XLR')[:4] or 'XLR'
    limit = int(bw.get('name_pool_size', 200))
    exclusions = bot_name_exclusions(config)
    own_conn = conn is None
    if own_conn:
        conn = connect_db()
        init_db(conn)
    names = []
    try:
        rows = conn.execute('\n            SELECT DISTINCT name FROM player_names\n            WHERE length(trim(name)) > 0\n            ORDER BY RANDOM()\n            LIMIT ?\n            ', (max(limit * 3, 60),)).fetchall()
        for row in rows:
            name = sanitize_bot_name(row['name'])
            if not name or name.lower() in exclusions:
                continue
            if name in names:
                continue
            names.append(name)
            if len(names) >= limit:
                break
    finally:
        if own_conn:
            conn.close()
    if len(names) < 20:
        for name in load_fallback_bot_names(exclusions):
            if name not in names:
                names.append(name)
            if len(names) >= max(20, limit):
                break
    if not names:
        names = [f'Player{i}' for i in range(1, 21)]
    lines = [f'{name},{tag}' for name in names]
    BOTS_TXT_PATH.parent.mkdir(parents=True, exist_ok=True)
    BOTS_TXT_PATH.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(lines)

def welcome_message(config, player_name):
    custom = config.get('customization', {})
    invite = custom.get('discord_invite', 'discord.gg/63FAj2ZMrN')
    template = custom.get('welcome_chat_en', '^5[XLR]^7 Welcome {player}! Discord: {discord}')
    return template.format(player=player_name, discord=invite)

def upsert_player(conn, plutonium_id, name, ip, steam_id=None):
    now = utc_now()
    row = conn.execute('SELECT plutonium_id FROM players WHERE plutonium_id = ?', (plutonium_id,)).fetchone()
    if row:
        conn.execute('UPDATE players SET current_name = ?, last_seen = ?, steam_id = COALESCE(?, steam_id) WHERE plutonium_id = ?', (name, now, steam_id, plutonium_id))
    else:
        conn.execute('INSERT INTO players (plutonium_id, steam_id, current_name, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)', (plutonium_id, steam_id, name, now, now))
    if name:
        conn.execute('INSERT OR IGNORE INTO player_names (plutonium_id, name, first_seen) VALUES (?, ?, ?)', (plutonium_id, name, now))
    if ip:
        conn.execute('\n            INSERT INTO player_ips (plutonium_id, ip, first_seen, last_seen)\n            VALUES (?, ?, ?, ?)\n            ON CONFLICT(plutonium_id, ip) DO UPDATE SET last_seen = excluded.last_seen\n            ', (plutonium_id, ip, now, now))
    conn.commit()

def is_banned(conn, plutonium_id=None, ip=None):
    if ip:
        row = conn.execute('SELECT 1 FROM bans WHERE active = 1 AND ip = ? LIMIT 1', (ip,)).fetchone()
        if row:
            return True
    if plutonium_id:
        row = conn.execute('SELECT 1 FROM bans WHERE active = 1 AND plutonium_id = ? LIMIT 1', (plutonium_id,)).fetchone()
        if row:
            return True
    return False

def nft_ban_ip(ip):
    if not ip:
        return
    subprocess.run(['nft', 'add', 'element', 'inet', 'xlr', 'banned_ips', '{' + ip + '}'], capture_output=True, text=True)

def nft_unban_ip(ip):
    if not ip:
        return
    subprocess.run(['nft', 'delete', 'element', 'inet', 'xlr', 'banned_ips', '{' + ip + '}'], capture_output=True, text=True)

def add_ban(conn, ip=None, plutonium_id=None, reason='', banned_by='system'):
    now = utc_now()
    conn.execute('INSERT INTO bans (plutonium_id, ip, reason, banned_by, banned_at, active) VALUES (?, ?, ?, ?, ?, 1)', (plutonium_id, ip, reason, banned_by, now))
    conn.commit()
    if ip:
        nft_ban_ip(ip)

def remove_ban(conn, ip=None, plutonium_id=None):
    ips_to_unban = set()
    if ip:
        ips_to_unban.add(ip)
    if plutonium_id:
        ban_rows = conn.execute("\n            SELECT DISTINCT ip FROM bans\n            WHERE active = 1 AND plutonium_id = ? AND ip IS NOT NULL AND ip != ''\n            ", (plutonium_id,)).fetchall()
        for row in ban_rows:
            ips_to_unban.add(row['ip'])
        player_row = conn.execute('SELECT GROUP_CONCAT(DISTINCT ip) AS ips FROM player_ips WHERE plutonium_id = ?', (plutonium_id,)).fetchone()
        if player_row and player_row['ips']:
            ips_to_unban.update((ip.strip() for ip in player_row['ips'].split(',') if ip.strip()))
    clauses = []
    params = []
    if ip:
        clauses.append('ip = ?')
        params.append(ip)
    if plutonium_id:
        clauses.append('plutonium_id = ?')
        params.append(plutonium_id)
    if not clauses:
        return 0
    cur = conn.execute(f"UPDATE bans SET active = 0 WHERE active = 1 AND ({' OR '.join(clauses)})", params)
    conn.commit()
    for banned_ip in ips_to_unban:
        nft_unban_ip(banned_ip)
    return cur.rowcount

def create_report(conn, reporter_name, reporter_id, target_name, target_id, reason, server_id, source):
    now = utc_now()
    cur = conn.execute('\n        INSERT INTO reports (reporter_name, reporter_id, target_name, target_id, reason, server_id, source, created_at)\n        VALUES (?, ?, ?, ?, ?, ?, ?, ?)\n        ', (reporter_name, reporter_id, target_name, target_id, reason, server_id, source, now))
    conn.commit()
    return cur.lastrowid

def lookup_player(conn, query):
    query = query.strip()
    rows = conn.execute('\n        SELECT p.*, GROUP_CONCAT(DISTINCT pi.ip) AS ips\n        FROM players p\n        LEFT JOIN player_ips pi ON pi.plutonium_id = p.plutonium_id\n        WHERE p.plutonium_id = ? OR p.current_name LIKE ? OR p.steam_id = ?\n        GROUP BY p.plutonium_id\n        LIMIT 5\n        ', (query, f'%{query}%', query)).fetchall()
    return rows
CONNECT_RE = re.compile("client\\s+'([^']+)'\\s+connected", re.I)
DISCONNECT_RE = re.compile("client\\s+'([^']+)'\\s+disconnected", re.I)
DISCONNECT_PATTERNS = (DISCONNECT_RE, re.compile("client\\s+'([^']+)'\\s+dropped", re.I), re.compile('client\\s+([^\\s]+)\\s+disconnected', re.I), re.compile("lost connection to client\\s+'([^']+)'", re.I))
AUTH_RE = re.compile('User with id\\s+(\\d+)\\s+successfully authenticated', re.I)
LET_PLAYER_RE = re.compile('Letting player with userid\\s+(\\d+)', re.I)
CLIENT_ENDPOINT_RE = re.compile("'(\\d{1,3}(?:\\.\\d{1,3}){3}):\\d+'")
STEAM_RE = re.compile('steam(?:_id)?[:=\\s]+(\\d+)', re.I)
REPORT_CHAT_RE = re.compile('!report\\s+(\\S+)(?:\\s+(.*))?', re.I)
