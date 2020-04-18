module gds.utility;

import std.datetime : Date;

Date currentDate()
{
    import std.conv : to;
    import std.datetime : Clock;

    return Clock.currTime.to!Date;
}
