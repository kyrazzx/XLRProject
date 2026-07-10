#!/usr/bin/env python3
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from xlr_lib import WORKROOT, discord_webhook_url, is_server_running, load_config, resolve_install_dir, utc_now

STATE_PATH = WORKROOT / 'Plutonium' / 'storage' / 'xlr' / 'watchdog_state.json'
ERROR_RE = re.compile(
    r'error|fatal|assert|crash|exception|corrupt|fastfile|ipak|zone|overflow|stack|'
    r'signal|segfault|abort|wine:|err:|out of memory|cannot load|missing|failed|'
    r'limbo|no current map|pure client|killed process',
    re.I,
)
LIMBO_RE = re.compile(r'no current map loaded|no map specified in sv_maprotation|map_restart will do nothing', re.I)
INTENTIONAL_RESTART_RE = re.compile(
    r'Scheduled restart \(idle|Scheduled restart skipped|Starting XLR \|',
    re.I,
)


def format_duration(seconds):
    seconds = max(int(seconds or 0), 0)
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f'{hours}h {minutes}m {secs}s'
    if minutes:
        return f'{minutes}m {secs}s'
    return f'{secs}s'


def find_server_pid(port):
    port = int(port)
    try:
        result = subprocess.run(['pgrep', '-f', 'plutonium-bootstrapper-win32.exe'], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    for pid in result.stdout.split():
        pid = pid.strip()
        if not pid:
            continue
        cmdline_path = Path(f'/proc/{pid}/cmdline')
        if not cmdline_path.is_file():
            continue
        cmdline = cmdline_path.read_bytes().replace(b'\x00', b' ').decode('latin-1', errors='ignore')
        if re.search(f'net_port\\s+\\"?{port}\\"?', cmdline):
            return int(pid)
    return None


def process_uptime_seconds(pid):
    if not pid:
        return 0
    try:
        result = subprocess.run(['ps', '-p', str(pid), '-o', 'lstart='], capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.SubprocessError, ValueError):
        return 0
    started = (result.stdout or '').strip()
    if not started:
        return 0
    try:
        result = subprocess.run(['date', '-d', started, '+%s'], capture_output=True, text=True, timeout=2)
        started_at = int((result.stdout or '0').strip() or 0)
    except (OSError, subprocess.SubprocessError, ValueError):
        return 0
    if started_at <= 0:
        return 0
    return max(int(time.time()) - started_at, 0)


def server_log_paths(config, server):
    install_dir = resolve_install_dir(config)
    servers_root = (config.get('general_config', {}) or {}).get('servers_root', './servers')
    root = Path(servers_root) if str(servers_root).startswith('/') else install_dir / str(servers_root).lstrip('./')
    sid = server.get('id', '')
    log_dir = root / sid / 'logs'
    return {
        'stdout': log_dir / 'stdout.log',
        'wrapper': log_dir / 'wrapper.log',
        'manager': log_dir / 'manager.log',
        'monitoring': install_dir / 'logs' / 'monitoring' / 'manager.log',
    }


def tail_text(path, lines=200, max_bytes=524288):
    path = Path(path)
    if not path.is_file():
        return f'(missing {path})\n'
    try:
        size = path.stat().st_size
        with open(path, 'rb') as handle:
            handle.seek(max(0, size - max_bytes))
            data = handle.read().decode('latin-1', errors='ignore')
    except OSError as exc:
        return f'(read error {path}: {exc})\n'
    rows = data.splitlines()
    if len(rows) > lines:
        rows = rows[-lines:]
    return '\n'.join(rows) + '\n'


def grep_errors(text, limit=25):
    matches = []
    for line in text.splitlines():
        if ERROR_RE.search(line):
            matches.append(line.strip())
    return matches[-limit:]


def kernel_hints():
    try:
        result = subprocess.run(
            ['journalctl', '-k', '--since', '45 min ago', '--no-pager'],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.SubprocessError, ValueError):
        return ''
    if result.returncode != 0:
        return ''
    rows = []
    for line in (result.stdout or '').splitlines():
        if re.search(r'oom|killed process|segfault|out of memory|wine|plutonium', line, re.I):
            rows.append(line)
    return '\n'.join(rows[-20:])


def memory_summary():
    try:
        result = subprocess.run(['free', '-h'], capture_output=True, text=True, timeout=3)
        if result.returncode == 0:
            return (result.stdout or '').strip()
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return '(unavailable)'


def build_log_bundle(config, server, paths):
    sid = server.get('id', 'server')
    chunks = [
        f'=== XLR crash report {utc_now()} ===',
        f'server: {server.get("name", sid)} ({sid})',
        f'port: {server.get("port")}',
        '',
        '=== memory ===',
        memory_summary(),
        '',
        '=== kernel (45 min) ===',
        kernel_hints() or '(nothing relevant)',
        '',
        '=== manager.log ===',
        tail_text(paths['manager'], lines=80),
        '',
        '=== wrapper.log ===',
        tail_text(paths['wrapper'], lines=150),
        '',
        '=== stdout.log ===',
        tail_text(paths['stdout'], lines=250),
        '',
        '=== monitoring log ===',
        tail_text(paths['monitoring'], lines=40),
    ]
    return '\n'.join(chunks)


def load_state():
    if not STATE_PATH.is_file():
        return {}
    try:
        return json.loads(STATE_PATH.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2), encoding='utf-8')


def post_webhook(webhook_url, embed, attachment_name, attachment_body):
    payload = {'username': 'XLR Watchdog', 'embeds': [embed]}
    body = attachment_body or ''
    if len(body) > 1500:
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', delete=False, suffix='.txt') as handle:
            handle.write(body)
            temp_path = handle.name
        try:
            subprocess.run(
                [
                    'curl',
                    '-sS',
                    '-f',
                    '-F',
                    f'payload_json={json.dumps(payload)};type=application/json',
                    f'-F', f'files[0]=@{temp_path};filename={attachment_name}',
                    webhook_url,
                ],
                check=False,
                timeout=45,
            )
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
        return
    payload['content'] = f'```\n{body[:1800]}\n```'
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(webhook_url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=20):
            pass
    except (urllib.error.URLError, TimeoutError, OSError):
        pass


def should_alert(state_entry, kind, cooldown):
    last_kind = state_entry.get('last_alert_kind')
    last_ts = float(state_entry.get('last_alert_ts', 0))
    if last_kind == kind and (time.time() - last_ts) < cooldown:
        return False
    return True


def mark_alert(state_entry, kind):
    state_entry['last_alert_kind'] = kind
    state_entry['last_alert_ts'] = time.time()


def recent_intentional_restart(paths, grace_seconds=240):
    manager_tail = tail_text(paths['manager'], lines=30)
    if INTENTIONAL_RESTART_RE.search(manager_tail):
        return True
    return False


def check_server(config, server, state, webhook_url, cooldown):
    sid = server.get('id')
    port = int(server.get('port'))
    paths = server_log_paths(config, server)
    entry = state.setdefault(sid, {})
    running = is_server_running(port)
    pid = find_server_pid(port) if running else None
    uptime = process_uptime_seconds(pid) if pid else 0
    was_running = bool(entry.get('running', False))
    stdout_tail = tail_text(paths['stdout'], lines=120)
    errors = grep_errors(stdout_tail)
    limbo = bool(LIMBO_RE.search(stdout_tail))

    if running and pid:
        entry['running'] = True
        entry['pid'] = pid
        if not entry.get('started_at'):
            entry['started_at'] = time.time() - uptime if uptime else time.time()
        entry['last_seen_up'] = time.time()
    else:
        if was_running and should_alert(entry, 'down', cooldown):
            if recent_intentional_restart(paths):
                entry['restart_grace_until'] = time.time() + 240
                entry['running'] = False
                entry['pid'] = None
                return
            if float(entry.get('restart_grace_until', 0)) > time.time():
                entry['running'] = False
                entry['pid'] = None
                return
            started_at = float(entry.get('started_at') or entry.get('last_seen_up') or time.time())
            uptime_before = max(int(time.time() - started_at), 0)
            summary = errors[-5:] if errors else ['Process exited or stopped responding.']
            embed = {
                'title': f'🔴 {server.get("name", sid)} is DOWN',
                'color': 0xFF4444,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'fields': [
                    {'name': 'Server', 'value': f'{sid} (:{port})', 'inline': True},
                    {'name': 'Uptime before crash', 'value': format_duration(uptime_before), 'inline': True},
                    {'name': 'Status', 'value': 'DOWN — auto-restart expected via XLRManager', 'inline': False},
                    {'name': 'Error summary', 'value': '\n'.join(summary)[:1024] or 'n/a', 'inline': False},
                    {'name': 'Memory', 'value': memory_summary()[:1024], 'inline': False},
                ],
                'footer': {'text': 'XLR Crash Watchdog'},
            }
            bundle = build_log_bundle(config, server, paths)
            post_webhook(webhook_url, embed, f'{sid}_crash_{int(time.time())}.txt', bundle)
            mark_alert(entry, 'down')
        entry['running'] = False
        entry['pid'] = None
        entry['started_at'] = None

    if running and limbo and should_alert(entry, 'limbo', cooldown):
        embed = {
            'title': f'🟠 {server.get("name", sid)} stuck in limbo',
            'color': 0xFFAA00,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'fields': [
                {'name': 'Server', 'value': f'{sid} (:{port})', 'inline': True},
                {'name': 'Uptime', 'value': format_duration(uptime), 'inline': True},
                {'name': 'Status', 'value': 'RUNNING but no map loaded', 'inline': False},
            ],
            'footer': {'text': 'XLR Crash Watchdog'},
        }
        bundle = build_log_bundle(config, server, paths)
        post_webhook(webhook_url, embed, f'{sid}_limbo_{int(time.time())}.txt', bundle)
        mark_alert(entry, 'limbo')

    if running and errors and should_alert(entry, 'error', cooldown * 2):
        embed = {
            'title': f'🟡 {server.get("name", sid)} errors in log',
            'color': 0xFFCC00,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'fields': [
                {'name': 'Server', 'value': f'{sid} (:{port})', 'inline': True},
                {'name': 'Uptime', 'value': format_duration(uptime), 'inline': True},
                {'name': 'Recent errors', 'value': '\n'.join(errors[-8:])[:1024], 'inline': False},
            ],
            'footer': {'text': 'XLR Crash Watchdog'},
        }
        bundle = build_log_bundle(config, server, paths)
        post_webhook(webhook_url, embed, f'{sid}_errors_{int(time.time())}.txt', bundle)
        mark_alert(entry, 'error')


def main():
    webhook_url = discord_webhook_url()
    if not webhook_url:
        print('DISCORD_WEBHOOK not set in /etc/xlr/secrets.env — exiting')
        raise SystemExit(1)
    print(f'[watchdog] started {utc_now()}')
    while True:
        try:
            config = load_config()
            monitoring = config.get('monitoring_config', {})
            if monitoring.get('watchdog_enabled', True) is False:
                time.sleep(30)
                continue
            interval = int(monitoring.get('watchdog_interval', 20))
            cooldown = int(monitoring.get('alert_cooldown_seconds', 600))
            state = load_state()
            for server in config.get('servers', []):
                if not server.get('enabled', True):
                    continue
                check_server(config, server, state, webhook_url, cooldown)
            save_state(state)
        except Exception as exc:
            print(f'[watchdog] loop error: {exc}')
        time.sleep(max(interval, 10))


if __name__ == '__main__':
    main()
