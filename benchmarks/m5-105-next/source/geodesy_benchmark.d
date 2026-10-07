module m5_105_next_benchmark;

import geodesy;

import core.time : MonoTime;
import std.stdio : stderr, writefln;

private struct Case
{
    string name;
    double lat,lon,aziX,aziY;
}

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

int main()
{
    const solver =
        Geodesic!double.fromEllipsoid(
            wgs84!double());

    enum size_t count = 8;

    Case[count] cases = [
        Case("ordinary",0,0,30,120),
        Case("orthogonal",0,0,0,90),
        Case("near_parallel",10,20,45,45.1),
        Case("polar",82,-40,20,145),
        Case("reverse",-25,70,-35,140),
        Case("coincident_same",0,0,90,90),
        Case("coincident_reverse",0,0,90,-90),
        Case("almost_symmetric",0.0001,0,45,135)
    ];

    GeodesicLine!double[count] xlines;
    GeodesicLine!double[count] ylines;

    foreach (i,item; cases)
    {
        const origin = gc(item.lat,item.lon);

        xlines[i] =
            GeodesicLine!double.fromGeodesic(
                solver,
                origin,
                Angle!double.fromDegrees(item.aziX));

        ylines[i] =
            GeodesicLine!double.fromGeodesic(
                solver,
                origin,
                Angle!double.fromDegrees(item.aziY));
    }

    enum size_t warmups = 4;
    enum size_t rounds = 64;

    double checksum;

    foreach (_;0..warmups)
        foreach (i;0..count)
        {
            GeodesicNextIntersectionResult!double result;
            if (!tryNextGeodesicIntersection(
                    solver,
                    xlines[i],
                    ylines[i],
                    result))
            {
                stderr.writefln(
                    "ERROR: tryNextGeodesicIntersection failed for case %s",
                    cases[i].name);
                return 2;
            }

            checksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

    const start = MonoTime.currTime;

    foreach (_;0..rounds)
        foreach (i;0..count)
        {
            GeodesicNextIntersectionResult!double result;
            if (!tryNextGeodesicIntersection(
                    solver,
                    xlines[i],
                    ylines[i],
                    result))
            {
                stderr.writefln(
                    "ERROR: tryNextGeodesicIntersection failed for case %s",
                    cases[i].name);
                return 2;
            }

            checksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

    const elapsed = MonoTime.currTime - start;

    enum size_t operations = rounds * count;

    writefln("implementation=geodesy-d");
    writefln("operations=%s",operations);
    writefln(
        "ns_per_op=%.6f",
        cast(double) elapsed.total!"nsecs"
            / cast(double) operations);
    writefln("checksum=%.12f",checksum);
    return 0;
}
