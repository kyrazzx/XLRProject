import discord
from discord.ext import commands

from xlr_bot_core import (
    HelpView,
    LOGO_PATH,
    discord_invite_link,
    discord_owner_id,
    get_prefix_value,
    xlr_embed,
)
from xlr_lib import collect_server_statuses, format_discord_presence, load_config


class BotCommands(commands.Cog):
    category = "Bot"

    def __init__(self, bot):
        self.bot = bot

    @commands.command(name="ping")
    async def ping(self, ctx):
        message = await ctx.send(embed=xlr_embed(self.bot, description="Pinging..."))
        api_ms = round(self.bot.latency * 1000)
        edit_ms = round((message.created_at - ctx.message.created_at).total_seconds() * 1000)
        await message.edit(
            embed=xlr_embed(
                self.bot,
                description=f"Pong!\n**Message:** {edit_ms}ms\n**API:** {api_ms}ms",
            )
        )

    @commands.command(name="help", aliases=["xlrhelp", "commands"])
    async def help_cmd(self, ctx):
        categories = []
        for cog in self.bot.cogs.values():
            name = getattr(cog, "category", cog.__class__.__name__)
            if name not in categories:
                categories.append(name)
        prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
        view = HelpView(self.bot, ctx.author.id, categories, prefix)
        await ctx.send(embed=view.build_embed(), view=view)

    @commands.command(name="setprefix")
    @commands.has_permissions(administrator=True)
    async def setprefix(self, ctx, prefix: str):
        if not prefix or len(prefix) > 5:
            await ctx.send(embed=xlr_embed(self.bot, description="Provide a prefix up to 5 characters."))
            return
        self.bot.store.set(ctx.guild.id, "prefix", prefix)
        await ctx.send(embed=xlr_embed(self.bot, description=f"This server's prefix is now `{prefix}`."))

    @commands.command(name="stat", aliases=["stats", "servers"])
    async def stat(self, ctx):
        await ctx.send(embed=xlr_embed(self.bot, description=f"I am in **{len(self.bot.guilds)}** servers."))

    @commands.command(name="support", aliases=["discord"])
    async def support(self, ctx):
        invite = discord_invite_link()
        await ctx.send(
            embed=xlr_embed(
                self.bot,
                title="XLR Community",
                description=f"Join the XLR EU community on Discord:\n**{invite}**",
            )
        )

    @commands.command(name="patchnotes", aliases=["patch-note"])
    async def patchnotes(self, ctx):
        description = (
            "• Full anti-nuke suite with whitelist support\n"
            "• Moderation, warnings, temp-bans and global bans\n"
            "• Captcha verification, tickets, welcome messages and logs\n"
            "• XLR BO2 server status, player lookup, reports and game bans\n"
            "• Styled embeds with XLR PROJECT branding"
        )
        await ctx.send(embed=xlr_embed(self.bot, title="XLR Bot Patch Notes", description=description))

    @commands.command(name="allservers", aliases=["allserveur"])
    async def allservers(self, ctx):
        if str(ctx.author.id) != discord_owner_id():
            await ctx.send(embed=xlr_embed(self.bot, description="This command is owner-only."))
            return
        lines = [f"**{guild.name}** · `{guild.id}`" for guild in self.bot.guilds]
        embed = xlr_embed(self.bot, title="Connected Servers", description="\n".join(lines)[:4000])
        await ctx.send(embed=embed)

    @commands.command(name="leave")
    async def leave(self, ctx, guild_id: int = None):
        if str(ctx.author.id) != discord_owner_id():
            await ctx.send(embed=xlr_embed(self.bot, description="This command is owner-only."))
            return
        guild = self.bot.get_guild(guild_id) if guild_id else ctx.guild
        if not guild:
            await ctx.send(embed=xlr_embed(self.bot, description="I am not in that server."))
            return
        name = guild.name
        await guild.leave()
        await ctx.send(embed=xlr_embed(self.bot, description=f"Left **{name}**."))

    @commands.command(name="setstatus", aliases=["set-bio"])
    async def setstatus(self, ctx, *, text: str):
        if str(ctx.author.id) != discord_owner_id():
            await ctx.send(embed=xlr_embed(self.bot, description="This command is owner-only."))
            return
        config = load_config()
        statuses, total_players, _ = collect_server_statuses(config)
        label = text or format_discord_presence(statuses, total_players)
        await self.bot.change_presence(activity=discord.Game(name=label[:128]))
        await ctx.send(embed=xlr_embed(self.bot, description="Bot status updated."))

    @commands.command(name="join")
    async def join_vc(self, ctx):
        if str(ctx.author.id) != discord_owner_id():
            await ctx.send(embed=xlr_embed(self.bot, description="This command is owner-only."))
            return
        if not ctx.author.voice or not ctx.author.voice.channel:
            await ctx.send(embed=xlr_embed(self.bot, description="You need to be in a voice channel."))
            return
        if ctx.voice_client:
            await ctx.voice_client.move_to(ctx.author.voice.channel)
        else:
            await ctx.author.voice.channel.connect()
        await ctx.send(embed=xlr_embed(self.bot, description=f"Joined {ctx.author.voice.channel.mention}."))

    @commands.command(name="token")
    async def token(self, ctx):
        await ctx.send(embed=xlr_embed(self.bot, description="My token is secure. Never share your bot token with anyone."))


async def setup(bot):
    await bot.add_cog(BotCommands(bot))
