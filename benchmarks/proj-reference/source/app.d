module app;

import geodesy;

import std.algorithm.comparison : max;
import std.datetime.stopwatch : benchmark;
import std.math : fabs, isFinite;
import std.stdio : writefln, writeln;

__gshared double benchmarkSink = 0.0;


/*
 * Minimal benchmark-local binding to the PROJ C API.
 *
 * This deliberately does not introduce a runtime dependency into geodesy-d.
 * Only the independent reference benchmark links libproj.
 */
extern(C):

struct PJ {}
struct PJ_CONTEXT {}

union PJ_COORD
{
    double[4] v;
}

static assert(PJ_COORD.sizeof == 4 * double.sizeof);
static assert(PJ_COORD.alignof == double.alignof);

enum PJ_DIRECTION : int
{
    inverse = -1,
    identity = 0,
    forward = 1
}

PJ_CONTEXT* proj_context_create();
PJ_CONTEXT* proj_context_destroy(PJ_CONTEXT* ctx);

PJ* proj_create(PJ_CONTEXT* ctx, const(char)* definition);
PJ* proj_destroy(PJ* operation);

PJ_COORD proj_trans(
    PJ* operation,
    PJ_DIRECTION direction,
    PJ_COORD coordinate);


extern(D):

PJ_COORD projCoordinate(
    const double x,
    const double y,
    const double z,
    const double t = 0.0)
{
    PJ_COORD result;
    result.v[0] = x;
    result.v[1] = y;
    result.v[2] = z;
    result.v[3] = t;
    return result;
}


double geocentricFingerprint(
    const GeocentricCoordinate!double value)
{
    return
        value.x * 1.0e-9 +
        value.y * 1.0e-10 +
        value.z * 1.0e-11;
}


double geocentricFingerprint(
    const PJ_COORD value)
{
    return
        value.v[0] * 1.0e-9 +
        value.v[1] * 1.0e-10 +
        value.v[2] * 1.0e-11;
}


double geodeticFingerprint(
    const GeodeticCoordinate!double value)
{
    return
        value.latitude.radians +
        value.longitude.radians * 0.1 +
        value.ellipsoidalHeight * 1.0e-9;
}


double geodeticFingerprint(
    const PJ_COORD value)
{
    // PROJ cart inverse returns longitude, latitude, height.
    return
        value.v[1] +
        value.v[0] * 0.1 +
        value.v[2] * 1.0e-9;
}


void reportComparison(
    const char[] name,
    const long geodesyNanoseconds,
    const long projNanoseconds,
    const size_t operations)
{
    const double geodesyNsPerOperation =
        cast(double) geodesyNanoseconds /
        cast(double) operations;

    const double projNsPerOperation =
        cast(double) projNanoseconds /
        cast(double) operations;

    const double geodesyMops =
        1_000.0 / geodesyNsPerOperation;

    const double projMops =
        1_000.0 / projNsPerOperation;

    const double ratio =
        projNsPerOperation / geodesyNsPerOperation;

    writeln(name);

    writefln(
        "  geodesy-d  %10.3f ns/op   %10.3f Mops/s",
        geodesyNsPerOperation,
        geodesyMops);

    writefln(
        "  PROJ       %10.3f ns/op   %10.3f Mops/s",
        projNsPerOperation,
        projMops);

    writefln(
        "  PROJ/geodesy-d: %.3fx",
        ratio);
}


PJ* createOperation(
    PJ_CONTEXT* context,
    string definition)
{
    auto operation =
        proj_create(
            context,
            (definition ~ "\0").ptr);

    if (operation is null)
        throw new Exception(
            "PROJ could not create operation: " ~ definition);

    return operation;
}


void requireFinite(
    const PJ_COORD coordinate,
    string message)
{
    if (!isFinite(coordinate.v[0])
        || !isFinite(coordinate.v[1])
        || !isFinite(coordinate.v[2]))
        throw new Exception(message);
}


void requireWithin(
    const double value,
    const double limit,
    string message)
{
    if (!isFinite(value) || value > limit)
        throw new Exception(message);
}


double normalizedLongitudeDifference(
    double lhs,
    double rhs)
{
    import std.math : PI;

    double difference = lhs - rhs;

    while (difference > PI)
        difference -= 2.0 * PI;

    while (difference < -PI)
        difference += 2.0 * PI;

    return difference;
}


void main()
{
    enum size_t sampleCount = 8_192;
    enum size_t benchmarkRepetitions = 200;

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

    auto projGeographic =
        new PJ_COORD[sampleCount];

    auto projGeocentric =
        new PJ_COORD[sampleCount];

    foreach (i; 0 .. sampleCount)
    {
        projGeographic[i] =
            projCoordinate(
                geodetic[i].longitude.radians,
                geodetic[i].latitude.radians,
                geodetic[i].ellipsoidalHeight);

        projGeocentric[i] =
            projCoordinate(
                geocentric[i].x,
                geocentric[i].y,
                geocentric[i].z);
    }

    auto context = proj_context_create();

    if (context is null)
        throw new Exception(
            "proj_context_create returned null");

    scope(exit)
        proj_context_destroy(context);

    auto cart =
        createOperation(
            context,
            "+proj=cart +ellps=WGS84");

    scope(exit)
        proj_destroy(cart);

    auto translation =
        createOperation(
            context,
            "+proj=helmert " ~
            "+x=84.87 +y=96.49 +z=116.95");

    scope(exit)
        proj_destroy(translation);

    auto positionVector =
        createOperation(
            context,
            "+proj=helmert " ~
            "+x=0 +y=0 +z=4.5 " ~
            "+rx=0 +ry=0 +rz=0.554 " ~
            "+s=0.219 " ~
            "+convention=position_vector");

    scope(exit)
        proj_destroy(positionVector);

    /*
     * Same physical source -> target transformation as the Position Vector
     * parameters above. Coordinate Frame therefore uses negated rotations.
     */
    auto coordinateFrame =
        createOperation(
            context,
            "+proj=helmert " ~
            "+x=0 +y=0 +z=4.5 " ~
            "+rx=0 +ry=0 +rz=-0.554 " ~
            "+s=0.219 " ~
            "+convention=coordinate_frame");

    scope(exit)
        proj_destroy(coordinateFrame);

    const geodesyTranslation =
        GeocentricTranslation!double.fromComponents(
            84.87,
            96.49,
            116.95);

    const geodesyPositionVector =
        PositionVectorHelmert!double.fromArcSecondsAndPpm(
            0.0,
            0.0,
            4.5,
            0.0,
            0.0,
            0.554,
            0.219);

    const geodesyCoordinateFrame =
        toCoordinateFrame(
            geodesyPositionVector);

    double maxForwardX = 0.0;
    double maxForwardY = 0.0;
    double maxForwardZ = 0.0;

    double maxInverseLatitude = 0.0;
    double maxInverseLongitude = 0.0;
    double maxInverseHeight = 0.0;

    double maxTranslationX = 0.0;
    double maxTranslationY = 0.0;
    double maxTranslationZ = 0.0;

    double maxPositionVectorX = 0.0;
    double maxPositionVectorY = 0.0;
    double maxPositionVectorZ = 0.0;

    double maxCoordinateFrameX = 0.0;
    double maxCoordinateFrameY = 0.0;
    double maxCoordinateFrameZ = 0.0;

    foreach (i; 0 .. sampleCount)
    {
        /*
         * EPSG 9602 forward:
         * PROJ cart expects longitude, latitude in radians and height.
         */
        const geographicInput =
            projGeographic[i];

        const projForward =
            proj_trans(
                cart,
                PJ_DIRECTION.forward,
                geographicInput);

        requireFinite(
            projForward,
            "PROJ EPSG 9602 forward produced a non-finite result");

        const geodesyForward =
            geocentric[i];

        maxForwardX =
            max(
                maxForwardX,
                fabs(
                    projForward.v[0]
                    - geodesyForward.x));

        maxForwardY =
            max(
                maxForwardY,
                fabs(
                    projForward.v[1]
                    - geodesyForward.y));

        maxForwardZ =
            max(
                maxForwardZ,
                fabs(
                    projForward.v[2]
                    - geodesyForward.z));

        /*
         * EPSG 9602 inverse.
         */
        const geocentricInput =
            projGeocentric[i];

        const projInverse =
            proj_trans(
                cart,
                PJ_DIRECTION.inverse,
                geocentricInput);

        requireFinite(
            projInverse,
            "PROJ EPSG 9602 inverse produced a non-finite result");

        const geodesyInverse =
            geocentricToGeodetic(
                geocentric[i],
                earth);

        maxInverseLongitude =
            max(
                maxInverseLongitude,
                fabs(
                    normalizedLongitudeDifference(
                        projInverse.v[0],
                        geodesyInverse.longitude.radians)));

        maxInverseLatitude =
            max(
                maxInverseLatitude,
                fabs(
                    projInverse.v[1]
                    - geodesyInverse.latitude.radians));

        maxInverseHeight =
            max(
                maxInverseHeight,
                fabs(
                    projInverse.v[2]
                    - geodesyInverse.ellipsoidalHeight));

        /*
         * EPSG 1031.
         */
        const projTranslation =
            proj_trans(
                translation,
                PJ_DIRECTION.forward,
                geocentricInput);

        const geodesyTranslated =
            applyGeocentricTranslation(
                geocentric[i],
                geodesyTranslation);

        maxTranslationX =
            max(
                maxTranslationX,
                fabs(
                    projTranslation.v[0]
                    - geodesyTranslated.x));

        maxTranslationY =
            max(
                maxTranslationY,
                fabs(
                    projTranslation.v[1]
                    - geodesyTranslated.y));

        maxTranslationZ =
            max(
                maxTranslationZ,
                fabs(
                    projTranslation.v[2]
                    - geodesyTranslated.z));

        /*
         * EPSG 1033.
         */
        const projPositionVector =
            proj_trans(
                positionVector,
                PJ_DIRECTION.forward,
                geocentricInput);

        const geodesyPositionVectorResult =
            applyPositionVectorHelmert(
                geocentric[i],
                geodesyPositionVector);

        maxPositionVectorX =
            max(
                maxPositionVectorX,
                fabs(
                    projPositionVector.v[0]
                    - geodesyPositionVectorResult.x));

        maxPositionVectorY =
            max(
                maxPositionVectorY,
                fabs(
                    projPositionVector.v[1]
                    - geodesyPositionVectorResult.y));

        maxPositionVectorZ =
            max(
                maxPositionVectorZ,
                fabs(
                    projPositionVector.v[2]
                    - geodesyPositionVectorResult.z));

        /*
         * EPSG 1032.
         */
        const projCoordinateFrame =
            proj_trans(
                coordinateFrame,
                PJ_DIRECTION.forward,
                geocentricInput);

        const geodesyCoordinateFrameResult =
            applyCoordinateFrameHelmert(
                geocentric[i],
                geodesyCoordinateFrame);

        maxCoordinateFrameX =
            max(
                maxCoordinateFrameX,
                fabs(
                    projCoordinateFrame.v[0]
                    - geodesyCoordinateFrameResult.x));

        maxCoordinateFrameY =
            max(
                maxCoordinateFrameY,
                fabs(
                    projCoordinateFrame.v[1]
                    - geodesyCoordinateFrameResult.y));

        maxCoordinateFrameZ =
            max(
                maxCoordinateFrameZ,
                fabs(
                    projCoordinateFrame.v[2]
                    - geodesyCoordinateFrameResult.z));
    }

    /*
     * Validation envelopes for this independent reference comparison.
     *
     * These are deliberately looser than the differences observed with
     * PROJ 9.7.1 so harmless platform-level floating-point variation does
     * not turn this probe into a bit-for-bit test.
     */
    enum double cartesianTolerance = 1.0e-8;
    enum double angularTolerance = 1.0e-13;
    enum double inverseHeightTolerance = 1.0e-6;

    requireWithin(
        maxForwardX,
        cartesianTolerance,
        "EPSG 9602 forward X exceeded PROJ comparison tolerance");
    requireWithin(
        maxForwardY,
        cartesianTolerance,
        "EPSG 9602 forward Y exceeded PROJ comparison tolerance");
    requireWithin(
        maxForwardZ,
        cartesianTolerance,
        "EPSG 9602 forward Z exceeded PROJ comparison tolerance");

    requireWithin(
        maxInverseLatitude,
        angularTolerance,
        "EPSG 9602 inverse latitude exceeded PROJ comparison tolerance");
    requireWithin(
        maxInverseLongitude,
        angularTolerance,
        "EPSG 9602 inverse longitude exceeded PROJ comparison tolerance");
    requireWithin(
        maxInverseHeight,
        inverseHeightTolerance,
        "EPSG 9602 inverse height exceeded PROJ comparison tolerance");

    requireWithin(
        maxTranslationX,
        cartesianTolerance,
        "EPSG 1031 X exceeded PROJ comparison tolerance");
    requireWithin(
        maxTranslationY,
        cartesianTolerance,
        "EPSG 1031 Y exceeded PROJ comparison tolerance");
    requireWithin(
        maxTranslationZ,
        cartesianTolerance,
        "EPSG 1031 Z exceeded PROJ comparison tolerance");

    requireWithin(
        maxPositionVectorX,
        cartesianTolerance,
        "EPSG 1033 X exceeded PROJ comparison tolerance");
    requireWithin(
        maxPositionVectorY,
        cartesianTolerance,
        "EPSG 1033 Y exceeded PROJ comparison tolerance");
    requireWithin(
        maxPositionVectorZ,
        cartesianTolerance,
        "EPSG 1033 Z exceeded PROJ comparison tolerance");

    requireWithin(
        maxCoordinateFrameX,
        cartesianTolerance,
        "EPSG 1032 X exceeded PROJ comparison tolerance");
    requireWithin(
        maxCoordinateFrameY,
        cartesianTolerance,
        "EPSG 1032 Y exceeded PROJ comparison tolerance");
    requireWithin(
        maxCoordinateFrameZ,
        cartesianTolerance,
        "EPSG 1032 Z exceeded PROJ comparison tolerance");

    writeln();
    writeln("geodesy-d / PROJ numerical equivalence probe");
    writefln("samples: %s", sampleCount);
    writeln();

    writefln(
        "EPSG 9602 forward max |dX|: %.17g m",
        maxForwardX);
    writefln(
        "EPSG 9602 forward max |dY|: %.17g m",
        maxForwardY);
    writefln(
        "EPSG 9602 forward max |dZ|: %.17g m",
        maxForwardZ);

    writeln();

    writefln(
        "EPSG 9602 inverse max |dLat|: %.17g rad",
        maxInverseLatitude);
    writefln(
        "EPSG 9602 inverse max |dLon|: %.17g rad",
        maxInverseLongitude);
    writefln(
        "EPSG 9602 inverse max |dH|:   %.17g m",
        maxInverseHeight);

    writeln();

    writefln(
        "EPSG 1031 max |dX|: %.17g m",
        maxTranslationX);
    writefln(
        "EPSG 1031 max |dY|: %.17g m",
        maxTranslationY);
    writefln(
        "EPSG 1031 max |dZ|: %.17g m",
        maxTranslationZ);

    writeln();

    writefln(
        "EPSG 1033 max |dX|: %.17g m",
        maxPositionVectorX);
    writefln(
        "EPSG 1033 max |dY|: %.17g m",
        maxPositionVectorY);
    writefln(
        "EPSG 1033 max |dZ|: %.17g m",
        maxPositionVectorZ);

    writeln();

    writefln(
        "EPSG 1032 max |dX|: %.17g m",
        maxCoordinateFrameX);
    writefln(
        "EPSG 1032 max |dY|: %.17g m",
        maxCoordinateFrameY);
    writefln(
        "EPSG 1032 max |dZ|: %.17g m",
        maxCoordinateFrameZ);

    /*
     * Performance comparison.
     *
     * All operation construction, definition parsing, fixture generation and
     * numerical equivalence checks have completed before entering these timed
     * sections.
     *
     * PROJ is measured through its scalar public C API, proj_trans().
     * Consequently the comparison intentionally includes the public API/FFI
     * call boundary, but not operation construction or pipeline parsing.
     */
    const geodesyForwardTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            if (tryGeodeticToGeocentric(
                    geodetic[i],
                    earth,
                    result))
                localSink +=
                    geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const projForwardTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            const result =
                proj_trans(
                    cart,
                    PJ_DIRECTION.forward,
                    projGeographic[i]);

            localSink +=
                geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const geodesyInverseTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeodeticCoordinate!double result;

            if (tryGeocentricToGeodetic(
                    geocentric[i],
                    earth,
                    result))
                localSink +=
                    geodeticFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const projInverseTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            const result =
                proj_trans(
                    cart,
                    PJ_DIRECTION.inverse,
                    projGeocentric[i]);

            localSink +=
                geodeticFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const geodesyTranslationTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            if (tryApplyGeocentricTranslation(
                    geocentric[i],
                    geodesyTranslation,
                    result))
                localSink +=
                    geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const projTranslationTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            const result =
                proj_trans(
                    translation,
                    PJ_DIRECTION.forward,
                    projGeocentric[i]);

            localSink +=
                geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const geodesyPositionVectorTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            if (tryApplyPositionVectorHelmert(
                    geocentric[i],
                    geodesyPositionVector,
                    result))
                localSink +=
                    geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const projPositionVectorTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            const result =
                proj_trans(
                    positionVector,
                    PJ_DIRECTION.forward,
                    projGeocentric[i]);

            localSink +=
                geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const geodesyCoordinateFrameTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            GeocentricCoordinate!double result;

            if (tryApplyCoordinateFrameHelmert(
                    geocentric[i],
                    geodesyCoordinateFrame,
                    result))
                localSink +=
                    geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const projCoordinateFrameTiming = benchmark!({
        double localSink = 0.0;

        foreach (i; 0 .. sampleCount)
        {
            const result =
                proj_trans(
                    coordinateFrame,
                    PJ_DIRECTION.forward,
                    projGeocentric[i]);

            localSink +=
                geocentricFingerprint(result);
        }

        benchmarkSink += localSink;
    })(benchmarkRepetitions);

    const size_t benchmarkOperations =
        sampleCount * benchmarkRepetitions;

    writeln();
    writeln("geodesy-d / PROJ performance comparison");
    writefln("samples:      %s", sampleCount);
    writefln("repetitions:  %s", benchmarkRepetitions);
    writefln(
        "operations:   %s per implementation/operation",
        benchmarkOperations);
    writeln();

    reportComparison(
        "EPSG 9602 forward",
        geodesyForwardTiming[0].total!"nsecs",
        projForwardTiming[0].total!"nsecs",
        benchmarkOperations);

    writeln();

    reportComparison(
        "EPSG 9602 inverse",
        geodesyInverseTiming[0].total!"nsecs",
        projInverseTiming[0].total!"nsecs",
        benchmarkOperations);

    writeln();

    reportComparison(
        "EPSG 1031 translation",
        geodesyTranslationTiming[0].total!"nsecs",
        projTranslationTiming[0].total!"nsecs",
        benchmarkOperations);

    writeln();

    reportComparison(
        "EPSG 1033 Position Vector",
        geodesyPositionVectorTiming[0].total!"nsecs",
        projPositionVectorTiming[0].total!"nsecs",
        benchmarkOperations);

    writeln();

    reportComparison(
        "EPSG 1032 Coordinate Frame",
        geodesyCoordinateFrameTiming[0].total!"nsecs",
        projCoordinateFrameTiming[0].total!"nsecs",
        benchmarkOperations);

    writefln(
        "\nbenchmark sink: %.17g",
        benchmarkSink);

}
