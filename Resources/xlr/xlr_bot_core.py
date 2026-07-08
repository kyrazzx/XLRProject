import json
import re
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path

import discord
from discord.ext import commands

from xlr_lib import WORKROOT, load_config, load_secrets

XLR_COLOR = 0x00A2FF
XLR_DANGER = 0xFF3355
XLR_SUCCESS = 0x2ECC71
LOGO_PATH = Path(__file__).resolve().parent / "assets" / "xlr_logo.png"
BOT_DB_PATH = WORKROOT / "Plutonium" / "storage" / "xlr" / "discord_bot.db"

SECURITY_KEYS = [
    "antibot",
    "antichannel",
    "antilink",
    "antiinvite",
    "antiexe",
    "antiban",
    "antiguildupdate",
    "anticreateinvite",
    "antikick",
    "antimassban",
    "antimasskick",
    "antiraid",
    "antimassmention",
    "antispam",
]

DISCORD_INVITE_RE = re.compile(
    r"(discord(?:app)?\.(?:com/invite|gg)|discord\.gg)/[a-z0-9-]+",
    re.I,
)

GENERAL_LINK_RE = re.compile(r"(https?://|www\.)", re.I)

ACTIVITY_IDS = {
    "poker": 755827207812677713,
    "betrayal": 773336526917861400,
    "fishing": 814288819477020702,
    "chess": 832012774040141894,
    "letterleague": 879863686565621790,
    "wordsnack": 879863976006127627,
    "doodlecrew": 878067389634314250,
    "spellcast": 852509694341283871,
    "ankword": 879863881349087252,
    "puttparty": 763133495753408553,
    "checkers": 832013003968348200,
    "youtube": 880218394199220334,
}

DURATION_RE = re.compile(r"^(\d+)(s|m|h|d|w)$", re.I)


def utc_now():
    return datetime.now(timezone.utc)


def discord_owner_id():
    secrets = load_secrets()
    if secrets.get("DISCORD_OWNER_ID"):
        return str(secrets["DISCORD_OWNER_ID"])
    config = load_config()
    owner = config.get("discord_config", {}).get("owner_id", "")
    return str(owner) if owner else ""


def default_prefix():
    config = load_config()
    return config.get("discord_config", {}).get("default_prefix", "!")


def discord_invite_link():
    config = load_config()
    return config.get("customization", {}).get("discord_invite", "discord.gg/63FAj2ZMrN")


def message_has_discord_invite(message):
    parts = [message.content or ""]
    for embed in message.embeds:
        if embed.url:
            parts.append(embed.url)
        if embed.description:
            parts.append(embed.description)
        if embed.title:
            parts.append(embed.title)
    return bool(DISCORD_INVITE_RE.search(" ".join(parts)))


def message_has_exe_attachment(message):
    for attachment in message.attachments:
        filename = (attachment.filename or "").lower()
        if filename.endswith(".exe"):
            return True
        content_type = (attachment.content_type or "").lower()
        if content_type == "application/x-msdownload":
            return True
    return False


def parse_duration(text):
    if not text:
        return None
    match = DURATION_RE.match(text.strip())
    if not match:
        return None
    amount = int(match.group(1))
    unit = match.group(2).lower()
    multipliers = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}
    return amount * multipliers[unit] * 1000


def format_duration_ms(ms):
    seconds = ms // 1000
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


class BotStore:
    def __init__(self, path=BOT_DB_PATH):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self):
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS guild_kv (
                    guild_id TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value TEXT NOT NULL,
                    PRIMARY KEY (guild_id, key)
                )
                """
            )
            conn.commit()

    def get(self, guild_id, key, default=None):
        row = self._connect().execute(
            "SELECT value FROM guild_kv WHERE guild_id = ? AND key = ?",
            (str(guild_id), key),
        ).fetchone()
        if not row:
            return default
        try:
            return json.loads(row["value"])
        except json.JSONDecodeError:
            return row["value"]

    def set(self, guild_id, key, value):
        payload = json.dumps(value)
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO guild_kv (guild_id, key, value) VALUES (?, ?, ?)
                ON CONFLICT(guild_id, key) DO UPDATE SET value = excluded.value
                """,
                (str(guild_id), key, payload),
            )
            conn.commit()

    def delete(self, guild_id, key):
        with self._connect() as conn:
            conn.execute(
                "DELETE FROM guild_kv WHERE guild_id = ? AND key = ?",
                (str(guild_id), key),
            )
            conn.commit()

    def get_global(self, key, default=None):
        return self.get("global", key, default)

    def set_global(self, key, value):
        self.set("global", key, value)


class ActionTracker:
    def __init__(self):
        self._data = {}

    def track(self, guild_id, executor_id, kind, window_ms=10000):
        key = f"{kind}_{guild_id}_{executor_id}"
        now = time.time() * 1000
        arr = [t for t in self._data.get(key, []) if now - t < window_ms]
        arr.append(now)
        self._data[key] = arr
        return len(arr)


class SpamTracker:
    def __init__(self):
        self._data = {}

    def track(self, guild_id, user_id, window_ms=5000):
        key = f"{guild_id}_{user_id}"
        now = time.time() * 1000
        arr = [t for t in self._data.get(key, []) if now - t < window_ms]
        arr.append(now)
        self._data[key] = arr
        return len(arr)

    def reset(self, guild_id, user_id):
        self._data[f"{guild_id}_{user_id}"] = []


class RaidTracker:
    def __init__(self):
        self._data = {}

    def track(self, guild_id, window_ms=10000):
        now = time.time() * 1000
        arr = [t for t in self._data.get(guild_id, []) if now - t < window_ms]
        arr.append(now)
        self._data[guild_id] = arr
        return len(arr)


def brand_icon_url(bot):
    if bot.user and bot.user.display_avatar:
        return bot.user.display_avatar.url
    return None


def xlr_embed(bot=None, *, title=None, description=None, color=XLR_COLOR):
    embed = discord.Embed(
        title=title,
        description=description,
        colour=color,
        timestamp=utc_now(),
    )
    icon = brand_icon_url(bot) if bot else None
    embed.set_author(name="XLR PROJECT", icon_url=icon)
    embed.set_footer(text="XLR EU · Black Ops II")
    return embed


def xlr_log_embed(bot, title, description, color=XLR_COLOR):
    embed = xlr_embed(bot, title=title, description=description, color=color)
    return embed


async def get_prefix_value(store, guild_id):
    return store.get(guild_id, "prefix") or default_prefix()


async def get_settings(store, guild_id):
    return store.get(guild_id, "settings") or {}


async def is_enabled(store, guild_id, key):
    settings = await get_settings(store, guild_id)
    return bool(settings.get(key))


async def is_whitelisted(bot, guild, user_id):
    if not user_id or not guild:
        return False
    if str(user_id) == str(bot.user.id):
        return True
    owner = discord_owner_id()
    if owner and str(user_id) == str(owner):
        return True
    if str(user_id) == str(guild.owner_id):
        return True
    whitelist = bot.store.get(guild.id, "whitelist") or []
    return str(user_id) in [str(item) for item in whitelist]


async def send_mod_log(guild, bot, embed):
    channel_id = bot.store.get(guild.id, "logs")
    if not channel_id:
        return
    channel = guild.get_channel(int(channel_id))
    if channel and isinstance(channel, discord.abc.Messageable):
        try:
            await channel.send(embed=embed)
        except discord.HTTPException:
            pass


async def fetch_executor(guild, action, target_id=None):
    try:
        async for entry in guild.audit_logs(limit=5, action=action):
            if (discord.utils.utcnow() - entry.created_at).total_seconds() > 6:
                continue
            if target_id and getattr(entry.target, "id", None) != int(target_id):
                continue
            return entry.user
    except (discord.Forbidden, discord.HTTPException):
        return None
    return None


async def punish_member(guild, bot, user_id, reason):
    if not user_id:
        return
    if await is_whitelisted(bot, guild, user_id):
        return
    member = guild.get_member(int(user_id))
    if not member:
        try:
            member = await guild.fetch_member(int(user_id))
        except (discord.NotFound, discord.HTTPException):
            return
    if member.guild_permissions.administrator:
        return
    try:
        if member.top_role < guild.me.top_role:
            await member.ban(reason=f"[Anti-Nuke] {reason}")
    except discord.HTTPException:
        try:
            await member.edit(roles=[])
        except discord.HTTPException:
            pass


async def add_warn(store, guild_id, user_id, moderator_id, reason):
    key = f"warns_{user_id}"
    warns = store.get(guild_id, key) or []
    warn = {
        "id": len(warns) + 1,
        "moderator": str(moderator_id),
        "reason": reason,
        "date": int(time.time() * 1000),
    }
    warns.append(warn)
    store.set(guild_id, key, warns)
    return warn


def format_welcome(template, member):
    text = template or "Hello {user}, welcome to **{server}**! You are member #{count}."
    return (
        text.replace("{user}", member.mention)
        .replace("{username}", member.display_name)
        .replace("{server}", member.guild.name)
        .replace("{count}", str(member.guild.member_count))
    )


CATEGORY_OWNER = "Owner"
CATEGORY_BO2 = "BO2 Servers"
CATEGORY_ORDER = [
    CATEGORY_BO2,
    CATEGORY_OWNER,
    "Moderation",
    "Utility",
    "Fun",
    "Mini-Games",
    "Bot",
]

COMMAND_DESCRIPTIONS = {
    "antibot": "Enable or disable the anti-bot module.",
    "antichannel": "Enable or disable anti-channel create/delete protection.",
    "antilink": "Enable or disable the anti-link module.",
    "antiinvite": "Auto-delete Discord invite links posted in chat.",
    "antiexe": "Auto-delete messages that contain .exe file attachments.",
    "antiban": "Enable or disable the anti-ban module.",
    "antiguildupdate": "Enable or disable anti-guild-update protection.",
    "anticreateinvite": "Enable or disable anti-invite creation.",
    "antikick": "Enable or disable the anti-kick module.",
    "antimassban": "Enable or disable anti-mass-ban detection.",
    "antimasskick": "Enable or disable anti-mass-kick detection.",
    "antiraid": "Enable or disable anti-raid join protection.",
    "anti-mass-mention": "Enable or disable anti-mass-mention protection.",
    "spam": "Enable or disable the anti-spam module.",
    "secur-max": "Activate all security modules at once.",
    "secur-on": "Activate standard security modules.",
    "secur-off": "Deactivate all security modules.",
    "secur": "Show the current state of every security module.",
    "whitelist": "Manage the anti-nuke whitelist. Usage: add/remove/list @user",
    "setup-captcha": "Set up captcha verification. Usage: #channel @role",
    "setup-logs": "Set the moderation and security log channel.",
    "setup-autorole": "Set the role automatically given to new members.",
    "scan-members": "Apply the auto-role to all members who are missing it.",
    "setup-ticket": "Deploy the support ticket panel in a channel. Usage: [#channel] or run in the target channel.",
    "status": "Show live status of all XLR BO2 game servers.",
    "stats": "Show XLR server stats: online players, unique players and bans.",
    "forcetip": "Force a random in-game tip in chat on BO2 servers. Bot owner only. Usage: [ffa|tdm|all]",
    "players": "Show player counts per game server. Optional: server id.",
    "report": "Submit a player report. Usage: <player> <reason>",
    "lookup": "Look up a player by name, Plutonium ID, Steam ID or IP. Bot owner only.",
    "gameban": "Ban a player from XLR BO2 servers. Usage: <player|id|ip> <reason>",
    "gamekick": "Kick an online player from their BO2 server. Usage: <player|id|ip> [reason]",
    "gameunban": "Remove a player ban from XLR BO2 servers.",
    "restart": "Restart game servers. Usage: [ffa|tdm|all]",
    "backup": "Run an XLR server backup immediately.",
    "dismiss": "Dismiss a pending in-game or Discord report by ID.",
    "ban": "Permanently ban a member from this Discord server.",
    "kick": "Kick a member from this Discord server.",
    "mute": "Temporarily mute a member. Usage: @user <duration> [reason]",
    "unmute": "Remove a member timeout/mute.",
    "tempban": "Temporarily ban a member. Usage: @user <duration> [reason]",
    "unban": "Unban a user by their Discord ID.",
    "warn": "Warn a member and log the infraction.",
    "clearwarns": "Clear all warnings for a member.",
    "sanction": "View a member's warning history.",
    "clear": "Delete messages in bulk. Usage: <1-100>",
    "prune": "Delete recent messages from one user.",
    "lock": "Lock the current channel for @everyone.",
    "unlock": "Unlock the current channel for @everyone.",
    "renew": "Clone and replace the current channel.",
    "snipe": "Show the last deleted message in this channel.",
    "gban": "Globally ban a user across every server the bot is in.",
    "gunban": "Remove a global ban from a user.",
    "greet": "Configure welcome messages. Usage: #channel [message]",
    "greet-list": "Show the current welcome message configuration.",
    "invite-guild": "Create a permanent invite link for this server.",
    "member": "Show the member count of this server.",
    "serverinfo": "Display information about this server.",
    "userinfo": "Display information about a user.",
    "banner": "Show a user's profile banner.",
    "avatar": "Show a user's avatar.",
    "random-avatar": "Show a random member's avatar.",
    "servericon": "Show this server's icon.",
    "alladmin": "List all administrators in this server.",
    "vc": "Show how many members are in voice channels.",
    "poll": "Create a yes/no poll.",
    "set-status": "Grant a role when a custom status contains a keyword.",
    "say": "Make the bot send an embed message.",
    "embed": "Send a custom embed from JSON.",
    "8ball": "Ask the magic 8-ball a question.",
    "coinflip": "Flip a coin.",
    "roll": "Roll a dice. Optional: number of sides.",
    "rate": "Rate anything from 0 to 100.",
    "poker": "Start a Poker activity in your voice channel.",
    "chess": "Start a Chess activity in your voice channel.",
    "checkers": "Start a Checkers activity in your voice channel.",
    "fishing": "Start a Fishing activity in your voice channel.",
    "betrayal": "Start a Betrayal activity in your voice channel.",
    "letterleague": "Start a Letter League activity in your voice channel.",
    "wordsnack": "Start a Word Snack activity in your voice channel.",
    "doodlecrew": "Start a Doodle Crew activity in your voice channel.",
    "spellcast": "Start a Spellcast activity in your voice channel.",
    "ankword": "Start an Ankword activity in your voice channel.",
    "puttparty": "Start a Putt Party activity in your voice channel.",
    "youtube": "Start a Watch Together activity in your voice channel.",
    "ping": "Check the bot latency.",
    "help": "Show commands you are allowed to use.",
    "setprefix": "Change the bot prefix for this server.",
    "stat": "Show how many servers the bot is in.",
    "support": "Get the XLR community Discord invite.",
    "allservers": "List every server the bot is connected to.",
    "leave": "Make the bot leave a server.",
    "setstatus": "Change the bot playing status.",
    "join": "Make the bot join your voice channel.",
}


def guild_owner_only():
    async def predicate(ctx):
        if not ctx.guild:
            raise commands.NoPrivateMessage()
        if ctx.author.id != ctx.guild.owner_id:
            raise commands.CheckFailure("Only the server owner can use this command.")
        return True
    return commands.check(predicate)


def bot_owner_only():
    async def predicate(ctx):
        owner_id = discord_owner_id()
        if not owner_id or str(ctx.author.id) != str(owner_id):
            raise commands.CheckFailure("Only the bot owner can use this command.")
        return True
    return commands.check(predicate)


def command_description(command):
    if command.help:
        return command.help
    return COMMAND_DESCRIPTIONS.get(command.name, "No description available.")


async def user_can_run_command(ctx, command):
    if command.hidden or not command.enabled:
        return False
    cog = command.cog
    if cog and getattr(cog, "category", None) == CATEGORY_OWNER:
        if not ctx.guild or ctx.author.id != ctx.guild.owner_id:
            return False
    try:
        await command.can_run(ctx)
        return True
    except commands.CommandError:
        return False


async def build_help_pages(ctx, bot, prefix):
    pages = {}
    for command in bot.commands:
        if not command.cog:
            continue
        if not await user_can_run_command(ctx, command):
            continue
        category = getattr(command.cog, "category", command.cog.__class__.__name__)
        pages.setdefault(category, []).append((command.name, command_description(command)))
    categories = [cat for cat in CATEGORY_ORDER if pages.get(cat)]
    for category in pages:
        if category not in categories:
            categories.append(category)
    for category in pages:
        pages[category].sort(key=lambda item: item[0])
    return categories, pages


class HelpView(discord.ui.View):
    def __init__(self, bot, author_id, categories, pages, prefix):
        super().__init__(timeout=120)
        self.bot = bot
        self.author_id = author_id
        self.categories = categories
        self.pages = pages
        self.prefix = prefix
        self.page = 0

    async def interaction_check(self, interaction):
        if interaction.user.id != self.author_id:
            await interaction.response.send_message(
                embed=xlr_embed(self.bot, description="Only the command author can use this menu."),
                ephemeral=True,
            )
            return False
        return True

    def build_embed(self):
        if not self.categories:
            return xlr_embed(self.bot, title="Help", description="You do not have access to any commands here.")
        category = self.categories[self.page]
        lines = [f"`{self.prefix}{name}`\n{desc}" for name, desc in self.pages.get(category, [])]
        return xlr_embed(
            self.bot,
            title=f"Help · {category}",
            description="\n\n".join(lines)[:4000] or "No commands available in this category.",
        ).set_footer(text=f"Page {self.page + 1}/{len(self.categories)} · XLR EU · Black Ops II")

    @discord.ui.button(label="◀", style=discord.ButtonStyle.secondary)
    async def prev_page(self, interaction: discord.Interaction, button: discord.ui.Button):
        if not self.categories:
            await interaction.response.defer()
            return
        self.page = (self.page - 1) % len(self.categories)
        await interaction.response.edit_message(embed=self.build_embed(), view=self)

    @discord.ui.button(label="▶", style=discord.ButtonStyle.secondary)
    async def next_page(self, interaction: discord.Interaction, button: discord.ui.Button):
        if not self.categories:
            await interaction.response.defer()
            return
        self.page = (self.page + 1) % len(self.categories)
        await interaction.response.edit_message(embed=self.build_embed(), view=self)

    async def on_timeout(self):
        for child in self.children:
            child.disabled = True
