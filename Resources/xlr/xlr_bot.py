import asyncio
import logging
import traceback
import discord
from discord.ext import commands, tasks
from xlr_bot_core import ActionTracker, BotStore, LOGO_PATH, RaidTracker, SpamTracker, default_prefix, get_prefix_value, xlr_embed
from xlr_bot_events import SecurityEvents, SecurityRuntime
from xlr_bot_views import CaptchaView, CloseTicketView, TicketPanelView
from xlr_lib import WORKROOT, collect_server_statuses, connect_db, discord_token, format_discord_presence, init_db, load_config
COG_MODULES = ['cogs.administration', 'cogs.moderation', 'cogs.utility', 'cogs.fun', 'cogs.games', 'cogs.xlr_servers', 'cogs.bot_commands']
logger = logging.getLogger('xlr_bot')

async def dynamic_prefix(bot, message):
    prefix = default_prefix()
    if message.guild:
        prefix = await get_prefix_value(bot.store, message.guild.id)
    return commands.when_mentioned_or(prefix)(bot, message)

class XLRBot(commands.Bot):

    def __init__(self, config):
        intents = discord.Intents.default()
        intents.message_content = True
        intents.members = True
        intents.moderation = True
        intents.invites = True
        intents.voice_states = True
        intents.presences = True
        super().__init__(command_prefix=dynamic_prefix, intents=intents, help_command=None)
        self.config = config
        self.store = BotStore()
        self.action_tracker = ActionTracker()
        self.spam_tracker = SpamTracker()
        self.raid_tracker = RaidTracker()
        self.security = SecurityRuntime(self)
        self._branding_applied = False

    async def setup_hook(self):
        for module in COG_MODULES:
            await self.load_extension(module)
        await self.add_cog(SecurityEvents(self))
        self.add_view(CaptchaView())
        self.add_view(TicketPanelView())
        self.add_view(CloseTicketView())
        interval = int(self.config.get('discord_config', {}).get('update_interval', 30))
        self.status_loop.change_interval(seconds=max(interval, 15))
        self.reports_loop.change_interval(seconds=15)
        self.status_loop.start()
        self.reports_loop.start()

    async def on_command_error(self, ctx, error):
        if isinstance(error, commands.CommandInvokeError) and error.original:
            error = error.original
        if isinstance(error, commands.CheckFailure):
            message = str(error) or 'You cannot run this command.'
            await ctx.send(embed=xlr_embed(self, description=message))
            return
        if isinstance(error, commands.MissingPermissions):
            await ctx.send(embed=xlr_embed(self, description='You do not have permission to use this command.'))
            return
        if isinstance(error, commands.CommandNotFound):
            return
        if isinstance(error, commands.MissingRequiredArgument):
            await ctx.send(embed=xlr_embed(self, description=f'Missing argument: `{error.param.name}`'))
            return
        if isinstance(error, (commands.BadArgument, commands.ChannelNotFound, commands.RoleNotFound)):
            await ctx.send(embed=xlr_embed(self, description='Invalid argument. For tickets, run `!setup-ticket` inside the target channel or use `!setup-ticket #channel`.'))
            return
        logger.exception('Command failed: %s', getattr(ctx.command, 'qualified_name', 'unknown'))
        traceback.print_exception(type(error), error, error.__traceback__)
        detail = str(error)[:300] if str(error) else 'Unknown error'
        await ctx.send(embed=xlr_embed(self, description=f'An error occurred while running that command.\n`{detail}`'))

    async def on_ready(self):
        if not self._branding_applied:
            await self._apply_branding()
            self._branding_applied = True
        try:
            (statuses, total_players, _) = collect_server_statuses(load_config())
            await self.change_presence(activity=discord.Game(name=format_discord_presence(statuses, total_players)))
        except Exception:
            logger.exception('Initial status update failed')

    async def _apply_branding(self):
        if not LOGO_PATH.is_file():
            return
        try:
            with open(LOGO_PATH, 'rb') as handle:
                await self.user.edit(avatar=handle.read())
        except discord.HTTPException:
            pass

    @tasks.loop(seconds=30)
    async def status_loop(self):
        try:
            self.config = load_config()
            (statuses, total_players, _) = collect_server_statuses(self.config)
            await self.change_presence(activity=discord.Game(name=format_discord_presence(statuses, total_players)))
        except Exception:
            logger.exception('status_loop failed')

    @tasks.loop(seconds=15)
    async def reports_loop(self):
        from cogs.xlr_servers import moderation_channel_id
        conn = connect_db()
        try:
            init_db(conn)
            rows = conn.execute("SELECT * FROM reports WHERE status = 'pending' AND discord_message_id IS NULL ORDER BY id LIMIT 5").fetchall()
            channel_id = moderation_channel_id(self.config)
            if not channel_id or not rows:
                return
            channel = self.get_channel(int(channel_id))
            if not channel:
                return
            for row in rows:
                embed = xlr_embed(self, title=f"Player Report #{row['id']}", color=16724821)
                embed.add_field(name='Server', value=row['server_id'] or 'unknown', inline=True)
                embed.add_field(name='Source', value=row['source'] or 'unknown', inline=True)
                embed.add_field(name='Reporter', value=row['reporter_name'] or 'unknown', inline=True)
                embed.add_field(name='Reporter ID', value=row['reporter_id'] or 'n/a', inline=True)
                embed.add_field(name='Target', value=row['target_name'] or 'unknown', inline=True)
                embed.add_field(name='Target ID', value=row['target_id'] or 'n/a', inline=True)
                embed.add_field(name='Reason', value=row['reason'] or 'n/a', inline=False)
                embed.set_footer(text='Use !gameban / !gameunban / !dismiss <id> · XLR EU · Black Ops II')
                message = await channel.send(embed=embed)
                conn.execute('UPDATE reports SET discord_message_id = ? WHERE id = ?', (str(message.id), row['id']))
                conn.commit()
        except Exception:
            logger.exception('reports_loop failed')
        finally:
            conn.close()

    @status_loop.before_loop
    async def before_status_loop(self):
        await self.wait_until_ready()

    @reports_loop.before_loop
    async def before_reports_loop(self):
        await self.wait_until_ready()

def main():
    logging.basicConfig(level=logging.INFO)
    config_path = WORKROOT / 'Plutonium' / 'server_config.json'
    if not config_path.exists():
        print(f'Missing configuration: {config_path}')
        raise SystemExit(1)
    config = load_config()
    token = discord_token()
    if not token:
        print('Discord token not configured. Set /etc/xlr/secrets.env DISCORD_TOKEN=...')
        raise SystemExit(1)
    if not config.get('discord_config', {}).get('enabled', False):
        print('Discord bot disabled in configuration')
        raise SystemExit(0)
    bot = XLRBot(config)
    bot.run(token)
if __name__ == '__main__':
    main()
