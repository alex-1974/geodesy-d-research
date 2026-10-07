module m5_104_closest_benchmark;

import geodesy;
import core.time : MonoTime;
import std.stdio : writefln;

private struct Case
{
    string name;
    double latX,lonX,aziX;
    double latY,lonY,aziY;
    double p0x,p0y;
}

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

void main()
{
    const solver = Geodesic!double.fromEllipsoid(wgs84!double());
    enum size_t count = 8;
    Case[count] cases = [
        Case("ordinary",0,-20,45,10,20,-60,0,0),
        Case("offset",0,-20,45,10,20,-60,2.5e6,-1.0e6),
        Case("antimeridian",15,175,80,-20,-175,10,0,0),
        Case("polar",80,-60,20,82,50,-80,0,0),
        Case("near_parallel",10,-30,85,10.1,-30,85.1,0,0),
        Case("coincident_same",0,0,90,0,10,90,1.0e6,-2.0e6),
        Case("large_offset",-20,-120,30,35,80,-110,1.5e7,-1.1e7),
        Case("reverse_y",0,-20,45,10,20,120,0,0)
    ];
    GeodesicLine!double[count] xlines;
    GeodesicLine!double[count] ylines;
    foreach(i,item;cases)
    {
        xlines[i] = GeodesicLine!double.fromGeodesic(
            solver,gc(item.latX,item.lonX),Angle!double.fromDegrees(item.aziX));
        ylines[i] = GeodesicLine!double.fromGeodesic(
            solver,gc(item.latY,item.lonY),Angle!double.fromDegrees(item.aziY));
    }
    enum size_t warmups=8;
    enum size_t rounds=128;
    double checksum;
    foreach(_;0..warmups)
        foreach(i;0..count)
        {
            GeodesicClosestIntersectionResult!double r;
            assert(tryClosestGeodesicIntersection(
                solver,xlines[i],ylines[i],cases[i].p0x,cases[i].p0y,r));
            checksum += r.distanceOnFirst*1e-12 + r.distanceOnSecond*1e-12;
        }
    const start=MonoTime.currTime;
    foreach(_;0..rounds)
        foreach(i;0..count)
        {
            GeodesicClosestIntersectionResult!double r;
            assert(tryClosestGeodesicIntersection(
                solver,xlines[i],ylines[i],cases[i].p0x,cases[i].p0y,r));
            checksum += r.distanceOnFirst*1e-12 + r.distanceOnSecond*1e-12;
        }
    const elapsed=MonoTime.currTime-start;
    enum size_t operations=rounds*count;
    writefln("implementation=geodesy-d");
    writefln("operations=%s",operations);
    writefln("ns_per_op=%.6f",cast(double)elapsed.total!"nsecs"/operations);
    writefln("checksum=%.12f",checksum);
}
