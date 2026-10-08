module r69_prolate_intersection_all;

import geodesy;
import std.math : fabs;
import std.stdio : stderr, writefln;

extern(C) size_t r69_all(
    double a,double f,
    double latX,double lonX,double aziX,
    double latY,double lonY,double aziY,
    double maxdist,double x0,double y0,
    double* xs,double* ys,int* cs,
    size_t capacity);

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private struct Case
{
    string name;
    double f;
    double latX,lonX,aziX;
    double latY,lonY,aziY;
    double radius,x0,y0;
}

private int coincidenceCode(
    GeodesicIntersectionCoincidence value)
{
    final switch(value) {
        case GeodesicIntersectionCoincidence.distinct: return 0;
        case GeodesicIntersectionCoincidence.parallel: return 1;
        case GeodesicIntersectionCoincidence.antiparallel: return -1;
    }
}

int main()
{
    enum double a=6_378_137.0;

    Case[] cases=[
        Case("mild_ordinary_20m",-1.0/300.0,
            0,-20,45, 10,20,-60, 20_000_000,0,0),
        Case("mild_ordinary_40m",-1.0/300.0,
            0,-20,45, 10,20,-60, 40_000_000,0,0),
        Case("mild_near_parallel",-1.0/300.0,
            10,20,45, 11,21,45.1, 40_000_000,0,0),
        Case("mild_offset",-1.0/300.0,
            -25,70,-40, 30,-100,125, 40_000_000,-5_000_000,3_000_000),

        Case("moderate_ordinary_20m",-0.01,
            0,-20,45, 10,20,-60, 20_000_000,0,0),
        Case("moderate_ordinary_40m",-0.01,
            0,-20,45, 10,20,-60, 40_000_000,0,0),
        Case("moderate_near_parallel",-0.01,
            10,20,45, 11,21,45.1, 40_000_000,0,0),
        Case("moderate_offset",-0.01,
            -25,70,-40, 30,-100,125, 40_000_000,-5_000_000,3_000_000)
    ];

    enum size_t cap=256;

    GeodesicIntersectionWorkspaceEntry!double[256] starts;
    bool[256] skip;
    GeodesicIntersectionWorkspaceEntry!double[512] found;
    GeodesicIntersectionWorkspaceEntry!double[128] centers;
    GeodesicIntersectionPoint!double[cap] output;

    double[cap] ox;
    double[cap] oy;
    int[cap] oc;

    size_t failures;

    foreach(tc;cases)
    {
        const solver=Geodesic!double.fromEllipsoid(
            Ellipsoid!double.fromFlattening(a,tc.f));

        GeodesicIntersectionSolver!double intersector;
        if(!GeodesicIntersectionSolver!double.tryFromGeodesic(
            solver,intersector))
        {
            stderr.writefln("FAIL %s: prepared intersector rejected",tc.name);
            ++failures;
            continue;
        }

        GeodesicLine!double lineX;
        GeodesicLine!double lineY;

        if(!GeodesicLine!double.tryFromGeodesic(
                solver,gc(tc.latX,tc.lonX),
                Angle!double.fromDegrees(tc.aziX),lineX)
            || !GeodesicLine!double.tryFromGeodesic(
                solver,gc(tc.latY,tc.lonY),
                Angle!double.fromDegrees(tc.aziY),lineY))
        {
            stderr.writefln("FAIL %s: line preparation",tc.name);
            ++failures;
            continue;
        }

        GeodesicIntersectionWorkspace!double workspace;
        if(!GeodesicIntersectionWorkspace!double.tryFromStorage(
            starts[],skip[],found[],centers[],workspace))
        {
            stderr.writefln("FAIL workspace construction");
            return 2;
        }

        GeodesicIntersectionEnumeration enumeration;

        if(!tryAllGeodesicIntersections(
            intersector,lineX,lineY,
            tc.radius,tc.x0,tc.y0,
            output[],workspace,enumeration))
        {
            stderr.writefln(
                "FAIL %s: D All rejected status=%s tiles=%s found=%s",
                tc.name,enumeration.status,
                enumeration.requiredTiles,
                enumeration.minimumFoundCapacity);
            ++failures;
            continue;
        }

        const size_t oracleCount=r69_all(
            a,tc.f,
            tc.latX,tc.lonX,tc.aziX,
            tc.latY,tc.lonY,tc.aziY,
            tc.radius,tc.x0,tc.y0,
            ox.ptr,oy.ptr,oc.ptr,cap);

        if(oracleCount==0 || oracleCount!=enumeration.total)
        {
            stderr.writefln(
                "FAIL %s: count D=%s oracle=%s",
                tc.name,enumeration.total,oracleCount);
            ++failures;
            continue;
        }

        bool bad;
        foreach(i;0..oracleCount)
        {
            const double dx=fabs(output[i].distanceOnFirst-ox[i]);
            const double dy=fabs(output[i].distanceOnSecond-oy[i]);
            const int dc=coincidenceCode(output[i].coincidence);

            if(dx>2e-4 || dy>2e-4 || dc!=oc[i])
            {
                stderr.writefln(
                    "FAIL %s[%s] dx=%.9f dy=%.9f dc=%s oc=%s",
                    tc.name,i,dx,dy,dc,oc[i]);
                bad=true;
                break;
            }
        }

        if(bad) {
            ++failures;
            continue;
        }

        writefln(
            "PASS %-28s count=%s tiles=%s",
            tc.name,enumeration.total,enumeration.requiredTiles);
    }

    if(failures) {
        stderr.writefln(
            "R69.4d PROLATE ALL FAIL: %s/%s cases",
            failures,cases.length);
        return 1;
    }

    writefln("R69.4d PROLATE ALL PASS: %s cases",cases.length);
    return 0;
}
