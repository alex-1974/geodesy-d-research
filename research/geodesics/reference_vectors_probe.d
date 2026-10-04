module geodesy.research.reference_vectors_probe;

import geodesy;
import std.algorithm : max;
import std.conv : to;
import std.file : readText;
import std.math : PI, abs, asin, cos, isFinite, sin, sqrt;
import std.stdio : writeln;
import std.string : split, splitLines, strip;

private enum real WGS84_A = 6_378_137.0L;
private enum real WGS84_F = 1.0L / 298.257223563L;
private enum real LIMIT = 2.0e-10L;

private real degToRad(const real degrees) pure nothrow @safe @nogc
{
    return degrees * PI / 180.0L;
}

private real clampUnit(const real x) pure nothrow @safe @nogc
{
    if (x < -1.0L)
        return -1.0L;
    if (x > 1.0L)
        return 1.0L;
    return x;
}

private real positionAngle(
    const real latA,
    const real lonA,
    const real latB,
    const real lonB)
    pure nothrow @safe @nogc
{
    const real ca = cos(latA);
    const real cb = cos(latB);

    const real ax = ca * cos(lonA);
    const real ay = ca * sin(lonA);
    const real az = sin(latA);

    const real bx = cb * cos(lonB);
    const real by = cb * sin(lonB);
    const real bz = sin(latB);

    const real dx = ax - bx;
    const real dy = ay - by;
    const real dz = az - bz;
    const real chord = sqrt(dx * dx + dy * dy + dz * dz);

    return 2.0L * asin(clampUnit(chord / 2.0L));
}

private void tangent(
    const real lat,
    const real lon,
    const real azi,
    out real x,
    out real y,
    out real z)
    pure nothrow @safe @nogc
{
    const real slat = sin(lat);
    const real clat = cos(lat);
    const real slon = sin(lon);
    const real clon = cos(lon);
    const real sazi = sin(azi);
    const real cazi = cos(azi);

    const real nx = -slat * clon;
    const real ny = -slat * slon;
    const real nz = clat;

    const real ex = -slon;
    const real ey = clon;

    x = cazi * nx + sazi * ex;
    y = cazi * ny + sazi * ey;
    z = cazi * nz;
}

private real tangentAngle(
    const real latA,
    const real lonA,
    const real aziA,
    const real latB,
    const real lonB,
    const real aziB)
    pure nothrow @safe @nogc
{
    real ax, ay, az;
    real bx, by, bz;

    tangent(latA, lonA, aziA, ax, ay, az);
    tangent(latB, lonB, aziB, bx, by, bz);

    const real dx = ax - bx;
    const real dy = ay - by;
    const real dz = az - bz;
    const real chord = sqrt(dx * dx + dy * dy + dz * dz);

    return 2.0L * asin(clampUnit(chord / 2.0L));
}

private GeographicCoordinate!T point(T)(
    const real latitudeDegrees,
    const real longitudeDegrees)
{
    return GeographicCoordinate!T.fromComponents(
        Latitude!T.fromDegrees(cast(T) latitudeDegrees),
        Longitude!T.fromDegrees(cast(T) longitudeDegrees));
}

private Angle!T azimuth(T)(const real degrees)
{
    return Angle!T.fromDegrees(cast(T) degrees);
}

private struct Summary
{
    size_t rows = 0;
    real maxDirectPosition = 0;
    real maxDirectTangent = 0;
    real maxInverseDistance = 0;
    real maxInverseClosure = 0;
}

private Summary validateGeodTest(T)(const string dataPath)
{
    const ellipsoid = Ellipsoid!T.fromFlattening(
        cast(T) WGS84_A,
        cast(T) WGS84_F);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    Summary summary;

    foreach (rawLine; readText(dataPath).splitLines())
    {
        const line = rawLine.strip();

        if (line.length == 0 || line[0] == '#')
            continue;

        const fields = line.split();

        if (fields.length != 12)
            throw new Exception("unexpected GEO-B data field count");

        const real lat1 = to!real(fields[2]);
        const real lon1 = to!real(fields[3]);
        const real azi1 = to!real(fields[4]);
        const real lat2 = to!real(fields[5]);
        const real lon2 = to!real(fields[6]);
        const real azi2 = to!real(fields[7]);
        const real s12 = to!real(fields[8]);

        const start = point!T(lat1, lon1);
        const end = point!T(lat2, lon2);

        GeodesicDirectResult!T direct;

        if (!solver.tryDirect(
                start,
                azimuth!T(azi1),
                cast(T) s12,
                direct))
            throw new Exception("GEO-B direct operation failed");

        const real directLat = cast(real) direct.position.latitude.radians;
        const real directLon = cast(real) direct.position.longitude.radians;
        const real directAzi = cast(real) direct.finalAzimuth.radians;

        const real refLat = degToRad(lat2);
        const real refLon = degToRad(lon2);
        const real refAzi = degToRad(azi2);

        const real directPositionError =
            positionAngle(directLat, directLon, refLat, refLon);

        const real directTangentError =
            tangentAngle(
                directLat,
                directLon,
                directAzi,
                refLat,
                refLon,
                refAzi);

        if (!isFinite(directPositionError) ||
            !isFinite(directTangentError))
            throw new Exception("GEO-B direct metric is non-finite");

        summary.maxDirectPosition =
            max(summary.maxDirectPosition, directPositionError);
        summary.maxDirectTangent =
            max(summary.maxDirectTangent, directTangentError);

        if (directPositionError > LIMIT ||
            directTangentError > LIMIT)
            throw new Exception("GEO-B direct reference mismatch");

        GeodesicInverseResult!T inverse;

        if (!solver.tryInverse(start, end, inverse))
            throw new Exception("GEO-B inverse operation failed");

        const real inverseDistanceError =
            abs(cast(real) inverse.distance - s12) / WGS84_A;

        if (!isFinite(inverseDistanceError))
            throw new Exception("GEO-B inverse distance metric is non-finite");

        summary.maxInverseDistance =
            max(summary.maxInverseDistance, inverseDistanceError);

        if (inverseDistanceError > LIMIT)
            throw new Exception("GEO-B inverse distance mismatch");

        GeodesicDirectResult!T closure;

        if (!solver.tryDirect(
                start,
                inverse.initialAzimuth,
                inverse.distance,
                closure))
            throw new Exception("GEO-B inverse closure direct failed");

        const real closureError = positionAngle(
            cast(real) closure.position.latitude.radians,
            cast(real) closure.position.longitude.radians,
            refLat,
            refLon);

        if (!isFinite(closureError))
            throw new Exception("GEO-B inverse closure metric is non-finite");

        summary.maxInverseClosure =
            max(summary.maxInverseClosure, closureError);

        if (closureError > LIMIT)
            throw new Exception("GEO-B inverse closure mismatch");

        ++summary.rows;
    }

    return summary;
}

private void validateSphere()
{
    enum real A = 6_371_000.0L;

    const ellipsoid = Ellipsoid!real.fromFlattening(A, 0.0L);
    const solver = Geodesic!real.fromEllipsoid(ellipsoid);

    // Exact equatorial quarter-circle inverse.
    {
        GeodesicInverseResult!real inverse;

        assert(solver.tryInverse(
            point!real(0.0L, 0.0L),
            point!real(0.0L, 90.0L),
            inverse));

        assert(abs(inverse.distance - A * PI / 2.0L) / A < 5e-18L);
        assert(abs(inverse.initialAzimuth.radians - PI / 2.0L) < 5e-18L);
        assert(abs(inverse.finalAzimuth.radians - PI / 2.0L) < 5e-18L);
    }

    // Exact meridional 30-degree inverse.
    {
        GeodesicInverseResult!real inverse;

        assert(solver.tryInverse(
            point!real(10.0L, 20.0L),
            point!real(40.0L, 20.0L),
            inverse));

        assert(abs(inverse.distance - A * PI / 6.0L) / A < 5e-18L);
        assert(abs(inverse.initialAzimuth.radians) < 5e-18L);
        assert(abs(inverse.finalAzimuth.radians) < 5e-18L);
    }

    // Exact equatorial quarter-circle direct.
    {
        GeodesicDirectResult!real direct;

        assert(solver.tryDirect(
            point!real(0.0L, 0.0L),
            azimuth!real(90.0L),
            A * PI / 2.0L,
            direct));

        assert(positionAngle(
            direct.position.latitude.radians,
            direct.position.longitude.radians,
            0.0L,
            PI / 2.0L) < 5e-18L);
    }

    // Negative direct distance travels backwards on the same oriented line.
    {
        GeodesicDirectResult!real direct;

        assert(solver.tryDirect(
            point!real(0.0L, 0.0L),
            azimuth!real(90.0L),
            -A * PI / 2.0L,
            direct));

        assert(positionAngle(
            direct.position.latitude.radians,
            direct.position.longitude.radians,
            0.0L,
            -PI / 2.0L) < 5e-18L);
        assert(abs(direct.finalAzimuth.radians - PI / 2.0L) < 5e-18L);
    }
}

private void validatePublishedExamples()
{
    const ellipsoid = Ellipsoid!real.fromFlattening(
        WGS84_A,
        WGS84_F);
    const solver = Geodesic!real.fromEllipsoid(ellipsoid);

    // GeographicLib tutorial: Wellington -> Salamanca inverse.
    {
        GeodesicInverseResult!real inverse;

        assert(solver.tryInverse(
            point!real(-41.32L, 174.81L),
            point!real(40.96L, -5.50L),
            inverse));

        // Published to nearest millimetre.
        assert(abs(inverse.distance - 19_959_679.267L) <= 0.0006L);
    }

    // GeographicLib tutorial: Perth direct example.
    {
        GeodesicDirectResult!real direct;

        assert(solver.tryDirect(
            point!real(-32.06L, 115.74L),
            azimuth!real(225.0L),
            20_000_000.0L,
            direct));

        // Endpoint is published to 8 decimal degrees.
        assert(positionAngle(
            direct.position.latitude.radians,
            direct.position.longitude.radians,
            degToRad(32.11195529L),
            degToRad(-63.95925278L)) <= degToRad(1.0e-8L));
    }
}

private void printSummary(const string scalar, const Summary summary)
{
    writeln("scalar: ", scalar);
    writeln("reference rows: ", summary.rows);
    writeln("max direct position angle [rad]: ", summary.maxDirectPosition);
    writeln("max direct tangent angle [rad]: ", summary.maxDirectTangent);
    writeln("max inverse normalized distance error: ", summary.maxInverseDistance);
    writeln("max inverse closure angle [rad]: ", summary.maxInverseClosure);
}

void main(string[] args)
{
    if (args.length != 2)
        throw new Exception(
            "usage: reference_vectors_probe <geodtest-subset.tsv>");

    validateSphere();
    validatePublishedExamples();

    const doubleSummary =
        validateGeodTest!double(args[1]);
    const realSummary =
        validateGeodTest!real(args[1]);

    printSummary("double", doubleSummary);
    printSummary("real", realSummary);

    writeln("sphere analytical cases: PASS");
    writeln("published smoke examples: PASS");
    writeln("GEO-B WGS84 RESULT: PASS (PARTIAL GEO-B)");
}

