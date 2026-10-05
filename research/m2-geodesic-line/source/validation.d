module geodesic_line_validation;

import geodesy;

import std.math :
    PI,
    fabs;

import std.stdio :
    writefln,
    writeln;


extern(C)
int geodesic_line_reference_position(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians);


struct LineCase
{
    const(char)[] name;
    double a;
    double f;
    double latitude1;
    double longitude1;
    double azimuth1;
    double[5] distances;
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


void checkLineCase(
    const LineCase item,
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
            Latitude!double.fromRadians(
                item.latitude1),
            Longitude!double.fromRadians(
                item.longitude1));

    const azimuth =
        Angle!double.fromRadians(
            item.azimuth1);

    GeodesicLine!double line;

    if (!GeodesicLine!double.tryFromGeodesic(
            solver,
            start,
            azimuth,
            line))
    {
        writefln(
            "FAIL %-22s line preparation failed",
            item.name);

        ++failures;
        return;
    }

    foreach (distance; item.distances)
    {
        GeodesicDirectResult!double actual;

        if (!line.tryPosition(
                distance,
                actual))
        {
            writefln(
                "FAIL %-22s distance=% .3f line position failed",
                item.name,
                distance);

            ++failures;
            continue;
        }

        double expectedLatitude;
        double expectedLongitude;
        double expectedAzimuth;

        if (!geodesic_line_reference_position(
                item.a,
                item.f,
                item.latitude1,
                item.longitude1,
                item.azimuth1,
                distance,
                &expectedLatitude,
                &expectedLongitude,
                &expectedAzimuth))
        {
            writefln(
                "FAIL %-22s distance=% .3f GeographicLib failed",
                item.name,
                distance);

            ++failures;
            continue;
        }

        const double latitudeError =
            fabs(
                actual.position.latitude.radians
                    - expectedLatitude);

        const double longitudeError =
            angularError(
                actual.position.longitude.radians,
                expectedLongitude);

        const double azimuthError =
            angularError(
                actual.finalAzimuth.radians,
                expectedAzimuth);

        enum double tolerance =
            5.0e-13;

        const bool pass =
            latitudeError <= tolerance
            && longitudeError <= tolerance
            && azimuthError <= tolerance;

        writefln(
            "%s %-22s distance=% .3f lat=% .3e lon=% .3e azi=% .3e",
            pass ? "PASS" : "FAIL",
            item.name,
            distance,
            latitudeError,
            longitudeError,
            azimuthError);

        if (!pass)
            ++failures;
    }
}


void main()
{
    enum double d2r =
        cast(double) PI / 180.0;

    LineCase[] cases = [
        LineCase(
            "ordinary",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            73.0 * d2r,
            [0.0, 1.0, 1_000.0, 450_000.0, -50_000.0]),
        LineCase(
            "antimeridian",
            6_378_137.0,
            1.0 / 298.257223563,
            25.0 * d2r,
            179.7 * d2r,
            80.0 * d2r,
            [0.0, 10.0, 1_500_000.0, -1_500_000.0, 19_000_000.0]),
        LineCase(
            "north-pole",
            6_378_137.0,
            1.0 / 298.257223563,
            90.0 * d2r,
            45.0 * d2r,
            130.0 * d2r,
            [0.0, 1.0, 800_000.0, -800_000.0, 12_000_000.0]),
        LineCase(
            "sphere",
            6_371_000.0,
            0.0,
            -35.0 * d2r,
            -120.0 * d2r,
            38.0 * d2r,
            [0.0, 1.0, 3_000_000.0, -2_000_000.0, 20_000_000.0]),
        LineCase(
            "flattening-boundary",
            7_000_000.0,
            0.01,
            -55.0 * d2r,
            -80.0 * d2r,
            125.0 * d2r,
            [0.0, 0.001, 5_000_000.0, -5_000_000.0, 20_000_000.0]),
        LineCase(
            "scaled-ellipsoid",
            63_781.37,
            1.0 / 298.257223563,
            10.0 * d2r,
            -150.0 * d2r,
            20.0 * d2r,
            [0.0, 0.001, 40_000.0, -40_000.0, 180_000.0]),
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
        checkLineCase(
            item,
            failures);

    if (failures != 0)
    {
        writefln(
            "GEODESIC LINE VALIDATION FAIL: %s position(s)",
            failures);

        assert(0);
    }

    writeln(
        "GEODESIC LINE VALIDATION PASS");
}
