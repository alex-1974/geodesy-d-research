module app;

import geodesy;

import std.math :
    PI,
    atan2,
    cos,
    fabs,
    isFinite,
    sin,
    sqrt;

import std.stdio : writefln, writeln;


struct RawGeodetic
{
    double latitude;
    double longitude;
    double height;
}


struct ErrorEnvelope
{
    double latitude = 0.0;
    double longitude = 0.0;
    double height = 0.0;

    void observe(
        const RawGeodetic actual,
        const GeodeticCoordinate!double expected)
    {
        const double latitudeError =
            fabs(
                actual.latitude -
                expected.latitude.radians);

        const double longitudeError =
            fabs(
                normalizedLongitudeDifference(
                    actual.longitude,
                    expected.longitude.radians));

        const double heightError =
            fabs(
                actual.height -
                expected.ellipsoidalHeight);

        if (latitudeError > latitude)
            latitude = latitudeError;

        if (longitudeError > longitude)
            longitude = longitudeError;

        if (heightError > height)
            height = heightError;
    }
}

static assert(ErrorEnvelope.init.latitude == 0.0);
static assert(ErrorEnvelope.init.longitude == 0.0);
static assert(ErrorEnvelope.init.height == 0.0);


double hypot2(
    const double x,
    const double y)
{
    const double ax = fabs(x);
    const double ay = fabs(y);
    const double hi = ax >= ay ? ax : ay;
    const double lo = ax >= ay ? ay : ax;

    if (hi == 0.0)
        return 0.0;

    const double ratio = lo / hi;

    return
        hi *
        sqrt(1.0 + ratio * ratio);
}


double normalizedLongitudeDifference(
    double lhs,
    double rhs)
{
    double difference = lhs - rhs;

    while (difference > PI)
        difference -= 2.0 * PI;

    while (difference < -PI)
        difference += 2.0 * PI;

    return difference;
}


double bowringSeed(
    const double p,
    const double z,
    const Ellipsoid!double ellipsoid)
{
    const double a =
        ellipsoid.semiMajorAxis;

    const double b =
        ellipsoid.semiMinorAxis;

    const double e2 =
        ellipsoid.firstEccentricitySquared;

    const double oneMinusE2 =
        1.0 - e2;

    const double secondEccentricitySquared =
        e2 / oneMinusE2;

    const double q =
        atan2(
            z / b,
            p / a);

    const double sinQ = sin(q);
    const double cosQ = cos(q);

    return atan2(
        z +
            secondEccentricitySquared *
            b *
            sinQ *
            sinQ *
            sinQ,
        p -
            e2 *
            a *
            cosQ *
            cosQ *
            cosQ);
}


double refineLatitude(
    const double p,
    const double z,
    const Ellipsoid!double ellipsoid,
    const double phi)
{
    const double a =
        ellipsoid.semiMajorAxis;

    const double e2 =
        ellipsoid.firstEccentricitySquared;

    const double sinPhi =
        sin(phi);

    const double nu =
        a /
        sqrt(
            1.0 -
            e2 *
            sinPhi *
            sinPhi);

    return atan2(
        z +
            e2 *
            nu *
            sinPhi,
        p);
}


RawGeodetic inverseWithRefinements(
    const GeocentricCoordinate!double source,
    const Ellipsoid!double ellipsoid,
    const size_t refinements)
{
    const double x = source.x;
    const double y = source.y;
    const double z = source.z;

    const double a =
        ellipsoid.semiMajorAxis;

    const double b =
        ellipsoid.semiMinorAxis;

    const double e2 =
        ellipsoid.firstEccentricitySquared;

    const double oneMinusE2 =
        1.0 - e2;

    const double p =
        hypot2(x, y);

    if (p == 0.0)
    {
        return RawGeodetic(
            atan2(z, p),
            0.0,
            fabs(z) - b);
    }

    const double longitude =
        atan2(y, x);

    double phi =
        bowringSeed(
            p,
            z,
            ellipsoid);

    foreach (_; 0 .. refinements)
    {
        phi =
            refineLatitude(
                p,
                z,
                ellipsoid,
                phi);
    }

    const double sinPhi =
        sin(phi);

    const double cosPhi =
        cos(phi);

    const double nu =
        a /
        sqrt(
            1.0 -
            e2 *
            sinPhi *
            sinPhi);

    double height;

    if (fabs(cosPhi) >= fabs(sinPhi))
        height =
            p / cosPhi -
            nu;
    else
        height =
            z / sinPhi -
            oneMinusE2 *
            nu;

    return RawGeodetic(
        phi,
        longitude,
        height);
}


size_t iterationsUntilExactStability(
    const GeocentricCoordinate!double source,
    const Ellipsoid!double ellipsoid)
{
    const double p =
        hypot2(
            source.x,
            source.y);

    if (p == 0.0)
        return 0;

    double phi =
        bowringSeed(
            p,
            source.z,
            ellipsoid);

    foreach (iteration; 1 .. 9)
    {
        const double nextPhi =
            refineLatitude(
                p,
                source.z,
                ellipsoid,
                phi);

        if (nextPhi == phi)
            return iteration;

        phi = nextPhi;
    }

    return 9;
}


void observePoint(
    ref ErrorEnvelope[9] envelopes,
    ref size_t[10] stabilizationCounts,
    const GeodeticCoordinate!double source,
    const Ellipsoid!double ellipsoid)
{
    const xyz =
        geodeticToGeocentric(
            source,
            ellipsoid);

    foreach (refinementCount; 0 .. 9)
    {
        const candidate =
            inverseWithRefinements(
                xyz,
                ellipsoid,
                refinementCount);

        if (!isFinite(candidate.latitude)
            || !isFinite(candidate.longitude)
            || !isFinite(candidate.height))
            throw new Exception(
                "candidate inverse produced a non-finite result");

        envelopes[refinementCount].observe(
            candidate,
            source);
    }

    const size_t stabilization =
        iterationsUntilExactStability(
            xyz,
            ellipsoid);

    ++stabilizationCounts[stabilization];
}


void printResults(
    const char[] name,
    const ErrorEnvelope[9] envelopes,
    const size_t[10] stabilizationCounts)
{
    writeln();
    writeln(name);

    writeln(
        "refinements   max |dLat| rad       max |dLon| rad       max |dH| m");

    foreach (refinementCount; 0 .. 9)
    {
        const error =
            envelopes[refinementCount];

        writefln(
            "%11s   %17.10g   %17.10g   %17.10g",
            refinementCount,
            error.latitude,
            error.longitude,
            error.height);
    }

    writeln();
    writeln("exact-stabilization iteration distribution:");

    foreach (iteration; 0 .. 9)
    {
        if (stabilizationCounts[iteration] != 0)
        {
            writefln(
                "  %s: %s",
                iteration,
                stabilizationCounts[iteration]);
        }
    }

    if (stabilizationCounts[9] != 0)
    {
        writefln(
            "  >8: %s",
            stabilizationCounts[9]);
    }
}


void main()
{
    const earth =
        wgs84!double();

    /*
     * Dataset A:
     * identical latitude/longitude/height distribution to the existing
     * performance benchmark.
     */
    ErrorEnvelope[9] baselineErrors;
    size_t[10] baselineStabilization;

    enum size_t sampleCount = 8_192;

    foreach (i; 0 .. sampleCount)
    {
        const double fraction =
            cast(double) i /
            cast(double) (sampleCount - 1);

        const size_t longitudeIndex =
            (i * 4_051UL) %
            sampleCount;

        const double longitudeFraction =
            cast(double) longitudeIndex /
            cast(double) (sampleCount - 1);

        const source =
            GeodeticCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(
                    -89.0 +
                    178.0 *
                    fraction),
                Longitude!double.fromDegrees(
                    -180.0 +
                    360.0 *
                    longitudeFraction),
                cast(double) (i % 5_001UL) -
                    1_000.0);

        observePoint(
            baselineErrors,
            baselineStabilization,
            source,
            earth);
    }

    printResults(
        "Dataset A: existing 8192-point benchmark distribution",
        baselineErrors,
        baselineStabilization);

    /*
     * Dataset B:
     * height stress grid, including the existing 1000 km test domain
     * and higher orbital-scale heights.
     */
    ErrorEnvelope[9] stressErrors;
    size_t[10] stressStabilization;

    immutable double[] heights =
    [
        -1_000.0,
        0.0,
        1_000.0,
        100_000.0,
        1_000_000.0,
        10_000_000.0,
        35_786_000.0
    ];

    foreach (height; heights)
    {
        foreach (latitudeDegrees; -89 .. 90)
        {
            const source =
                GeodeticCoordinate!double.fromComponents(
                    Latitude!double.fromDegrees(
                        cast(double) latitudeDegrees),
                    Longitude!double.fromDegrees(
                        37.123456789),
                    height);

            observePoint(
                stressErrors,
                stressStabilization,
                source,
                earth);
        }

        foreach (latitudeDegrees;
            [-89.999999, 89.999999])
        {
            const source =
                GeodeticCoordinate!double.fromComponents(
                    Latitude!double.fromDegrees(
                        latitudeDegrees),
                    Longitude!double.fromDegrees(
                        -123.456789),
                    height);

            observePoint(
                stressErrors,
                stressStabilization,
                source,
                earth);
        }
    }

    printResults(
        "Dataset B: height and near-pole stress grid",
        stressErrors,
        stressStabilization);
}
