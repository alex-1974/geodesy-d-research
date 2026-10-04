module geodesy.research.f001_reference_probe;

import geodesy;
import std.algorithm : max;
import std.conv : to;
import std.file : readText;
import std.math : PI, abs, asin, cos, isFinite, sin, sqrt;
import std.stdio : writeln;
import std.string : split, splitLines, strip;

private enum real ELLIPSOID_A = 7_000_000.0L;
private enum real ELLIPSOID_F = 0.01L;
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
    size_t directRows = 0;
    size_t inverseRows = 0;
    real maxDirectPosition = 0;
    real maxDirectTangent = 0;
    real maxInverseDistance = 0;
    real maxInverseClosure = 0;
}

private Summary validateCorpus(T)(const string dataPath)
{
    const ellipsoid = Ellipsoid!T.fromFlattening(
        cast(T) ELLIPSOID_A,
        cast(T) ELLIPSOID_F);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    Summary summary;

    foreach (rawLine; readText(dataPath).splitLines())
    {
        const line = rawLine.strip();

        if (line.length == 0 || line[0] == '#')
            continue;

        const fields = line.split();

        if (fields.length != 15)
            throw new Exception("unexpected f=0.01 GEO-B field count");

        const string mode = fields[0];

        const real lat1 = to!real(fields[3]);
        const real lon1 = to!real(fields[4]);
        const real azi1 = to!real(fields[5]);
        const real lat2 = to!real(fields[6]);
        const real lon2 = to!real(fields[7]);
        const real azi2 = to!real(fields[8]);
        const real s12 = to!real(fields[9]);

        const start = point!T(lat1, lon1);
        const end = point!T(lat2, lon2);

        const real refLat = degToRad(lat2);
        const real refLon = degToRad(lon2);
        const real refAzi = degToRad(azi2);

        if (mode == "direct")
        {
            GeodesicDirectResult!T direct;

            if (!solver.tryDirect(
                    start,
                    azimuth!T(azi1),
                    cast(T) s12,
                    direct))
                throw new Exception("f=0.01 GEO-B direct failed");

            const real positionError = positionAngle(
                cast(real) direct.position.latitude.radians,
                cast(real) direct.position.longitude.radians,
                refLat,
                refLon);

            const real tangentError = tangentAngle(
                cast(real) direct.position.latitude.radians,
                cast(real) direct.position.longitude.radians,
                cast(real) direct.finalAzimuth.radians,
                refLat,
                refLon,
                refAzi);

            if (!isFinite(positionError) || !isFinite(tangentError))
                throw new Exception("f=0.01 GEO-B direct metric non-finite");

            summary.maxDirectPosition =
                max(summary.maxDirectPosition, positionError);
            summary.maxDirectTangent =
                max(summary.maxDirectTangent, tangentError);

            if (positionError > LIMIT || tangentError > LIMIT)
                throw new Exception("f=0.01 GEO-B direct mismatch");

            ++summary.directRows;
        }
        else if (mode == "inverse")
        {
            GeodesicInverseResult!T inverse;

            if (!solver.tryInverse(start, end, inverse))
                throw new Exception("f=0.01 GEO-B inverse failed");

            const real distanceError =
                abs(cast(real) inverse.distance - s12) / ELLIPSOID_A;

            if (!isFinite(distanceError))
                throw new Exception(
                    "f=0.01 GEO-B inverse distance metric non-finite");

            summary.maxInverseDistance =
                max(summary.maxInverseDistance, distanceError);

            if (distanceError > LIMIT)
                throw new Exception("f=0.01 GEO-B inverse distance mismatch");

            GeodesicDirectResult!T closure;

            if (!solver.tryDirect(
                    start,
                    inverse.initialAzimuth,
                    inverse.distance,
                    closure))
                throw new Exception(
                    "f=0.01 GEO-B inverse closure direct failed");

            const real closureError = positionAngle(
                cast(real) closure.position.latitude.radians,
                cast(real) closure.position.longitude.radians,
                refLat,
                refLon);

            if (!isFinite(closureError))
                throw new Exception(
                    "f=0.01 GEO-B inverse closure metric non-finite");

            summary.maxInverseClosure =
                max(summary.maxInverseClosure, closureError);

            if (closureError > LIMIT)
                throw new Exception("f=0.01 GEO-B inverse closure mismatch");

            ++summary.inverseRows;
        }
        else
        {
            throw new Exception("unknown f=0.01 GEO-B mode");
        }
    }

    return summary;
}

private void printSummary(const string scalar, const Summary summary)
{
    writeln("scalar: ", scalar);
    writeln("direct rows: ", summary.directRows);
    writeln("inverse rows: ", summary.inverseRows);
    writeln("max direct position angle [rad]: ", summary.maxDirectPosition);
    writeln("max direct tangent angle [rad]: ", summary.maxDirectTangent);
    writeln("max inverse normalized distance error: ", summary.maxInverseDistance);
    writeln("max inverse closure angle [rad]: ", summary.maxInverseClosure);
}

void main(string[] args)
{
    if (args.length != 2)
        throw new Exception(
            "usage: f001_reference_probe <f001-reference.tsv>");

    const doubleSummary = validateCorpus!double(args[1]);
    const realSummary = validateCorpus!real(args[1]);

    assert(doubleSummary.directRows == 12);
    assert(doubleSummary.inverseRows == 14);
    assert(realSummary.directRows == 12);
    assert(realSummary.inverseRows == 14);

    printSummary("double", doubleSummary);
    printSummary("real", realSummary);

    writeln("GEO-B f=0.01 MPFR RESULT: PASS");
}
