module geodesic_polygon_validation;

import geodesy;

import std.math : PI, fabs;
import std.stdio : writefln, writeln;

extern(C)
int geodesic_polygon_reference(
    double a,
    double f,
    const double* latitudesRadians,
    const double* longitudesRadians,
    size_t count,
    double* perimeter,
    double* signedArea);

struct Vertex
{
    double lat;
    double lon;
}

struct Case
{
    const(char)[] name;
    double a;
    double f;
    Vertex[] vertices;
}

double perimeterTolerance(double a, double expected)
{
    const double scale =
        fabs(expected) > a ? fabs(expected) : a;

    return 5.0e-13 * scale + 1.0e-8;
}

double areaTolerance(double a, double expected)
{
    const double a2 = a * a;
    const double scale =
        fabs(expected) > a2 ? fabs(expected) : a2;

    return 2.0e-13 * scale + 1.0e-4;
}

void checkCase(const Case item, ref size_t failures)
{
    const ellipsoid =
        item.f == 0.0
            ? Ellipsoid!double.sphere(item.a)
            : Ellipsoid!double.fromFlattening(item.a, item.f);

    const solver =
        Geodesic!double.fromEllipsoid(ellipsoid);

    auto accumulator =
        GeodesicPolygonAccumulator!double.fromGeodesic(solver);

    double[] latitudes = new double[item.vertices.length];
    double[] longitudes = new double[item.vertices.length];

    foreach (i, const ref vertex; item.vertices)
    {
        latitudes[i] = vertex.lat;
        longitudes[i] = vertex.lon;

        accumulator.addPoint(
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromRadians(vertex.lat),
                Longitude!double.fromRadians(vertex.lon)));
    }

    const actual =
        accumulator.compute();

    double expectedPerimeter;
    double expectedArea;

    const int ok =
        geodesic_polygon_reference(
            item.a,
            item.f,
            latitudes.ptr,
            longitudes.ptr,
            item.vertices.length,
            &expectedPerimeter,
            &expectedArea);

    if (!ok)
    {
        writefln("FAIL %-24s GeographicLib failed", item.name);
        ++failures;
        return;
    }

    const double pError =
        fabs(actual.perimeter - expectedPerimeter);

    const double aError =
        fabs(actual.signedArea - expectedArea);

    const bool pass =
        actual.pointCount == item.vertices.length
        && pError <= perimeterTolerance(item.a, expectedPerimeter)
        && aError <= areaTolerance(item.a, expectedArea);

    writefln(
        "%s %-24s points=%s perimeter=% .3e area=% .3e",
        pass ? "PASS" : "FAIL",
        item.name,
        actual.pointCount,
        pError,
        aError);

    if (!pass)
    {
        writefln(
            "  actual   perimeter=% .17e area=% .17e",
            actual.perimeter,
            actual.signedArea);
        writefln(
            "  expected perimeter=% .17e area=% .17e",
            expectedPerimeter,
            expectedArea);
        ++failures;
    }
}

void main()
{
    enum double d2r = cast(double) PI / 180.0;

    Case[] cases = [
        Case("triangle-ccw", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(0*d2r,0*d2r), Vertex(0*d2r,1*d2r), Vertex(1*d2r,0*d2r)]),
        Case("triangle-cw", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(0*d2r,0*d2r), Vertex(1*d2r,0*d2r), Vertex(0*d2r,1*d2r)]),
        Case("antimeridian", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(10*d2r,179*d2r), Vertex(10*d2r,-179*d2r), Vertex(20*d2r,-179*d2r), Vertex(20*d2r,179*d2r)]),
        Case("north-pole-cap", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(80*d2r,-120*d2r), Vertex(80*d2r,0*d2r), Vertex(80*d2r,120*d2r)]),
        Case("degenerate-two-point", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(48*d2r,16*d2r), Vertex(49*d2r,17*d2r)]),
        Case("figure-eight", 6_378_137.0, 1.0 / 298.257223563,
            [Vertex(0*d2r,0*d2r), Vertex(1*d2r,1*d2r), Vertex(0*d2r,2*d2r), Vertex(1*d2r,0*d2r), Vertex(0*d2r,1*d2r), Vertex(1*d2r,2*d2r)]),
        Case("sphere", 6_371_000.0, 0.0,
            [Vertex(-20*d2r,170*d2r), Vertex(-20*d2r,-170*d2r), Vertex(0*d2r,180*d2r)]),
        Case("flattening-boundary", 7_000_000.0, 0.01,
            [Vertex(-55*d2r,-80*d2r), Vertex(-20*d2r,30*d2r), Vertex(25*d2r,140*d2r), Vertex(60*d2r,-120*d2r)]),
        Case("scaled-ellipsoid", 63_781.37, 1.0 / 298.257223563,
            [Vertex(10*d2r,-150*d2r), Vertex(20*d2r,-130*d2r), Vertex(5*d2r,-120*d2r)])
    ];

    size_t failures = 0;

    foreach (const ref item; cases)
        checkCase(item, failures);

    if (failures != 0)
    {
        writefln(
            "GEODESIC POLYGON VALIDATION FAIL: %s case(s)",
            failures);
        assert(0);
    }

    writeln("GEODESIC POLYGON VALIDATION PASS");
}
