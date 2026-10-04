module geodesy.research.topocentric.epsg_reference_probe;

import std.math : PI, abs, atan2, cos, sin, sqrt;
import std.stdio : writefln, writeln;

private enum real WGS84_A = 6_378_137.0L;
private enum real WGS84_F = 1.0L / 298.257223563L;
private enum real WGS84_E2 =
    WGS84_F * (2.0L - WGS84_F);

private struct Vec3
{
    real x;
    real y;
    real z;
}

private struct Geodetic
{
    real latitude;
    real longitude;
    real height;
}

private real degToRad(const real degrees)
    pure nothrow @safe @nogc
{
    return degrees * PI / 180.0L;
}

private real dmsToDegrees(
    const real degrees,
    const real minutes,
    const real seconds)
    pure nothrow @safe @nogc
{
    return degrees + minutes / 60.0L + seconds / 3600.0L;
}

private void requireClose(
    const string label,
    const real actual,
    const real expected,
    const real tolerance)
{
    const real error = abs(actual - expected);

    writefln(
        "%-40s actual=%.21g expected=%.21g error=%.6e",
        label,
        actual,
        expected,
        error);

    if (error > tolerance)
        throw new Exception(label ~ " outside tolerance");
}


/*
 * Independent EPSG 9602 forward reference formula.
 *
 * This probe deliberately does not call geodesy-d production code.
 */
private Vec3 geodeticToGeocentric(const Geodetic source)
    pure nothrow @safe @nogc
{
    const real sinPhi = sin(source.latitude);
    const real cosPhi = cos(source.latitude);
    const real sinLambda = sin(source.longitude);
    const real cosLambda = cos(source.longitude);

    const real nu =
        WGS84_A
        / sqrt(1.0L - WGS84_E2 * sinPhi * sinPhi);

    return Vec3(
        (nu + source.height) * cosPhi * cosLambda,
        (nu + source.height) * cosPhi * sinLambda,
        ((1.0L - WGS84_E2) * nu + source.height) * sinPhi);
}


/*
 * Independent ordinary-position EPSG 9602 reverse reference.
 *
 * This is intentionally a simple iterative research implementation suitable
 * for the published North Sea worked example. It is not proposed production
 * code and is not intended to replace geodesy-d's robust inverse kernel.
 */
private Geodetic geocentricToGeodetic(const Vec3 source)
    pure nothrow @safe @nogc
{
    const real horizontal =
        sqrt(source.x * source.x + source.y * source.y);

    const real longitude =
        atan2(source.y, source.x);

    real latitude =
        atan2(
            source.z,
            horizontal * (1.0L - WGS84_E2));

    foreach (_; 0 .. 32)
    {
        const real sinPhi = sin(latitude);

        const real nu =
            WGS84_A
            / sqrt(1.0L - WGS84_E2 * sinPhi * sinPhi);

        const real height =
            horizontal / cos(latitude) - nu;

        latitude =
            atan2(
                source.z,
                horizontal
                    * (1.0L
                        - WGS84_E2 * nu / (nu + height)));
    }

    const real sinPhi = sin(latitude);
    const real nu =
        WGS84_A
        / sqrt(1.0L - WGS84_E2 * sinPhi * sinPhi);

    const real height =
        horizontal / cos(latitude) - nu;

    return Geodetic(latitude, longitude, height);
}


/*
 * EPSG 9836 forward: geocentric -> topocentric.
 */
private Vec3 geocentricToTopocentric(
    const Vec3 source,
    const Vec3 origin,
    const real originLatitude,
    const real originLongitude)
    pure nothrow @safe @nogc
{
    const real dX = source.x - origin.x;
    const real dY = source.y - origin.y;
    const real dZ = source.z - origin.z;

    const real sinPhi = sin(originLatitude);
    const real cosPhi = cos(originLatitude);
    const real sinLambda = sin(originLongitude);
    const real cosLambda = cos(originLongitude);

    return Vec3(
        -dX * sinLambda
            + dY * cosLambda,

        -dX * sinPhi * cosLambda
            - dY * sinPhi * sinLambda
            + dZ * cosPhi,

        dX * cosPhi * cosLambda
            + dY * cosPhi * sinLambda
            + dZ * sinPhi);
}


/*
 * EPSG 9836 reverse: topocentric -> geocentric.
 *
 * The inverse rotation is the transpose of the orthonormal forward rotation.
 */
private Vec3 topocentricToGeocentric(
    const Vec3 source,
    const Vec3 origin,
    const real originLatitude,
    const real originLongitude)
    pure nothrow @safe @nogc
{
    const real east = source.x;
    const real north = source.y;
    const real up = source.z;

    const real sinPhi = sin(originLatitude);
    const real cosPhi = cos(originLatitude);
    const real sinLambda = sin(originLongitude);
    const real cosLambda = cos(originLongitude);

    return Vec3(
        origin.x
            - east * sinLambda
            - north * sinPhi * cosLambda
            + up * cosPhi * cosLambda,

        origin.y
            + east * cosLambda
            - north * sinPhi * sinLambda
            + up * cosPhi * sinLambda,

        origin.z
            + north * cosPhi
            + up * sinPhi);
}


void main()
{
    /*
     * IOGP Guidance Note 7-2 / EPSG 9836 and 9837 worked example.
     */
    const real originLatitude = degToRad(55.0L);
    const real originLongitude = degToRad(5.0L);

    const Geodetic geodeticOrigin = Geodetic(
        originLatitude,
        originLongitude,
        200.0L);

    const Geodetic geodeticSource = Geodetic(
        degToRad(dmsToDegrees(53.0L, 48.0L, 33.820L)),
        degToRad(dmsToDegrees(2.0L, 7.0L, 46.380L)),
        73.0L);

    const Vec3 publishedOrigin = Vec3(
        3_652_755.3058L,
          319_574.6799L,
        5_201_547.3536L);

    const Vec3 publishedSource = Vec3(
        3_771_793.968L,
          140_253.342L,
        5_124_304.349L);

    const Vec3 publishedTopocentric = Vec3(
        -189_013.869L,
        -128_642.040L,
          -4_220.171L);

    /*
     * First verify the independent EPSG 9602 forward formula reproduces the
     * rounded geocentric values used by the published example.
     */
    writeln("=== EPSG 9602 reference preparation ===");

    const Vec3 computedOrigin =
        geodeticToGeocentric(geodeticOrigin);

    const Vec3 computedSource =
        geodeticToGeocentric(geodeticSource);

    requireClose(
        "origin X",
        computedOrigin.x,
        publishedOrigin.x,
        0.001L);
    requireClose(
        "origin Y",
        computedOrigin.y,
        publishedOrigin.y,
        0.001L);
    requireClose(
        "origin Z",
        computedOrigin.z,
        publishedOrigin.z,
        0.001L);

    requireClose(
        "source X",
        computedSource.x,
        publishedSource.x,
        0.001L);
    requireClose(
        "source Y",
        computedSource.y,
        publishedSource.y,
        0.001L);
    requireClose(
        "source Z",
        computedSource.z,
        publishedSource.z,
        0.001L);

    /*
     * EPSG 9836 directly from the published rounded ECEF coordinates.
     */
    writeln();
    writeln("=== EPSG 9836 forward ===");

    const Vec3 topo9836 =
        geocentricToTopocentric(
            publishedSource,
            publishedOrigin,
            originLatitude,
            originLongitude);

    requireClose(
        "9836 East",
        topo9836.x,
        publishedTopocentric.x,
        0.001L);
    requireClose(
        "9836 North",
        topo9836.y,
        publishedTopocentric.y,
        0.001L);
    requireClose(
        "9836 Up",
        topo9836.z,
        publishedTopocentric.z,
        0.001L);

    writeln();
    writeln("=== EPSG 9836 reverse ===");

    const Vec3 reverse9836 =
        topocentricToGeocentric(
            publishedTopocentric,
            publishedOrigin,
            originLatitude,
            originLongitude);

    requireClose(
        "9836 reverse X",
        reverse9836.x,
        publishedSource.x,
        0.001L);
    requireClose(
        "9836 reverse Y",
        reverse9836.y,
        publishedSource.y,
        0.001L);
    requireClose(
        "9836 reverse Z",
        reverse9836.z,
        publishedSource.z,
        0.001L);

    /*
     * EPSG 9837 composition from exact represented geographic input, without
     * using the rounded published ECEF intermediates.
     */
    writeln();
    writeln("=== EPSG 9837 forward ===");

    const Vec3 topo9837 =
        geocentricToTopocentric(
            computedSource,
            computedOrigin,
            originLatitude,
            originLongitude);

    requireClose(
        "9837 East",
        topo9837.x,
        publishedTopocentric.x,
        0.001L);
    requireClose(
        "9837 North",
        topo9837.y,
        publishedTopocentric.y,
        0.001L);
    requireClose(
        "9837 Up",
        topo9837.z,
        publishedTopocentric.z,
        0.001L);

    writeln();
    writeln("=== EPSG 9837 reverse ===");

    const Vec3 reverse9837Ecef =
        topocentricToGeocentric(
            publishedTopocentric,
            computedOrigin,
            originLatitude,
            originLongitude);

    const Geodetic reverse9837 =
        geocentricToGeodetic(reverse9837Ecef);

    /*
     * Geographic input angles in the publication are rounded to 0.001 arcsec.
     * 5e-9 rad is approximately that angular resolution.
     */
    requireClose(
        "9837 reverse latitude",
        reverse9837.latitude,
        geodeticSource.latitude,
        5.0e-9L);
    requireClose(
        "9837 reverse longitude",
        reverse9837.longitude,
        geodeticSource.longitude,
        5.0e-9L);
    requireClose(
        "9837 reverse height",
        reverse9837.height,
        geodeticSource.height,
        0.005L);

    writeln();
    writeln("PASS: EPSG 9836 / 9837 published reference vectors");
}
