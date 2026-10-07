module m5_68_arc_unroll_validation;

import geodesy;

import std.math :
    PI,
    fabs;

import std.stdio :
    writefln,
    writeln;


extern(C)
int geodesic_line_reference_general_position(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    int arcMode,
    int longUnroll,
    double input,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians);


struct Case
{
    const(char)[] name;
    double a;
    double f;
    double latitude1;
    double longitude1;
    double azimuth1;
    double[6] arcs;
    double[6] distances;
}


double angularError(
    const double actual,
    const double expected)
{
    double delta = actual - expected;

    while (delta < -cast(double) PI)
        delta += 2.0 * cast(double) PI;

    while (delta >= cast(double) PI)
        delta -= 2.0 * cast(double) PI;

    return fabs(delta);
}


void reference(
    const Case item,
    const bool arcMode,
    const bool unroll,
    const double input,
    out double latitude,
    out double longitude,
    out double azimuth)
{
    const ok =
        geodesic_line_reference_general_position(
            item.a,
            item.f,
            item.latitude1,
            item.longitude1,
            item.azimuth1,
            arcMode ? 1 : 0,
            unroll ? 1 : 0,
            input,
            &latitude,
            &longitude,
            &azimuth);

    assert(ok != 0);
}


void check(
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
            Latitude!double.fromRadians(
                item.latitude1),
            Longitude!double.fromRadians(
                item.longitude1));

    const line =
        GeodesicLine!double.fromGeodesic(
            solver,
            start,
            Angle!double.fromRadians(
                item.azimuth1));

    enum double angularTolerance = 8.0e-13;
    enum double unrolledTolerance = 2.0e-12;

    foreach (arc; item.arcs)
    {
        double refLat;
        double refLon;
        double refAzi;

        reference(
            item,
            true,
            false,
            arc,
            refLat,
            refLon,
            refAzi);

        const actual =
            line.arcPosition(
                Angle!double.fromRadians(arc));

        const latError =
            fabs(actual.position.latitude.radians - refLat);

        const lonError =
            angularError(
                actual.position.longitude.radians,
                refLon);

        const aziError =
            angularError(
                actual.finalAzimuth.radians,
                refAzi);

        const pass =
            latError <= angularTolerance
            && lonError <= angularTolerance
            && aziError <= angularTolerance;

        writefln(
            "%s %-22s arc canonical=% .6f lat=% .3e lon=% .3e azi=% .3e",
            pass ? "PASS" : "FAIL",
            item.name,
            arc,
            latError,
            lonError,
            aziError);

        if (!pass)
            ++failures;

        reference(
            item,
            true,
            true,
            arc,
            refLat,
            refLon,
            refAzi);

        const unrolled =
            line.arcPositionUnrolled(
                Angle!double.fromRadians(arc));

        const unrolledLatError =
            fabs(unrolled.latitude.radians - refLat);

        const unrolledLonError =
            fabs(unrolled.unrolledLongitude.radians - refLon);

        const unrolledAziError =
            angularError(
                unrolled.finalAzimuth.radians,
                refAzi);

        const unrolledPass =
            unrolledLatError <= angularTolerance
            && unrolledLonError <= unrolledTolerance
            && unrolledAziError <= angularTolerance;

        writefln(
            "%s %-22s arc unrolled =% .6f lat=% .3e lon=% .3e azi=% .3e",
            unrolledPass ? "PASS" : "FAIL",
            item.name,
            arc,
            unrolledLatError,
            unrolledLonError,
            unrolledAziError);

        if (!unrolledPass)
            ++failures;
    }

    foreach (distance; item.distances)
    {
        double refLat;
        double refLon;
        double refAzi;

        reference(
            item,
            false,
            true,
            distance,
            refLat,
            refLon,
            refAzi);

        const actual =
            line.positionUnrolled(distance);

        const latError =
            fabs(actual.latitude.radians - refLat);

        const lonError =
            fabs(actual.unrolledLongitude.radians - refLon);

        const aziError =
            angularError(
                actual.finalAzimuth.radians,
                refAzi);

        const pass =
            latError <= angularTolerance
            && lonError <= unrolledTolerance
            && aziError <= angularTolerance;

        writefln(
            "%s %-22s dist unrolled=% .3f lat=% .3e lon=% .3e azi=% .3e",
            pass ? "PASS" : "FAIL",
            item.name,
            distance,
            latError,
            lonError,
            aziError);

        if (!pass)
            ++failures;
    }
}


void main()
{
    enum double d2r =
        cast(double) PI / 180.0;

    Case[] cases = [
        Case(
            "ordinary",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            73.0 * d2r,
            [
                0.0,
                0.001,
                90.0 * d2r,
                361.0 * d2r,
                810.0 * d2r,
                -450.0 * d2r
            ],
            [
                0.0,
                1.0,
                1_000_000.0,
                40_000_000.0,
                80_000_000.0,
                -60_000_000.0
            ]),
        Case(
            "antimeridian",
            6_378_137.0,
            1.0 / 298.257223563,
            25.0 * d2r,
            179.7 * d2r,
            80.0 * d2r,
            [
                0.0,
                30.0 * d2r,
                180.0 * d2r,
                540.0 * d2r,
                900.0 * d2r,
                -720.0 * d2r
            ],
            [
                0.0,
                500_000.0,
                20_000_000.0,
                60_000_000.0,
                100_000_000.0,
                -80_000_000.0
            ]),
        Case(
            "positive-antimeridian",
            6_371_000.0,
            0.0,
            0.0,
            180.0 * d2r,
            90.0 * d2r,
            [
                0.0,
                90.0 * d2r,
                360.0 * d2r,
                810.0 * d2r,
                -90.0 * d2r,
                -810.0 * d2r
            ],
            [
                0.0,
                1_000_000.0,
                20_000_000.0,
                50_000_000.0,
                90_000_000.0,
                -90_000_000.0
            ]),
        Case(
            "flattening-boundary",
            7_000_000.0,
            0.01,
            -55.0 * d2r,
            -80.0 * d2r,
            125.0 * d2r,
            [
                0.0,
                1.0 * d2r,
                179.0 * d2r,
                540.0 * d2r,
                1080.0 * d2r,
                -540.0 * d2r
            ],
            [
                0.0,
                1.0,
                5_000_000.0,
                40_000_000.0,
                80_000_000.0,
                -40_000_000.0
            ]),
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
        check(item, failures);

    if (failures != 0)
    {
        writefln(
            "M5 #68 ARC/UNROLL VALIDATION FAIL: %s result(s)",
            failures);

        assert(0);
    }

    writeln(
        "M5 #68 ARC/UNROLL VALIDATION PASS");
}
