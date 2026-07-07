#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    level.callbackPlayerSay = ::xlr_on_player_say;
    level thread onPlayerConnect();
    level thread xlrAutoMessages();
    xlr_log( "init OK - owner cmds + welcome active" );
}

xlr_log( msg )
{
    println( "[XLR] " + msg );
}

xlr_cache_player_lang()
{
    self endon( "disconnect" );

    wait 0.1;

    self.xlrLangCode = 0;
    self.xlrLangIsFrench = false;
    xlr_log( "lang " + self.name + "=0 (EN default)" );
}

xlr_player_prefers_french( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) )
        return false;

    if ( isDefined( player.xlrLangIsFrench ) )
        return player.xlrLangIsFrench;

    return false;
}

xlr_tell_player( player, msg_en, msg_fr )
{
    if ( xlr_player_prefers_french( player ) )
        player iprintln( msg_fr );
    else
        player iprintln( msg_en );
}

xlr_tell_player_bold( player, msg_en, msg_fr )
{
    if ( xlr_player_prefers_french( player ) )
        player iprintlnbold( msg_fr );
    else
        player iprintlnbold( msg_en );
}

xlr_broadcast_line( msg_en, msg_fr )
{
    foreach ( player in level.players )
    {
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        xlr_tell_player( player, msg_en, msg_fr );
    }
}

xlr_broadcast_line_bold( msg_en, msg_fr )
{
    foreach ( player in level.players )
    {
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        xlr_tell_player_bold( player, msg_en, msg_fr );
    }
}

xlr_is_owner( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) )
        return false;

    name = toLower( player.name );
    owner_name = toLower( "PLACEHOLDER_OWNER_NAME" );

    if ( owner_name != "" && isSubStr( name, owner_name ) )
        return true;

    if ( isDefined( player.userid ) && player.userid == PLACEHOLDER_OWNER_ID )
        return true;

    return false;
}

xlr_find_player( needle )
{
    if ( !isDefined( needle ) || needle == "" )
        return undefined;

    needle = toLower( needle );

    foreach ( player in level.players )
    {
        if ( !isDefined( player ) )
            continue;

        if ( isSubStr( toLower( player.name ), needle ) )
            return player;
    }

    return undefined;
}

xlr_on_player_say( message, team )
{
    if ( !isDefined( self ) || !isPlayer( self ) )
        return;

    msg = toLower( message );

    if ( xlr_is_owner( self ) )
    {
        if ( msg[0] == "!" || msg[0] == "/" )
        {
            xlr_log( "owner cmd attempt: " + self.name + " -> " + message );
            if ( xlr_try_owner_command( message, msg ) )
                return false;

            return;
        }

        xlr_log( "owner chat restyle: " + self.name + " team=" + team );
        self thread xlr_owner_say_styled( message, team );
        return false;
    }

    return;
}

xlr_owner_say_styled( message, team_mode )
{
    tag = "^6PLACEHOLDER_OWNER_CHAT_TAG^7";
    name_color = "^PLACEHOLDER_OWNER_NAME_COLOR";
    text_color = "^PLACEHOLDER_OWNER_TEXT_COLOR";
    styled = tag + " " + name_color + self.name + "^7: " + text_color + message + "^7";

    foreach ( player in level.players )
    {
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        if ( isDefined( team_mode ) && team_mode == 1 && player.team != self.team )
            continue;

        player iprintln( styled );
    }

    xlr_log( "owner chat styled (iprintln): " + self.name );
}

xlr_try_owner_command( message, msg )
{
    if ( msg == "!ownercmds" || msg == "!help" )
    {
        xlr_log( "cmd help from " + self.name );
        self xlr_owner_help();
        return true;
    }

    if ( msg == "!shake" || msg == "!earthquake" )
    {
        xlr_log( "cmd shake from " + self.name );
        level thread xlr_cmd_shake();
        return true;
    }

    if ( msg == "!boo" )
    {
        xlr_log( "cmd boo from " + self.name );
        level thread xlr_cmd_boo();
        return true;
    }

    if ( msg == "!god" )
    {
        xlr_log( "cmd god from " + self.name );
        self thread xlr_cmd_god();
        return true;
    }

    if ( msg == "!lowgrav" )
    {
        xlr_log( "cmd lowgrav from " + self.name );
        level thread xlr_cmd_lowgrav();
        return true;
    }

    if ( msg == "!slap me" )
    {
        xlr_log( "cmd slap me from " + self.name );
        self thread xlr_cmd_slap( self );
        return true;
    }

    if ( isSubStr( msg, "!slap " ) )
    {
        target_name = getSubStr( message, 6, message.size );
        target = xlr_find_player( target_name );
        if ( !isDefined( target ) )
        {
            self iprintlnbold( "^1No player found." );
            xlr_log( "cmd slap miss target=" + target_name + " by " + self.name );
            return true;
        }
        xlr_log( "cmd slap " + target.name + " from " + self.name );
        target thread xlr_cmd_slap( target );
        return true;
    }

    if ( isSubStr( msg, "!fakeban " ) )
    {
        target_name = getSubStr( message, 9, message.size );
        target = xlr_find_player( target_name );
        if ( !isDefined( target ) )
        {
            self iprintlnbold( "^1No player found." );
            xlr_log( "cmd fakeban miss target=" + target_name + " by " + self.name );
            return true;
        }
        xlr_log( "cmd fakeban " + target.name + " from " + self.name );
        foreach ( player in level.players )
            xlr_tell_player( player, "^1" + target.name + " ^7was banned by admin.", "^1" + target.name + " ^7a ete banni par l'admin." );
        return true;
    }

    if ( isSubStr( msg, "!yeet " ) )
    {
        target_name = getSubStr( message, 6, message.size );
        target = xlr_find_player( target_name );
        if ( !isDefined( target ) )
        {
            self iprintlnbold( "^1No player found." );
            xlr_log( "cmd yeet miss target=" + target_name + " by " + self.name );
            return true;
        }
        xlr_log( "cmd yeet " + target.name + " from " + self.name );
        target thread xlr_cmd_yeet();
        return true;
    }

    if ( msg == "!yeet me" )
    {
        xlr_log( "cmd yeet me from " + self.name );
        self thread xlr_cmd_yeet();
        return true;
    }

    return false;
}

xlr_owner_help()
{
    self iprintlnbold( "^5[XLR OWNER]^7 Commands" );
    self iprintln( "^7!shake ^5!boo ^7!god ^5!lowgrav" );
    self iprintln( "^7!slap <player> ^5!yeet <player> ^7!fakeban <player>" );
}

xlr_cmd_shake()
{
    Earthquake( 0.7, 4, 0, 2 );
    xlr_broadcast_line_bold( "^5[XLR]^7 The ground is shaking...", "^5[XLR]^7 Le sol tremble..." );
    xlr_log( "shake executed" );
}

xlr_cmd_boo()
{
    foreach ( player in level.players )
    {
        player iprintlnbold( "^1BOO!" );
        player playSound( "evt_alarm" );
    }
    xlr_log( "boo executed" );
}

xlr_cmd_god()
{
    self endon( "disconnect" );

    if ( isDefined( self.xlrGod ) && self.xlrGod )
    {
        self.xlrGod = false;
        self iprintlnbold( "^5[XLR]^7 God mode ^1OFF" );
        xlr_log( "god OFF " + self.name );
        return;
    }

    self.xlrGod = true;
    self iprintlnbold( "^5[XLR]^7 God mode ^2ON" );
    xlr_log( "god ON " + self.name );

    while ( isDefined( self.xlrGod ) && self.xlrGod )
    {
        self.health = self.maxhealth;
        wait 0.25;
    }
}

xlr_cmd_lowgrav()
{
    level.lowGravity = true;
    setDvar( "g_gravity", 100 );
    xlr_broadcast_line_bold( "^5[XLR]^7 Low gravity for 30 seconds!", "^5[XLR]^7 Gravite basse pendant 30 secondes !" );
    xlr_log( "lowgrav start" );
    wait 30;
    setDvar( "g_gravity", 800 );
    level.lowGravity = false;
    xlr_log( "lowgrav end" );
}

xlr_cmd_slap( player )
{
    player endon( "disconnect" );

    if ( !isDefined( player ) )
        return;

    player iprintlnbold( "^5[XLR]^7 Slapped!" );
    Earthquake( 0.4, 1, player.origin, 1 );
    if ( player.health > 25 )
        player.health = player.health - 15;
    xlr_log( "slap " + player.name );
}

xlr_cmd_yeet()
{
    self endon( "disconnect" );

    self iprintlnbold( "^5[XLR]^7 YEET!" );
    Earthquake( 0.3, 1, self.origin, 1 );
    if ( self.health > 5 )
        self.health = self.health - 5;
    xlr_log( "yeet " + self.name );
}

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connecting", player );
        xlr_log( "connecting: " + player.name );
        player thread xlr_cache_player_lang();
        player thread onPlayerSpawned();
        player thread xlr_owner_disconnect_watch();
    }
}

xlr_owner_disconnect_watch()
{
    self endon( "disconnect" );

    if ( !xlr_is_owner( self ) )
        return;

    self waittill( "disconnect" );
    level.xlrOwnerAnnounced = undefined;
    xlr_log( "owner disconnected: " + self.name );
}

onPlayerSpawned()
{
    self endon( "disconnect" );

    if ( isDefined( self.xlrWelcomed ) )
        return;

    self waittill( "spawned_player" );
    self.xlrWelcomed = true;

    wait 0.15;

    if ( xlr_is_owner( self ) )
        xlr_log( "spawned: " + self.name + " (owner)" );
    else
        xlr_log( "spawned: " + self.name );

    self iprintlnbold( "^6XLR EU^7" );

    if ( xlr_player_prefers_french( self ) )
    {
        self iprintln( "^6[XLR]^7 Bienvenue ^7" + self.name + "^7 ! Discord : ^6discord.gg/63FAj2ZMrN" );
        self iprintln( "^6[XLR]^7 Report : ^7!report <joueur> <raison>" );
    }
    else
    {
        self iprintln( "^6[XLR]^7 Welcome ^7" + self.name + "^7! Discord: ^6discord.gg/63FAj2ZMrN" );
        self iprintln( "^6[XLR]^7 Report: ^7!report <player> <reason>" );
    }

    if ( xlr_is_owner( self ) && !isDefined( level.xlrOwnerAnnounced ) )
    {
        level.xlrOwnerAnnounced = true;
        xlr_log( "owner announce broadcast: " + self.name );
        foreach ( player in level.players )
        {
            xlr_tell_player_bold(
                player,
                "^6[XLR OWNER]^7 The owner ^7" + self.name + " ^7joined!",
                "^6[OWNER]^7 Le owner ^7" + self.name + " ^7a rejoint le serveur !"
            );
        }
    }
}

xlrAutoMessages()
{
    level endon( "game_ended" );

    for ( ;; )
    {
        wait 300;
        xlr_broadcast_line_bold(
            "^6[XLR]^7 discord.gg/63FAj2ZMrN",
            "^6[XLR]^7 discord.gg/63FAj2ZMrN"
        );
        xlr_broadcast_line(
            "^6[XLR]^7 Report cheaters: !report <player> <reason>",
            "^6[XLR]^7 Signale les tricheurs : !report <joueur> <raison>"
        );
        xlr_log( "auto message broadcast" );
    }
}
