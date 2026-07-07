#include maps\mp\_utility;
#include common_scripts\utility;

init()
{
    level thread onPlayerConnect();
    level thread xlrAutoMessages();
}

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connecting", player );
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

    self iprintlnbold( "^5XLR EU^7" );
    self iprintln( "^5[XLR]^7 Welcome ^7" + self.name + "^7! Discord: ^5discord.gg/63FAj2ZMrN" );
    self iprintln( "^5[XLR]^7 Bienvenue ^7" + self.name + "^7 ! Discord : ^5discord.gg/63FAj2ZMrN" );
    self iprintln( "^5[XLR]^7 Report: ^7!report <player> <reason>" );
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
