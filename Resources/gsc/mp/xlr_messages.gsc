#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    level.callbackPlayerSay = ::xlr_on_player_say;
    level thread onPlayerConnect();
    level thread xlrAutoMessages();
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
            if ( xlr_try_owner_command( message, msg ) )
                return false;

            return;
        }

        self thread xlr_owner_say_styled( message, team );
        return false;
    }

    return;
}

xlr_owner_say_styled( message, team_mode )
{
    tag = "^5PLACEHOLDER_OWNER_CHAT_TAG^7";
    name_color = "^PLACEHOLDER_OWNER_NAME_COLOR";
    text_color = "^PLACEHOLDER_OWNER_TEXT_COLOR";
    styled = tag + " " + name_color + self.name + "^7: " + text_color + message + "^7";

    if ( isDefined( team_mode ) && team_mode == 1 )
    {
        foreach ( player in level.players )
        {
            if ( !isDefined( player ) || !isPlayer( player ) )
                continue;

            if ( player.team == self.team )
                player tell( styled );
        }

        return;
    }

    say( styled );
}

xlr_try_owner_command( message, msg )
{
    if ( msg == "!ownercmds" || msg == "!help" )
    {
        self xlr_owner_help();
        return true;
    }

    if ( msg == "!shake" || msg == "!earthquake" )
    {
        level thread xlr_cmd_shake();
        return true;
    }

    if ( msg == "!boo" )
    {
        level thread xlr_cmd_boo();
        return true;
    }

    if ( msg == "!god" )
    {
        self thread xlr_cmd_god();
        return true;
    }

    if ( msg == "!lowgrav" )
    {
        level thread xlr_cmd_lowgrav();
        return true;
    }

    if ( msg == "!slap me" )
    {
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
            return true;
        }
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
            return true;
        }
        foreach ( player in level.players )
            player iprintln( "^1" + target.name + " ^7was banned by admin." );
        return true;
    }

    if ( isSubStr( msg, "!yeet " ) )
    {
        target_name = getSubStr( message, 6, message.size );
        target = xlr_find_player( target_name );
        if ( !isDefined( target ) )
        {
            self iprintlnbold( "^1No player found." );
            return true;
        }
        target thread xlr_cmd_yeet();
        return true;
    }

    if ( msg == "!yeet me" )
    {
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
    foreach ( player in level.players )
        player iprintlnbold( "^5[XLR]^7 The ground is shaking..." );
}

xlr_cmd_boo()
{
    foreach ( player in level.players )
    {
        player iprintlnbold( "^1BOO!" );
        player playSound( "evt_alarm" );
    }
}

xlr_cmd_god()
{
    self endon( "disconnect" );

    if ( isDefined( self.xlrGod ) && self.xlrGod )
    {
        self.xlrGod = false;
        self iprintlnbold( "^5[XLR]^7 God mode ^1OFF" );
        return;
    }

    self.xlrGod = true;
    self iprintlnbold( "^5[XLR]^7 God mode ^2ON" );

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
    foreach ( player in level.players )
        player iprintlnbold( "^5[XLR]^7 Low gravity for 30 seconds!" );
    wait 30;
    setDvar( "g_gravity", 800 );
    level.lowGravity = false;
}

xlr_cmd_slap( player )
{
    player endon( "disconnect" );

    if ( !isDefined( player ) )
        return;

    player iprintlnbold( "^5[XLR]^7 Slapped!" );
    player Earthquake( 0.4, 1, player.origin, 1 );
    player.damageShellShock( 20, 0.5 );
    if ( player.health > 25 )
        player.health = player.health - 15;
}

xlr_cmd_yeet()
{
    self endon( "disconnect" );

    self iprintlnbold( "^5[XLR]^7 YEET!" );
    self.damageShellShock( 30, 0.8 );
    self.health = self.health - 5;
}

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connecting", player );
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
}

onPlayerSpawned()
{
    self endon( "disconnect" );

    if ( isDefined( self.xlrWelcomed ) )
        return;

    self waittill( "spawned_player" );
    self.xlrWelcomed = true;

    self iprintlnbold( "^5XLR EU^7" );
    self iprintln( "^5[XLR]^7 Welcome ^7" + self.name + "^7! Discord: ^5discord.gg/63FAj2ZMrN" );
    self iprintln( "^5[XLR]^7 Bienvenue ^7" + self.name + "^7 ! Discord : ^5discord.gg/63FAj2ZMrN" );
    self iprintln( "^5[XLR]^7 Report: ^7!report <player> <reason>" );

    if ( xlr_is_owner( self ) && !isDefined( level.xlrOwnerAnnounced ) )
    {
        level.xlrOwnerAnnounced = true;
        foreach ( player in level.players )
        {
            player iprintlnbold( "^5[XLR OWNER]^7 The owner ^7" + self.name + " ^7joined!" );
            player iprintln( "^5[OWNER]^7 Le owner ^7" + self.name + " ^7a rejoint le serveur !" );
        }
    }
}

xlrAutoMessages()
{
    level endon( "game_ended" );

    for ( ;; )
    {
        wait 300;
        iprintlnbold( "^5[XLR]^7 discord.gg/63FAj2ZMrN" );
        iprintlnbold( "^5[XLR]^7 Report cheaters: !report <player> <reason>" );
    }
}
