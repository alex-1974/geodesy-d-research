module geodesy.internal.area_validation_probe;

import std.math :
    PI,
    fabs;

import std.stdio :
    writefln,
    writeln;

import geodesy.internal.geodesic_inverse_dispatch :
    geodesicInverseArea,
    geodesicInverseDispatch;

import geodesy.internal.geodesic_series :
    fillGeodesicA3x,
    fillGeodesicC3x;


extern(C) int geodesic_area_reference_inverse(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double latitude2Radians,
    double longitude2Radians,
    double* signedArea);


struct Prepared
{
    double a;
    double f;
    double f1;
    double b;
    double ep2;
    double n;
    double[8] a3x;
    double[28] c3x;
}


Prepared prepare(
    const double a,
    const double f)
{
    Prepared result;

    result.a = a;
    result.f = f;
    result.f1 = 1.0 - f;
    result.b = a * result.f1;

    const double e2 =
        f * (2.0 - f);

    result.ep2 =
        e2
        / (result.f1 * result.f1);

    result.n =
        f / (2.0 - f);

    fillGeodesicA3x!(
        double,
        6)(
            result.n,
            result.a3x);

    fillGeodesicC3x!(
        double,
        6)(
            result.n,
            result.c3x);

    return result;
}


struct Case
{
    const(char)[] name;
    double a;
    double f;
    double lat1;
    double lon1;
    double lat2;
    double lon2;
}


void checkCase(
    const Case item,
    ref size_t failures)
{
    const state =
        prepare(
            item.a,
            item.f);

    const actual =
        geodesicInverseDispatch!(
            double,
            6,
            geodesicInverseArea)(
                state.a,
                state.f,
                state.f1,
                state.b,
                state.ep2,
                state.n,
                state.a3x,
                state.c3x,
                item.lat1,
                item.lon1,
                item.lat2,
                item.lon2);

    double expected;

    const int referenceOk =
        geodesic_area_reference_inverse(
            item.a,
            item.f,
            item.lat1,
            item.lon1,
            item.lat2,
            item.lon2,
            &expected);

    if (!referenceOk)
    {
        writefln(
            "FAIL %-22s GeographicLib reference failed",
            item.name);

        ++failures;
        return;
    }

    const double error =
        fabs(
            actual.signedArea
            - expected);

    const double magnitude =
        fabs(expected) > item.a * item.a
        ? fabs(expected)
        : item.a * item.a;

    /*
     * This is a research acceptance envelope, not the eventual release
     * tolerance.  It is deliberately tight enough to expose sign, quadrant,
     * and C4 transcription errors while accommodating series/reference
     * rounding at O(a^2).
     */
    const double tolerance =
        1.0e-14 * magnitude
        + 1.0e-6;

    const bool pass =
        error <= tolerance;

    writefln(
        "%s %-22s actual=% .17e expected=% .17e abs=% .6e tol=% .6e",
        pass ? "PASS" : "FAIL",
        item.name,
        actual.signedArea,
        expected,
        error,
        tolerance);

    if (!pass)
        ++failures;
}


void main()
{
    enum double d2r =
        cast(double) PI / 180.0;

    Case[] cases = [
        Case(
            "ordinary-vienna-graz",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            47.07071 * d2r,
            15.43950 * d2r),
        Case(
            "ordinary-reversed",
            6_378_137.0,
            1.0 / 298.257223563,
            47.07071 * d2r,
            15.43950 * d2r,
            48.20849 * d2r,
            16.37208 * d2r),
        Case(
            "antimeridian",
            6_378_137.0,
            1.0 / 298.257223563,
            25.0 * d2r,
            179.7 * d2r,
            -18.0 * d2r,
            -179.4 * d2r),
        Case(
            "near-antipodal",
            6_378_137.0,
            1.0 / 298.257223563,
            12.0 * d2r,
            20.0 * d2r,
            -12.0002 * d2r,
            -160.0003 * d2r),
        Case(
            "meridian",
            6_378_137.0,
            1.0 / 298.257223563,
            -40.0 * d2r,
            70.0 * d2r,
            30.0 * d2r,
            70.0 * d2r),
        Case(
            "equator",
            6_378_137.0,
            1.0 / 298.257223563,
            0.0,
            -30.0 * d2r,
            0.0,
            80.0 * d2r),
        Case(
            "coincident",
            6_378_137.0,
            1.0 / 298.257223563,
            0.3,
            -1.2,
            0.3,
            -1.2),
        Case(
            "sphere",
            6_371_000.0,
            0.0,
            -35.0 * d2r,
            -120.0 * d2r,
            42.0 * d2r,
            55.0 * d2r),
        Case(
            "flattening-boundary",
            7_000_000.0,
            0.01,
            -55.0 * d2r,
            -80.0 * d2r,
            38.0 * d2r,
            95.0 * d2r),
        Case(
            "scaled-ellipsoid",
            63_781.37,
            1.0 / 298.257223563,
            10.0 * d2r,
            -150.0 * d2r,
            -60.0 * d2r,
            40.0 * d2r),
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
        checkCase(item, failures);

    /*
     * Explicit antisymmetry check independent of the C++ oracle comparison.
     */
    const state =
        prepare(
            6_378_137.0,
            1.0 / 298.257223563);

    const forward =
        geodesicInverseDispatch!(
            double,
            6,
            geodesicInverseArea)(
                state.a,
                state.f,
                state.f1,
                state.b,
                state.ep2,
                state.n,
                state.a3x,
                state.c3x,
                -0.55,
                -0.3,
                0.2,
                1.1);

    const reverse =
        geodesicInverseDispatch!(
            double,
            6,
            geodesicInverseArea)(
                state.a,
                state.f,
                state.f1,
                state.b,
                state.ep2,
                state.n,
                state.a3x,
                state.c3x,
                0.2,
                1.1,
                -0.55,
                -0.3);

    const double antisymmetryError =
        fabs(
            forward.signedArea
            + reverse.signedArea);

    writefln(
        "%s %-22s abs=% .6e",
        antisymmetryError <= 1.0
            ? "PASS"
            : "FAIL",
        "antisymmetry",
        antisymmetryError);

    if (antisymmetryError > 1.0)
        ++failures;

    if (failures != 0)
    {
        writefln(
            "AREA VALIDATION FAIL: %s case(s)",
            failures);

        assert(0);
    }

    writeln("AREA VALIDATION PASS");
}
