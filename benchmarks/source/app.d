module app;

import geodesy;

import std.datetime.stopwatch : benchmark;
import std.stdio : writefln, writeln;

enum size_t sampleCount = 8_192;
enum size_t repetitions = 200;

__gshared double benchmarkSink = 0.0;


double fingerprint(const GeocentricCoordinate!double value)
{
    return
        value.x * 1.0e-9 +
        value.y * 1.0e-10 +
        value.z * 1.0e-11;
}


double fingerprint(const GeodeticCoordinate!double value)
{
    return
        value.latitude.radians +
        value.longitude.radians * 0.1 +
        value.ellipsoidalHeight * 1.0e-9;
}


void report(
    const char[] name,
    const long totalNanoseconds,
    const size_t operations)
{
    const double nsPerOperation =
        cast(double) totalNanoseconds / cast(double) operations;

    const double millionOperationsPerSecond =
        1_000.0 / nsPerOperation;

    writefln(
        "%-38s %10.3f ns/op   %10.3f Mops/s",
        name,
        nsPerOperation,
        millionOperationsPerSecond);
}


void main()
{
    const earth = wgs84!double();

    auto geodetic =
        new GeodeticCoordinate!double[sampleCount];

    auto geocentric =
        new GeocentricCoordinate!double[sampleCount];

    foreach (i; 0 .. sampleCount)
    {
        const double fraction =
            cast(double) i /
            cast(double) (sampleCount - 1);

        const size_t longitudeIndex =
            (i * 4_051UL) % sampleCount;

        const double longitudeFraction =
            cast(double) longitudeIndex /
            cast(double) (sampleCount - 1);

        const latitude =
            Latitude!double.fromDegrees(
                -89.0 + 178.0 * fraction);

        const longitude =
            Longitude!double.fromDegrees(
                -180.0 + 360.0 * longitudeFraction);

        const double height =
            cast(double) (i % 5_001UL) - 1_000.0;

        geodetic[i] =
            GeodeticCoordinate!double.fromComponents(
                latitude,
                longitude,
                height);

        geocentric[i] =
            geodeticToGeocentric(
                geodetic[i],
                earth);
    }

    const translation =
        GeocentricTranslation!double.fromComponents(
            84.87,
            96.49,
            116.95);

    const positionVector =
        PositionVectorHelmert!double.fromArcSecondsAndPpm(
            0.0,
            0.0,
            4.5,
            0.0,
            0.0,
            0.554,
            0.219);

    const coordinateFrame =
        toCoordinateFrame(positionVector);

    // Warm all public kernels once before measurement.
    foreach (i; 0 .. sampleCount)
    {
        GeocentricCoordinate!double ecef;
        if (tryGeodeticToGeocentric(
                geodetic[i],
                earth,
                ecef))
            benchmarkSink += fingerprint(ecef);

        GeodeticCoordinate!double geographic;
        if (tryGeocentricToGeodetic(
                geocentric[i],
                earth,
                geographic))
            benchmarkSink += fingerprint(geographic);

        GeocentricCoordinate!double translated;
        if (tryApplyGeocentricTranslation(
                geocentric[i],
                translation,
                translated))
            benchmarkSink += fingerprint(translated);

        GeocentricCoordinate!double positionVectorResult;
        if (tryApplyPositionVectorHelmert(
                geocentric[i],
                positionVector,
                positionVectorResult))
            benchmarkSink += fingerprint(positionVectorResult);

        GeocentricCoordinate!double coordinateFrameResult;
        if (tryApplyCoordinateFrameHelmert(
                geocentric[i],
                coordinateFrame,
                coordinateFrameResult))
            benchmarkSink += fingerprint(coordinateFrameResult);
    }

    const geodeticFloor = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
            localSink += fingerprint(geodetic[i]);

        benchmarkSink += localSink;
    })(repetitions);

    const geocentricFloor = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
            localSink += fingerprint(geocentric[i]);

        benchmarkSink += localSink;
    })(repetitions);

    const forward = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            const bool ok =
                tryGeodeticToGeocentric(
                    geodetic[i],
                    earth,
                    result);

            if (ok)
                localSink += fingerprint(result);
        }

        benchmarkSink += localSink;
    })(repetitions);

    const inverse = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeodeticCoordinate!double result;

            const bool ok =
                tryGeocentricToGeodetic(
                    geocentric[i],
                    earth,
                    result);

            if (ok)
                localSink += fingerprint(result);
        }

        benchmarkSink += localSink;
    })(repetitions);

    const translationTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            const bool ok =
                tryApplyGeocentricTranslation(
                    geocentric[i],
                    translation,
                    result);

            if (ok)
                localSink += fingerprint(result);
        }

        benchmarkSink += localSink;
    })(repetitions);

    const positionVectorTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            const bool ok =
                tryApplyPositionVectorHelmert(
                    geocentric[i],
                    positionVector,
                    result);

            if (ok)
                localSink += fingerprint(result);
        }

        benchmarkSink += localSink;
    })(repetitions);

    const coordinateFrameTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            const bool ok =
                tryApplyCoordinateFrameHelmert(
                    geocentric[i],
                    coordinateFrame,
                    result);

            if (ok)
                localSink += fingerprint(result);
        }

        benchmarkSink += localSink;
    })(repetitions);

    const size_t operations =
        sampleCount * repetitions;

    writeln();
    writeln("geodesy-d bulk benchmark baseline");
    writefln("samples:      %s", sampleCount);
    writefln("repetitions:  %s", repetitions);
    writefln("operations:   %s per benchmark", operations);
    writeln();

    report(
        "Harness floor: geodetic",
        geodeticFloor[0].total!"nsecs",
        operations);

    report(
        "Harness floor: geocentric",
        geocentricFloor[0].total!"nsecs",
        operations);

    writeln();

    report(
        "EPSG 9602 forward",
        forward[0].total!"nsecs",
        operations);

    report(
        "EPSG 9602 inverse",
        inverse[0].total!"nsecs",
        operations);

    report(
        "EPSG 1031 translation",
        translationTiming[0].total!"nsecs",
        operations);

    report(
        "EPSG 1033 Position Vector",
        positionVectorTiming[0].total!"nsecs",
        operations);

    report(
        "EPSG 1032 Coordinate Frame",
        coordinateFrameTiming[0].total!"nsecs",
        operations);

    writefln("\nsink: %.17g", benchmarkSink);
}
