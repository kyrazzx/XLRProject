import discord
from discord.ext import commands
from xlr_bot_core import ACTIVITY_IDS, xlr_embed

class Games(commands.Cog):
    category = 'Mini-Games'

    def __init__(self, bot):
        self.bot = bot

    async def start_activity(self, ctx, name):
        if not ctx.author.voice or not ctx.author.voice.channel:
            await ctx.send(embed=xlr_embed(self.bot, description='You must be in a voice channel to start an activity.'))
            return
        vc = ctx.author.voice.channel
        app_id = ACTIVITY_IDS.get(name)
        if not app_id:
            await ctx.send(embed=xlr_embed(self.bot, description='Unknown activity.'))
            return
        try:
            invite = await vc.create_invite(max_age=300, target_application=app_id, target_type=discord.InviteTarget.embedded_application)
            label = name.replace('_', ' ').title()
            await ctx.send(embed=xlr_embed(self.bot, title=label, description=f'Click here to start **{label}**.\n[Activity Link]({invite.url})'))
        except discord.HTTPException:
            await ctx.send(embed=xlr_embed(self.bot, description='I could not create an activity invite. I may be missing the Create Invite permission.'))

    @commands.command(name='poker')
    async def poker(self, ctx):
        await self.start_activity(ctx, 'poker')

    @commands.command(name='chess')
    async def chess(self, ctx):
        await self.start_activity(ctx, 'chess')

    @commands.command(name='checkers')
    async def checkers(self, ctx):
        await self.start_activity(ctx, 'checkers')

    @commands.command(name='fishing')
    async def fishing(self, ctx):
        await self.start_activity(ctx, 'fishing')

    @commands.command(name='betrayal')
    async def betrayal(self, ctx):
        await self.start_activity(ctx, 'betrayal')

    @commands.command(name='letterleague')
    async def letterleague(self, ctx):
        await self.start_activity(ctx, 'letterleague')

    @commands.command(name='wordsnack')
    async def wordsnack(self, ctx):
        await self.start_activity(ctx, 'wordsnack')

    @commands.command(name='doodlecrew')
    async def doodlecrew(self, ctx):
        await self.start_activity(ctx, 'doodlecrew')

    @commands.command(name='spellcast')
    async def spellcast(self, ctx):
        await self.start_activity(ctx, 'spellcast')

    @commands.command(name='ankword')
    async def ankword(self, ctx):
        await self.start_activity(ctx, 'ankword')

    @commands.command(name='puttparty')
    async def puttparty(self, ctx):
        await self.start_activity(ctx, 'puttparty')

    @commands.command(name='youtube')
    async def youtube(self, ctx):
        await self.start_activity(ctx, 'youtube')

async def setup(bot):
    await bot.add_cog(Games(bot))
