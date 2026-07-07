#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    onPlayerSay( ::xlr_on_player_say );
    level thread xlr_chat_listener();
    xlr_log( "init OK owner cmds" );
}

xlr_log( msg )
{
    println( "[XLR] " + msg );
}

xlr_first_char( text )
{
    if ( !isDefined( text ) || text.size < 1 )
        return "";

    return getSubStr( text, 0, 1 );
}

xlr_player_id_str( player )
{
    if ( !isDefined( player ) || !isDefined( player.userid ) )
        return "na";

    return "" + player.userid;
}

xlr_clean_player_name( name )
{
    if ( !isDefined( name ) )
        return "";

    name = toLower( name );

    if ( isSubStr( name, "]" ) )
    {
        idx = 0;
        for ( i = 0; i < name.size; i++ )
        {
            if ( getSubStr( name, i, 1 ) == "]" )
                idx = i + 1;
        }

        if ( idx > 0 && idx < name.size )
            name = getSubStr( name, idx );
    }

    return name;
}

xlr_fix_say_message( message )
{
    if ( !isDefined( message ) || message.size < 1 )
        return message;

    first = xlr_first_char( message );
    if ( first != "!" && first != "/" )
        message = getSubStr( message, 1 );

    return message;
}

xlr_is_owner( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) )
        return false;

    clean_name = xlr_clean_player_name( player.name );
    owner_name = toLower( "PLACEHOLDER_OWNER_NAME" );
    owner_id = "" + PLACEHOLDER_OWNER_ID;
    uid = xlr_player_id_str( player );

    if ( owner_name != "" && clean_name == owner_name )
        return true;

    if ( owner_name != "" && isSubStr( clean_name, owner_name ) )
        return true;

    if ( uid == owner_id )
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
        return true;

    fixed = xlr_fix_say_message( message );
    msg = toLower( fixed );
    first = xlr_first_char( msg );

    if ( !xlr_is_owner( self ) )
        return true;

    xlr_log( "onPlayerSay owner raw=[" + message + "] fixed=[" + fixed + "] team=" + team );

    if ( first == "!" || first == "/" )
    {
        if ( xlr_try_owner_command( fixed, msg ) )
        {
            xlr_log( "onPlayerSay cmd OK: " + fixed );
            return false;
        }

        return true;
    }

    self thread xlr_owner_say_styled( fixed, team );
    return false;
}

xlr_chat_listener()
{
    level endon( "game_ended" );

    for ( ;; )
    {
        level waittill( "say", message, player );

        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        xlr_log( "waittill say: " + player.name + " msg=[" + message + "]" );
    }
}

xlr_owner_say_styled( message, team_mode )
{
    tag = "^6PLACEHOLDER_OWNER_CHAT_TAG^7";
    name_color = "^PLACEHOLDER_OWNER_NAME_COLOR";
    text_color = "^PLACEHOLDER_OWNER_TEXT_COLOR";
    styled = tag + " " + name_color + self.name + "^7: " + text_color + message + "^7";

    foreach ( p in level.players )
    {
        if ( !isDefined( p ) || !isPlayer( p ) )
            continue;

        if ( isDefined( team_mode ) && team_mode == 1 && p.team != self.team )
            continue;

        p iprintlnbold( styled );
    }

    xlr_log( "owner chat styled: " + self.name );
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
    iprintlnbold( "^5[XLR]^7 The ground is shaking..." );
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
    setDvar( "g_gravity", 100 );
    iprintlnbold( "^5[XLR]^7 Low gravity for 30 seconds!" );
    wait 30;
    setDvar( "g_gravity", 800 );
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
}

xlr_cmd_yeet()
{
    self endon( "disconnect" );

    self iprintlnbold( "^5[XLR]^7 YEET!" );
    Earthquake( 0.3, 1, self.origin, 1 );
    if ( self.health > 5 )
        self.health = self.health - 5;
}
