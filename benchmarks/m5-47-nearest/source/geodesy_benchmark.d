module m5_47_nearest_benchmark;

import geodesy;

import core.time : MonoTime;
import std.stdio : writefln;

private struct Case
{
    double latA;
    double lonA;
    double latB;
    double lonB;
    double latC;
    double lonC;
}

void main()
{
    const solver =
        Geodesic!double.fromEllipsoid(
            Ellipsoid!double.fromInverseFlattening(
                6_378_137.0,
                298.257223563));

    enum size_t caseCount = 6;

    Case[caseCount] cases = [
        Case(48.0, 10.0, 48.0, 20.0, 49.2, 15.0),
        Case(40.0, -75.0, 42.0, -60.0, 38.0, -66.0),
        Case(48.0, 10.0, 48.0, 12.0, 48.4, 8.0),
        Case(48.0, 10.0, 48.0, 12.0, 47.7, 14.0),
        Case(15.0, 175.0, 18.0, -175.0, 20.0, 179.0),
        Case(0.0, -20.0, 0.0, 20.0, -2.0, 3.0),
    ];

    GeographicCoordinate!double[caseCount] a;
    GeographicCoordinate!double[caseCount] b;
    GeographicCoordinate!double[caseCount] c;

    foreach (i, item; cases)
    {
        a[i] =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(item.latA),
                Longitude!double.fromDegrees(item.lonA));

        b[i] =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(item.latB),
                Longitude!double.fromDegrees(item.lonB));

        c[i] =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(item.latC),
                Longitude!double.fromDegrees(item.lonC));
    }

    enum size_t warmupRounds = 16;
    enum size_t timedRounds = 256;

    double checksum = 0.0;

    foreach (_; 0 .. warmupRounds)
    {
        foreach (i; 0 .. caseCount)
        {
            GeodesicSegmentNearestResult!double result;
            if (!tryNearestPointOnSegment(
                    solver,
                    a[i],
                    b[i],
                    c[i],
                    result))
                assert(0);

            checksum +=
                result.nearestDistance
                + result.alongTrack * 1.0e-6
                + result.signedCrossTrack * 1.0e-6;
        }
    }

    const start = MonoTime.currTime;

    foreach (_; 0 .. timedRounds)
    {
        foreach (i; 0 .. caseCount)
        {
            GeodesicSegmentNearestResult!double result;
            if (!tryNearestPointOnSegment(
                    solver,
                    a[i],
                    b[i],
                    c[i],
                    result))
                assert(0);

            checksum +=
                result.nearestDistance
                + result.alongTrack * 1.0e-6
                + result.signedCrossTrack * 1.0e-6;
        }
    }

    const elapsed = MonoTime.currTime - start;
    enum size_t operations = timedRounds * caseCount;

    const double nsPerOp =
        cast(double) elapsed.total!"nsecs"
        / cast(double) operations;

    writefln("implementation=geodesy-d");
    writefln("operations=%s", operations);
    writefln("ns_per_op=%.6f", nsPerOp);
    writefln("checksum=%.12f", checksum);
}
