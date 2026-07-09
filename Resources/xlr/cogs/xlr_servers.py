import asyncio
import subprocess

import discord
from discord.ext import commands

from xlr_bot_core import CATEGORY_BO2, XLR_DANGER, XLR_SUCCESS, bot_owner_only, discord_invite_link, xlr_embed
from xlr_lib import (
    WORKROOT,
    add_ban,
    announce_ban_and_kick,
    announce_kick,
    collect_server_statuses,
    connect_db,
    create_report,
    fetch_platform_stats,
    force_random_game_tip,
    init_db,
    load_config,
    lookup_player,
    remove_ban,
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


def moderation_channel_id(config):
    mod = config.get("moderation", {})
    discord_cfg = config.get("discord_config", {})
    return mod.get("discord_reports_channel_id") or discord_cfg.get("reports_channel_id") or ""


class XLRServers(commands.Cog):
    category = CATEGORY_BO2

    def __init__(self, bot):
        self.bot = bot

    @commands.command(name="status")
    async def status(self, ctx):
        config = load_config()
        statuses, total_players, online_servers = collect_server_statuses(config)
        embed = xlr_embed(self.bot, title="Server Status")
        if not statuses:
            embed.description = "No servers configured."
            await ctx.send(embed=embed)
            return
        for item in statuses:
            if item["online"]:
                value = f"Online · **{item['players']}** players"
                emoji = "🟢"
            else:
                value = "Offline"
                emoji = "🔴"
            embed.add_field(name=f"{emoji} {item['name']}", value=value, inline=False)
        embed.add_field(name="Total Players", value=str(total_players), inline=True)
        embed.add_field(name="Online Servers", value=f"{online_servers}/{len(statuses)}", inline=True)
        embed.add_field(name="Discord", value=discord_invite_link(), inline=False)
        await ctx.send(embed=embed)

    @commands.command(name="stats")
    async def stats(self, ctx):
        try:
            data = await asyncio.to_thread(fetch_platform_stats)
        except Exception:
            await ctx.send(
                embed=xlr_embed(
                    self.bot,
                    description="Stats are temporarily unavailable. Try again in a few seconds.",
                    color=XLR_DANGER,
                )
            )
            return
        embed = xlr_embed(self.bot, title="XLR Server Stats")
        embed.add_field(name="Players Online", value=str(data["total_players"]), inline=True)
        embed.add_field(name="Servers Online", value=f"{data['online_servers']}/{len(data['servers'])}", inline=True)
        embed.add_field(name="Unique Players", value=str(data["global_unique_players"]), inline=True)
        embed.add_field(name="Active Game Bans", value=str(data["active_bans"]), inline=True)
        for item in data["servers"]:
            if item["online"]:
                status = f"Online · **{item['players']}** playing"
                emoji = "🟢"
            else:
                status = "Offline"
                emoji = "🔴"
            embed.add_field(
                name=f"{emoji} {item['name']}",
                value=status,
                inline=False,
            )
        await ctx.send(embed=embed)

    @commands.command(name="forcetip", aliases=["gametip"])
    @bot_owner_only()
    async def forcetip(self, ctx, server_id: str = "all"):
        results = await asyncio.to_thread(force_random_game_tip, load_config(), server_id)
        sent = [item for item in results if item.get("sent")]
        if not sent:
            embed = xlr_embed(self.bot, description="No tip was sent. Servers may be offline.", color=XLR_DANGER)
            if results:
                lines = [f"**{item['server_id']}** — {item.get('reason', 'failed')}" for item in results]
                embed.add_field(name="Details", value="\n".join(lines), inline=False)
            await ctx.send(embed=embed)
            return
        embed = xlr_embed(self.bot, title="Game Tip Sent", color=XLR_SUCCESS)
        embed.description = "A random tip was pushed in-game (GSC chat, same as welcome messages)."
        for item in sent:
            embed.add_field(
                name=item["server_id"].upper(),
                value=f"RCON status: **{item['players']}** player(s) parsed",
                inline=False,
            )
        await ctx.send(embed=embed)

    @commands.command(name="players")
    async def players(self, ctx, server_id: str = ""):
        statuses, _, _ = collect_server_statuses(load_config())
        embed = xlr_embed(self.bot, title="Player Count")
        found = False
        for item in statuses:
            if server_id and item["id"] != server_id:
                continue
            found = True
            if item["online"]:
                embed.add_field(name=item["name"], value=f"**{item['players']}** players", inline=False)
            else:
                embed.add_field(name=item["name"], value="Offline", inline=False)
        if not found:
            embed.description = "No matching server found."
        await ctx.send(embed=embed)

    @commands.command(name="report")
    async def report(self, ctx, target: str, *, reason: str = "No reason provided"):
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
        embed = xlr_embed(self.bot, title="Report Submitted", color=XLR_SUCCESS)
        embed.add_field(name="Report ID", value=f"#{report_id}", inline=True)
        embed.add_field(name="Target", value=target_name, inline=True)
        embed.add_field(name="Reason", value=reason, inline=False)
        await ctx.send(embed=embed)

    @commands.command(name="lookup")
    @bot_owner_only()
    async def lookup(self, ctx, *, query: str):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, query)
        if not rows:
            await ctx.send(embed=xlr_embed(self.bot, description="No player found."))
            return
        for row in rows[:5]:
            embed = xlr_embed(self.bot, title=row["current_name"])
            embed.add_field(name="Plutonium ID", value=row["plutonium_id"] or "n/a", inline=True)
            embed.add_field(name="Steam ID", value=row["steam_id"] or "n/a", inline=True)
            embed.add_field(name="IPs", value=row["ips"] or "n/a", inline=False)
            embed.add_field(name="First Seen", value=row["first_seen"] or "n/a", inline=True)
            embed.add_field(name="Last Seen", value=row["last_seen"] or "n/a", inline=True)
            await ctx.send(embed=embed)

    @commands.command(name="gameban", aliases=["bo2ban"])
    @commands.has_permissions(administrator=True)
    async def gameban(self, ctx, target: str, *, reason: str = "Banned by staff"):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        ip = target if target.replace(".", "").isdigit() and "." in target else None
        plutonium_id = rows[0]["plutonium_id"] if rows else (target if target.isdigit() else None)
        if rows and rows[0]["ips"]:
            ip = rows[0]["ips"].split(",")[0]
        add_ban(conn, ip=ip, plutonium_id=plutonium_id, reason=reason, banned_by=str(ctx.author))
        player_name = rows[0]["current_name"] if rows else target
        config = load_config()
        kicked = await asyncio.to_thread(
            announce_ban_and_kick,
            config,
            plutonium_id=plutonium_id,
            ip=ip,
            player_name=player_name,
            reason=reason,
        )
        embed = xlr_embed(self.bot, title="Game Ban Applied", color=XLR_DANGER)
        embed.add_field(name="Target", value=target, inline=True)
        embed.add_field(name="Reason", value=reason, inline=False)
        if kicked:
            embed.add_field(name="In-game", value="Player was online and announced on their server.", inline=False)
        await ctx.send(embed=embed)

    @commands.command(name="gamekick", aliases=["bo2kick"])
    @commands.has_permissions(administrator=True)
    async def gamekick(self, ctx, target: str, *, reason: str = "Kicked by staff"):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        ip = target if target.replace(".", "").isdigit() and "." in target else None
        plutonium_id = rows[0]["plutonium_id"] if rows else (target if target.isdigit() else None)
        if rows and rows[0]["ips"]:
            ip = rows[0]["ips"].split(",")[0]
        player_name = rows[0]["current_name"] if rows else target
        config = load_config()
        kicked, name = await asyncio.to_thread(
            announce_kick,
            config,
            plutonium_id=plutonium_id,
            ip=ip,
            player_name=player_name,
            reason=reason,
        )
        if kicked:
            embed = xlr_embed(self.bot, title="Player Kicked", color=XLR_SUCCESS)
            embed.add_field(name="Target", value=name or target, inline=True)
            embed.add_field(name="Reason", value=reason, inline=False)
            embed.add_field(name="In-game", value="Player was online and kicked from their server.", inline=False)
        else:
            embed = xlr_embed(
                self.bot,
                title="Player Not Found",
                description=f"`{target}` is not currently online on any XLR server.",
                color=XLR_DANGER,
            )
        await ctx.send(embed=embed)

    @commands.command(name="gameunban", aliases=["bo2deban", "gamedeban"])
    @commands.has_permissions(administrator=True)
    async def gameunban(self, ctx, target: str):
        conn = connect_db()
        init_db(conn)
        rows = lookup_player(conn, target)
        ip = target if target.replace(".", "").isdigit() and "." in target else None
        plutonium_id = rows[0]["plutonium_id"] if rows else (target if target.isdigit() else None)
        if rows and rows[0]["ips"]:
            ip = rows[0]["ips"].split(",")[0]
        count = remove_ban(conn, ip=ip, plutonium_id=plutonium_id)
        if count:
            await ctx.send(embed=xlr_embed(self.bot, description=f"Removed game ban for `{target}` ({count} record(s) cleared).", color=XLR_SUCCESS))
        else:
            await ctx.send(embed=xlr_embed(self.bot, description=f"No active game ban found for `{target}`."))

    @commands.command(name="restart")
    @commands.has_permissions(administrator=True)
    async def restart(self, ctx, server_id: str = "all"):
        code, output = await asyncio.to_thread(run_manager, "restart", server_id)
        color = XLR_SUCCESS if code == 0 else XLR_DANGER
        await ctx.send(embed=xlr_embed(self.bot, title="Server Restart", description=output[:3900], color=color))

    @commands.command(name="backup", aliases=["xlrbackup"])
    @commands.has_permissions(administrator=True)
    async def backup(self, ctx):
        code, output = await asyncio.to_thread(run_manager, "backup")
        color = XLR_SUCCESS if code == 0 else XLR_DANGER
        await ctx.send(embed=xlr_embed(self.bot, title="Backup", description=output[:3900], color=color))

    @commands.command(name="dismiss")
    @commands.has_permissions(administrator=True)
    async def dismiss(self, ctx, report_id: int):
        conn = connect_db()
        init_db(conn)
        cur = conn.execute(
            "UPDATE reports SET status = 'dismissed' WHERE id = ? AND status = 'pending'",
            (report_id,),
        )
        conn.commit()
        if cur.rowcount:
            await ctx.send(embed=xlr_embed(self.bot, description=f"Report #{report_id} dismissed.", color=XLR_SUCCESS))
        else:
            await ctx.send(embed=xlr_embed(self.bot, description=f"Report #{report_id} was not found or already handled."))


async def setup(bot):
    await bot.add_cog(XLRServers(bot))
