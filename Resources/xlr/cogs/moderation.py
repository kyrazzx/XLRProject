import asyncio
import time

import discord
from discord.ext import commands

from xlr_bot_core import (
    XLR_DANGER,
    add_warn,
    bot_owner_only,
    parse_duration,
    send_mod_log,
    xlr_embed,
    xlr_log_embed,
)


class Moderation(commands.Cog):
    category = "Moderation"

    def __init__(self, bot):
        self.bot = bot

    @commands.command(name="ban")
    @commands.has_permissions(ban_members=True)
    async def ban(self, ctx, member: discord.Member, *, reason: str = "No reason provided"):
        if not member.bannable:
            await ctx.send(embed=xlr_embed(self.bot, description="I cannot ban this user."))
            return
        await member.ban(reason=reason)
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been banned.\n**Reason:** {reason}"))
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Banned",
                f"**User:** {member} ({member.id})\n**Moderator:** {ctx.author}\n**Reason:** {reason}",
                color=XLR_DANGER,
            ),
        )

    @commands.command(name="kick")
    @commands.has_permissions(kick_members=True)
    async def kick(self, ctx, member: discord.Member, *, reason: str = "No reason provided"):
        if not member.kickable:
            await ctx.send(embed=xlr_embed(self.bot, description="I cannot kick this user."))
            return
        await member.kick(reason=reason)
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been kicked.\n**Reason:** {reason}"))
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Kicked",
                f"**User:** {member} ({member.id})\n**Moderator:** {ctx.author}\n**Reason:** {reason}",
                color=XLR_DANGER,
            ),
        )

    @commands.command(name="mute")
    @commands.has_permissions(moderate_members=True)
    async def mute(self, ctx, member: discord.Member, duration: str, *, reason: str = "No reason provided"):
        ms = parse_duration(duration)
        if not ms or ms > 28 * 24 * 3600 * 1000:
            await ctx.send(embed=xlr_embed(self.bot, description="Invalid duration. Maximum is 28 days. Example: `10m`, `1h`, `1d`."))
            return
        until = discord.utils.utcnow() + discord.timedelta(milliseconds=ms)
        await member.timeout(until, reason=reason)
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been muted for **{duration}**.\n**Reason:** {reason}"))
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Muted",
                f"**User:** {member}\n**Moderator:** {ctx.author}\n**Duration:** {duration}\n**Reason:** {reason}",
                color=XLR_DANGER,
            ),
        )

    @commands.command(name="unmute")
    @commands.has_permissions(moderate_members=True)
    async def unmute(self, ctx, member: discord.Member):
        await member.timeout(None)
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been unmuted."))

    @commands.command(name="tempban")
    @commands.has_permissions(ban_members=True)
    async def tempban(self, ctx, member: discord.Member, duration: str, *, reason: str = "No reason provided"):
        ms = parse_duration(duration)
        if not ms:
            await ctx.send(embed=xlr_embed(self.bot, description="Invalid duration. Example: `7d`."))
            return
        if not member.bannable:
            await ctx.send(embed=xlr_embed(self.bot, description="I cannot ban this user."))
            return
        await member.ban(reason=f"[Tempban {duration}] {reason}")
        tempbans = self.bot.store.get_global("tempbans") or []
        tempbans.append({"guild_id": str(ctx.guild.id), "user_id": str(member.id), "unban_at": int(time.time() * 1000) + ms})
        self.bot.store.set_global("tempbans", tempbans)
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been banned for **{duration}**."))
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Temp-Banned",
                f"**User:** {member}\n**Moderator:** {ctx.author}\n**Duration:** {duration}\n**Reason:** {reason}",
                color=XLR_DANGER,
            ),
        )

    @commands.command(name="unban")
    @commands.has_permissions(ban_members=True)
    async def unban(self, ctx, user_id: str):
        try:
            user = await self.bot.fetch_user(int(user_id))
            await ctx.guild.unban(user)
            await ctx.send(embed=xlr_embed(self.bot, description=f"Successfully unbanned **{user}** (`{user_id}`)."))
        except (ValueError, discord.NotFound, discord.HTTPException):
            await ctx.send(embed=xlr_embed(self.bot, description="Could not unban this user. Check the ID and try again."))

    @commands.command(name="warn")
    @commands.has_permissions(kick_members=True)
    async def warn(self, ctx, member: discord.Member, *, reason: str = "No reason provided"):
        warn = await add_warn(self.bot.store, ctx.guild.id, member.id, ctx.author.id, reason)
        try:
            await member.send(embed=xlr_embed(self.bot, description=f"You have been warned in **{ctx.guild.name}**.\n**Reason:** {reason}"))
        except discord.HTTPException:
            pass
        await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has been warned. (Case #{warn['id']})\n**Reason:** {reason}"))
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Warned",
                f"**User:** {member}\n**Moderator:** {ctx.author}\n**Case:** #{warn['id']}\n**Reason:** {reason}",
                color=XLR_DANGER,
            ),
        )

    @commands.command(name="clearwarns")
    @commands.has_permissions(kick_members=True)
    async def clearwarns(self, ctx, member: discord.Member):
        self.bot.store.delete(ctx.guild.id, f"warns_{member.id}")
        await ctx.send(embed=xlr_embed(self.bot, description=f"Cleared all infractions for {member}."))

    @commands.command(name="sanction", aliases=["warns", "infractions"])
    @commands.has_permissions(view_audit_log=True)
    async def sanction(self, ctx, member: discord.Member = None):
        member = member or ctx.author
        warns = self.bot.store.get(ctx.guild.id, f"warns_{member.id}") or []
        if not warns:
            await ctx.send(embed=xlr_embed(self.bot, description=f"{member} has no infractions."))
            return
        lines = []
        for item in warns:
            ts = int(item["date"] / 1000)
            lines.append(
                f"**Case #{item['id']}** · <t:{ts}:R>\nModerator: <@{item['moderator']}>\nReason: {item['reason']}"
            )
        await ctx.send(embed=xlr_embed(self.bot, title=f"Infractions for {member}", description="\n\n".join(lines)[:4000]))

    @commands.command(name="clear", aliases=["purge"])
    @commands.has_permissions(manage_messages=True)
    async def clear(self, ctx, amount: int):
        if amount <= 0 or amount > 100:
            await ctx.send(embed=xlr_embed(self.bot, description="Provide a number between 1 and 100."))
            return
        deleted = await ctx.channel.purge(limit=amount + 1)
        notice = await ctx.send(embed=xlr_embed(self.bot, description=f"Deleted **{len(deleted) - 1}** messages."))
        await asyncio.sleep(3)
        try:
            await notice.delete()
        except discord.HTTPException:
            pass

    @commands.command(name="prune")
    @commands.has_permissions(manage_messages=True)
    async def prune(self, ctx, member: discord.Member, amount: int):
        if amount <= 0 or amount > 100:
            await ctx.send(embed=xlr_embed(self.bot, description="Usage: `prune @user <1-100>`"))
            return
        def check(message):
            return message.author.id == member.id
        deleted = await ctx.channel.purge(limit=100, check=check)
        deleted = deleted[:amount]
        notice = await ctx.send(
            embed=xlr_embed(self.bot, description=f"Deleted **{len(deleted)}** messages from {member}.")
        )
        await asyncio.sleep(3)
        try:
            await notice.delete()
        except discord.HTTPException:
            pass

    @commands.command(name="lock")
    @commands.has_permissions(manage_channels=True)
    async def lock(self, ctx):
        await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=False)
        await ctx.send(embed=xlr_embed(self.bot, description="Channel has been locked."))

    @commands.command(name="unlock")
    @commands.has_permissions(manage_channels=True)
    async def unlock(self, ctx):
        await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=None)
        await ctx.send(embed=xlr_embed(self.bot, description="Channel has been unlocked."))

    @commands.command(name="renew")
    @commands.has_permissions(manage_channels=True)
    async def renew(self, ctx):
        position = ctx.channel.position
        new_channel = await ctx.channel.clone()
        await ctx.channel.delete()
        await new_channel.edit(position=position)
        await new_channel.send(embed=xlr_embed(self.bot, description="Channel has been successfully renewed."))

    @commands.command(name="snipe")
    async def snipe(self, ctx):
        events = self.bot.get_cog("SecurityEvents")
        data = events.snipe.get(ctx.channel.id) if events else None
        if not data:
            await ctx.send(embed=xlr_embed(self.bot, description="There is nothing to snipe in this channel."))
            return
        embed = xlr_embed(self.bot, description=data["content"])
        embed.set_author(name=str(data["author"]), icon_url=data["author"].display_avatar.url)
        embed.timestamp = data["timestamp"]
        await ctx.send(embed=embed)

    @commands.command(name="gban")
    @bot_owner_only()
    async def gban(self, ctx, user: discord.User = None, *, reason: str = "Global ban"):
        if not user:
            await ctx.send(embed=xlr_embed(self.bot, description="Usage: `gban @user [reason]` or `gban <userId> [reason]`"))
            return
        gbans = [str(x) for x in (self.bot.store.get_global("gbans") or [])]
        if str(user.id) not in gbans:
            gbans.append(str(user.id))
            self.bot.store.set_global("gbans", gbans)
        count = 0
        for guild in self.bot.guilds:
            try:
                await guild.ban(user, reason=f"[GBAN] {reason}")
                count += 1
            except discord.HTTPException:
                pass
        await ctx.send(embed=xlr_embed(self.bot, description=f"Globally banned {user.mention} across **{count}** server(s)."))

    @commands.command(name="gunban")
    @bot_owner_only()
    async def gunban(self, ctx, user: discord.User = None):
        if not user:
            await ctx.send(embed=xlr_embed(self.bot, description="Usage: `gunban @user` or `gunban <userId>`"))
            return
        gbans = [str(x) for x in (self.bot.store.get_global("gbans") or []) if str(x) != str(user.id)]
        self.bot.store.set_global("gbans", gbans)
        count = 0
        for guild in self.bot.guilds:
            try:
                await guild.unban(user, reason="[GUNBAN]")
                count += 1
            except discord.HTTPException:
                pass
        await ctx.send(embed=xlr_embed(self.bot, description=f"Removed the global ban for {user.mention} across **{count}** server(s)."))


async def setup(bot):
    await bot.add_cog(Moderation(bot))
