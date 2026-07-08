import asyncio

import discord
from discord.ext import commands

from xlr_bot_core import (
    CATEGORY_OWNER,
    SECURITY_KEYS,
    get_prefix_value,
    get_settings,
    send_mod_log,
    xlr_embed,
    xlr_log_embed,
)
from xlr_bot_views import CaptchaView, TicketPanelView


class Administration(commands.Cog):
    category = CATEGORY_OWNER

    def __init__(self, bot):
        self.bot = bot

    async def cog_check(self, ctx):
        if not ctx.guild:
            return False
        if ctx.author.id != ctx.guild.owner_id:
            await ctx.send(embed=xlr_embed(self.bot, description="Only the server owner can use owner commands."))
            return False
        return True

    async def toggle_setting(self, ctx, setting, label):
        settings = await get_settings(self.bot.store, ctx.guild.id)
        settings[setting] = not bool(settings.get(setting))
        self.bot.store.set(ctx.guild.id, "settings", settings)
        state = "enabled" if settings[setting] else "disabled"
        await ctx.send(embed=xlr_embed(self.bot, description=f"**{label}** module has been **{state}**."))

    async def set_all_security(self, ctx, status, profile):
        settings = {key: status for key in SECURITY_KEYS}
        self.bot.store.set(ctx.guild.id, "settings", settings)
        state = "activated" if status else "deactivated"
        await ctx.send(embed=xlr_embed(self.bot, description=f"**{profile}** profile has been **{state}**."))

    @commands.command(name="antibot")
    async def antibot(self, ctx):
        await self.toggle_setting(ctx, "antibot", "Anti-Bot")

    @commands.command(name="antichannel")
    async def antichannel(self, ctx):
        await self.toggle_setting(ctx, "antichannel", "Anti-Channel")

    @commands.command(name="antilink")
    async def antilink(self, ctx):
        await self.toggle_setting(ctx, "antilink", "Anti-Link")

    @commands.command(name="antiinvite")
    async def antiinvite(self, ctx):
        await self.toggle_setting(ctx, "antiinvite", "Anti-Discord-Invite")

    @commands.command(name="antiexe")
    async def antiexe(self, ctx):
        await self.toggle_setting(ctx, "antiexe", "Anti-Executable")

    @commands.command(name="antiban")
    async def antiban(self, ctx):
        await self.toggle_setting(ctx, "antiban", "Anti-Ban")

    @commands.command(name="antiguildupdate")
    async def antiguildupdate(self, ctx):
        await self.toggle_setting(ctx, "antiguildupdate", "Anti-Guild Update")

    @commands.command(name="anticreateinvite")
    async def anticreateinvite(self, ctx):
        await self.toggle_setting(ctx, "anticreateinvite", "Anti-Invite Create")

    @commands.command(name="antikick")
    async def antikick(self, ctx):
        await self.toggle_setting(ctx, "antikick", "Anti-Kick")

    @commands.command(name="antimassban")
    async def antimassban(self, ctx):
        await self.toggle_setting(ctx, "antimassban", "Anti-Mass Ban")

    @commands.command(name="antimasskick")
    async def antimasskick(self, ctx):
        await self.toggle_setting(ctx, "antimasskick", "Anti-Mass Kick")

    @commands.command(name="antiraid")
    async def antiraid(self, ctx):
        await self.toggle_setting(ctx, "antiraid", "Anti-Raid")

    @commands.command(name="anti-mass-mention")
    async def antimassmention(self, ctx):
        await self.toggle_setting(ctx, "antimassmention", "Anti-Mass Mention")

    @commands.command(name="spam")
    async def antispam(self, ctx):
        await self.toggle_setting(ctx, "antispam", "Anti-Spam")

    @commands.command(name="secur-max")
    async def secur_max(self, ctx):
        await self.set_all_security(ctx, True, "Maximum Security")

    @commands.command(name="secur-on")
    async def secur_on(self, ctx):
        await self.set_all_security(ctx, True, "Standard Security")

    @commands.command(name="secur-off")
    async def secur_off(self, ctx):
        await self.set_all_security(ctx, False, "All Security")

    @commands.command(name="secur")
    async def secur(self, ctx):
        settings = await get_settings(self.bot.store, ctx.guild.id)
        lines = [f"{'🟢' if settings.get(key) else '🔴'} `{key}`" for key in SECURITY_KEYS]
        await ctx.send(embed=xlr_embed(self.bot, title="Security Modules", description="\n".join(lines)))

    @commands.command(name="whitelist")
    async def whitelist(self, ctx, action: str = "", member: discord.Member = None):
        action = action.lower()
        key = "whitelist"
        wl = [str(x) for x in (self.bot.store.get(ctx.guild.id, key) or [])]
        if action == "add" and member:
            if str(member.id) not in wl:
                wl.append(str(member.id))
                self.bot.store.set(ctx.guild.id, key, wl)
            await ctx.send(embed=xlr_embed(self.bot, description=f"{member.mention} is now whitelisted from anti-nuke punishments."))
            return
        if action == "remove" and member:
            wl = [x for x in wl if x != str(member.id)]
            self.bot.store.set(ctx.guild.id, key, wl)
            await ctx.send(embed=xlr_embed(self.bot, description=f"{member.mention} has been removed from the whitelist."))
            return
        if action == "list":
            desc = "\n".join(f"<@{item}>" for item in wl) if wl else "The whitelist is empty."
            await ctx.send(embed=xlr_embed(self.bot, title="Anti-Nuke Whitelist", description=desc))
            return
        prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
        await ctx.send(
            embed=xlr_embed(
                self.bot,
                description=f"Usage: `{prefix}whitelist add @user`, `{prefix}whitelist remove @user`, `{prefix}whitelist list`",
            )
        )

    @commands.command(name="setup-captcha")
    async def setup_captcha(self, ctx, channel: discord.TextChannel = None, role: discord.Role = None):
        channel = channel or ctx.channel
        if not role:
            prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
            await ctx.send(embed=xlr_embed(self.bot, description=f"Usage: `{prefix}setup-captcha #channel @role`"))
            return
        self.bot.store.set(ctx.guild.id, "captcha", {"channel": str(channel.id), "role": str(role.id)})
        embed = xlr_embed(
            self.bot,
            title="Verification",
            description=f"Welcome to **{ctx.guild.name}**!\nClick the button below to verify yourself and gain access to the server.",
        )
        view = CaptchaView()
        await channel.send(embed=embed, view=view)
        await ctx.send(embed=xlr_embed(self.bot, description=f"Captcha system set in {channel.mention} with role {role.mention}."))

    @commands.command(name="setup-logs")
    async def setup_logs(self, ctx, channel: discord.TextChannel = None):
        channel = channel or ctx.channel
        self.bot.store.set(ctx.guild.id, "logs", str(channel.id))
        await ctx.send(embed=xlr_embed(self.bot, description=f"Log channel set to {channel.mention}."))

    @commands.command(name="setup-autorole")
    async def setup_autorole(self, ctx, role: discord.Role = None):
        if not role:
            prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
            await ctx.send(embed=xlr_embed(self.bot, description=f"Usage: `{prefix}setup-autorole @role`"))
            return
        self.bot.store.set(ctx.guild.id, "autorole", str(role.id))
        prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
        await ctx.send(
            embed=xlr_embed(
                self.bot,
                description=f"New members will receive {role.mention}. Run `{prefix}scan-members` to apply it to existing members.",
            )
        )

    @commands.command(name="scan-members", aliases=["scan-membre"])
    async def scan_members(self, ctx, role: discord.Role = None):
        role_id = self.bot.store.get(ctx.guild.id, "autorole")
        role = role or (ctx.guild.get_role(int(role_id)) if role_id else None)
        if not role:
            prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
            await ctx.send(
                embed=xlr_embed(
                    self.bot,
                    description=f"No member role set. Use `{prefix}setup-autorole @role` or `{prefix}scan-members @role`.",
                )
            )
            return
        if role.position >= ctx.guild.me.top_role.position:
            await ctx.send(embed=xlr_embed(self.bot, description="That role is above my highest role."))
            return
        status = await ctx.send(embed=xlr_embed(self.bot, description=f"Scanning members and applying {role.mention}..."))
        await ctx.guild.chunk()
        added = skipped = failed = 0
        for member in ctx.guild.members:
            if member.bot or role in member.roles:
                skipped += 1
                continue
            try:
                await member.add_roles(role, reason="Member scan")
                added += 1
            except discord.HTTPException:
                failed += 1
        await status.edit(
            embed=xlr_embed(
                self.bot,
                description=f"Scan complete.\n**Added:** {added}\n**Skipped:** {skipped}\n**Failed:** {failed}",
            )
        )
        await send_mod_log(
            ctx.guild,
            self.bot,
            xlr_log_embed(
                self.bot,
                "Member Scan",
                f"**Role:** {role.mention}\n**Added:** {added} · **Skipped:** {skipped} · **Failed:** {failed}\n**By:** {ctx.author}",
            ),
        )

    @commands.command(name="setup-ticket")
    async def setup_ticket(self, ctx, channel: discord.TextChannel = None):
        if not channel:
            await ctx.send(embed=xlr_embed(self.bot, description="Please mention a channel for the ticket panel."))
            return
        embed = xlr_embed(
            self.bot,
            title="Support Ticket",
            description="Click the button below to create a ticket and our support team will assist you shortly.",
        )
        view = TicketPanelView()
        message = await channel.send(embed=embed, view=view)
        self.bot.store.set(ctx.guild.id, "ticket_setup", {"channel": str(channel.id), "message": str(message.id)})
        await ctx.send(embed=xlr_embed(self.bot, description=f"Ticket system set up in {channel.mention}."))


async def setup(bot):
    await bot.add_cog(Administration(bot))