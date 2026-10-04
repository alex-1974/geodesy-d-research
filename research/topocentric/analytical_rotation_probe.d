module geodesy.research.topocentric.analytical_rotation_probe;

import std.math : PI, abs, cos, sin, sqrt;
import std.stdio : writeln;

private enum real EPS = 2.0e-15L;

private struct Vec3
{
    real x;
    real y;
    real z;
}

private struct Mat3
{
    real[3][3] m;
}

private real degToRad(const real degrees)
    pure nothrow @safe @nogc
{
    return degrees * PI / 180.0L;
}

private real dot(const Vec3 a, const Vec3 b)
    pure nothrow @safe @nogc
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

private real norm(const Vec3 v)
    pure nothrow @safe @nogc
{
    return sqrt(dot(v, v));
}

private Vec3 multiply(const Mat3 a, const Vec3 v)
    pure nothrow @safe @nogc
{
    return Vec3(
        a.m[0][0] * v.x + a.m[0][1] * v.y + a.m[0][2] * v.z,
        a.m[1][0] * v.x + a.m[1][1] * v.y + a.m[1][2] * v.z,
        a.m[2][0] * v.x + a.m[2][1] * v.y + a.m[2][2] * v.z);
}

private Mat3 multiply(const Mat3 a, const Mat3 b)
    pure nothrow @safe @nogc
{
    Mat3 result;

    foreach (i; 0 .. 3)
    {
        foreach (j; 0 .. 3)
        {
            real sum = 0;

            foreach (k; 0 .. 3)
                sum += a.m[i][k] * b.m[k][j];

            result.m[i][j] = sum;
        }
    }

    return result;
}

private Mat3 transpose(const Mat3 a)
    pure nothrow @safe @nogc
{
    Mat3 result;

    foreach (i; 0 .. 3)
        foreach (j; 0 .. 3)
            result.m[i][j] = a.m[j][i];

    return result;
}

private real determinant(const Mat3 a)
    pure nothrow @safe @nogc
{
    return
        a.m[0][0]
            * (a.m[1][1] * a.m[2][2]
                - a.m[1][2] * a.m[2][1])
        - a.m[0][1]
            * (a.m[1][0] * a.m[2][2]
                - a.m[1][2] * a.m[2][0])
        + a.m[0][2]
            * (a.m[1][0] * a.m[2][1]
                - a.m[1][1] * a.m[2][0]);
}


/*
 * Independent EPSG 9836 ECEF-difference -> ENU rotation matrix.
 *
 * Rows are East, North, Up basis vectors expressed in ECEF coordinates.
 */
private Mat3 enuRotation(
    const real latitude,
    const real longitude)
    pure nothrow @safe @nogc
{
    const real sinPhi = sin(latitude);
    const real cosPhi = cos(latitude);
    const real sinLambda = sin(longitude);
    const real cosLambda = cos(longitude);

    Mat3 result;

    result.m[0] = [
        -sinLambda,
         cosLambda,
         0.0L];

    result.m[1] = [
        -sinPhi * cosLambda,
        -sinPhi * sinLambda,
         cosPhi];

    result.m[2] = [
         cosPhi * cosLambda,
         cosPhi * sinLambda,
         sinPhi];

    return result;
}

private void requireClose(
    const string label,
    const real actual,
    const real expected,
    const real tolerance = EPS)
{
    if (abs(actual - expected) > tolerance)
        throw new Exception(label);
}

private void requireVector(
    const string label,
    const Vec3 actual,
    const Vec3 expected,
    const real tolerance = EPS)
{
    requireClose(label ~ ".x", actual.x, expected.x, tolerance);
    requireClose(label ~ ".y", actual.y, expected.y, tolerance);
    requireClose(label ~ ".z", actual.z, expected.z, tolerance);
}

private void validateOrthonormal(
    const real latitudeDegrees,
    const real longitudeDegrees)
{
    const Mat3 r =
        enuRotation(
            degToRad(latitudeDegrees),
            degToRad(longitudeDegrees));

    const Mat3 rt = transpose(r);

    const Mat3 left = multiply(r, rt);
    const Mat3 right = multiply(rt, r);

    foreach (i; 0 .. 3)
    {
        foreach (j; 0 .. 3)
        {
            const real expected = i == j ? 1.0L : 0.0L;

            requireClose(
                "R*Rt",
                left.m[i][j],
                expected);

            requireClose(
                "Rt*R",
                right.m[i][j],
                expected);
        }
    }

    requireClose(
        "det(R)",
        determinant(r),
        1.0L);

    const Vec3 displacement =
        Vec3(
            1_234.5L,
            -9_876.25L,
            432.125L);

    const Vec3 local = multiply(r, displacement);
    const Vec3 recovered = multiply(rt, local);

    requireClose(
        "norm preservation",
        norm(local),
        norm(displacement),
        2.0e-12L);

    requireVector(
        "transpose inverse",
        recovered,
        displacement,
        2.0e-12L);
}


void main()
{
    writeln("=== matrix invariants ===");

    foreach (const real latitude; [
        -90.0L,
        -80.0L,
        -45.0L,
        0.0L,
        45.0L,
        80.0L,
        90.0L])
    {
        foreach (const real longitude; [
            -180.0L,
            -90.0L,
            -1.0L,
            0.0L,
            1.0L,
            90.0L,
            180.0L])
        {
            validateOrthonormal(latitude, longitude);
        }
    }

    writeln("PASS: orthonormality / determinant / transpose inverse / norm");


    writeln("=== equatorial cardinal directions ===");

    {
        const Mat3 r = enuRotation(0.0L, 0.0L);

        requireVector(
            "equator east",
            multiply(r, Vec3(0.0L, 1.0L, 0.0L)),
            Vec3(1.0L, 0.0L, 0.0L));

        requireVector(
            "equator north",
            multiply(r, Vec3(0.0L, 0.0L, 1.0L)),
            Vec3(0.0L, 1.0L, 0.0L));

        requireVector(
            "equator up",
            multiply(r, Vec3(1.0L, 0.0L, 0.0L)),
            Vec3(0.0L, 0.0L, 1.0L));
    }

    writeln("PASS: equatorial East/North/Up signs");


    writeln("=== north-pole orientation ===");

    {
        const Mat3 r0 =
            enuRotation(degToRad(90.0L), 0.0L);

        requireVector(
            "north pole lon0 east",
            multiply(r0, Vec3(0.0L, 1.0L, 0.0L)),
            Vec3(1.0L, 0.0L, 0.0L));

        requireVector(
            "north pole lon0 north",
            multiply(r0, Vec3(-1.0L, 0.0L, 0.0L)),
            Vec3(0.0L, 1.0L, 0.0L));

        requireVector(
            "north pole lon0 up",
            multiply(r0, Vec3(0.0L, 0.0L, 1.0L)),
            Vec3(0.0L, 0.0L, 1.0L));

        const Mat3 r90 =
            enuRotation(
                degToRad(90.0L),
                degToRad(90.0L));

        requireVector(
            "north pole lon90 east",
            multiply(r90, Vec3(-1.0L, 0.0L, 0.0L)),
            Vec3(1.0L, 0.0L, 0.0L));

        requireVector(
            "north pole lon90 north",
            multiply(r90, Vec3(0.0L, -1.0L, 0.0L)),
            Vec3(0.0L, 1.0L, 0.0L));

        requireVector(
            "north pole lon90 up",
            multiply(r90, Vec3(0.0L, 0.0L, 1.0L)),
            Vec3(0.0L, 0.0L, 1.0L));
    }

    writeln("PASS: explicit polar longitude rotates East/North orientation");


    writeln("=== origin translation ===");

    {
        const Vec3 origin =
            Vec3(
                3_652_755.3058L,
                319_574.6799L,
                5_201_547.3536L);

        const Vec3 displacement =
            Vec3(
                origin.x - origin.x,
                origin.y - origin.y,
                origin.z - origin.z);

        const Mat3 r =
            enuRotation(
                degToRad(55.0L),
                degToRad(5.0L));

        requireVector(
            "origin -> zero",
            multiply(r, displacement),
            Vec3(0.0L, 0.0L, 0.0L));
    }

    writeln("PASS: frame origin maps to ENU zero");

    writeln();
    writeln("PASS: analytical EPSG 9836 rotation invariants");
}
