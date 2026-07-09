#!/usr/bin/env python3
from xlr_lib import (
    WORKROOT,
    _bot_name_cache,
    _human_player_cap,
    api_human_player_count,
    conntrack_real_player_count,
    estimate_humans_from_logs,
    fetch_getstatus_raw,
    getstatus_player_count,
    load_config,
    query_server_getstatus,
    resolve_install_dir,
    resolve_public_ip,
    resolve_server_log_paths,
    rcon_query,
    server_uses_bot_warfare,
    ss_udp_peer_count,
)

def main():
    print('xlr_player_count=v3')
    config = load_config()
    general = config.get('general_config', {})
    host = general.get('rcon_ip', '127.0.0.1')
    public_ip = resolve_public_ip(general)
    print(f'workroot={WORKROOT}')
    print(f'install_dir={resolve_install_dir(config)}')
    print(f'public_ip={public_ip or "(auto)"}')
    for server in config.get('servers', []):
        if not server.get('enabled', True):
            continue
        sid = server.get('id')
        port = int(server.get('port'))
        password = server.get('rcon_password') or server.get('key', '')
        max_clients = int(server.get('additional_params', {}).get('sv_maxclients', 18))
        human_cap = _human_player_cap(config, server, max_clients)
        print(f'\n=== {sid} :{port} (human_cap={human_cap}) ===')
        bw = server_uses_bot_warfare(config, sid)
        print(f'bot_warfare={bw} known_bot_names={len(_bot_name_cache())}')
        stdout_log, game_log = resolve_server_log_paths(config, server)
        print(f'stdout_log={stdout_log} exists={stdout_log.is_file()}')
        print(f'game_log={game_log} exists={game_log.is_file()}')
        raw = fetch_getstatus_raw(host, port, public_ip=public_ip)
        if raw:
            preview = raw.replace('\n', '\\n')[:240]
            print(f'getstatus_raw={preview}')
        else:
            print('getstatus_raw=(empty)')
        gs = query_server_getstatus(host, port, public_ip=public_ip)
        if gs:
            print(f'getstatus: total={gs.get("total")} bots={gs.get("bots")} real={gs.get("real")} info={gs.get("info")}')
        else:
            print('getstatus: no reliable parse')
        print(f'getstatus_count={getstatus_player_count(host, port, public_ip=public_ip, max_clients=human_cap)}')
        print(f'ss_count={ss_udp_peer_count(port, public_ip=public_ip, max_clients=human_cap)}')
        print(f'api_count={api_human_player_count(server, config, public_ip=public_ip)}')
        print(f'conntrack_count={conntrack_real_player_count(port, public_ip=public_ip, max_clients=human_cap)}')
        print(f'log_count={estimate_humans_from_logs(config, server, port=port)}')
        rcon = rcon_query(host, port, password, 'status')
        preview = (rcon or '').replace('\n', ' ')[:160]
        print(f'rcon_status={preview or "(empty)"}')

if __name__ == '__main__':
    main()
