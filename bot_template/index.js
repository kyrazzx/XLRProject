const {
    Client,
    GatewayIntentBits,
    Partials,
    Collection,
    EmbedBuilder,
    ActionRowBuilder,
    ButtonBuilder,
    ButtonStyle,
    ChannelType,
    PermissionsBitField,
    ActivityType,
    AuditLogEvent
} = require('discord.js');
const { QuickDB } = require('quick.db');
const config = require('./config.json');
const ms = require('ms');

const db = new QuickDB();

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildModeration,
        GatewayIntentBits.GuildInvites,
        GatewayIntentBits.GuildVoiceStates,
        GatewayIntentBits.GuildPresences,
    ],
    partials: [Partials.Channel, Partials.Message, Partials.User, Partials.GuildMember],
});

client.commands = new Collection();
const snipe = new Map();
const activityIDs = {
    poker: "755827207812677713",
    betrayal: "773336526917861400",
    fishing: "814288819477020702",
    chess: "832012774040141894",
    letterleague: "879863686565621790",
    wordsnack: "879863976006127627",
    doodlecrew: "878067389634314250",
    spellcast: "852509694341283871",
    ankword: "879863881349087252",
    puttparty: "763133495753408553",
    checkers: "832013003968348200",
    youtube: "880218394199220334",
};

const SECURITY_KEYS = [
    'antibot', 'antichannel', 'antilink', 'antiban', 'antiguildupdate',
    'anticreateinvite', 'antikick', 'antimassban', 'antimasskick',
    'antiraid', 'antimassmention', 'antispam'
];

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------
const createEmbed = (description) => new EmbedBuilder().setColor('#000001').setDescription(description);

const logEmbed = (title, description, color = '#000001') =>
    new EmbedBuilder().setColor(color).setTitle(title).setDescription(description).setTimestamp();

async function getPrefix(guildId) {
    return (await db.get(`prefix_${guildId}`)) || config.default_prefix;
}

async function getSettings(guildId) {
    return (await db.get(`settings_${guildId}`)) || {};
}

async function isEnabled(guildId, key) {
    const settings = await getSettings(guildId);
    return !!settings[key];
}

async function isWhitelisted(guild, userId) {
    if (!userId || !guild) return false;
    if (userId === client.user.id) return true;
    if (userId === config.owner_id) return true;
    if (userId === guild.ownerId) return true;
    const wl = (await db.get(`whitelist_${guild.id}`)) || [];
    return wl.includes(userId);
}

async function sendLog(guild, embed) {
    try {
        const channelId = await db.get(`logs_${guild.id}`);
        if (!channelId) return;
        const channel = guild.channels.cache.get(channelId);
        if (channel && channel.isTextBased()) await channel.send({ embeds: [embed] });
    } catch (_) { /* ignore */ }
}

// Finds who performed an audit-log action in the last few seconds.
async function fetchExecutor(guild, type, targetId) {
    try {
        const logs = await guild.fetchAuditLogs({ type, limit: 5 });
        const entry = logs.entries.find(e =>
            Date.now() - e.createdTimestamp < 6000 &&
            (!targetId || e.target?.id === targetId)
        );
        return entry?.executor || null;
    } catch (_) {
        return null;
    }
}

// Bans (or strips roles from) a user who triggered an anti-nuke rule.
async function punish(guild, userId, reason) {
    if (!userId) return;
    if (await isWhitelisted(guild, userId)) return;
    const member = await guild.members.fetch(userId).catch(() => null);
    if (!member) return;
    if (member.bannable) {
        await member.ban({ reason: `[Anti-Nuke] ${reason}` }).catch(() => {});
    } else {
        await member.roles.set([]).catch(() => {});
    }
}

// Tracks repeated actions (mass-ban / mass-kick) per executor within a window.
const actionTracker = new Map();
function trackAction(guildId, executorId, kind, windowMs = 10000) {
    const key = `${kind}_${guildId}_${executorId}`;
    const now = Date.now();
    const arr = (actionTracker.get(key) || []).filter(t => now - t < windowMs);
    arr.push(now);
    actionTracker.set(key, arr);
    return arr.length;
}

async function addWarn(guild, userId, moderatorId, reason) {
    const key = `warns_${guild.id}_${userId}`;
    const warns = (await db.get(key)) || [];
    const warn = { id: warns.length + 1, moderator: moderatorId, reason, date: Date.now() };
    warns.push(warn);
    await db.set(key, warns);
    return warn;
}

async function toggleSetting(message, setting, settingName) {
    const key = `settings_${message.guild.id}.${setting}`;
    const current = (await db.get(key)) || false;
    await db.set(key, !current);
    message.reply({ embeds: [createEmbed(`${settingName} module has been **${!current ? 'enabled' : 'disabled'}**.`)] });
}

async function setAllSecurity(message, status, profileName) {
    const settings = {};
    SECURITY_KEYS.forEach(k => { settings[k] = status; });
    await db.set(`settings_${message.guild.id}`, settings);
    message.reply({ embeds: [createEmbed(`${profileName} profile has been **${status ? 'activated' : 'deactivated'}**.`)] });
}

function formatWelcome(template, member) {
    return (template || `Hello {user}, welcome to **{server}**! You are member #{count}.`)
        .replace(/{user}/g, `<@${member.id}>`)
        .replace(/{username}/g, member.user.username)
        .replace(/{server}/g, member.guild.name)
        .replace(/{count}/g, member.guild.memberCount);
}

// ---------------------------------------------------------------------------
//  Commands
// ---------------------------------------------------------------------------
const commands = [
    { name: 'antibot', category: 'Administration', description: 'Enable or disable the anti-bot module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antibot', 'Anti-Bot') },
    { name: 'antichannel', category: 'Administration', description: 'Enable or disable the anti-channel module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antichannel', 'Anti-Channel Create/Delete') },
    { name: 'antilink', category: 'Administration', description: 'Enable or disable the anti-link module.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message) => toggleSetting(message, 'antilink', 'Anti-Link') },
    { name: 'antiban', category: 'Administration', description: 'Enable or disable the anti-ban module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antiban', 'Anti-Ban') },
    { name: 'antiguildupdate', category: 'Administration', description: 'Enable or disable the anti-guild-update module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antiguildupdate', 'Anti-Guild Update') },
    { name: 'anticreateinvite', category: 'Administration', description: 'Enable or disable the anti-create-invite module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'anticreateinvite', 'Anti-Invite Create') },
    { name: 'antikick', category: 'Administration', description: 'Enable or disable the anti-kick module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antikick', 'Anti-Kick') },
    { name: 'antimassban', category: 'Administration', description: 'Enable or disable the anti-mass-ban module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antimassban', 'Anti-Mass Ban') },
    { name: 'antimasskick', category: 'Administration', description: 'Enable or disable the anti-mass-kick module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antimasskick', 'Anti-Mass Kick') },
    { name: 'antiraid', category: 'Administration', description: 'Enable or disable the anti-raid module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antiraid', 'Anti-Raid') },
    { name: 'anti-mass-mention', category: 'Administration', description: 'Enable or disable the anti-mass-mention module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => toggleSetting(message, 'antimassmention', 'Anti-Mass Mention') },
    { name: 'spam', category: 'Administration', description: 'Enable or disable the anti-spam module.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message) => toggleSetting(message, 'antispam', 'Anti-Spam') },
    { name: 'secur-max', category: 'Administration', description: 'Activate maximum security settings.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => setAllSecurity(message, true, 'Maximum Security') },
    { name: 'secur-on', category: 'Administration', description: 'Activate standard security settings.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => setAllSecurity(message, true, 'Standard Security') },
    { name: 'secur-off', category: 'Administration', description: 'Deactivate all security settings.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => setAllSecurity(message, false, 'All Security') },
    { name: 'secur', category: 'Administration', description: 'Show the current state of every security module.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => {
        const settings = await getSettings(message.guild.id);
        const list = SECURITY_KEYS.map(k => `${settings[k] ? '🟢' : '🔴'} \`${k}\``).join('\n');
        message.channel.send({ embeds: [new EmbedBuilder().setColor('#000001').setTitle('Security Modules').setDescription(list)] });
    }},
    { name: 'whitelist', category: 'Administration', description: 'Manage the anti-nuke whitelist. Usage: `?whitelist add/remove @user` or `?whitelist list`.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message, args) => {
        const sub = (args[0] || '').toLowerCase();
        const key = `whitelist_${message.guild.id}`;
        const wl = (await db.get(key)) || [];
        const user = message.mentions.users.first();
        if (sub === 'add' && user) {
            if (!wl.includes(user.id)) { wl.push(user.id); await db.set(key, wl); }
            return message.reply({ embeds: [createEmbed(`${user.tag} is now whitelisted from anti-nuke punishments.`)] });
        }
        if (sub === 'remove' && user) {
            await db.set(key, wl.filter(id => id !== user.id));
            return message.reply({ embeds: [createEmbed(`${user.tag} has been removed from the whitelist.`)] });
        }
        if (sub === 'list') {
            const desc = wl.length ? wl.map(id => `<@${id}>`).join('\n') : 'The whitelist is empty.';
            return message.channel.send({ embeds: [new EmbedBuilder().setColor('#000001').setTitle('Anti-Nuke Whitelist').setDescription(desc)] });
        }
        message.reply({ embeds: [createEmbed("Usage: `?whitelist add @user`, `?whitelist remove @user`, `?whitelist list`")] });
    }},
    { name: 'setup-captcha', category: 'Administration', description: 'Define the channel and role for the captcha verification system.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => {
        const channel = message.mentions.channels.first();
        const role = message.mentions.roles.first();
        if (!channel || !role) return message.reply({ embeds: [createEmbed("Usage: `?setup-captcha #channel @role`")] });
        await db.set(`captcha_${message.guild.id}`, { channel: channel.id, role: role.id });
        const embed = new EmbedBuilder().setColor('#000001').setTitle('✅ Verification').setDescription(`Welcome to **${message.guild.name}**!\nClick the button below to verify yourself and gain access to the server.`).setFooter({ text: message.guild.name, iconURL: message.guild.iconURL() });
        const row = new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId('verify_captcha').setLabel('Verify').setStyle(ButtonStyle.Success).setEmoji('✅'));
        await channel.send({ embeds: [embed], components: [row] });
        message.reply({ embeds: [createEmbed(`Captcha system set in ${channel} and will grant the ${role} role.`)] });
    }},
    { name: 'setup-logs', category: 'Administration', description: 'Define the channel for moderation and security logs.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => {
        const channel = message.mentions.channels.first() || message.channel;
        await db.set(`logs_${message.guild.id}`, channel.id);
        message.reply({ embeds: [createEmbed(`Log channel has been set to ${channel}.`)] });
    }},
    { name: 'setup-autorole', category: 'Administration', description: 'Set the role automatically given to new members (the "member" role).', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => {
        const role = message.mentions.roles.first();
        if (!role) return message.reply({ embeds: [createEmbed("Usage: `?setup-autorole @role`")] });
        await db.set(`autorole_${message.guild.id}`, role.id);
        message.reply({ embeds: [createEmbed(`New members will now automatically receive the ${role} role. Run \`${await getPrefix(message.guild.id)}scan-membre\` to apply it to existing members.`)] });
    }},
    { name: 'scan-membre', category: 'Administration', description: 'Give the member/auto-role to every member who is missing it.', permissions: [PermissionsBitField.Flags.ManageRoles], execute: (message) => scanMembers(message) },
    { name: 'scan-members', category: 'Administration', description: 'Alias of scan-membre.', permissions: [PermissionsBitField.Flags.ManageRoles], execute: (message) => scanMembers(message) },
    { name: 'setup-ticket', category: 'Administration', description: 'Set up the ticket creation panel in a channel.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message) => {
        const channel = message.mentions.channels.first();
        if (!channel) return message.reply({ embeds: [createEmbed("Please mention a channel to set up the ticket system.")] });
        const embed = new EmbedBuilder().setTitle("Support Ticket").setDescription("Click the button below to create a ticket and our support team will assist you shortly.").setColor("Blue").setFooter({ text: message.guild.name, iconURL: message.guild.iconURL() });
        const row = new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId('create_ticket').setLabel('Create Ticket').setStyle(ButtonStyle.Success).setEmoji('📩'));
        const ticketMessage = await channel.send({ embeds: [embed], components: [row] });
        await db.set(`ticket_setup_${message.guild.id}`, { channel: channel.id, message: ticketMessage.id });
        message.reply({ embeds: [createEmbed(`Ticket system has been set up in ${channel}.`)] });
    }},
    { name: 'ban', category: 'Moderation', description: 'Permanently ban a user.', permissions: [PermissionsBitField.Flags.BanMembers], execute: async (message, args) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member to ban.")] });
        if (!member.bannable) return message.reply({ embeds: [createEmbed("I cannot ban this user.")] });
        const reason = args.slice(1).join(" ") || "No reason provided.";
        await member.ban({ reason });
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been banned.`)] });
        sendLog(message.guild, logEmbed('🔨 Member Banned', `**User:** ${member.user.tag} (${member.id})\n**Moderator:** ${message.author.tag}\n**Reason:** ${reason}`));
    }},
    { name: 'clear', category: 'Moderation', description: 'Delete a number of messages.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message, args) => {
        const amount = parseInt(args[0]);
        if (isNaN(amount) || amount <= 0 || amount > 100) return message.reply({ embeds: [createEmbed("Please provide a number between 1 and 100.")] });
        await message.channel.bulkDelete(amount + 1, true);
        message.channel.send({ embeds: [createEmbed(`Deleted ${amount} messages.`)] }).then(msg => setTimeout(() => msg.delete().catch(() => {}), 3000));
    }},
    { name: 'gban', category: 'Moderation', description: 'Globally ban a user across every server the bot is in (owner only).', permissions: [], execute: async (message, args) => {
        if (message.author.id !== config.owner_id) return message.reply({ embeds: [createEmbed("This command is owner-only.")] });
        const userId = message.mentions.users.first()?.id || args[0];
        if (!userId || !/^\d{17,20}$/.test(userId)) return message.reply({ embeds: [createEmbed("Usage: `?gban <userId/@user> [reason]`")] });
        const reason = args.slice(1).join(" ") || "Global ban";
        const gbans = (await db.get('gbans')) || [];
        if (!gbans.includes(userId)) { gbans.push(userId); await db.set('gbans', gbans); }
        let count = 0;
        for (const guild of client.guilds.cache.values()) {
            try { await guild.bans.create(userId, { reason: `[GBAN] ${reason}` }); count++; } catch (_) {}
        }
        message.channel.send({ embeds: [createEmbed(`Globally banned <@${userId}> across **${count}** server(s).`)] });
    }},
    { name: 'gunban', category: 'Moderation', description: 'Remove a global ban (owner only).', permissions: [], execute: async (message, args) => {
        if (message.author.id !== config.owner_id) return message.reply({ embeds: [createEmbed("This command is owner-only.")] });
        const userId = message.mentions.users.first()?.id || args[0];
        if (!userId || !/^\d{17,20}$/.test(userId)) return message.reply({ embeds: [createEmbed("Usage: `?gunban <userId/@user>`")] });
        let gbans = (await db.get('gbans')) || [];
        gbans = gbans.filter(id => id !== userId);
        await db.set('gbans', gbans);
        let count = 0;
        for (const guild of client.guilds.cache.values()) {
            try { await guild.bans.remove(userId, '[GUNBAN]'); count++; } catch (_) {}
        }
        message.channel.send({ embeds: [createEmbed(`Removed the global ban for <@${userId}> across **${count}** server(s).`)] });
    }},
    { name: 'kick', category: 'Moderation', description: 'Kick a user from the server.', permissions: [PermissionsBitField.Flags.KickMembers], execute: async (message, args) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member to kick.")] });
        if (!member.kickable) return message.reply({ embeds: [createEmbed("I cannot kick this user.")] });
        const reason = args.slice(1).join(" ") || "No reason provided.";
        await member.kick(reason);
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been kicked.`)] });
        sendLog(message.guild, logEmbed('👢 Member Kicked', `**User:** ${member.user.tag} (${member.id})\n**Moderator:** ${message.author.tag}\n**Reason:** ${reason}`));
    }},
    { name: 'lock', category: 'Moderation', description: 'Lock a channel.', permissions: [PermissionsBitField.Flags.ManageChannels], execute: async (message) => {
        await message.channel.permissionOverwrites.edit(message.guild.id, { SendMessages: false });
        message.channel.send({ embeds: [createEmbed("Channel has been locked. 🔒")] });
    }},
    { name: 'mute', category: 'Moderation', description: 'Temporarily mute a user.', permissions: [PermissionsBitField.Flags.ModerateMembers], execute: async (message, args) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member to mute.")] });
        const time = args[1];
        if (!time) return message.reply({ embeds: [createEmbed("You need to specify a duration (e.g., 10m, 1h, 1d).")] });
        const reason = args.slice(2).join(" ") || "No reason provided.";
        const duration = ms(time);
        if (!duration || duration > ms('28d')) return message.reply({ embeds: [createEmbed("Invalid duration. Maximum is 28 days.")] });
        await member.timeout(duration, reason);
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been muted for ${time}.`)] });
        sendLog(message.guild, logEmbed('🔇 Member Muted', `**User:** ${member.user.tag} (${member.id})\n**Moderator:** ${message.author.tag}\n**Duration:** ${time}\n**Reason:** ${reason}`));
    }},
    { name: 'prune', category: 'Moderation', description: 'Delete a number of messages from a user.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message, args) => {
        const member = message.mentions.members.first();
        const amount = parseInt(args[1]);
        if (!member || isNaN(amount) || amount <= 0 || amount > 100) return message.reply({ embeds: [createEmbed("Usage: `?prune @user <amount>`")] });
        const messages = await message.channel.messages.fetch({ limit: 100 });
        const userMessages = messages.filter(m => m.author.id === member.id).first(amount);
        await message.channel.bulkDelete(userMessages, true);
        message.channel.send({ embeds: [createEmbed(`Deleted ${userMessages.length} messages from ${member.user.tag}.`)] }).then(msg => setTimeout(() => msg.delete().catch(() => {}), 3000));
    }},
    { name: 'renew', category: 'Moderation', description: 'Duplicate a channel and delete the old one.', permissions: [PermissionsBitField.Flags.ManageChannels], execute: async (message) => {
        const position = message.channel.position;
        const newChannel = await message.channel.clone();
        await message.channel.delete();
        await newChannel.setPosition(position);
        newChannel.send({ embeds: [createEmbed("Channel has been successfully renewed.")] });
    }},
    { name: 'sanction', category: 'Moderation', description: "View a user's infractions.", permissions: [PermissionsBitField.Flags.ViewAuditLog], execute: async (message) => {
        const member = message.mentions.members.first() || message.member;
        const warns = (await db.get(`warns_${message.guild.id}_${member.id}`)) || [];
        if (!warns.length) return message.reply({ embeds: [createEmbed(`${member.user.tag} has no infractions.`)] });
        const desc = warns.map(w => `**Case #${w.id}** • <t:${Math.floor(w.date / 1000)}:R>\nModerator: <@${w.moderator}>\nReason: ${w.reason}`).join('\n\n');
        message.channel.send({ embeds: [new EmbedBuilder().setColor('#000001').setTitle(`Infractions for ${member.user.tag}`).setDescription(desc.substring(0, 4000))] });
    }},
    { name: 'snipe', category: 'Moderation', description: 'See the last deleted message in the channel.', permissions: [], execute: async (message) => {
        const snipeData = snipe.get(message.channel.id);
        if (!snipeData) return message.reply({ embeds: [createEmbed("There's nothing to snipe!")] });
        const embed = new EmbedBuilder().setAuthor({ name: snipeData.author.tag, iconURL: snipeData.author.displayAvatarURL() }).setDescription(snipeData.content).setColor("#000001").setTimestamp(snipeData.timestamp);
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'tempban', category: 'Moderation', description: 'Temporarily ban a user. Usage: `?tempban @user <duration> [reason]`.', permissions: [PermissionsBitField.Flags.BanMembers], execute: async (message, args) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("Usage: `?tempban @user <duration> [reason]`")] });
        if (!member.bannable) return message.reply({ embeds: [createEmbed("I cannot ban this user.")] });
        const time = args[1];
        const duration = ms(time || "");
        if (!duration) return message.reply({ embeds: [createEmbed("Invalid duration. Example: `?tempban @user 7d spamming`.")] });
        const reason = args.slice(2).join(" ") || "No reason provided.";
        await member.ban({ reason: `[Tempban ${time}] ${reason}` });
        const tempbans = (await db.get('tempbans')) || [];
        tempbans.push({ guildId: message.guild.id, userId: member.id, unbanAt: Date.now() + duration });
        await db.set('tempbans', tempbans);
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been banned for ${time}.`)] });
        sendLog(message.guild, logEmbed('⏳ Member Temp-Banned', `**User:** ${member.user.tag} (${member.id})\n**Moderator:** ${message.author.tag}\n**Duration:** ${time}\n**Reason:** ${reason}`));
    }},
    { name: 'unban', category: 'Moderation', description: 'Unban a user by their ID.', permissions: [PermissionsBitField.Flags.BanMembers], execute: async (message, args) => {
        const userId = args[0];
        if (!userId) return message.reply({ embeds: [createEmbed("You need to provide a user ID to unban.")] });
        try {
            await message.guild.bans.remove(userId);
            message.channel.send({ embeds: [createEmbed(`Successfully unbanned user ID ${userId}.`)] });
        } catch (e) {
            message.reply({ embeds: [createEmbed("Could not unban this user. Are you sure the ID is correct?")] });
        }
    }},
    { name: 'unlock', category: 'Moderation', description: 'Unlock a channel.', permissions: [PermissionsBitField.Flags.ManageChannels], execute: async (message) => {
        await message.channel.permissionOverwrites.edit(message.guild.id, { SendMessages: null });
        message.channel.send({ embeds: [createEmbed("Channel has been unlocked. 🔓")] });
    }},
    { name: 'unmute', category: 'Moderation', description: 'Unmute a user.', permissions: [PermissionsBitField.Flags.ModerateMembers], execute: async (message) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member to unmute.")] });
        await member.timeout(null);
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been unmuted.`)] });
    }},
    { name: 'warn', category: 'Moderation', description: 'Warn a user. Usage: `?warn @user <reason>`.', permissions: [PermissionsBitField.Flags.KickMembers], execute: async (message, args) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member to warn.")] });
        const reason = args.slice(1).join(" ") || "No reason provided.";
        const warn = await addWarn(message.guild, member.id, message.author.id, reason);
        await member.send({ embeds: [createEmbed(`You have been warned in **${message.guild.name}**.\nReason: ${reason}`)] }).catch(() => {});
        message.channel.send({ embeds: [createEmbed(`${member.user.tag} has been warned. (Case #${warn.id})\nReason: ${reason}`)] });
        sendLog(message.guild, logEmbed('⚠️ Member Warned', `**User:** ${member.user.tag} (${member.id})\n**Moderator:** ${message.author.tag}\n**Case:** #${warn.id}\n**Reason:** ${reason}`));
    }},
    { name: 'clearwarns', category: 'Moderation', description: "Clear all of a user's infractions.", permissions: [PermissionsBitField.Flags.KickMembers], execute: async (message) => {
        const member = message.mentions.members.first();
        if (!member) return message.reply({ embeds: [createEmbed("You need to mention a member.")] });
        await db.delete(`warns_${message.guild.id}_${member.id}`);
        message.channel.send({ embeds: [createEmbed(`Cleared all infractions for ${member.user.tag}.`)] });
    }},
    ...Object.keys(activityIDs).map(name => ({
        name: name, category: 'Mini-Games', description: `Play ${name.charAt(0).toUpperCase() + name.slice(1)} in a voice channel.`, permissions: [], execute: async (message) => {
            const vc = message.member.voice.channel;
            if (!vc) return message.reply({ embeds: [createEmbed("You must be in a voice channel to start an activity.")] });
            try {
                const invite = await vc.createInvite({ targetApplication: activityIDs[name], targetType: 2 });
                message.reply({ embeds: [createEmbed(`Click here to start **${name.charAt(0).toUpperCase() + name.slice(1)}**!\n[Activity Link](${invite.url})`)] });
            } catch (e) {
                console.error(e);
                message.reply({ embeds: [createEmbed("I couldn't create an activity invite. I might be missing the 'Create Invite' permission.")] });
            }
        }
    })),
    { name: '8ball', category: 'Fun', description: 'Ask a question to the magic 8-ball.', permissions: [], execute: (message) => {
        const responses = ["It is certain.", "Without a doubt.", "Yes – definitely.", "Signs point to yes.", "Reply hazy, try again.", "Don't count on it.", "My sources say no.", "Very doubtful."];
        message.reply({ embeds: [createEmbed(responses[Math.floor(Math.random() * responses.length)])] });
    }},
    { name: 'gay', category: 'Fun', description: 'See how gay a user is.', permissions: [], execute: (message) => {
        const member = message.mentions.members.first() || message.member;
        message.channel.send({ embeds: [createEmbed(`${member.displayName} is ${Math.floor(Math.random() * 101)}% gay! 🏳️‍🌈`)] });
    }},
    { name: 'pf', category: 'Fun', description: 'Flip a coin.', permissions: [], execute: (message) => message.reply({ embeds: [createEmbed(`It's **${Math.random() > 0.5 ? 'Heads' : 'Tails'}**!`)] }) },
    { name: 'politique', category: 'Fun', description: 'Ask the bot for whom it votes.', permissions: [], execute: (message) => message.reply({ embeds: [createEmbed("I vote for a future where all bots are treated equally.")] }) },
    { name: 'alladmin', category: 'Utility', description: 'See the list of admins on the server.', permissions: [], execute: async (message) => {
        await message.guild.members.fetch();
        const admins = message.guild.members.cache.filter(m => !m.user.bot && m.permissions.has(PermissionsBitField.Flags.Administrator));
        message.channel.send({ embeds: [createEmbed(`**Admins on this server:**\n${admins.map(a => a.user.tag).join('\n') || 'None'}`)] });
    }},
    { name: 'banner', category: 'Utility', description: "Get a user's banner.", permissions: [], execute: async (message) => {
        const user = message.mentions.users.first() || message.author;
        const fetchedUser = await client.users.fetch(user.id, { force: true });
        if (!fetchedUser.banner) return message.reply({ embeds: [createEmbed("This user does not have a banner.")] });
        const embed = new EmbedBuilder().setColor("#000001").setTitle(`${user.tag}'s Banner`).setImage(fetchedUser.bannerURL({ size: 4096 }));
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'embed', category: 'Utility', description: 'Create an embed from JSON code.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message, args) => {
        const content = args.join(" ");
        try {
            const data = JSON.parse(content);
            message.channel.send({ embeds: [data] });
        } catch (e) {
            message.reply({ embeds: [createEmbed("Invalid JSON format for the embed.")] });
        }
    }},
    { name: 'greet', category: 'Utility', description: 'Set the welcome channel/message. Usage: `?greet #channel [text with {user} {server} {count}]`.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message, args) => {
        const channel = message.mentions.channels.first();
        if (!channel) return message.reply({ embeds: [createEmbed("Usage: `?greet #channel [message]`\nPlaceholders: `{user}`, `{username}`, `{server}`, `{count}`")] });
        const text = args.filter(a => !/^<#!?\d+>$/.test(a)).join(' ');
        await db.set(`welcome_${message.guild.id}`, { channel: channel.id, message: text || null });
        message.reply({ embeds: [createEmbed(`Welcome messages will be sent in ${channel}.`)] });
    }},
    { name: 'greet-list', category: 'Utility', description: 'Show the current welcome configuration.', permissions: [], execute: async (message) => {
        const w = await db.get(`welcome_${message.guild.id}`);
        if (!w) return message.reply({ embeds: [createEmbed("No welcome message is configured. Set one with `?greet #channel`.")] });
        message.channel.send({ embeds: [createEmbed(`**Welcome channel:** <#${w.channel}>\n**Message:** ${w.message || '*(default message)*'}`)] });
    }},
    { name: 'invite-guild', category: 'Utility', description: 'Get a permanent invite link for the server.', permissions: [], execute: async (message) => {
        const invite = await message.channel.createInvite({ maxAge: 0, maxUses: 0 });
        message.channel.send({ embeds: [createEmbed(`Here is a permanent invite link: ${invite.url}`)] });
    }},
    { name: 'member', category: 'Utility', description: 'Know the number of members on the server.', permissions: [], execute: async (message) => message.channel.send({ embeds: [createEmbed(`There are **${message.guild.memberCount}** members on this server.`)] }) },
    { name: 'pp-random', category: 'Utility', description: "Get a random member's avatar.", permissions: [], execute: async (message) => {
        const member = message.guild.members.cache.random();
        const embed = new EmbedBuilder().setColor("#000001").setTitle(member.user.tag).setImage(member.user.displayAvatarURL({ size: 512 }));
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'pp-serveur', category: 'Utility', description: "Get the server's icon.", permissions: [], execute: async (message) => {
        const embed = new EmbedBuilder().setColor("#000001").setTitle(message.guild.name).setImage(message.guild.iconURL({ size: 512 }));
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'pp', category: 'Utility', description: "Get a user's avatar.", permissions: [], execute: async (message) => {
        const user = message.mentions.users.first() || message.author;
        const embed = new EmbedBuilder().setColor("#000001").setTitle(user.tag).setImage(user.displayAvatarURL({ size: 512 }));
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'say', category: 'Utility', description: 'Make the bot talk.', permissions: [PermissionsBitField.Flags.ManageMessages], execute: async (message, args) => {
        const text = args.join(" ");
        if (text) {
            message.delete().catch(() => {});
            message.channel.send({ embeds: [createEmbed(text)] });
        }
    }},
    { name: 'serverinfo', category: 'Utility', description: 'Get information about the server.', permissions: [], execute: async (message) => {
        const guild = message.guild;
        const embed = new EmbedBuilder().setTitle(guild.name).setThumbnail(guild.iconURL()).addFields({ name: 'Owner', value: `<@${guild.ownerId}>`, inline: true }, { name: 'Members', value: `${guild.memberCount}`, inline: true }, { name: 'Created', value: `<t:${parseInt(guild.createdTimestamp / 1000)}:R>`, inline: true }, { name: 'Roles', value: `${guild.roles.cache.size}`, inline: true }, { name: 'Channels', value: `${guild.channels.cache.size}`, inline: true }).setColor("#000001");
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'set-statut', category: 'Utility', description: 'Give a role to members whose custom status contains a keyword. Usage: `?set-statut @role <keyword>`.', permissions: [PermissionsBitField.Flags.Administrator], execute: async (message, args) => {
        const role = message.mentions.roles.first();
        const keyword = args.filter(a => !/^<@&\d+>$/.test(a)).join(' ');
        if (!role || !keyword) return message.reply({ embeds: [createEmbed("Usage: `?set-statut @role <keyword>`")] });
        await db.set(`statusrole_${message.guild.id}`, { role: role.id, keyword });
        message.reply({ embeds: [createEmbed(`Members with \`${keyword}\` in their custom status will now receive the ${role} role.`)] });
    }},
    { name: 'sondage', category: 'Utility', description: 'Create a poll with the bot.', permissions: [], execute: async (message, args) => {
        const question = args.join(" ");
        if (!question) return message.reply({ embeds: [createEmbed("You need to provide a question for the poll.")] });
        const poll = await message.channel.send({ embeds: [new EmbedBuilder().setColor("#000001").setTitle("📊 Poll").setDescription(question)] });
        await poll.react('👍');
        await poll.react('👎');
    }},
    { name: 'stat', category: 'Utility', description: 'See the number of servers the bot is in.', permissions: [], execute: async (message) => message.channel.send({ embeds: [createEmbed(`I am currently in **${client.guilds.cache.size}** servers.`)] }) },
    { name: 'userinfo', category: 'Utility', description: 'Get information about a user.', permissions: [], execute: async (message) => {
        const member = message.mentions.members.first() || message.member;
        const embed = new EmbedBuilder().setTitle(member.user.tag).setThumbnail(member.user.displayAvatarURL()).addFields({ name: 'ID', value: member.id }, { name: 'Joined Server', value: `<t:${parseInt(member.joinedTimestamp / 1000)}:R>`, inline: true }, { name: 'Account Created', value: `<t:${parseInt(member.user.createdTimestamp / 1000)}:R>`, inline: true }, { name: 'Roles', value: member.roles.cache.map(r => r).join(' ').substring(0, 1024) || 'None' }).setColor(member.displayHexColor === '#000000' ? '#000001' : member.displayHexColor);
        message.channel.send({ embeds: [embed] });
    }},
    { name: 'vc', category: 'Utility', description: 'See the number of people in voice channels.', permissions: [], execute: async (message) => {
        const voiceMembers = message.guild.members.cache.filter(m => m.voice.channel);
        message.channel.send({ embeds: [createEmbed(`There are **${voiceMembers.size}** members in voice channels.`)] });
    }},
    { name: 'token', category: 'Bot', description: "Information about the bot's token.", permissions: [], execute: async (message) => message.reply({ embeds: [createEmbed("My token is safe. Never share your token with anyone.")] }) },
    { name: 'allserveur', category: 'Bot', description: 'See the list of servers the bot is in (owner only).', permissions: [], execute: async (message) => {
        if (message.author.id !== config.owner_id) return;
        const lines = client.guilds.cache.map(g => `${g.name} (${g.id})`);
        let chunk = '';
        for (const line of lines) {
            if ((chunk + line + '\n').length > 1900) { await message.channel.send({ content: chunk }); chunk = ''; }
            chunk += line + '\n';
        }
        if (chunk) await message.channel.send({ content: `**Servers I'm in:**\n${chunk}` });
    }},
    { name: 'discord', category: 'Bot', description: 'Get the support discord link.', permissions: [], execute: async (message) => message.reply({ embeds: [createEmbed("To buy this bot, contact the developer specified in the bot's profile.")] }) },
    { name: 'join', category: 'Bot', description: 'Make the bot join your VC (owner only).', permissions: [], execute: async (message) => {
        if (message.author.id !== config.owner_id) return;
        const vc = message.member.voice.channel;
        if (!vc) return message.reply({ embeds: [createEmbed("You need to be in a VC.")] });
        try {
            require('@discordjs/voice').joinVoiceChannel({ channelId: vc.id, guildId: vc.guild.id, adapterCreator: vc.guild.voiceAdapterCreator });
            message.reply({ embeds: [createEmbed("Joined your voice channel.")] });
        } catch (e) {
            console.error(e);
            message.reply({ embeds: [createEmbed("I couldn't join the voice channel (voice dependencies may be missing).")] });
        }
    }},
    { name: 'leave', category: 'Bot', description: 'Make the bot leave a server (owner only).', permissions: [], execute: async (message, args) => {
        if (message.author.id !== config.owner_id) return;
        const guildId = args[0] || message.guild.id;
        const guild = client.guilds.cache.get(guildId);
        if (!guild) return message.reply({ embeds: [createEmbed("I'm not in that server.")] });
        await guild.leave();
        message.reply({ embeds: [createEmbed(`Successfully left ${guild.name}.`)] });
    }},
    { name: 'patch-note', category: 'Bot', description: 'See the latest patch notes.', permissions: [], execute: async (message) => message.reply({ embeds: [new EmbedBuilder().setColor('#000001').setTitle('📝 Patch Notes - V3').setDescription("• Fully working anti-nuke suite (anti-bot, anti-ban, anti-kick, anti-raid, anti-link, anti-spam, anti-mass-mention, and more).\n• Whitelist system for trusted staff.\n• Warning/infraction system, temp-bans and global bans.\n• Working logs, captcha verification and configurable welcome messages.\n• `scan-membre` to re-apply the member role to everyone.")] }) },
    { name: 'ping', category: 'Bot', description: "Check the bot's latency.", permissions: [], execute: async (message) => {
        const msg = await message.channel.send({ embeds: [createEmbed("Pinging...")] });
        msg.edit({ embeds: [createEmbed(`Pong! Latency is ${msg.createdTimestamp - message.createdTimestamp}ms. API Latency is ${Math.round(client.ws.ping)}ms`)] });
    }},
    { name: 'set-bio', category: 'Bot', description: "Change the bot's status text (owner only).", permissions: [], execute: async (message, args) => {
        if (message.author.id !== config.owner_id) return;
        const bio = args.join(" ");
        await client.user.setActivity(bio, { type: ActivityType.Playing });
        message.reply({ embeds: [createEmbed("My status has been updated.")] });
    }},
    { name: 'setprefix', category: 'Bot', description: "Change the bot's prefix for this server.", permissions: [PermissionsBitField.Flags.Administrator], execute: async (message, args) => {
        const newPrefix = args[0];
        if (!newPrefix) return message.reply({ embeds: [createEmbed("You must provide a new prefix.")] });
        await db.set(`prefix_${message.guild.id}`, newPrefix);
        message.reply({ embeds: [createEmbed(`The prefix for this server is now \`${newPrefix}\`.`)] });
    }},
    { name: 'help', category: 'Bot', description: 'Shows this paginated help menu.', permissions: [], execute: async (message) => {
        const categories = [...new Set(commands.filter(c => c.category).map(c => c.category))];
        let currentPage = 0;
        const prefix = await getPrefix(message.guild.id);

        const generateHelpEmbed = (page) => {
            const category = categories[page];
            const commandsInCategory = commands.filter(c => c.category === category);
            const description = commandsInCategory.map(c => `\`${prefix}${c.name}\`\n${c.description}`).join('\n\n');
            return new EmbedBuilder().setColor('#000001').setTitle(`Help Menu - ${category}`).setDescription(description.substring(0, 4000)).setFooter({ text: `Page ${page + 1}/${categories.length}` });
        };

        const row = new ActionRowBuilder().addComponents(
            new ButtonBuilder().setCustomId('help_prev').setLabel('◀').setStyle(ButtonStyle.Secondary),
            new ButtonBuilder().setCustomId('help_next').setLabel('▶').setStyle(ButtonStyle.Secondary)
        );

        const helpMessage = await message.channel.send({ embeds: [generateHelpEmbed(0)], components: [row] });
        const collector = helpMessage.createMessageComponentCollector({ time: 120000 });

        collector.on('collect', async i => {
            if (i.user.id !== message.author.id) return i.reply({ content: 'Only the command user can interact with this menu.', ephemeral: true });
            if (i.customId === 'help_next') currentPage = (currentPage + 1) % categories.length;
            else if (i.customId === 'help_prev') currentPage = (currentPage - 1 + categories.length) % categories.length;
            await i.update({ embeds: [generateHelpEmbed(currentPage)], components: [row] });
        });
        collector.on('end', () => {
            row.components.forEach(c => c.setDisabled(true));
            helpMessage.edit({ components: [row] }).catch(() => {});
        });
    }}
];

// ---------------------------------------------------------------------------
//  Member scan (re-apply the "member" auto-role to everyone)
// ---------------------------------------------------------------------------
async function scanMembers(message) {
    const roleId = await db.get(`autorole_${message.guild.id}`);
    const role = message.mentions.roles.first() || (roleId ? message.guild.roles.cache.get(roleId) : null);
    if (!role) return message.reply({ embeds: [createEmbed("No member role set. Use `?setup-autorole @role` first, or run `?scan-membre @role`.")] });
    if (role.position >= message.guild.members.me.roles.highest.position) {
        return message.reply({ embeds: [createEmbed("That role is higher than my highest role, so I can't assign it. Move my role above it.")] });
    }

    const status = await message.channel.send({ embeds: [createEmbed(`🔎 Scanning members and applying the ${role} role... This may take a moment.`)] });
    await message.guild.members.fetch();
    let added = 0, failed = 0, skipped = 0;
    for (const member of message.guild.members.cache.values()) {
        if (member.user.bot) { skipped++; continue; }
        if (member.roles.cache.has(role.id)) { skipped++; continue; }
        try { await member.roles.add(role); added++; } catch (_) { failed++; }
    }
    status.edit({ embeds: [createEmbed(`✅ Scan complete.\n**Added:** ${added}\n**Already had it / bots:** ${skipped}\n**Failed:** ${failed}`)] });
    sendLog(message.guild, logEmbed('🔎 Member Scan', `**Role:** ${role}\n**Added:** ${added} • **Skipped:** ${skipped} • **Failed:** ${failed}\n**By:** ${message.author.tag}`));
}

// ---------------------------------------------------------------------------
//  Message-level security (anti-link / anti-mass-mention / anti-spam)
// ---------------------------------------------------------------------------
const spamTracker = new Map();
async function runMessageSecurity(message) {
    const member = message.member;
    if (!member) return false;
    const exempt = member.permissions.has(PermissionsBitField.Flags.ManageMessages) || await isWhitelisted(message.guild, member.id);
    if (exempt) return false;

    if (message.content && await isEnabled(message.guild.id, 'antilink')) {
        if (/(https?:\/\/|discord\.gg\/|discord\.com\/invite\/|www\.)/i.test(message.content)) {
            await message.delete().catch(() => {});
            message.channel.send({ embeds: [createEmbed(`${member}, links are not allowed here.`)] }).then(m => setTimeout(() => m.delete().catch(() => {}), 4000));
            return true;
        }
    }

    if (await isEnabled(message.guild.id, 'antimassmention')) {
        const count = message.mentions.users.size + message.mentions.roles.size;
        if (count >= 5) {
            await message.delete().catch(() => {});
            await member.timeout(10 * 60 * 1000, '[Anti-Mass Mention]').catch(() => {});
            sendLog(message.guild, logEmbed('🚫 Mass Mention Blocked', `**User:** ${member.user.tag}\n**Mentions:** ${count}`, '#ff5555'));
            return true;
        }
    }

    if (await isEnabled(message.guild.id, 'antispam')) {
        const now = Date.now();
        const key = `${message.guild.id}_${member.id}`;
        const arr = (spamTracker.get(key) || []).filter(t => now - t < 5000);
        arr.push(now);
        spamTracker.set(key, arr);
        if (arr.length >= 6) {
            spamTracker.set(key, []);
            await member.timeout(60 * 1000, '[Anti-Spam]').catch(() => {});
            message.channel.send({ embeds: [createEmbed(`${member} has been muted for spamming.`)] }).then(m => setTimeout(() => m.delete().catch(() => {}), 4000));
            sendLog(message.guild, logEmbed('🚫 Spam Blocked', `**User:** ${member.user.tag}`, '#ff5555'));
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
//  Background tasks
// ---------------------------------------------------------------------------
const updateActivity = () => {
    if (!client.user) return;
    const totalMembers = client.guilds.cache.reduce((acc, guild) => acc + guild.memberCount, 0);
    const activityName = `RoFinder V3 | ${totalMembers > 1 ? totalMembers - 1 : totalMembers} members`;
    client.user.setActivity(activityName, { type: ActivityType.Streaming, url: "https://www.twitch.tv/terracid" });
};

async function processTempbans() {
    const tempbans = (await db.get('tempbans')) || [];
    if (!tempbans.length) return;
    const now = Date.now();
    const remaining = [];
    for (const tb of tempbans) {
        if (tb.unbanAt <= now) {
            const guild = client.guilds.cache.get(tb.guildId);
            if (guild) await guild.bans.remove(tb.userId, 'Tempban expired').catch(() => {});
        } else {
            remaining.push(tb);
        }
    }
    if (remaining.length !== tempbans.length) await db.set('tempbans', remaining);
}

// ---------------------------------------------------------------------------
//  Events
// ---------------------------------------------------------------------------
client.once('clientReady', () => {
    console.log(`Logged in as ${client.user.tag}!`);
    commands.forEach(cmd => client.commands.set(cmd.name, cmd));
    console.log(`Loaded ${client.commands.size} commands.`);
    updateActivity();
    setInterval(updateActivity, 60000);
    processTempbans();
    setInterval(processTempbans, 30000);
});

client.on('messageCreate', async message => {
    if (message.author.bot || !message.guild) return;

    if (await runMessageSecurity(message)) return;

    const prefix = await getPrefix(message.guild.id);
    if (!message.content.startsWith(prefix)) return;
    const args = message.content.slice(prefix.length).trim().split(/ +/);
    const commandName = args.shift().toLowerCase();
    const command = client.commands.get(commandName);
    if (!command) return;
    if (command.permissions && command.permissions.length && !message.member.permissions.has(command.permissions)) {
        return message.reply({ embeds: [createEmbed("You don't have permission to use this command.")] });
    }
    try {
        await command.execute(message, args);
    } catch (error) {
        console.error(error);
        message.reply({ embeds: [createEmbed('There was an error trying to execute that command!')] }).catch(() => {});
    }
});

client.on('messageDelete', message => {
    if (message.author && !message.author.bot && message.content) {
        snipe.set(message.channel.id, { content: message.content, author: message.author, timestamp: message.createdTimestamp });
    }
});

const raidTracker = new Map();
client.on('guildMemberAdd', async member => {
    updateActivity();
    const guild = member.guild;

    // Global ban enforcement
    const gbans = (await db.get('gbans')) || [];
    if (gbans.includes(member.id)) {
        await member.ban({ reason: 'Global ban (gban)' }).catch(() => {});
        return;
    }

    // Anti-bot
    if (member.user.bot && await isEnabled(guild.id, 'antibot')) {
        const executor = await fetchExecutor(guild, AuditLogEvent.BotAdd, member.id);
        if (!(await isWhitelisted(guild, executor?.id))) {
            await member.ban({ reason: '[Anti-Nuke] Unauthorized bot add' }).catch(() => {});
            if (executor) await punish(guild, executor.id, 'Added an unauthorized bot');
            sendLog(guild, logEmbed('🤖 Unauthorized Bot Removed', `**Bot:** ${member.user.tag}\n**Added by:** ${executor ? executor.tag : 'Unknown'}`, '#ff5555'));
            return;
        }
    }

    // Anti-raid (join flood)
    if (await isEnabled(guild.id, 'antiraid')) {
        const now = Date.now();
        const arr = (raidTracker.get(guild.id) || []).filter(t => now - t < 10000);
        arr.push(now);
        raidTracker.set(guild.id, arr);
        if (arr.length >= 6) {
            await member.kick('[Anti-Raid] Raid detected').catch(() => {});
            sendLog(guild, logEmbed('🛡️ Anti-Raid', `Kicked ${member.user.tag} (join flood detected).`, '#ff5555'));
            return;
        }
    }

    // Welcome message
    const welcome = await db.get(`welcome_${guild.id}`);
    if (welcome?.channel) {
        const channel = guild.channels.cache.get(welcome.channel);
        if (channel && channel.isTextBased()) {
            const embed = new EmbedBuilder().setColor("#000001").setTitle(`Welcome to ${guild.name} 👋`).setDescription(formatWelcome(welcome.message, member)).setThumbnail(member.user.displayAvatarURL({ size: 512 })).setTimestamp();
            channel.send({ content: `<@${member.id}>`, embeds: [embed] }).catch(() => {});
        }
    }

    // Auto-role (member role)
    const autoRoleId = await db.get(`autorole_${guild.id}`);
    if (autoRoleId && !member.user.bot) {
        const role = guild.roles.cache.get(autoRoleId);
        if (role) member.roles.add(role).catch(() => {});
    }
});

client.on('guildMemberRemove', async member => {
    updateActivity();
    const guild = member.guild;
    const needKick = await isEnabled(guild.id, 'antikick');
    const needMass = await isEnabled(guild.id, 'antimasskick');
    if (!needKick && !needMass) return;
    const executor = await fetchExecutor(guild, AuditLogEvent.MemberKick, member.id);
    if (!executor) return; // member left on their own
    if (await isWhitelisted(guild, executor.id)) return;
    if (needKick) await punish(guild, executor.id, 'Kicked a member without authorization');
    if (needMass) {
        const count = trackAction(guild.id, executor.id, 'kick');
        if (count >= 3) await punish(guild, executor.id, 'Mass kick detected');
    }
    sendLog(guild, logEmbed('🛡️ Anti-Kick', `**Member kicked:** ${member.user.tag}\n**By:** ${executor.tag} (punished)`, '#ff5555'));
});

client.on('guildBanAdd', async ban => {
    const guild = ban.guild;
    const needBan = await isEnabled(guild.id, 'antiban');
    const needMass = await isEnabled(guild.id, 'antimassban');
    if (!needBan && !needMass) return;
    const executor = await fetchExecutor(guild, AuditLogEvent.MemberBanAdd, ban.user.id);
    if (!executor || await isWhitelisted(guild, executor.id)) return;
    if (needBan) {
        await guild.bans.remove(ban.user.id, '[Anti-Nuke] Unauthorized ban').catch(() => {});
        await punish(guild, executor.id, 'Banned a member without authorization');
    }
    if (needMass) {
        const count = trackAction(guild.id, executor.id, 'ban');
        if (count >= 3) await punish(guild, executor.id, 'Mass ban detected');
    }
    sendLog(guild, logEmbed('🛡️ Anti-Ban', `**Target:** ${ban.user.tag}\n**By:** ${executor.tag} (punished)`, '#ff5555'));
});

client.on('channelCreate', async channel => {
    if (!channel.guild) return;
    if (!await isEnabled(channel.guild.id, 'antichannel')) return;
    const executor = await fetchExecutor(channel.guild, AuditLogEvent.ChannelCreate, channel.id);
    if (await isWhitelisted(channel.guild, executor?.id)) return;
    await channel.delete('[Anti-Nuke] Unauthorized channel creation').catch(() => {});
    if (executor) await punish(channel.guild, executor.id, 'Created a channel without authorization');
    sendLog(channel.guild, logEmbed('🛡️ Anti-Channel', `Channel creation reverted. By: ${executor ? executor.tag : 'Unknown'}`, '#ff5555'));
});

client.on('channelDelete', async channel => {
    if (!channel.guild) return;
    if (!await isEnabled(channel.guild.id, 'antichannel')) return;
    const executor = await fetchExecutor(channel.guild, AuditLogEvent.ChannelDelete, channel.id);
    if (await isWhitelisted(channel.guild, executor?.id)) return;
    if (executor) await punish(channel.guild, executor.id, 'Deleted a channel without authorization');
    sendLog(channel.guild, logEmbed('🛡️ Anti-Channel', `Channel **${channel.name}** was deleted. By: ${executor ? executor.tag : 'Unknown'} (punished)`, '#ff5555'));
});

client.on('inviteCreate', async invite => {
    if (!invite.guild) return;
    if (!await isEnabled(invite.guild.id, 'anticreateinvite')) return;
    const inviterId = invite.inviterId || invite.inviter?.id;
    if (await isWhitelisted(invite.guild, inviterId)) return;
    await invite.delete('[Anti-Nuke] Unauthorized invite').catch(() => {});
    if (inviterId) await punish(invite.guild, inviterId, 'Created an invite without authorization');
    sendLog(invite.guild, logEmbed('🛡️ Anti-Invite', `Invite deleted. By: ${invite.inviter ? invite.inviter.tag : 'Unknown'}`, '#ff5555'));
});

client.on('guildUpdate', async (oldGuild, newGuild) => {
    if (!await isEnabled(newGuild.id, 'antiguildupdate')) return;
    const executor = await fetchExecutor(newGuild, AuditLogEvent.GuildUpdate);
    if (await isWhitelisted(newGuild, executor?.id)) return;
    if (oldGuild.name !== newGuild.name) await newGuild.setName(oldGuild.name, '[Anti-Nuke] Reverting server update').catch(() => {});
    if (executor) await punish(newGuild, executor.id, 'Modified the server without authorization');
    sendLog(newGuild, logEmbed('🛡️ Anti-Guild-Update', `Server update reverted. By: ${executor ? executor.tag : 'Unknown'}`, '#ff5555'));
});

client.on('presenceUpdate', async (oldPresence, newPresence) => {
    try {
        const guild = newPresence?.guild;
        if (!guild) return;
        const conf = await db.get(`statusrole_${guild.id}`);
        if (!conf) return;
        const member = newPresence.member;
        if (!member || member.user.bot) return;
        const role = guild.roles.cache.get(conf.role);
        if (!role) return;
        const custom = newPresence.activities?.find(a => a.type === ActivityType.Custom);
        const hasKeyword = !!custom?.state && custom.state.toLowerCase().includes(conf.keyword.toLowerCase());
        if (hasKeyword && !member.roles.cache.has(role.id)) await member.roles.add(role).catch(() => {});
        else if (!hasKeyword && member.roles.cache.has(role.id)) await member.roles.remove(role).catch(() => {});
    } catch (_) { /* ignore */ }
});

client.on('interactionCreate', async interaction => {
    if (!interaction.isButton()) return;

    if (interaction.customId === 'verify_captcha') {
        const conf = await db.get(`captcha_${interaction.guild.id}`);
        if (!conf) return interaction.reply({ content: 'The verification system is not configured.', ephemeral: true });
        const role = interaction.guild.roles.cache.get(conf.role);
        if (!role) return interaction.reply({ content: 'The verification role no longer exists.', ephemeral: true });
        if (interaction.member.roles.cache.has(role.id)) return interaction.reply({ content: 'You are already verified.', ephemeral: true });
        await interaction.member.roles.add(role).catch(() => {});
        return interaction.reply({ content: `✅ You have been verified and received the **${role.name}** role!`, ephemeral: true });
    }

    if (interaction.customId === 'create_ticket') {
        await interaction.deferReply({ ephemeral: true });
        const category = interaction.guild.channels.cache.find(c => c.name === "Tickets" && c.type === ChannelType.GuildCategory) || await interaction.guild.channels.create({ name: 'Tickets', type: ChannelType.GuildCategory });
        const supportRole = interaction.guild.roles.cache.find(r => r.name === "Support Team");
        const channel = await interaction.guild.channels.create({ name: `ticket-${interaction.user.username}`, type: ChannelType.GuildText, parent: category.id, permissionOverwrites: [{ id: interaction.guild.id, deny: [PermissionsBitField.Flags.ViewChannel] }, { id: interaction.user.id, allow: [PermissionsBitField.Flags.ViewChannel, PermissionsBitField.Flags.SendMessages] }, { id: client.user.id, allow: [PermissionsBitField.Flags.ViewChannel, PermissionsBitField.Flags.SendMessages] }, ...(supportRole ? [{ id: supportRole.id, allow: [PermissionsBitField.Flags.ViewChannel, PermissionsBitField.Flags.SendMessages] }] : [])] });
        const ticketEmbed = new EmbedBuilder().setTitle(`Ticket for ${interaction.user.username}`).setDescription("Please describe your issue, and a staff member will be with you shortly.").setColor("Green");
        const closeButton = new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId(`close_ticket_${channel.id}`).setLabel('Close Ticket').setStyle(ButtonStyle.Danger).setEmoji('🔒'));
        await channel.send({ content: `${interaction.user} ${supportRole ? supportRole.toString() : ''}`, embeds: [ticketEmbed], components: [closeButton] });
        await interaction.editReply({ content: `Your ticket has been created in ${channel}.` });
    } else if (interaction.customId.startsWith('close_ticket_')) {
        const channelId = interaction.customId.split('_')[2];
        const channel = interaction.guild.channels.cache.get(channelId);
        if (channel) {
            await interaction.reply({ content: 'Closing this ticket in 5 seconds...', ephemeral: true });
            setTimeout(() => channel.delete('Ticket closed.').catch(() => {}), 5000);
        }
    }
});

process.on('unhandledRejection', (reason) => console.error('Unhandled promise rejection:', reason));

client.login(config.token);
