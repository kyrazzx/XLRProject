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

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connecting", player );
        xlr_log( "connecting: " + player.name );
        player thread onPlayerSpawned();
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
