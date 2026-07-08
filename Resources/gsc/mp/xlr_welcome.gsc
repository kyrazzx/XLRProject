#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    level thread onPlayerConnect();
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
        player thread xlrPlayerTipLoop();
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
    self iprintlnbold( "^6XLR Project - discord.gg/63FAj2ZMrN^7" );
    self iprintln( "^6[XLR]^7 Welcome ^7" + self.name + "^7! Discord: ^6discord.gg/63FAj2ZMrN" );
    self iprintln( "^6[XLR]^7 Report: ^7!report <player> <reason>" );
    if ( xlr_is_owner( self ) )
        xlr_announce_owner_join( self );
}

xlrTipInterval()
{
    interval = getDvarInt( "xlr_tip_interval" );
    if ( interval < 5 )
        interval = 5;
    if ( interval > 3600 )
        interval = 3600;
    return interval;
}

xlrPlayerTipLoop()
{
    self endon( "disconnect" );
    self.xlrTipIndex = 0;
    self.xlrLastForceTip = 0;
    self.xlrTipTimer = 0;
    for ( ;; )
    {
        wait 1;
        token = getDvarInt( "xlr_force_tip" );
        if ( token > 0 && token != self.xlrLastForceTip )
        {
            self.xlrLastForceTip = token;
            xlr_log( "force tip " + self.name + " token " + token );
            self thread xlrSendPlayerTip( self.xlrTipIndex );
            self.xlrTipIndex++;
            if ( self.xlrTipIndex >= 6 )
                self.xlrTipIndex = 0;
            self.xlrTipTimer = 0;
            continue;
        }
        self.xlrTipTimer = self.xlrTipTimer + 1;
        if ( self.xlrTipTimer < xlrTipInterval() )
            continue;
        self.xlrTipTimer = 0;
        xlr_log( "auto tip " + self.name + " index " + self.xlrTipIndex );
        self thread xlrSendPlayerTip( self.xlrTipIndex );
        self.xlrTipIndex++;
        if ( self.xlrTipIndex >= 6 )
            self.xlrTipIndex = 0;
    }
}

xlrSendPlayerTip( tipIndex )
{
    self endon( "disconnect" );
    switch ( tipIndex )
    {
        case 0:
            self iprintln( "^6[XLR]^7 Report cheaters: !report <player> <reason>" );
            break;
        case 1:
            self iprintln( "^6[XLR]^7 Join our Discord: discord.gg/63FAj2ZMrN" );
            break;
        case 2:
            self iprintln( "^6[XLR]^7 Respect other players - enjoy the match!" );
            break;
        case 3:
            self iprintln( "^6[XLR]^7 Need help? Open a ticket on our Discord." );
            break;
        case 4:
            self iprintln( "^6[XLR]^7 Make BO2 great again! Play fair and have fun!" );
            break;
        default:
            count = getDvarInt( "xlr_unique_players" );
            if ( count > 0 )
                self iprintln( "^6[XLR]^7 Unique players since launch: ^6" + count );
            else
                self iprintln( "^6[XLR]^7 Thanks for playing on XLR EU!" );
            break;
    }
}
