import asyncio
import time
import discord
from discord.ext import commands, tasks
from xlr_bot_core import GENERAL_LINK_RE, XLR_DANGER, fetch_executor, format_welcome, is_enabled, is_whitelisted, message_has_discord_invite, message_has_exe_attachment, punish_member, send_mod_log, xlr_embed, xlr_log_embed

class SecurityEvents(commands.Cog):

    def __init__(self, bot):
        self.bot = bot
        self.snipe = {}
        self.process_tempbans.start()

    def cog_unload(self):
        self.process_tempbans.cancel()

    @tasks.loop(seconds=30)
    async def process_tempbans(self):
        tempbans = self.bot.store.get_global('tempbans') or []
        if not tempbans:
            return
        now = int(time.time() * 1000)
        remaining = []
        for item in tempbans:
            if item.get('unban_at', 0) <= now:
                guild = self.bot.get_guild(int(item['guild_id']))
                if guild:
                    try:
                        await guild.unban(discord.Object(id=int(item['user_id'])), reason='Tempban expired')
                    except discord.HTTPException:
                        pass
            else:
                remaining.append(item)
        if len(remaining) != len(tempbans):
            self.bot.store.set_global('tempbans', remaining)

    @process_tempbans.before_loop
    async def before_tempbans(self):
        await self.bot.wait_until_ready()

    @commands.Cog.listener()
    async def on_message_delete(self, message):
        if not message.guild or not message.author or message.author.bot:
            return
        if message.content:
            self.snipe[message.channel.id] = {'content': message.content, 'author': message.author, 'timestamp': message.created_at}

    @commands.Cog.listener()
    async def on_message(self, message):
        if message.author.bot or not message.guild:
            return
        if await self.bot.security.run_message_security(message):
            return

    @commands.Cog.listener()
    async def on_member_join(self, member):
        guild = member.guild
        gbans = self.bot.store.get_global('gbans') or []
        if str(member.id) in [str(x) for x in gbans]:
            try:
                await member.ban(reason='Global ban')
            except discord.HTTPException:
                pass
            return
        if member.bot and await is_enabled(self.bot.store, guild.id, 'antibot'):
            executor = await fetch_executor(guild, discord.AuditLogAction.bot_add, member.id)
            if not await is_whitelisted(self.bot, guild, getattr(executor, 'id', None)):
                try:
                    await member.ban(reason='[Anti-Nuke] Unauthorized bot add')
                except discord.HTTPException:
                    pass
                if executor:
                    await punish_member(guild, self.bot, executor.id, 'Added an unauthorized bot')
                await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Unauthorized Bot Removed', f"**Bot:** {member} ({member.id})\n**Added by:** {executor or 'Unknown'}", color=XLR_DANGER))
                return
        if await is_enabled(self.bot.store, guild.id, 'antiraid'):
            count = self.bot.raid_tracker.track(guild.id)
            if count >= 6:
                try:
                    await member.kick(reason='[Anti-Raid] Join flood detected')
                except discord.HTTPException:
                    pass
                await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Raid', f'Kicked {member} during a join flood.', color=XLR_DANGER))
                return
        welcome = self.bot.store.get(guild.id, 'welcome')
        if welcome and welcome.get('channel'):
            channel = guild.get_channel(int(welcome['channel']))
            if channel:
                embed = xlr_embed(self.bot, title=f'Welcome to {guild.name}', description=format_welcome(welcome.get('message'), member))
                embed.set_thumbnail(url=member.display_avatar.url)
                try:
                    await channel.send(content=member.mention, embed=embed)
                except discord.HTTPException:
                    pass
        auto_role_id = self.bot.store.get(guild.id, 'autorole')
        if auto_role_id and (not member.bot):
            role = guild.get_role(int(auto_role_id))
            if role:
                try:
                    await member.add_roles(role, reason='Auto role')
                except discord.HTTPException:
                    pass

    @commands.Cog.listener()
    async def on_member_remove(self, member):
        guild = member.guild
        need_kick = await is_enabled(self.bot.store, guild.id, 'antikick')
        need_mass = await is_enabled(self.bot.store, guild.id, 'antimasskick')
        if not need_kick and (not need_mass):
            return
        executor = await fetch_executor(guild, discord.AuditLogAction.kick, member.id)
        if not executor:
            return
        if await is_whitelisted(self.bot, guild, executor.id):
            return
        if need_kick:
            await punish_member(guild, self.bot, executor.id, 'Kicked a member without authorization')
        if need_mass:
            count = self.bot.action_tracker.track(guild.id, executor.id, 'kick')
            if count >= 3:
                await punish_member(guild, self.bot, executor.id, 'Mass kick detected')
        await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Kick', f'**Member kicked:** {member}\n**By:** {executor} (punished)', color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_member_ban(self, guild, user):
        need_ban = await is_enabled(self.bot.store, guild.id, 'antiban')
        need_mass = await is_enabled(self.bot.store, guild.id, 'antimassban')
        if not need_ban and (not need_mass):
            return
        executor = await fetch_executor(guild, discord.AuditLogAction.ban, user.id)
        if not executor or await is_whitelisted(self.bot, guild, executor.id):
            return
        if need_ban:
            try:
                await guild.unban(user, reason='[Anti-Nuke] Unauthorized ban')
            except discord.HTTPException:
                pass
            await punish_member(guild, self.bot, executor.id, 'Banned a member without authorization')
        if need_mass:
            count = self.bot.action_tracker.track(guild.id, executor.id, 'ban')
            if count >= 3:
                await punish_member(guild, self.bot, executor.id, 'Mass ban detected')
        await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Ban', f'**Target:** {user}\n**By:** {executor} (punished)', color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_guild_channel_create(self, channel):
        if not isinstance(channel, discord.abc.GuildChannel):
            return
        guild = channel.guild
        if not await is_enabled(self.bot.store, guild.id, 'antichannel'):
            return
        executor = await fetch_executor(guild, discord.AuditLogAction.channel_create, channel.id)
        if await is_whitelisted(self.bot, guild, getattr(executor, 'id', None)):
            return
        try:
            await channel.delete(reason='[Anti-Nuke] Unauthorized channel creation')
        except discord.HTTPException:
            pass
        if executor:
            await punish_member(guild, self.bot, executor.id, 'Created a channel without authorization')
        await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Channel', f"Channel creation reverted.\n**By:** {executor or 'Unknown'}", color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_guild_channel_delete(self, channel):
        if not isinstance(channel, discord.abc.GuildChannel):
            return
        guild = channel.guild
        if not await is_enabled(self.bot.store, guild.id, 'antichannel'):
            return
        executor = await fetch_executor(guild, discord.AuditLogAction.channel_delete, channel.id)
        if await is_whitelisted(self.bot, guild, getattr(executor, 'id', None)):
            return
        if executor:
            await punish_member(guild, self.bot, executor.id, 'Deleted a channel without authorization')
        await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Channel', f"Channel **{channel.name}** was deleted.\n**By:** {executor or 'Unknown'} (punished)", color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_invite_create(self, invite):
        guild = invite.guild
        if not guild or not await is_enabled(self.bot.store, guild.id, 'anticreateinvite'):
            return
        inviter_id = invite.inviter.id if invite.inviter else None
        if await is_whitelisted(self.bot, guild, inviter_id):
            return
        try:
            await invite.delete(reason='[Anti-Nuke] Unauthorized invite')
        except discord.HTTPException:
            pass
        if inviter_id:
            await punish_member(guild, self.bot, inviter_id, 'Created an invite without authorization')
        await send_mod_log(guild, self.bot, xlr_log_embed(self.bot, 'Anti-Invite', f"Invite deleted.\n**By:** {invite.inviter or 'Unknown'}", color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_guild_update(self, before, after):
        if not await is_enabled(self.bot.store, after.id, 'antiguildupdate'):
            return
        executor = await fetch_executor(after, discord.AuditLogAction.guild_update)
        if await is_whitelisted(self.bot, after, getattr(executor, 'id', None)):
            return
        if before.name != after.name:
            try:
                await after.edit(name=before.name, reason='[Anti-Nuke] Reverting server update')
            except discord.HTTPException:
                pass
        if executor:
            await punish_member(after, self.bot, executor.id, 'Modified the server without authorization')
        await send_mod_log(after, self.bot, xlr_log_embed(self.bot, 'Anti-Guild-Update', f"Server update reverted.\n**By:** {executor or 'Unknown'}", color=XLR_DANGER))

    @commands.Cog.listener()
    async def on_presence_update(self, before, after):
        try:
            member = after if isinstance(after, discord.Member) else getattr(after, 'member', None)
            if not member or not member.guild or member.bot:
                return
            guild = member.guild
            conf = self.bot.store.get(guild.id, 'statusrole')
            if not conf:
                return
            role = guild.get_role(int(conf['role']))
            if not role:
                return
            custom = discord.utils.get(member.activities, type=discord.ActivityType.custom)
            keyword = conf.get('keyword', '').lower()
            has_keyword = bool(custom and custom.state and (keyword in custom.state.lower()))
            if has_keyword and role not in member.roles:
                try:
                    await member.add_roles(role, reason='Status keyword matched')
                except discord.HTTPException:
                    pass
            elif not has_keyword and role in member.roles:
                try:
                    await member.remove_roles(role, reason='Status keyword removed')
                except discord.HTTPException:
                    pass
        except Exception:
            pass

class SecurityRuntime:

    def __init__(self, bot):
        self.bot = bot

    async def _delete_and_warn(self, message, member, user_notice, log_title, log_description):
        try:
            await message.delete()
        except discord.HTTPException:
            pass
        notice = await message.channel.send(embed=xlr_embed(self.bot, description=user_notice))
        await asyncio.sleep(4)
        try:
            await notice.delete()
        except discord.HTTPException:
            pass
        await send_mod_log(message.guild, self.bot, xlr_log_embed(self.bot, log_title, log_description, color=XLR_DANGER))
        return True

    async def run_message_security(self, message):
        member = message.author
        if not isinstance(member, discord.Member):
            return False
        exempt = member.guild_permissions.manage_messages or await is_whitelisted(self.bot, message.guild, member.id)
        if exempt:
            return False
        if await is_enabled(self.bot.store, message.guild.id, 'antiinvite'):
            if message_has_discord_invite(message):
                return await self._delete_and_warn(message, member, f'{member.mention}, Discord invite links are not allowed here.', 'Discord Invite Blocked', f'**User:** {member}\n**Channel:** {message.channel.mention}')
        if await is_enabled(self.bot.store, message.guild.id, 'antiexe'):
            if message_has_exe_attachment(message):
                return await self._delete_and_warn(message, member, f'{member.mention}, executable (.exe) files are not allowed here.', 'Executable File Blocked', f'**User:** {member}\n**Channel:** {message.channel.mention}')
        if message.content and await is_enabled(self.bot.store, message.guild.id, 'antilink'):
            if GENERAL_LINK_RE.search(message.content):
                return await self._delete_and_warn(message, member, f'{member.mention}, links are not allowed here.', 'Link Blocked', f'**User:** {member}\n**Channel:** {message.channel.mention}')
        if await is_enabled(self.bot.store, message.guild.id, 'antimassmention'):
            count = len(message.mentions) + len(message.role_mentions)
            if count >= 5:
                try:
                    await message.delete()
                    await member.timeout(discord.utils.utcnow() + discord.timedelta(minutes=10), reason='[Anti-Mass Mention]')
                except discord.HTTPException:
                    pass
                await send_mod_log(message.guild, self.bot, xlr_log_embed(self.bot, 'Mass Mention Blocked', f'**User:** {member}\n**Mentions:** {count}', color=XLR_DANGER))
                return True
        if await is_enabled(self.bot.store, message.guild.id, 'antispam'):
            count = self.bot.spam_tracker.track(message.guild.id, member.id)
            if count >= 6:
                self.bot.spam_tracker.reset(message.guild.id, member.id)
                try:
                    await member.timeout(discord.utils.utcnow() + discord.timedelta(minutes=1), reason='[Anti-Spam]')
                except discord.HTTPException:
                    pass
                notice = await message.channel.send(embed=xlr_embed(self.bot, description=f'{member.mention} has been muted for spamming.'))
                await asyncio.sleep(4)
                try:
                    await notice.delete()
                except discord.HTTPException:
                    pass
                await send_mod_log(message.guild, self.bot, xlr_log_embed(self.bot, 'Spam Blocked', f'**User:** {member}', color=XLR_DANGER))
                return True
        return False
