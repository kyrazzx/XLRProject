import json
import re
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path

import discord

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


class HelpView(discord.ui.View):
    def __init__(self, bot, author_id, categories, prefix):
        super().__init__(timeout=120)
        self.bot = bot
        self.author_id = author_id
        self.categories = categories
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
        category = self.categories[self.page]
        lines = []
        for cmd in sorted(self.bot.commands, key=lambda c: c.name):
            if cmd.hidden or not cmd.cog:
                continue
            cat = getattr(cmd.cog, "category", cmd.cog.__class__.__name__)
            if cat != category:
                continue
            desc = cmd.help or cmd.brief or "No description."
            lines.append(f"`{self.prefix}{cmd.name}`\n{desc}")
        return xlr_embed(
            self.bot,
            title=f"Help · {category}",
            description="\n\n".join(lines)[:4000] or "No commands in this category.",
        ).set_footer(text=f"Page {self.page + 1}/{len(self.categories)} · XLR EU · Black Ops II")

    @discord.ui.button(label="◀", style=discord.ButtonStyle.secondary)
    async def prev_page(self, interaction: discord.Interaction, button: discord.ui.Button):
        self.page = (self.page - 1) % len(self.categories)
        await interaction.response.edit_message(embed=self.build_embed(), view=self)

    @discord.ui.button(label="▶", style=discord.ButtonStyle.secondary)
    async def next_page(self, interaction: discord.Interaction, button: discord.ui.Button):
        self.page = (self.page + 1) % len(self.categories)
        await interaction.response.edit_message(embed=self.build_embed(), view=self)

    async def on_timeout(self):
        for child in self.children:
            child.disabled = True
