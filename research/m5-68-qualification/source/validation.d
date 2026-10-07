module m5_68_advanced_line_validation;

import geodesy;

import std.math : PI, fabs, fmax;
import std.stdio : writefln, writeln;

extern(C)
int m5_line_reference_position(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    int arcMode,
    double distanceOrArcRadians,
    int unroll,
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
    double latitude1;
    double longitude1;
    double azimuth1;
    double[4] distances;
    double[4] arcs;
}

double angularError(double actual, double expected)
{
    double d = actual - expected;
    while (d < -cast(double) PI)
        d += 2.0 * cast(double) PI;
    while (d >= cast(double) PI)
        d -= 2.0 * cast(double) PI;
    return fabs(d);
}

bool nearArea(double actual, double expected)
{
    const double tolerance =
        fmax(1.0e-3, fabs(expected) * 5.0e-13);
    return fabs(actual - expected) <= tolerance;
}

void compareOne(
    const Case item,
    const bool arcMode,
    const double input,
    ref size_t failures)
{
    const ellipsoid =
        item.f == 0.0
            ? Ellipsoid!double.sphere(item.a)
            : Ellipsoid!double.fromFlattening(item.a, item.f);

    const solver = Geodesic!double.fromEllipsoid(ellipsoid);
    const start =
        GeographicCoordinate!double.fromComponents(
            Latitude!double.fromRadians(item.latitude1),
            Longitude!double.fromRadians(item.longitude1));
    const azimuth = Angle!double.fromRadians(item.azimuth1);
    const line =
        GeodesicLine!double.fromGeodesic(
            solver,
            start,
            azimuth);

    GeodesicDirectResult!double actual;
    GeodesicQuantities!double quantities;
    GeodesicLineUnrolledResult!double unrolled;

    bool ok;
    if (arcMode)
    {
        const arc = Angle!double.fromRadians(input);
        ok =
            line.tryArcPosition(arc, actual, quantities)
            && line.tryArcPositionUnrolled(arc, unrolled);
    }
    else
    {
        ok =
            line.tryPosition(input, actual, quantities)
            && line.tryPositionUnrolled(input, unrolled);
    }

    if (!ok)
    {
        writefln("FAIL %-18s mode=%s input=% .12g D evaluation failed",
            item.name, arcMode ? "arc" : "distance", input);
        ++failures;
        return;
    }

    double expectedLat;
    double expectedLon;
    double expectedAzi;
    double expectedM12red;
    double expectedScale12;
    double expectedScale21;
    double expectedArea;

    if (!m5_line_reference_position(
            item.a,
            item.f,
            item.latitude1,
            item.longitude1,
            item.azimuth1,
            arcMode ? 1 : 0,
            input,
            0,
            &expectedLat,
            &expectedLon,
            &expectedAzi,
            &expectedM12red,
            &expectedScale12,
            &expectedScale21,
            &expectedArea))
    {
        writefln("FAIL %-18s mode=%s input=% .12g reference failed",
            item.name, arcMode ? "arc" : "distance", input);
        ++failures;
        return;
    }

    double expectedUnrolledLon;
    double scratchLat;
    double scratchAzi;
    double scratchM;
    double scratchScale12;
    double scratchScale21;
    double scratchArea;

    if (!m5_line_reference_position(
            item.a,
            item.f,
            item.latitude1,
            item.longitude1,
            item.azimuth1,
            arcMode ? 1 : 0,
            input,
            1,
            &scratchLat,
            &expectedUnrolledLon,
            &scratchAzi,
            &scratchM,
            &scratchScale12,
            &scratchScale21,
            &scratchArea))
    {
        writefln("FAIL %-18s mode=%s input=% .12g unroll reference failed",
            item.name, arcMode ? "arc" : "distance", input);
        ++failures;
        return;
    }

    enum double angleTol = 8.0e-13;
    enum double reducedTol = 2.0e-6;
    enum double scaleTol = 8.0e-13;
    enum double unrollTol = 2.0e-12;

    const double latErr =
        fabs(actual.position.latitude.radians - expectedLat);
    const double lonErr =
        angularError(actual.position.longitude.radians, expectedLon);
    const double aziErr =
        angularError(actual.finalAzimuth.radians, expectedAzi);
    const double unrollErr =
        fabs(unrolled.unrolledLongitude.radians - expectedUnrolledLon);
    const double mErr =
        fabs(quantities.reducedLength - expectedM12red);
    const double s12Err =
        fabs(quantities.scale12 - expectedScale12);
    const double s21Err =
        fabs(quantities.scale21 - expectedScale21);
    const double areaErr =
        fabs(quantities.signedArea - expectedArea);

    const bool pass =
        latErr <= angleTol
        && lonErr <= angleTol
        && aziErr <= angleTol
        && unrollErr <= unrollTol
        && mErr <= reducedTol
        && s12Err <= scaleTol
        && s21Err <= scaleTol
        && nearArea(quantities.signedArea, expectedArea);

    writefln(
        "%s %-18s %-8s input=% .8g lat=% .2e lon=% .2e unroll=% .2e "
        ~ "azi=% .2e m=% .2e M12=% .2e M21=% .2e area=% .2e",
        pass ? "PASS" : "FAIL",
        item.name,
        arcMode ? "arc" : "distance",
        input,
        latErr,
        lonErr,
        unrollErr,
        aziErr,
        mErr,
        s12Err,
        s21Err,
        areaErr);

    if (!pass)
        ++failures;
}

void main()
{
    enum double d2r = cast(double) PI / 180.0;

    Case[] cases = [
        Case(
            "ordinary",
            6_378_137.0,
            1.0 / 298.257223563,
            48.20849 * d2r,
            16.37208 * d2r,
            73.0 * d2r,
            [0.0, 1_000.0, 1_000_000.0, -3_000_000.0],
            [0.0, 0.5 * d2r, 120.0 * d2r, -275.0 * d2r]),
        Case(
            "antimeridian",
            6_378_137.0,
            1.0 / 298.257223563,
            25.0 * d2r,
            179.7 * d2r,
            80.0 * d2r,
            [1.0, 2_000_000.0, 19_000_000.0, -19_000_000.0],
            [1.0 * d2r, 190.0 * d2r, 540.0 * d2r, -450.0 * d2r]),
        Case(
            "sphere",
            6_371_000.0,
            0.0,
            -35.0 * d2r,
            -120.0 * d2r,
            38.0 * d2r,
            [0.0, 3_000_000.0, 20_000_000.0, -20_000_000.0],
            [0.0, 90.0 * d2r, 810.0 * d2r, -810.0 * d2r]),
        Case(
            "flattening-boundary",
            7_000_000.0,
            0.01,
            -55.0 * d2r,
            -80.0 * d2r,
            125.0 * d2r,
            [0.001, 5_000_000.0, 20_000_000.0, -5_000_000.0],
            [0.001 * d2r, 45.0 * d2r, 250.0 * d2r, -120.0 * d2r]),
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
    {
        foreach (distance; item.distances)
            compareOne(item, false, distance, failures);

        foreach (arc; item.arcs)
            compareOne(item, true, arc, failures);
    }

    if (failures != 0)
    {
        writefln("M5 #68 ADVANCED LINE VALIDATION FAIL: %s case(s)", failures);
        assert(0);
    }

    writeln("M5 #68 ADVANCED LINE VALIDATION PASS");
}
