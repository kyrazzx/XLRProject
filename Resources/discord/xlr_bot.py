#!/usr/bin/env python3

import asyncio
import json
import os
import socket
import subprocess
import sys
from pathlib import Path

import discord
from discord.ext import commands, tasks

WORKROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = WORKROOT / "Plutonium" / "server_config.json"
MANAGER_PATH = WORKROOT / "Plutonium" / "XLRManager.sh"


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def run_manager(*args):
    if not MANAGER_PATH.exists():
        return 1, "XLRManager not found"
    result = subprocess.run(
        ["bash", str(MANAGER_PATH), *args],
        capture_output=True,
        text=True,
        timeout=120,
    )
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode, output.strip() or "done"


def rcon_query(host, port, password, command):
    payload = f"\xff\xff\xff\xffrcon {password} {command}".encode("latin-1", errors="ignore")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    try:
        sock.sendto(payload, (host, int(port)))
        data, _ = sock.recvfrom(4096)
        if len(data) > 4:
            return data[4:].decode("latin-1", errors="ignore")
    except OSError:
        return ""
    finally:
        sock.close()
    return ""


def parse_player_count(status_text):
    for line in status_text.splitlines():
        lower = line.lower()
        if "players" in lower:
            parts = line.split()
            for part in parts:
                if part.isdigit():
                    return int(part)
    return 0


def server_status_lines(config):
    general = config.get("general_config", {})
    host = general.get("rcon_ip", "127.0.0.1")
    lines = []
    for server in config.get("servers", []):
        if not server.get("enabled", True):
            continue
        port = server.get("port")
        password = server.get("rcon_password") or server.get("key", "")
        name = server.get("name", server.get("id", "server"))
        sid = server.get("id")
        status = rcon_query(host, port, password, "status")
        if status:
            players = parse_player_count(status)
            lines.append(f"**{name}** (`{sid}`) — online — {players} players — port {port}")
        else:
            lines.append(f"**{name}** (`{sid}`) — offline — port {port}")
    return lines


class XLRBot(commands.Bot):
    def __init__(self, config):
        intents = discord.Intents.default()
        intents.message_content = True
        super().__init__(command_prefix="!", intents=intents)
        self.config = config

    async def setup_hook(self):
        interval = int(self.config.get("discord_config", {}).get("update_interval", 60))
        self.status_loop.change_interval(seconds=max(interval, 30))
        self.status_loop.start()

    async def on_ready(self):
        await self.change_presence(activity=discord.Game(name="XLR T6 Servers"))

    @tasks.loop(seconds=60)
    async def status_loop(self):
        self.config = load_config()
        lines = server_status_lines(self.config)
        summary = " | ".join(line.replace("**", "") for line in lines[:3]) or "XLR T6"
        await self.change_presence(activity=discord.Game(name=summary[:120]))

    @status_loop.before_loop
    async def before_status_loop(self):
        await self.wait_until_ready()


def main():
    if not CONFIG_PATH.exists():
        print(f"Missing configuration: {CONFIG_PATH}")
        sys.exit(1)

    config = load_config()
    discord_config = config.get("discord_config", {})
    token = discord_config.get("token") or os.environ.get("XLR_DISCORD_TOKEN", "")

    if not token:
        print("Discord token not configured")
        sys.exit(1)

    if not discord_config.get("enabled", False):
        print("Discord bot disabled in configuration")
        sys.exit(0)

    bot = XLRBot(config)

    @bot.command(name="status")
    async def status_command(ctx):
        config_data = load_config()
        lines = server_status_lines(config_data)
        await ctx.send("\n".join(lines) or "No servers configured")

    @bot.command(name="players")
    async def players_command(ctx, server_id: str = ""):
        config_data = load_config()
        host = config_data.get("general_config", {}).get("rcon_ip", "127.0.0.1")
        replies = []
        for server in config_data.get("servers", []):
            if server_id and server.get("id") != server_id:
                continue
            port = server.get("port")
            password = server.get("rcon_password") or server.get("key", "")
            response = rcon_query(host, port, password, "status")
            count = parse_player_count(response)
            replies.append(f"{server.get('name')} ({server.get('id')}): {count} players")
        await ctx.send("\n".join(replies) or "No data")

    @bot.command(name="restart")
    @commands.has_permissions(administrator=True)
    async def restart_command(ctx, server_id: str = "all"):
        code, output = await asyncio.to_thread(run_manager, "restart", server_id)
        await ctx.send(output[:1900] if output else ("restart failed" if code else "restart sent"))

    @bot.command(name="xlrbackup")
    @commands.has_permissions(administrator=True)
    async def backup_command(ctx):
        code, output = await asyncio.to_thread(run_manager, "backup")
        await ctx.send(output[:1900] if output else ("backup failed" if code else "backup complete"))

    @bot.command(name="xlrhelp")
    async def help_command(ctx):
        await ctx.send("Commands: !status !players [id] !restart [id|all] !xlrbackup !xlrhelp")

    bot.run(token)


if __name__ == "__main__":
    main()
