#!/usr/bin/env python3

import asyncio
import json
import subprocess
from pathlib import Path

import discord
from discord.ext import commands, tasks

from xlr_lib import (
    WORKROOT,
    add_ban,
    connect_db,
    create_report,
    discord_token,
    init_db,
    load_config,
    lookup_player,
    parse_status_clients,
    rcon_query,
    remove_ban,
    utc_now,
)

MANAGER_PATH = WORKROOT / "Plutonium" / "XLRManager.sh"


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
            players = len(parse_status_clients(status))
            lines.append(f"**{name}** (`{sid}`) — online — {players} players — port {port}")
        else:
            lines.append(f"**{name}** (`{sid}`) — offline — port {port}")
    return lines


def moderation_channel_id(config):
    mod = config.get("moderation", {})
    discord_cfg = config.get("discord_config", {})
    return (
        mod.get("discord_reports_channel_id", "")
        or discord_cfg.get("reports_channel_id", "")
    )


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
        self.reports_loop.start()

    async def on_ready(self):
        await self.change_presence(activity=discord.Game(name="XLR EU | BO2"))

    @tasks.loop(seconds=60)
    async def status_loop(self):
        self.config = load_config()
        lines = server_status_lines(self.config)
        summary = " | ".join(line.replace("**", "") for line in lines[:3]) or "XLR EU"
        await self.change_presence(activity=discord.Game(name=summary[:120]))

    @tasks.loop(seconds=15)
    async def reports_loop(self):
        conn = connect_db()
        init_db(conn)
        rows = conn.execute(
            "SELECT * FROM reports WHERE status = 'pending' AND discord_message_id IS NULL ORDER BY id LIMIT 5"
        ).fetchall()
        channel_id = moderation_channel_id(self.config)
        if not channel_id or not rows:
            return
        channel = self.get_channel(int(channel_id))
        if not channel:
            return
        for row in rows:
            embed = discord.Embed(
                title=f"Report #{row['id']}",
                colour=discord.Colour.red(),
                timestamp=discord.utils.utcnow(),
            )
            embed.add_field(name="Server", value=row["server_id"] or "unknown", inline=True)
            embed.add_field(name="Source", value=row["source"] or "unknown", inline=True)
            embed.add_field(name="Reporter", value=row["reporter_name"] or "unknown", inline=False)
            embed.add_field(name="Target", value=row["target_name"] or "unknown", inline=True)
            embed.add_field(name="Target ID", value=row["target_id"] or "n/a", inline=True)
            embed.add_field(name="Reason", value=row["reason"] or "n/a", inline=False)
            embed.set_footer(text="!ban <id|name|ip> <reason> | !deban <id|name|ip> | !dismiss <report_id>")
            message = await channel.send(embed=embed)
            conn.execute(
                "UPDATE reports SET discord_message_id = ? WHERE id = ?",
                (str(message.id), row["id"]),
            )
            conn.commit()

    @status_loop.before_loop
    async def before_status_loop(self):
        await self.wait_until_ready()

    @reports_loop.before_loop
    async def before_reports_loop(self):
        await self.wait_until_ready()


def main():
    config_path = WORKROOT / "Plutonium" / "server_config.json"
    if not config_path.exists():
        print(f"Missing configuration: {config_path}")
        raise SystemExit(1)

    config = load_config()
    token = discord_token()
    if not token:
        print("Discord token not configured. Set /etc/xlr/secrets.env DISCORD_TOKEN=...")
        raise SystemExit(1)

    if not config.get("discord_config", {}).get("enabled", False):
        print("Discord bot disabled in configuration")
        raise SystemExit(0)

    bot = XLRBot(config)

    @bot.command(name="status")
    async def status_command(ctx):
        lines = server_status_lines(load_config())
        await ctx.send("\n".join(lines) or "No servers configured")

    @bot.command(name="players")
    async def players_command(ctx, server_id: str = ""):
        config_data = load_config()
        host = config_data.get("general_config", {}).get("rcon_ip", "127.0.0.1")
        replies = []
        for server in config_data.get("servers", []):
            if server_id and server.get("id") != server_id:
                continue
            if not server.get("enabled", True):
                continue
            port = server.get("port")
            password = server.get("rcon_password") or server.get("key", "")
            response = rcon_query(host, port, password, "status")
            count = len(parse_status_clients(response))
            replies.append(f"{server.get('name')} ({server.get('id')}): {count} players")
        await ctx.send("\n".join(replies) or "No data")

    @bot.command(name="report")
    async def report_command(ctx, target: str, *, reason: str = "No reason provided"):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        target_id = rows[0]["plutonium_id"] if rows else ""
        target_name = rows[0]["current_name"] if rows else target
        report_id = create_report(
            conn,
            str(ctx.author),
            str(ctx.author.id),
            target_name,
            target_id,
            reason,
            "discord",
            "discord",
        )
        await ctx.send(f"Report #{report_id} recorded for **{target_name}**.")

    @bot.command(name="lookup")
    async def lookup_command(ctx, *, query: str):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, query)
        if not rows:
            await ctx.send("No player found.")
            return
        lines = []
        for row in rows:
            lines.append(
                f"**{row['current_name']}** | ID `{row['plutonium_id']}` | Steam `{row['steam_id'] or 'n/a'}`\nIPs: {row['ips'] or 'n/a'}"
            )
        await ctx.send("\n".join(lines)[:1900])

    @bot.command(name="ban")
    @commands.has_permissions(administrator=True)
    async def ban_command(ctx, target: str, *, reason: str = "Banned by staff"):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        ip = target if "." in target and target.replace(".", "").isdigit() else None
        plutonium_id = rows[0]["plutonium_id"] if rows else (target if target.isdigit() else None)
        if rows and rows[0]["ips"]:
            ip = rows[0]["ips"].split(",")[0]
        add_ban(conn, ip=ip, plutonium_id=plutonium_id, reason=reason, banned_by=str(ctx.author))
        await ctx.send(f"Banned `{target}` ({reason}).")

    @bot.command(name="deban")
    @commands.has_permissions(administrator=True)
    async def deban_command(ctx, target: str):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        ip = target if "." in target and target.replace(".", "").isdigit() else None
        plutonium_id = rows[0]["plutonium_id"] if rows else (target if target.isdigit() else None)
        if rows and rows[0]["ips"]:
            ip = rows[0]["ips"].split(",")[0]
        count = remove_ban(conn, ip=ip, plutonium_id=plutonium_id)
        if count:
            await ctx.send(f"Unbanned `{target}` ({count} ban record(s) cleared).")
        else:
            await ctx.send(f"No active ban found for `{target}`.")

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
        await ctx.send(
            "Commands: !status !players [id] !report <player> <reason> !lookup <name|id> "
            "!ban <player|id|ip> <reason> !deban <player|id|ip> !restart [id|all] !xlrbackup !xlrhelp"
        )

    bot.run(token)


if __name__ == "__main__":
    main()
