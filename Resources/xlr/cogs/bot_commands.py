import discord
from discord.ext import commands

from xlr_bot_core import (
    CATEGORY_BO2,
    HelpView,
    bot_owner_only,
    build_help_pages,
    discord_invite_link,
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
        prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
        categories, pages = await build_help_pages(ctx, self.bot, prefix)
        view = HelpView(self.bot, ctx.author.id, categories, pages, prefix)
        await ctx.send(embed=view.build_embed(), view=view if categories else None)

    @commands.command(name="setprefix")
    @commands.has_permissions(administrator=True)
    async def setprefix(self, ctx, prefix: str):
        if not prefix or len(prefix) > 5:
            await ctx.send(embed=xlr_embed(self.bot, description="Provide a prefix up to 5 characters."))
            return
        self.bot.store.set(ctx.guild.id, "prefix", prefix)
        await ctx.send(embed=xlr_embed(self.bot, description=f"This server's prefix is now `{prefix}`."))

    @commands.command(name="stat", aliases=["servers"])
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

    @commands.command(name="allservers", aliases=["allserveur"])
    @bot_owner_only()
    async def allservers(self, ctx):
        lines = [f"**{guild.name}** · `{guild.id}`" for guild in self.bot.guilds]
        embed = xlr_embed(self.bot, title="Connected Servers", description="\n".join(lines)[:4000])
        await ctx.send(embed=embed)

    @commands.command(name="leave")
    @bot_owner_only()
    async def leave(self, ctx, guild_id: int = None):
        guild = self.bot.get_guild(guild_id) if guild_id else ctx.guild
        if not guild:
            await ctx.send(embed=xlr_embed(self.bot, description="I am not in that server."))
            return
        name = guild.name
        await guild.leave()
        await ctx.send(embed=xlr_embed(self.bot, description=f"Left **{name}**."))

    @commands.command(name="setstatus", aliases=["set-bio"])
    @bot_owner_only()
    async def setstatus(self, ctx, *, text: str):
        config = load_config()
        statuses, total_players, _ = collect_server_statuses(config)
        label = text or format_discord_presence(statuses, total_players)
        await self.bot.change_presence(activity=discord.Game(name=label[:128]))
        await ctx.send(embed=xlr_embed(self.bot, description="Bot status updated."))

    @commands.command(name="join")
    @bot_owner_only()
    async def join_vc(self, ctx):
        if not ctx.author.voice or not ctx.author.voice.channel:
            await ctx.send(embed=xlr_embed(self.bot, description="You need to be in a voice channel."))
            return
        if ctx.voice_client:
            await ctx.voice_client.move_to(ctx.author.voice.channel)
        else:
            await ctx.author.voice.channel.connect()
        await ctx.send(embed=xlr_embed(self.bot, description=f"Joined {ctx.author.voice.channel.mention}."))


async def setup(bot):
    await bot.add_cog(BotCommands(bot))
