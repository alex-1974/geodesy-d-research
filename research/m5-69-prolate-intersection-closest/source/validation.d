module r69_prolate_intersection_closest;

import geodesy;
import std.math : fabs;
import std.stdio : stderr, writefln;

extern(C) int r69_closest(
    double a, double f,
    double latX, double lonX, double aziX,
    double latY, double lonY, double aziY,
    double x0, double y0,
    double* x, double* y, int* coincidence);

private GeographicCoordinate!double gc(double lat, double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private struct Case
{
    string name;
    double f;
    double latX, lonX, aziX;
    double latY, lonY, aziY;
    double x0, y0;
}

int main()
{
    enum double a = 6_378_137.0;

    Case[] cases = [
        Case("mild_ordinary_zero", -1.0/300.0,
            0,-20,45, 10,20,-60, 0,0),
        Case("mild_ordinary_offset", -1.0/300.0,
            0,-20,45, 10,20,-60, 8_000_000,-4_000_000),
        Case("mild_near_parallel", -1.0/300.0,
            10,20,45, 11,21,45.1, 0,0),
        Case("mild_polar", -1.0/300.0,
            80,-40,15, 75,120,-35, 0,0),
        Case("mild_reverse_reference", -1.0/300.0,
            -25,70,-40, 30,-100,125, -9_000_000,7_000_000),

        Case("moderate_ordinary_zero", -0.01,
            0,-20,45, 10,20,-60, 0,0),
        Case("moderate_ordinary_offset", -0.01,
            0,-20,45, 10,20,-60, 8_000_000,-4_000_000),
        Case("moderate_near_parallel", -0.01,
            10,20,45, 11,21,45.1, 0,0),
        Case("moderate_polar", -0.01,
            80,-40,15, 75,120,-35, 0,0),
        Case("moderate_reverse_reference", -0.01,
            -25,70,-40, 30,-100,125, -9_000_000,7_000_000)
    ];

    size_t failures;

    foreach (tc; cases)
    {
        const ellipsoid =
            Ellipsoid!double.fromFlattening(a, tc.f);
        const solver =
            Geodesic!double.fromEllipsoid(ellipsoid);

        GeodesicClosestIntersectionResult!double actual;

        if (!tryClosestGeodesicIntersection(
                solver,
                gc(tc.latX,tc.lonX),
                Angle!double.fromDegrees(tc.aziX),
                gc(tc.latY,tc.lonY),
                Angle!double.fromDegrees(tc.aziY),
                tc.x0,
                tc.y0,
                actual))
        {
            stderr.writefln("FAIL %s: D closest rejected", tc.name);
            ++failures;
            continue;
        }

        double ox, oy;
        int oc;

        if (!r69_closest(
                a,tc.f,
                tc.latX,tc.lonX,tc.aziX,
                tc.latY,tc.lonY,tc.aziY,
                tc.x0,tc.y0,
                &ox,&oy,&oc))
        {
            stderr.writefln("FAIL %s: oracle closest rejected", tc.name);
            ++failures;
            continue;
        }

        const double dx = fabs(actual.distanceOnFirst - ox);
        const double dy = fabs(actual.distanceOnSecond - oy);

        int dc;
        final switch (actual.coincidence)
        {
            case GeodesicIntersectionCoincidence.distinct: dc = 0; break;
            case GeodesicIntersectionCoincidence.parallel: dc = 1; break;
            case GeodesicIntersectionCoincidence.antiparallel: dc = -1; break;
        }

        if (dx > 2e-4 || dy > 2e-4 || dc != oc)
        {
            stderr.writefln(
                "FAIL %s dx=%.12g dy=%.12g dc=%s oc=%s",
                tc.name, dx,dy,dc,oc);
            ++failures;
            continue;
        }

        writefln(
            "PASS %-28s x=%.6f y=%.6f c=%s",
            tc.name,
            actual.distanceOnFirst,
            actual.distanceOnSecond,
            dc);
    }

    if (failures)
    {
        stderr.writefln(
            "R69.4b PROLATE CLOSEST FAIL: %s/%s cases",
            failures,cases.length);
        return 1;
    }

    writefln(
        "R69.4b PROLATE CLOSEST PASS: %s cases",
        cases.length);
    return 0;
}
