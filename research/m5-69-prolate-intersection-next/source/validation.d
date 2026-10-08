module r69_prolate_intersection_next;

import geodesy;
import std.math : fabs;
import std.stdio : stderr, writefln;

extern(C) int r69_next(
    double a, double f,
    double lat, double lon,
    double aziX, double aziY,
    double* x, double* y, int* coincidence);

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private struct Case {
    string name;
    double f,lat,lon,aziX,aziY;
}

int main()
{
    enum double a=6_378_137.0;
    Case[] cases=[
        Case("mild_ordinary",-1.0/300.0,0,0,30,120),
        Case("mild_oblique",-1.0/300.0,12,-40,17,133),
        Case("mild_near_parallel",-1.0/300.0,-20,80,45,48),
        Case("mild_polar",-1.0/300.0,75,10,-20,100),
        Case("moderate_ordinary",-0.01,0,0,30,120),
        Case("moderate_oblique",-0.01,12,-40,17,133),
        Case("moderate_near_parallel",-0.01,-20,80,45,48),
        Case("moderate_polar",-0.01,75,10,-20,100)
    ];

    size_t failures;
    foreach(tc;cases)
    {
        const solver=Geodesic!double.fromEllipsoid(
            Ellipsoid!double.fromFlattening(a,tc.f));

        GeodesicNextIntersectionResult!double actual;
        if(!tryNextGeodesicIntersection(
            solver,gc(tc.lat,tc.lon),
            Angle!double.fromDegrees(tc.aziX),
            Angle!double.fromDegrees(tc.aziY),
            actual))
        {
            stderr.writefln("FAIL %s: D next rejected",tc.name);
            ++failures;
            continue;
        }

        double ox,oy; int oc;
        if(!r69_next(a,tc.f,tc.lat,tc.lon,tc.aziX,tc.aziY,&ox,&oy,&oc))
        {
            stderr.writefln("FAIL %s: oracle next rejected",tc.name);
            ++failures;
            continue;
        }

        int dc;
        final switch(actual.coincidence) {
            case GeodesicIntersectionCoincidence.distinct: dc=0; break;
            case GeodesicIntersectionCoincidence.parallel: dc=1; break;
            case GeodesicIntersectionCoincidence.antiparallel: dc=-1; break;
        }

        const double drank=fabs(actual.distanceOnFirst)+fabs(actual.distanceOnSecond);
        const double orank=fabs(ox)+fabs(oy);
        const bool samePoint=
            fabs(actual.distanceOnFirst-ox)<=2e-4
            && fabs(actual.distanceOnSecond-oy)<=2e-4;
        const bool sameRank=fabs(drank-orank)<=2e-4;

        if((!samePoint && !sameRank) || dc!=oc)
        {
            stderr.writefln(
                "FAIL %s dx=%.9f dy=%.9f drank=%.9f orank=%.9f dc=%s oc=%s",
                tc.name,
                actual.distanceOnFirst-ox,
                actual.distanceOnSecond-oy,
                drank,orank,dc,oc);
            ++failures;
            continue;
        }

        writefln(
            "PASS %-24s rank=%.6f oracle=%.6f c=%s representative=%s",
            tc.name,drank,orank,dc,samePoint ? "same" : "equidistant");
    }

    if(failures) {
        stderr.writefln("R69.4c PROLATE NEXT FAIL: %s/%s cases",failures,cases.length);
        return 1;
    }

    writefln("R69.4c PROLATE NEXT PASS: %s cases",cases.length);
    return 0;
}
