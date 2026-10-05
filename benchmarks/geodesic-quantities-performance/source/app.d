module app;

import geodesy;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

enum size_t corpusSize = 16_384;
enum size_t warmupRounds = 8;
enum size_t timedRounds = 24;

__gshared double sink = 0.0;

struct DirectCase
{
    GeographicCoordinate!double start;
    Angle!double azimuth;
    double distance;
}

struct InverseCase
{
    GeographicCoordinate!double start;
    GeographicCoordinate!double end;
}

double fraction(size_t index, size_t multiplier)
{
    const size_t value = (index * multiplier) % corpusSize;
    return cast(double) value / cast(double) (corpusSize - 1);
}

void fillDirect(ref DirectCase[corpusSize] cases)
{
    foreach (i, ref item; cases)
    {
        const double lat = -75.0 + 150.0 * fraction(i, 1);
        const double lon = -180.0 + 360.0 * fraction(i, 4_051);
        const double azi = -180.0 + 360.0 * fraction(i, 7_919);
        const double distance = 1_000.0 + 19_000_000.0 * fraction(i, 3_571);

        item.start = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(lat),
            Longitude!double.fromDegrees(lon));
        item.azimuth = Angle!double.fromDegrees(azi);
        item.distance = distance;
    }
}

void fillInverse(ref InverseCase[corpusSize] cases)
{
    foreach (i, ref item; cases)
    {
        const double lat1 = -75.0 + 150.0 * fraction(i, 1);
        const double lon1 = -180.0 + 360.0 * fraction(i, 4_051);
        const double lat2 = -72.0 + 144.0 * fraction(i, 7_919);
        const double lon2 = -180.0 + 360.0 * fraction(i, 3_571);

        item.start = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(lat1),
            Longitude!double.fromDegrees(lon1));
        item.end = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(lat2),
            Longitude!double.fromDegrees(lon2));
    }
}

double directLeanRound(
    const Geodesic!double solver,
    const DirectCase[] cases)
{
    double local = 0.0;
    StopWatch sw;
    sw.start();
    foreach (const ref item; cases)
    {
        GeodesicDirectResult!double result;
        if (!solver.tryDirect(item.start, item.azimuth, item.distance, result))
            return double.nan;

        local +=
            result.position.latitude.radians
            + result.position.longitude.radians * 0.125
            + result.finalAzimuth.radians * 0.015625;
    }
    sw.stop();
    sink += local;
    return cast(double) sw.peek.total!"nsecs" / cast(double) cases.length;
}

double directQuantitiesRound(
    const Geodesic!double solver,
    const DirectCase[] cases)
{
    double local = 0.0;
    StopWatch sw;
    sw.start();
    foreach (const ref item; cases)
    {
        GeodesicDirectResult!double result;
        GeodesicQuantities!double q;
        if (!solver.tryDirect(item.start, item.azimuth, item.distance, result, q))
            return double.nan;

        local +=
            result.position.latitude.radians
            + result.position.longitude.radians * 0.125
            + result.finalAzimuth.radians * 0.015625
            + q.reducedLength * 1.0e-8
            + q.scale12 * 0.00390625
            + q.scale21 * 0.001953125
            + q.signedArea * 1.0e-15;
    }
    sw.stop();
    sink += local;
    return cast(double) sw.peek.total!"nsecs" / cast(double) cases.length;
}

double inverseLeanRound(
    const Geodesic!double solver,
    const InverseCase[] cases)
{
    double local = 0.0;
    StopWatch sw;
    sw.start();
    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double result;
        if (!solver.tryInverse(item.start, item.end, result))
            return double.nan;

        local +=
            result.distance * 1.0e-8
            + result.initialAzimuth.radians
            + result.finalAzimuth.radians * 0.125;
    }
    sw.stop();
    sink += local;
    return cast(double) sw.peek.total!"nsecs" / cast(double) cases.length;
}

double inverseQuantitiesRound(
    const Geodesic!double solver,
    const InverseCase[] cases)
{
    double local = 0.0;
    StopWatch sw;
    sw.start();
    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double result;
        GeodesicQuantities!double q;
        if (!solver.tryInverse(item.start, item.end, result, q))
            return double.nan;

        local +=
            result.distance * 1.0e-8
            + result.initialAzimuth.radians
            + result.finalAzimuth.radians * 0.125
            + q.reducedLength * 1.0e-8
            + q.scale12 * 0.00390625
            + q.scale21 * 0.001953125
            + q.signedArea * 1.0e-15;
    }
    sw.stop();
    sink += local;
    return cast(double) sw.peek.total!"nsecs" / cast(double) cases.length;
}

double median(double[] values)
{
    values.sort();
    return values[values.length / 2];
}

void runMode(string mode)
{
    const solver = Geodesic!double.fromEllipsoid(wgs84!double());

    DirectCase[corpusSize] directCases;
    InverseCase[corpusSize] inverseCases;

    if (mode == "direct-lean" || mode == "direct-quantities")
        fillDirect(directCases);
    else if (mode == "inverse-lean" || mode == "inverse-quantities")
        fillInverse(inverseCases);
    else
        throw new Exception(
            "mode must be direct-lean, direct-quantities, inverse-lean, or inverse-quantities");

    double delegate() round;

    if (mode == "direct-lean")
        round = () => directLeanRound(solver, directCases[]);
    else if (mode == "direct-quantities")
        round = () => directQuantitiesRound(solver, directCases[]);
    else if (mode == "inverse-lean")
        round = () => inverseLeanRound(solver, inverseCases[]);
    else
        round = () => inverseQuantitiesRound(solver, inverseCases[]);

    foreach (_; 0 .. warmupRounds)
        round();

    double[timedRounds] timings;
    foreach (i; 0 .. timedRounds)
        timings[i] = round();

    const double value = median(timings[]);

    writefln("mode=%s", mode);
    writefln("operations=%s", corpusSize);
    writefln("warmups=%s", warmupRounds);
    writefln("samples=%s", timedRounds);
    writefln("median_ns_per_op=%.6f", value);
    writefln("sink=%.17g", sink);
}

void main(string[] args)
{
    if (args.length != 2)
        throw new Exception("usage: geodesic-quantities-performance <mode>");

    runMode(args[1]);
}
