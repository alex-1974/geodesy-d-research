module m5_103_intersection_benchmark;

import geodesy;

import core.time : MonoTime;
import std.stdio : writefln;

private struct Case
{
    double a1lat,a1lon,a2lat,a2lon;
    double b1lat,b1lon,b2lat,b2lon;
}

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

void main()
{
    const solver =
        Geodesic!double.fromEllipsoid(
            wgs84!double());

    enum size_t caseCount = 8;

    Case[caseCount] cases = [
        Case(0,-10,0,10,-10,0,10,0),
        Case(0,-10,0,0,0,0,10,0),
        Case(0,-10,0,-5,10,5,10,10),
        Case(0,-10,0,10,0,-5,0,15),
        Case(0,-10,0,10,0,15,0,-5),
        Case(0,170,0,-170,-10,180,10,180),
        Case(35,-20,55,30,50,-15,30,25),
        Case(84,-60,84,60,82,0,89,0)
    ];

    GeographicCoordinate!double[caseCount] a0;
    GeographicCoordinate!double[caseCount] a1;
    GeographicCoordinate!double[caseCount] b0;
    GeographicCoordinate!double[caseCount] b1;

    foreach (i,item;cases)
    {
        a0[i]=gc(item.a1lat,item.a1lon);
        a1[i]=gc(item.a2lat,item.a2lon);
        b0[i]=gc(item.b1lat,item.b1lon);
        b1[i]=gc(item.b2lat,item.b2lon);
    }

    enum size_t warmups = 8;
    enum size_t rounds = 128;

    double checksum=0;

    foreach (_;0..warmups)
    {
        foreach(i;0..caseCount)
        {
            GeodesicSegmentIntersectionResult!double r;
            if(!tryIntersectGeodesicSegments(
                solver,a0[i],a1[i],b0[i],b1[i],r))
                assert(0);
            checksum += cast(int)r.kind;
            if(r.kind==GeodesicSegmentIntersectionKind.point ||
               r.kind==GeodesicSegmentIntersectionKind.overlap)
                checksum += r.firstPoint.latitude.radians*1e-3;
        }
    }

    const start=MonoTime.currTime;

    foreach (_;0..rounds)
    {
        foreach(i;0..caseCount)
        {
            GeodesicSegmentIntersectionResult!double r;
            if(!tryIntersectGeodesicSegments(
                solver,a0[i],a1[i],b0[i],b1[i],r))
                assert(0);
            checksum += cast(int)r.kind;
            if(r.kind==GeodesicSegmentIntersectionKind.point ||
               r.kind==GeodesicSegmentIntersectionKind.overlap)
                checksum += r.firstPoint.latitude.radians*1e-3;
        }
    }

    const elapsed=MonoTime.currTime-start;
    enum size_t operations=rounds*caseCount;

    writefln("implementation=geodesy-d");
    writefln("operations=%s",operations);
    writefln("ns_per_op=%.6f",
        cast(double)elapsed.total!"nsecs"/cast(double)operations);
    writefln("checksum=%.12f",checksum);
}
