module m5_106_all_performance;

import geodesy;

import core.time : MonoTime;
import std.conv : to;
import std.math : isFinite;
import std.stdio : stderr, writefln;

private struct Geometry
{
    string name;
    double latX, lonX, aziX;
    double latY, lonY, aziY;
}

private GeographicCoordinate!double gc(double lat, double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private double consume(
    const GeodesicIntersectionPoint!double[] output,
    size_t written,
    const GeodesicIntersectionEnumeration enumeration)
{
    double value =
        cast(double) enumeration.total * 1e-6
        + cast(double) enumeration.requiredTiles * 1e-9;

    foreach (i; 0 .. written)
    {
        value +=
            output[i].distanceOnFirst * 1e-12
            + output[i].distanceOnSecond * 1e-12
            + output[i].referenceDistance * 1e-15;
    }

    return value;
}

int main(string[] args)
{
    size_t rounds = 8;

    if (args.length > 1)
        rounds = to!size_t(args[1]);

    if (rounds == 0)
    {
        stderr.writefln("ERROR: rounds must be positive");
        return 1;
    }

    const solver =
        Geodesic!double.fromEllipsoid(wgs84!double());

    GeodesicIntersectionSolver!double intersector;

    if (!GeodesicIntersectionSolver!double.tryFromGeodesic(
            solver,
            intersector))
    {
        stderr.writefln("ERROR: failed to prepare intersection solver");
        return 2;
    }

    Geometry[4] geometries = [
        Geometry("ordinary", 0,-20,45, 10,20,-60),
        Geometry("near_parallel", 10,20,45, 11,21,45.1),
        Geometry("symmetric", 0,0,45, 0,0,135),
        Geometry("coincident", 0,0,90, 0,0,90)
    ];

    double[4] radii = [
        20_000_000.0,
        40_000_000.0,
        80_000_000.0,
        160_000_000.0
    ];

    enum size_t geometryCount = 4;
    enum size_t radiusCount = 4;
    enum size_t caseCount = geometryCount * radiusCount;

    GeodesicLine!double[geometryCount] firstLines;
    GeodesicLine!double[geometryCount] secondLines;

    foreach (i,item; geometries)
    {
        firstLines[i] =
            GeodesicLine!double.fromGeodesic(
                solver,
                gc(item.latX,item.lonX),
                Angle!double.fromDegrees(item.aziX));

        secondLines[i] =
            GeodesicLine!double.fromGeodesic(
                solver,
                gc(item.latY,item.lonY),
                Angle!double.fromDegrees(item.aziY));
    }

    enum size_t tileCapacity = 256;
    enum size_t foundCapacity = 512;
    enum size_t centerCapacity = 128;
    enum size_t outputCapacity = 512;

    GeodesicIntersectionWorkspaceEntry!double[tileCapacity] starts;
    bool[tileCapacity] skip;
    GeodesicIntersectionWorkspaceEntry!double[foundCapacity] found;
    GeodesicIntersectionWorkspaceEntry!double[centerCapacity] centers;
    GeodesicIntersectionWorkspace!double workspace;

    if (!GeodesicIntersectionWorkspace!double.tryFromStorage(
            starts[],
            skip[],
            found[],
            centers[],
            workspace))
    {
        stderr.writefln("ERROR: failed to prepare workspace");
        return 3;
    }

    GeodesicIntersectionPoint!double[outputCapacity] output;

    size_t[caseCount] totals;
    size_t[caseCount] tiles;
    size_t caseIndex;

    foreach (g; 0 .. geometryCount)
    {
        foreach (r; 0 .. radiusCount)
        {
            GeodesicIntersectionEnumeration enumeration;

            if (!tryAllGeodesicIntersections(
                    intersector,
                    firstLines[g],
                    secondLines[g],
                    radii[r],
                    cast(GeodesicIntersectionPoint!double[]) null,
                    workspace,
                    enumeration))
            {
                stderr.writefln(
                    "ERROR: count query failed case=%s radius=%.0f status=%s requiredTiles=%s minFound=%s",
                    geometries[g].name,
                    radii[r],
                    enumeration.status,
                    enumeration.requiredTiles,
                    enumeration.minimumFoundCapacity);
                return 4;
            }

            if (enumeration.total > output.length)
            {
                stderr.writefln(
                    "ERROR: output capacity insufficient case=%s radius=%.0f total=%s",
                    geometries[g].name,
                    radii[r],
                    enumeration.total);
                return 5;
            }

            totals[caseIndex] = enumeration.total;
            tiles[caseIndex] = enumeration.requiredTiles;

            writefln(
                "shape.%s.r%.0f.results=%s tiles=%s",
                geometries[g].name,
                radii[r],
                enumeration.total,
                enumeration.requiredTiles);

            ++caseIndex;
        }
    }

    enum size_t warmups = 2;
    double checksum = 0.0;

    foreach (_; 0 .. warmups)
    {
        caseIndex = 0;

        foreach (g; 0 .. geometryCount)
        {
            foreach (r; 0 .. radiusCount)
            {
                GeodesicIntersectionEnumeration enumeration;
                auto exactOutput = output[0 .. totals[caseIndex]];

                if (!tryAllGeodesicIntersections(
                        intersector,
                        firstLines[g],
                        secondLines[g],
                        radii[r],
                        exactOutput,
                        workspace,
                        enumeration))
                    return 6;

                checksum += consume(
                    exactOutput,
                    enumeration.written,
                    enumeration);

                ++caseIndex;
            }
        }
    }

    double totalExactNs = 0.0;
    double totalCountNs = 0.0;
    double totalTruncatedNs = 0.0;
    ulong totalResults = 0;
    ulong totalTiles = 0;

    caseIndex = 0;

    foreach (g; 0 .. geometryCount)
    {
        foreach (r; 0 .. radiusCount)
        {
            const size_t expectedTotal = totals[caseIndex];
            const size_t expectedTiles = tiles[caseIndex];
            auto exactOutput = output[0 .. expectedTotal];
            const size_t shortLength =
                expectedTotal < 2 ? expectedTotal : 2;
            auto shortOutput = output[0 .. shortLength];

            double exactChecksum = 0.0;
            const exactStart = MonoTime.currTime;

            foreach (_; 0 .. rounds)
            {
                GeodesicIntersectionEnumeration enumeration;

                if (!tryAllGeodesicIntersections(
                        intersector,
                        firstLines[g],
                        secondLines[g],
                        radii[r],
                        exactOutput,
                        workspace,
                        enumeration))
                    return 7;

                if (enumeration.total != expectedTotal
                    || enumeration.written != expectedTotal
                    || enumeration.truncated)
                    return 8;

                exactChecksum += consume(
                    exactOutput,
                    enumeration.written,
                    enumeration);
            }

            const exactElapsed = MonoTime.currTime - exactStart;
            const double exactNs =
                cast(double) exactElapsed.total!"nsecs"
                    / cast(double) rounds;

            double countChecksum = 0.0;
            const countStart = MonoTime.currTime;

            foreach (_; 0 .. rounds)
            {
                GeodesicIntersectionEnumeration enumeration;

                if (!tryAllGeodesicIntersections(
                        intersector,
                        firstLines[g],
                        secondLines[g],
                        radii[r],
                        cast(GeodesicIntersectionPoint!double[]) null,
                        workspace,
                        enumeration))
                    return 9;

                if (enumeration.total != expectedTotal
                    || enumeration.written != 0
                    || enumeration.truncated != (expectedTotal != 0))
                    return 10;

                countChecksum +=
                    cast(double) enumeration.total * 1e-6
                    + cast(double) enumeration.requiredTiles * 1e-9;
            }

            const countElapsed = MonoTime.currTime - countStart;
            const double countNs =
                cast(double) countElapsed.total!"nsecs"
                    / cast(double) rounds;

            double truncatedChecksum = 0.0;
            const truncatedStart = MonoTime.currTime;

            foreach (_; 0 .. rounds)
            {
                GeodesicIntersectionEnumeration enumeration;

                if (!tryAllGeodesicIntersections(
                        intersector,
                        firstLines[g],
                        secondLines[g],
                        radii[r],
                        shortOutput,
                        workspace,
                        enumeration))
                    return 11;

                if (enumeration.total != expectedTotal
                    || enumeration.written != shortLength
                    || enumeration.truncated
                        != (shortLength < expectedTotal))
                    return 12;

                truncatedChecksum += consume(
                    shortOutput,
                    enumeration.written,
                    enumeration);
            }

            const truncatedElapsed =
                MonoTime.currTime - truncatedStart;
            const double truncatedNs =
                cast(double) truncatedElapsed.total!"nsecs"
                    / cast(double) rounds;

            const double nsPerResult =
                expectedTotal == 0
                    ? 0.0
                    : exactNs / cast(double) expectedTotal;

            const double nsPerTile =
                expectedTiles == 0
                    ? 0.0
                    : exactNs / cast(double) expectedTiles;

            writefln(
                "case.%s.r%.0f.exact_ns=%.6f count_ns=%.6f truncated_ns=%.6f results=%s tiles=%s ns_per_result=%.6f ns_per_tile=%.6f checksum=%.12f",
                geometries[g].name,
                radii[r],
                exactNs,
                countNs,
                truncatedNs,
                expectedTotal,
                expectedTiles,
                nsPerResult,
                nsPerTile,
                exactChecksum + countChecksum + truncatedChecksum);

            totalExactNs += exactNs;
            totalCountNs += countNs;
            totalTruncatedNs += truncatedNs;
            totalResults += expectedTotal;
            totalTiles += expectedTiles;
            checksum +=
                exactChecksum + countChecksum + truncatedChecksum;

            ++caseIndex;
        }
    }

    writefln("implementation=geodesy-d");
    writefln("queries=%s",caseCount);
    writefln(
        "exact_ns_per_query=%.6f",
        totalExactNs / cast(double) caseCount);
    writefln(
        "count_ns_per_query=%.6f",
        totalCountNs / cast(double) caseCount);
    writefln(
        "truncated_ns_per_query=%.6f",
        totalTruncatedNs / cast(double) caseCount);
    writefln(
        "exact_ns_per_result=%.6f",
        totalResults == 0
            ? 0.0
            : totalExactNs / cast(double) totalResults);
    writefln(
        "exact_ns_per_tile=%.6f",
        totalTiles == 0
            ? 0.0
            : totalExactNs / cast(double) totalTiles);
    writefln("total_results=%s",totalResults);
    writefln("total_tiles=%s",totalTiles);
    writefln("checksum=%.12f",checksum);

    return isFinite(checksum) ? 0 : 13;
}
