#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    level thread onPlayerConnect();
    level thread xlrAutoMessages();
    xlr_log( "init OK welcome" );
}

xlr_log( msg )
{
    println( "[XLR] " + msg );
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

xlr_announce_owner_join( owner )
{
    if ( !isDefined( owner ) || !isPlayer( owner ) )
        return;
    if ( isDefined( level.xlrOwnerAnnounced ) )
        return;
    level.xlrOwnerAnnounced = true;
    xlr_log( "owner announce: " + owner.name );
    foreach ( player in level.players )
    {
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;
        player iprintlnbold( "^6[XLR OWNER]^7 The owner ^7" + owner.name + " ^7joined the server!" );
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

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connecting", player );
        xlr_log( "connecting: " + player.name );
        player thread onPlayerSpawned();
        player thread xlr_owner_disconnect_watch();
    }
}

onPlayerSpawned()
{
    self endon( "disconnect" );
    if ( isDefined( self.xlrWelcomed ) )
        return;
    self waittill( "spawned_player" );
    self.xlrWelcomed = true;
    wait 0.15;
    xlr_log( "spawned: " + self.name );
    self iprintlnbold( "^6XLR EU^7" );
    self iprintln( "^6[XLR]^7 Welcome ^7" + self.name + "^7! Discord: ^6discord.gg/63FAj2ZMrN" );
    self iprintln( "^6[XLR]^7 Report: ^7!report <player> <reason>" );
    if ( xlr_is_owner( self ) )
        xlr_announce_owner_join( self );
}

xlrAutoMessages()
{
    level endon( "game_ended" );
    for ( ;; )
    {
        wait 300;
        iprintlnbold( "^6[XLR]^7 discord.gg/63FAj2ZMrN" );
        iprintln( "^6[XLR]^7 Report cheaters: !report <player> <reason>" );
        xlr_log( "auto message broadcast" );
    }
}
