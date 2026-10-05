module geodesic_quantities_api_validation;

import std.math :
    PI,
    fabs;

import std.stdio :
    writefln,
    writeln;

import geodesy;


extern(C) int geodesic_quantities_reference_inverse(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double latitude2Radians,
    double longitude2Radians,
    double* reducedLength,
    double* scale12,
    double* scale21,
    double* signedArea);


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


double linearTolerance(
    const double a,
    const double expected)
{
    const double scale =
        fabs(expected) > a
            ? fabs(expected)
            : a;

    return 2.0e-13 * scale
        + 1.0e-9;
}


double scaleTolerance(
    const double expected)
{
    const double scale =
        fabs(expected) > 1.0
            ? fabs(expected)
            : 1.0;

    return 2.0e-13 * scale;
}


double areaTolerance(
    const double a,
    const double expected)
{
    const double a2 =
        a * a;

    const double scale =
        fabs(expected) > a2
            ? fabs(expected)
            : a2;

    return 1.0e-14 * scale
        + 1.0e-6;
}


void checkCase(
    const Case item,
    ref size_t failures)
{
    const ellipsoid =
        item.f == 0.0
            ? Ellipsoid!double.sphere(item.a)
            : Ellipsoid!double.fromFlattening(
                item.a,
                item.f);

    const solver =
        Geodesic!double.fromEllipsoid(
            ellipsoid);

    const start =
        GeographicCoordinate!double.fromComponents(
            Latitude!double.fromRadians(item.lat1),
            Longitude!double.fromRadians(item.lon1));

    const end =
        GeographicCoordinate!double.fromComponents(
            Latitude!double.fromRadians(item.lat2),
            Longitude!double.fromRadians(item.lon2));

    GeodesicInverseResult!double inverse;
    GeodesicQuantities!double actual;

    if (!solver.tryInverse(
            start,
            end,
            inverse,
            actual))
    {
        writefln(
            "FAIL %-24s public tryInverse failed",
            item.name);

        ++failures;
        return;
    }

    double expectedM12;
    double expectedScale12;
    double expectedScale21;
    double expectedArea;

    const int referenceOk =
        geodesic_quantities_reference_inverse(
            item.a,
            item.f,
            item.lat1,
            item.lon1,
            item.lat2,
            item.lon2,
            &expectedM12,
            &expectedScale12,
            &expectedScale21,
            &expectedArea);

    if (!referenceOk)
    {
        writefln(
            "FAIL %-24s GeographicLib reference failed",
            item.name);

        ++failures;
        return;
    }

    const double mError =
        fabs(actual.reducedLength - expectedM12);

    const double s12Error =
        fabs(actual.scale12 - expectedScale12);

    const double s21Error =
        fabs(actual.scale21 - expectedScale21);

    const double areaError =
        fabs(actual.signedArea - expectedArea);

    const bool mPass =
        mError
        <= linearTolerance(
            item.a,
            expectedM12);

    const bool s12Pass =
        s12Error
        <= scaleTolerance(
            expectedScale12);

    const bool s21Pass =
        s21Error
        <= scaleTolerance(
            expectedScale21);

    const bool areaPass =
        areaError
        <= areaTolerance(
            item.a,
            expectedArea);

    writefln(
        "%s %-24s m12 abs=% .3e  M12 abs=% .3e  M21 abs=% .3e  S12 abs=% .3e",
        mPass && s12Pass && s21Pass && areaPass
            ? "PASS"
            : "FAIL",
        item.name,
        mError,
        s12Error,
        s21Error,
        areaError);

    if (!(mPass && s12Pass && s21Pass && areaPass))
    {
        writefln(
            "  actual   m12=% .17e M12=% .17e M21=% .17e S12=% .17e",
            actual.reducedLength,
            actual.scale12,
            actual.scale21,
            actual.signedArea);

        writefln(
            "  expected m12=% .17e M12=% .17e M21=% .17e S12=% .17e",
            expectedM12,
            expectedScale12,
            expectedScale21,
            expectedArea);

        ++failures;
    }
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
            "very-short",
            6_378_137.0,
            1.0 / 298.257223563,
            -0.2,
            0.3,
            -0.2 + 1.0e-10,
            0.3 + 1.0e-10),
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

    if (failures != 0)
    {
        writefln(
            "GEODESIC QUANTITIES API VALIDATION FAIL: %s case(s)",
            failures);

        assert(0);
    }

    writeln("GEODESIC QUANTITIES API VALIDATION PASS");
}
