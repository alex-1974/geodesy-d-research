module r69_prolate_kernel_validation;

import geodesy;
import std.math : fabs;
import std.stdio : stderr, writefln;

extern(C) int r69_direct(
    double a, double f,
    double lat1, double lon1, double azi1, double s12,
    double* lat2, double* lon2, double* azi2);

extern(C) int r69_inverse(
    double a, double f,
    double lat1, double lon1, double lat2, double lon2,
    double* s12, double* azi1, double* azi2);

private GeographicCoordinate!double gc(double lat, double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private double angleDelta(double a, double b)
{
    double d = a - b;
    while (d >= 180.0) d -= 360.0;
    while (d < -180.0) d += 360.0;
    return fabs(d);
}

private struct DirectCase
{
    string name;
    double f, lat, lon, azi, s12;
}

private struct InverseCase
{
    string name;
    double f, lat1, lon1, lat2, lon2;
}

int main()
{
    enum double a = 6_378_137.0;

    DirectCase[] directCases = [
        DirectCase("mild_ordinary", -1.0 / 300.0, 12.5,-33,47,2500000),
        DirectCase("mild_polar", -1.0 / 300.0, 82,15,170,1800000),
        DirectCase("mild_equatorial", -1.0 / 300.0, 0,20,90,12000000),
        DirectCase("mild_long", -1.0 / 300.0, -35,70,-40,19000000),
        DirectCase("mild_reverse", -1.0 / 300.0, 25,-120,35,-4000000),
        DirectCase("moderate_ordinary", -0.01, 12.5,-33,47,2500000),
        DirectCase("moderate_polar", -0.01, 82,15,170,1800000),
        DirectCase("moderate_equatorial", -0.01, 0,20,90,12000000),
        DirectCase("moderate_long", -0.01, -35,70,-40,19000000)
    ];

    InverseCase[] inverseCases = [
        InverseCase("mild_ordinary", -1.0/300.0, 10,20,-25,130),
        InverseCase("mild_equatorial", -1.0/300.0, 0,0,0,170),
        InverseCase("mild_polar", -1.0/300.0, 88,-40,80,135),
        InverseCase("mild_near_antipodal", -1.0/300.0, 0.01,0,-0.01,179.999),
        InverseCase("mild_near_antipodal_asym", -1.0/300.0, 15,10,-14.999,-169.999),
        InverseCase("moderate_ordinary", -0.01, 10,20,-25,130),
        InverseCase("moderate_equatorial", -0.01, 0,0,0,170),
        InverseCase("moderate_polar", -0.01, 88,-40,80,135),
        InverseCase("moderate_near_antipodal", -0.01, 0.01,0,-0.01,179.999),
        InverseCase("moderate_near_antipodal_asym", -0.01, 15,10,-14.999,-169.999)
    ];

    size_t failures;

    foreach (tc; directCases)
    {
        auto ellipsoid = Ellipsoid!double.fromFlattening(a, tc.f);
        auto solver = Geodesic!double.fromEllipsoid(ellipsoid);

        GeodesicDirectResult!double actual;
        if (!solver.tryDirect(
                gc(tc.lat, tc.lon),
                Angle!double.fromDegrees(tc.azi),
                tc.s12,
                actual))
        {
            stderr.writefln("FAIL direct %s: D solver rejected", tc.name);
            ++failures;
            continue;
        }

        double lat2, lon2, azi2;
        if (!r69_direct(a, tc.f, tc.lat, tc.lon, tc.azi, tc.s12,
                &lat2, &lon2, &azi2))
        {
            stderr.writefln("FAIL direct %s: oracle rejected", tc.name);
            ++failures;
            continue;
        }

        const dlat = fabs(actual.position.latitude.degrees - lat2);
        const dlon = angleDelta(actual.position.longitude.degrees, lon2);
        const dazi = angleDelta(actual.finalAzimuth.degrees, azi2);

        if (dlat > 2e-9 || dlon > 2e-9 || dazi > 2e-9)
        {
            stderr.writefln(
                "FAIL direct %s dlat=%.12g dlon=%.12g dazi=%.12g",
                tc.name,dlat,dlon,dazi);
            ++failures;
        }
        else
            writefln("PASS direct %-29s", tc.name);
    }

    foreach (tc; inverseCases)
    {
        auto ellipsoid = Ellipsoid!double.fromFlattening(a, tc.f);
        auto solver = Geodesic!double.fromEllipsoid(ellipsoid);

        GeodesicInverseResult!double actual;
        if (!solver.tryInverse(
                gc(tc.lat1,tc.lon1),
                gc(tc.lat2,tc.lon2),
                actual))
        {
            stderr.writefln("FAIL inverse %s: D solver rejected", tc.name);
            ++failures;
            continue;
        }

        double s12, azi1, azi2;
        if (!r69_inverse(a,tc.f,tc.lat1,tc.lon1,tc.lat2,tc.lon2,
                &s12,&azi1,&azi2))
        {
            stderr.writefln("FAIL inverse %s: oracle rejected", tc.name);
            ++failures;
            continue;
        }

        const ds = fabs(actual.distance - s12);
        const da1 = angleDelta(actual.initialAzimuth.degrees, azi1);
        const da2 = angleDelta(actual.finalAzimuth.degrees, azi2);

        if (ds > 2e-5 || da1 > 2e-9 || da2 > 2e-9)
        {
            stderr.writefln(
                "FAIL inverse %s ds=%.12g da1=%.12g da2=%.12g",
                tc.name,ds,da1,da2);
            ++failures;
        }
        else
            writefln("PASS inverse %-28s", tc.name);
    }

    if (failures)
    {
        stderr.writefln("R69.3 KERNEL ADMISSION FAIL: %s cases", failures);
        return 1;
    }

    writefln(
        "R69.3 KERNEL ADMISSION PASS: %s direct + %s inverse cases",
        directCases.length,
        inverseCases.length);
    return 0;
}
