module geodesic_direct_quantities_validation;

import std.math :
    PI,
    fabs;

import std.stdio :
    writefln,
    writeln;

import geodesy;


extern(C) int geodesic_direct_quantities_reference(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians,
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
    double azi1;
    double distance;
}


double angularError(
    const double actual,
    const double expected)
{
    double delta =
        actual - expected;

    while (delta < -cast(double) PI)
        delta += 2.0 * cast(double) PI;

    while (delta >= cast(double) PI)
        delta -= 2.0 * cast(double) PI;

    return fabs(delta);
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

    const azimuth =
        Angle!double.fromRadians(item.azi1);

    GeodesicDirectResult!double actualResult;
    GeodesicQuantities!double actualQuantities;

    if (!solver.tryDirect(
            start,
            azimuth,
            item.distance,
            actualResult,
            actualQuantities))
    {
        writefln(
            "FAIL %-24s public tryDirect failed",
            item.name);

        ++failures;
        return;
    }

    double expectedLat2;
    double expectedLon2;
    double expectedAzi2;
    double expectedM12;
    double expectedScale12;
    double expectedScale21;
    double expectedArea;

    const int referenceOk =
        geodesic_direct_quantities_reference(
            item.a,
            item.f,
            item.lat1,
            item.lon1,
            item.azi1,
            item.distance,
            &expectedLat2,
            &expectedLon2,
            &expectedAzi2,
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

    const double latError =
        fabs(
            actualResult.position.latitude.radians
            - expectedLat2);

    const double lonError =
        angularError(
            actualResult.position.longitude.radians,
            expectedLon2);

    const double aziError =
        angularError(
            actualResult.finalAzimuth.radians,
            expectedAzi2);

    const double mError =
        fabs(
            actualQuantities.reducedLength
            - expectedM12);

    const double s12Error =
        fabs(
            actualQuantities.scale12
            - expectedScale12);

    const double s21Error =
        fabs(
            actualQuantities.scale21
            - expectedScale21);

    const double areaError =
        fabs(
            actualQuantities.signedArea
            - expectedArea);

    const double angularTolerance =
        5.0e-13;

    const bool pass =
        latError <= angularTolerance
        && lonError <= angularTolerance
        && aziError <= angularTolerance
        && mError <= linearTolerance(item.a, expectedM12)
        && s12Error <= scaleTolerance(expectedScale12)
        && s21Error <= scaleTolerance(expectedScale21)
        && areaError <= areaTolerance(item.a, expectedArea);

    writefln(
        "%s %-24s lat=% .3e lon=% .3e azi=% .3e m12=% .3e M12=% .3e M21=% .3e S12=% .3e",
        pass ? "PASS" : "FAIL",
        item.name,
        latError,
        lonError,
        aziError,
        mError,
        s12Error,
        s21Error,
        areaError);

    if (!pass)
    {
        writefln(
            "  actual quantities   m12=% .17e M12=% .17e M21=% .17e S12=% .17e",
            actualQuantities.reducedLength,
            actualQuantities.scale12,
            actualQuantities.scale21,
            actualQuantities.signedArea);

        writefln(
            "  expected quantities m12=% .17e M12=% .17e M21=% .17e S12=% .17e",
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
            "ordinary-eastward",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            92.0 * d2r,
            450_000.0),
        Case(
            "ordinary-negative",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            92.0 * d2r,
            -450_000.0),
        Case(
            "very-short",
            6_378_137.0,
            1.0 / 298.257223563,
            -0.2,
            0.3,
            1.1,
            0.001),
        Case(
            "zero-distance",
            6_378_137.0,
            1.0 / 298.257223563,
            -0.2,
            0.3,
            1.1,
            0.0),
        Case(
            "antimeridian-crossing",
            6_378_137.0,
            1.0 / 298.257223563,
            25.0 * d2r,
            179.7 * d2r,
            80.0 * d2r,
            1_500_000.0),
        Case(
            "north-pole-start",
            6_378_137.0,
            1.0 / 298.257223563,
            90.0 * d2r,
            45.0 * d2r,
            130.0 * d2r,
            800_000.0),
        Case(
            "sphere",
            6_371_000.0,
            0.0,
            -35.0 * d2r,
            -120.0 * d2r,
            38.0 * d2r,
            3_000_000.0),
        Case(
            "sphere-negative",
            6_371_000.0,
            0.0,
            20.0 * d2r,
            170.0 * d2r,
            -70.0 * d2r,
            -2_000_000.0),
        Case(
            "flattening-boundary",
            7_000_000.0,
            0.01,
            -55.0 * d2r,
            -80.0 * d2r,
            125.0 * d2r,
            5_000_000.0),
        Case(
            "scaled-ellipsoid",
            63_781.37,
            1.0 / 298.257223563,
            10.0 * d2r,
            -150.0 * d2r,
            20.0 * d2r,
            40_000.0),
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
        checkCase(item, failures);

    if (failures != 0)
    {
        writefln(
            "DIRECT QUANTITIES VALIDATION FAIL: %s case(s)",
            failures);

        assert(0);
    }

    writeln("DIRECT QUANTITIES VALIDATION PASS");
}
