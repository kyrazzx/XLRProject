import random

import discord
from discord.ext import commands

from xlr_bot_core import xlr_embed


class Fun(commands.Cog):
    category = "Fun"

    def __init__(self, bot):
        self.bot = bot

    @commands.command(name="8ball")
    async def eight_ball(self, ctx, *, question: str = ""):
        responses = [
            "It is certain.",
            "Without a doubt.",
            "Yes, definitely.",
            "Signs point to yes.",
            "Reply hazy, try again.",
            "Don't count on it.",
            "My sources say no.",
            "Very doubtful.",
        ]
        await ctx.send(embed=xlr_embed(self.bot, title="Magic 8-Ball", description=random.choice(responses)))

    @commands.command(name="coinflip", aliases=["pf", "flip"])
    async def coinflip(self, ctx):
        result = "Heads" if random.random() > 0.5 else "Tails"
        await ctx.send(embed=xlr_embed(self.bot, description=f"The coin landed on **{result}**."))

    @commands.command(name="roll")
    async def roll(self, ctx, sides: int = 6):
        if sides < 2 or sides > 1000:
            await ctx.send(embed=xlr_embed(self.bot, description="Choose a die between 2 and 1000 sides."))
            return
        await ctx.send(embed=xlr_embed(self.bot, description=f"You rolled **{random.randint(1, sides)}** on a d{sides}."))

    @commands.command(name="rate")
    async def rate(self, ctx, *, target: str = "you"):
        await ctx.send(embed=xlr_embed(self.bot, description=f"I rate **{target}** {random.randint(0, 100)}/100."))


async def setup(bot):
    await bot.add_cog(Fun(bot))
