module r69_prolate_family_propagation;

import geodesy;
import std.math : isFinite;
import std.stdio : stderr, writefln;

private GeographicCoordinate!double gc(double lat, double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

int main()
{
    enum double a = 6_378_137.0;
    enum double f = -0.01;

    const ellipsoid = Ellipsoid!double.fromFlattening(a, f);
    const solver = Geodesic!double.fromEllipsoid(ellipsoid);

    if (!solver.isValid)
    {
        stderr.writefln("FAIL base solver invalid");
        return 1;
    }

    const start = gc(12.5, -33.0);
    const azi = Angle!double.fromDegrees(47.0);
    enum double distance = 2_500_000.0;

    GeodesicDirectResult!double direct;
    if (!solver.tryDirect(start, azi, distance, direct))
    {
        stderr.writefln("FAIL base direct");
        return 2;
    }

    GeodesicLine!double line;
    if (!GeodesicLine!double.tryFromGeodesic(
            solver, start, azi, line))
    {
        stderr.writefln("FAIL prepared line construction");
        return 3;
    }

    GeodesicDirectResult!double linePosition;
    if (!line.tryPosition(distance, linePosition))
    {
        stderr.writefln("FAIL prepared line position");
        return 4;
    }

    const double lineLatDelta =
        linePosition.position.latitude.degrees
        - direct.position.latitude.degrees;
    const double lineLonDelta =
        linePosition.position.longitude.degrees
        - direct.position.longitude.degrees;

    if (lineLatDelta > 1e-10 || lineLatDelta < -1e-10
        || lineLonDelta > 1e-10 || lineLonDelta < -1e-10)
    {
        stderr.writefln(
            "FAIL prepared line mismatch lat=%s lon=%s",
            lineLatDelta, lineLonDelta);
        return 5;
    }

    writefln("PASS prepared_line");

    GeodesicQuantities!double quantities;
    GeodesicDirectResult!double withQuantities;
    const bool quantitiesOk =
        solver.tryDirect(
            start, azi, distance,
            withQuantities, quantities);

    if (!quantitiesOk
        || !isFinite(quantities.reducedLength)
        || !isFinite(quantities.scale12)
        || !isFinite(quantities.scale21)
        || !isFinite(quantities.signedArea))
    {
        stderr.writefln("FAIL advanced quantities propagation");
        return 7;
    }

    writefln(
        "PASS advanced_quantities signed_area=%.9f",
        quantities.signedArea);

    GeodesicPolygonAccumulator!double polygon;
    const bool polygonOk =
        GeodesicPolygonAccumulator!double.tryFromGeodesic(
            solver, polygon);

    if (!polygonOk || !polygon.isValid)
    {
        stderr.writefln("FAIL polygon prepare propagation");
        return 8;
    }

    writefln("PASS polygon_prepare");

    GeodesicSegmentNearestResult!double nearest;
    const bool nearestOk =
        tryNearestPointOnSegment(
            solver,
            gc(0.0,-20.0),
            gc(0.0,20.0),
            gc(10.0,0.0),
            nearest);

    if (!nearestOk
        || !nearest.isValid
        || !isFinite(nearest.nearestDistance))
    {
        stderr.writefln("FAIL nearest propagation");
        return 6;
    }

    writefln(
        "PASS nearest distance=%.9f along=%.9f cross=%.9f",
        nearest.nearestDistance,
        nearest.alongTrack,
        nearest.signedCrossTrack);

    GeodesicIntersectionSolver!double intersection;
    const bool intersectionOk =
        GeodesicIntersectionSolver!double.tryFromGeodesic(
            solver,
            intersection);

    writefln(
        "STATUS intersection_prepare=%s",
        intersectionOk ? "pass" : "blocked");

    if (intersectionOk)
    {
        stderr.writefln(
            "FAIL intersection unexpectedly passed despite explicit prolate gate");
        return 9;
    }

    writefln(
        "R69.4 PROPAGATION PASS: line+quantities+polygon+nearest pass; intersection remains explicitly blocked");
    return 0;
}
