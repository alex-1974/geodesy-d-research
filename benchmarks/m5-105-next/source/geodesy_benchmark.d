module m5_105_next_benchmark;

import geodesy;

import core.time : MonoTime;
import std.math : isFinite;
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

    GeodesicIntersectionSolver!double intersector;

    if (!GeodesicIntersectionSolver!double.tryFromGeodesic(
            solver,
            intersector))
    {
        stderr.writefln("ERROR: failed to prepare intersection solver");
        return 1;
    }

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

    double checksum = 0.0;

    foreach (_;0..warmups)
        foreach (i;0..count)
        {
            GeodesicNextIntersectionResult!double result;
            if (!tryNextGeodesicIntersection(
                    intersector,
                    xlines[i],
                    ylines[i],
                    result))
            {
                stderr.writefln(
                    "ERROR: tryNextGeodesicIntersection failed for case %s",
                    cases[i].name);
                return 2;
            }

            if (!isFinite(result.distanceOnFirst)
                || !isFinite(result.distanceOnSecond)
                || !isFinite(result.displacementDistance))
            {
                stderr.writefln(
                    "ERROR: non-finite result for case %s: x=%s y=%s rank=%s coincidence=%s",
                    cases[i].name,
                    result.distanceOnFirst,
                    result.distanceOnSecond,
                    result.displacementDistance,
                    result.coincidence);
                return 3;
            }

            checksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

    foreach (i; 0 .. count)
    {
        enum size_t diagnosticRounds = 32;
        double caseChecksum = 0.0;
        const caseStart = MonoTime.currTime;

        foreach (_; 0 .. diagnosticRounds)
        {
            GeodesicNextIntersectionResult!double result;

            if (!tryNextGeodesicIntersection(
                    intersector,
                    xlines[i],
                    ylines[i],
                    result))
            {
                stderr.writefln(
                    "ERROR: diagnostic call failed for case %s",
                    cases[i].name);
                return 4;
            }

            if (!isFinite(result.distanceOnFirst)
                || !isFinite(result.distanceOnSecond)
                || !isFinite(result.displacementDistance))
            {
                stderr.writefln(
                    "ERROR: diagnostic non-finite result for case %s: x=%s y=%s rank=%s coincidence=%s",
                    cases[i].name,
                    result.distanceOnFirst,
                    result.distanceOnSecond,
                    result.displacementDistance,
                    result.coincidence);
                return 5;
            }

            caseChecksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

        const caseElapsed = MonoTime.currTime - caseStart;

        writefln(
            "case_ns_per_op.%s=%.6f checksum=%.12f",
            cases[i].name,
            cast(double) caseElapsed.total!"nsecs"
                / cast(double) diagnosticRounds,
            caseChecksum);
    }

    enum size_t prepareRounds = 32;
    double prepareChecksum = 0.0;
    const prepareStart = MonoTime.currTime;

    foreach (_; 0 .. prepareRounds)
    {
        GeodesicIntersectionSolver!double prepared;

        if (!GeodesicIntersectionSolver!double.tryFromGeodesic(
                solver,
                prepared))
        {
            stderr.writefln("ERROR: repeated intersection preparation failed");
            return 6;
        }

        prepareChecksum += prepared.isValid ? 1.0 : 0.0;
    }

    const prepareElapsed = MonoTime.currTime - prepareStart;

    const double prepareNsPerOp =
        cast(double) prepareElapsed.total!"nsecs"
            / cast(double) prepareRounds;

    writefln("prepare_ns_per_op=%.6f", prepareNsPerOp);
    writefln("prepare_checksum=%.12f", prepareChecksum);

    double coldChecksum = 0.0;
    const coldStart = MonoTime.currTime;

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
                    "ERROR: cold tryNextGeodesicIntersection failed for case %s",
                    cases[i].name);
                return 7;
            }

            coldChecksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

    const coldElapsed = MonoTime.currTime - coldStart;

    writefln(
        "cold_ns_per_op=%.6f",
        cast(double) coldElapsed.total!"nsecs"
            / cast(double) (rounds * count));
    writefln("cold_checksum=%.12f", coldChecksum);

    const start = MonoTime.currTime;

    foreach (_;0..rounds)
        foreach (i;0..count)
        {
            GeodesicNextIntersectionResult!double result;
            if (!tryNextGeodesicIntersection(
                    intersector,
                    xlines[i],
                    ylines[i],
                    result))
            {
                stderr.writefln(
                    "ERROR: tryNextGeodesicIntersection failed for case %s",
                    cases[i].name);
                return 2;
            }

            if (!isFinite(result.distanceOnFirst)
                || !isFinite(result.distanceOnSecond)
                || !isFinite(result.displacementDistance))
            {
                stderr.writefln(
                    "ERROR: non-finite result for case %s: x=%s y=%s rank=%s coincidence=%s",
                    cases[i].name,
                    result.distanceOnFirst,
                    result.distanceOnSecond,
                    result.displacementDistance,
                    result.coincidence);
                return 3;
            }

            checksum +=
                result.distanceOnFirst * 1e-12
                + result.distanceOnSecond * 1e-12;
        }

    const elapsed = MonoTime.currTime - start;

    enum size_t operations = rounds * count;

    writefln("implementation=geodesy-d");
    writefln("operations=%s",operations);
    const double preparedNsPerOp =
        cast(double) elapsed.total!"nsecs"
            / cast(double) operations;

    const double coldNsPerOp =
        cast(double) coldElapsed.total!"nsecs"
            / cast(double) operations;

    writefln("ns_per_op=%.6f", preparedNsPerOp);
    writefln("checksum=%.12f",checksum);

    if (coldNsPerOp > preparedNsPerOp)
    {
        const double breakEvenCalls =
            prepareNsPerOp / (coldNsPerOp - preparedNsPerOp);
        writefln("break_even_calls=%.6f", breakEvenCalls);
    }
    else
    {
        writefln("break_even_calls=inf");
    }

    return 0;
}
