import json
import random
import discord
from discord.ext import commands
from xlr_bot_core import get_prefix_value, xlr_embed

class Utility(commands.Cog):
    category = 'Utility'

    def __init__(self, bot):
        self.bot = bot

    @commands.command(name='greet')
    @commands.has_permissions(administrator=True)
    async def greet(self, ctx, channel: discord.TextChannel, *, message: str=''):
        self.bot.store.set(ctx.guild.id, 'welcome', {'channel': str(channel.id), 'message': message or None})
        await ctx.send(embed=xlr_embed(self.bot, description=f'Welcome messages will be sent in {channel.mention}.'))

    @commands.command(name='greet-list')
    async def greet_list(self, ctx):
        data = self.bot.store.get(ctx.guild.id, 'welcome')
        if not data:
            prefix = await get_prefix_value(self.bot.store, ctx.guild.id)
            await ctx.send(embed=xlr_embed(self.bot, description=f'No welcome message configured. Use `{prefix}greet #channel`.'))
            return
        await ctx.send(embed=xlr_embed(self.bot, description=f"**Welcome channel:** <#{data['channel']}>\n**Message:** {data.get('message') or '*(default message)*'}"))

    @commands.command(name='invite-guild', aliases=['invite'])
    async def invite_guild(self, ctx):
        invite = await ctx.channel.create_invite(max_age=0, max_uses=0)
        await ctx.send(embed=xlr_embed(self.bot, description=f'Permanent invite: {invite.url}'))

    @commands.command(name='member', aliases=['members'])
    async def member(self, ctx):
        await ctx.send(embed=xlr_embed(self.bot, description=f'This server has **{ctx.guild.member_count}** members.'))

    @commands.command(name='serverinfo')
    async def serverinfo(self, ctx):
        guild = ctx.guild
        embed = xlr_embed(self.bot, title=guild.name)
        embed.set_thumbnail(url=guild.icon.url if guild.icon else None)
        embed.add_field(name='Owner', value=guild.owner.mention if guild.owner else 'Unknown', inline=True)
        embed.add_field(name='Members', value=str(guild.member_count), inline=True)
        embed.add_field(name='Created', value=discord.utils.format_dt(guild.created_at, style='R'), inline=True)
        embed.add_field(name='Roles', value=str(len(guild.roles)), inline=True)
        embed.add_field(name='Channels', value=str(len(guild.channels)), inline=True)
        await ctx.send(embed=embed)

    @commands.command(name='userinfo')
    async def userinfo(self, ctx, member: discord.Member=None):
        member = member or ctx.author
        embed = xlr_embed(self.bot, title=str(member))
        embed.set_thumbnail(url=member.display_avatar.url)
        embed.add_field(name='ID', value=str(member.id), inline=False)
        embed.add_field(name='Joined Server', value=discord.utils.format_dt(member.joined_at, style='R'), inline=True)
        embed.add_field(name='Account Created', value=discord.utils.format_dt(member.created_at, style='R'), inline=True)
        roles = ' '.join((role.mention for role in member.roles if role != ctx.guild.default_role)) or 'None'
        embed.add_field(name='Roles', value=roles[:1024], inline=False)
        await ctx.send(embed=embed)

    @commands.command(name='banner')
    async def banner(self, ctx, user: discord.User=None):
        user = user or ctx.author
        fetched = await self.bot.fetch_user(user.id)
        if not fetched.banner:
            await ctx.send(embed=xlr_embed(self.bot, description='This user does not have a banner.'))
            return
        embed = xlr_embed(self.bot, title=f"{user}'s Banner")
        embed.set_image(url=fetched.banner.url)
        await ctx.send(embed=embed)

    @commands.command(name='avatar', aliases=['pp', 'av'])
    async def avatar(self, ctx, member: discord.Member=None):
        member = member or ctx.author
        embed = xlr_embed(self.bot, title=str(member))
        embed.set_image(url=member.display_avatar.url)
        await ctx.send(embed=embed)

    @commands.command(name='random-avatar', aliases=['pp-random'])
    async def random_avatar(self, ctx):
        members = [m for m in ctx.guild.members if not m.bot]
        if not members:
            await ctx.send(embed=xlr_embed(self.bot, description='No members found.'))
            return
        member = random.choice(members)
        embed = xlr_embed(self.bot, title=str(member))
        embed.set_image(url=member.display_avatar.url)
        await ctx.send(embed=embed)

    @commands.command(name='servericon', aliases=['pp-serveur'])
    async def servericon(self, ctx):
        if not ctx.guild.icon:
            await ctx.send(embed=xlr_embed(self.bot, description='This server has no icon.'))
            return
        embed = xlr_embed(self.bot, title=ctx.guild.name)
        embed.set_image(url=ctx.guild.icon.url)
        await ctx.send(embed=embed)

    @commands.command(name='alladmin', aliases=['admins'])
    async def alladmin(self, ctx):
        admins = [m for m in ctx.guild.members if not m.bot and m.guild_permissions.administrator]
        text = '\n'.join((str(m) for m in admins)) or 'None'
        await ctx.send(embed=xlr_embed(self.bot, title='Server Administrators', description=text[:4000]))

    @commands.command(name='vc')
    async def vc(self, ctx):
        count = sum((1 for m in ctx.guild.members if m.voice and m.voice.channel))
        await ctx.send(embed=xlr_embed(self.bot, description=f'**{count}** members are in voice channels.'))

    @commands.command(name='poll', aliases=['sondage'])
    async def poll(self, ctx, *, question: str):
        if not question:
            await ctx.send(embed=xlr_embed(self.bot, description='Provide a question for the poll.'))
            return
        embed = xlr_embed(self.bot, title='Poll', description=question)
        message = await ctx.send(embed=embed)
        await message.add_reaction('👍')
        await message.add_reaction('👎')

    @commands.command(name='set-status', aliases=['set-statut'])
    @commands.has_permissions(administrator=True)
    async def set_status(self, ctx, role: discord.Role, *, keyword: str):
        self.bot.store.set(ctx.guild.id, 'statusrole', {'role': str(role.id), 'keyword': keyword})
        await ctx.send(embed=xlr_embed(self.bot, description=f'Members with `{keyword}` in their custom status will receive {role.mention}.'))

    @commands.command(name='say')
    @commands.has_permissions(manage_messages=True)
    async def say(self, ctx, *, text: str):
        if not text:
            return
        try:
            await ctx.message.delete()
        except discord.HTTPException:
            pass
        await ctx.send(embed=xlr_embed(self.bot, description=text))

    @commands.command(name='embed')
    @commands.has_permissions(manage_messages=True)
    async def embed_cmd(self, ctx, *, payload: str):
        try:
            data = json.loads(payload)
            await ctx.send(embed=discord.Embed.from_dict(data))
        except (json.JSONDecodeError, TypeError, ValueError):
            await ctx.send(embed=xlr_embed(self.bot, description='Invalid JSON format for the embed.'))

async def setup(bot):
    await bot.add_cog(Utility(bot))
