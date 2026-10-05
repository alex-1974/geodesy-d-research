module geodesic_line_benchmark;

import geodesy;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

enum size_t operationCount = 65_536;
enum size_t warmupRounds = 8;
enum size_t timedRounds = 24;

__gshared double sink = 0.0;

double distanceAt(const size_t i)
{
    const double fraction =
        cast(double) ((i * 4051) % operationCount)
        / cast(double) (operationCount - 1);

    return -2_000_000.0
        + 21_000_000.0 * fraction;
}

double fingerprint(
    const GeodesicDirectResult!double result)
{
    return
        result.position.latitude.radians
        + result.position.longitude.radians * 0.125
        + result.finalAzimuth.radians * 0.015625;
}

double timeRepeatedDirect(
    const Geodesic!double solver,
    const GeographicCoordinate!double start,
    const Angle!double azimuth)
{
    double local = 0.0;
    StopWatch sw;

    sw.start();

    foreach (i; 0 .. operationCount)
    {
        GeodesicDirectResult!double result;

        if (!solver.tryDirect(
                start,
                azimuth,
                distanceAt(i),
                result))
            return double.nan;

        local += fingerprint(result);
    }

    sw.stop();
    sink += local;

    return
        cast(double) sw.peek.total!"nsecs"
        / cast(double) operationCount;
}

double timePreparedLine(
    const GeodesicLine!double line)
{
    double local = 0.0;
    StopWatch sw;

    sw.start();

    foreach (i; 0 .. operationCount)
    {
        GeodesicDirectResult!double result;

        if (!line.tryPosition(
                distanceAt(i),
                result))
            return double.nan;

        local += fingerprint(result);
    }

    sw.stop();
    sink += local;

    return
        cast(double) sw.peek.total!"nsecs"
        / cast(double) operationCount;
}

double median(double[] values)
{
    values.sort();
    return values[values.length / 2];
}

void main(string[] args)
{
    if (args.length != 2
        || (args[1] != "direct"
            && args[1] != "line"))
        throw new Exception(
            "usage: geodesic-line-benchmark direct|line");

    const solver =
        Geodesic!double.fromEllipsoid(
            Ellipsoid!double.fromFlattening(
                6_378_137.0,
                1.0 / 298.257223563));

    const start =
        GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(48.20849),
            Longitude!double.fromDegrees(16.37208));

    const azimuth =
        Angle!double.fromDegrees(73.0);

    const line =
        GeodesicLine!double.fromGeodesic(
            solver,
            start,
            azimuth);

    double delegate() round =
        args[1] == "direct"
            ? () => timeRepeatedDirect(
                solver,
                start,
                azimuth)
            : () => timePreparedLine(line);

    foreach (_; 0 .. warmupRounds)
        round();

    double[timedRounds] values;

    foreach (i; 0 .. timedRounds)
        values[i] = round();

    writefln("mode=%s", args[1]);
    writefln("operations=%s", operationCount);
    writefln("warmups=%s", warmupRounds);
    writefln("samples=%s", timedRounds);
    writefln(
        "median_ns_per_op=%.6f",
        median(values[]));
    writefln("sink=%.17g", sink);
}
