module m5_47_interception_validation;

import geodesy;

import std.math : PI, abs, atan, atan2, cos, hypot, sin, sqrt;
import std.stdio : stderr;

extern(C)
int m5_47_reference(
    double a,
    double f,
    double latA,
    double lonA,
    double latB,
    double lonB,
    double latC,
    double lonC,
    double* footLat,
    double* footLon,
    double* alongTrack,
    double* signedCrossTrack,
    double* segmentNearestLat,
    double* segmentNearestLon,
    double* segmentNearestDistance,
    int* segmentClass);

struct XY { double x; double y; }

double wrapPi(double x)
{
    const double tau = 2.0 * cast(double) PI;
    x %= tau;
    if (x >= cast(double) PI) x -= tau;
    if (x < -cast(double) PI) x += tau;
    return x;
}

bool gnomonicForward(
    const Geodesic!double solver,
    const GeographicCoordinate!double center,
    const GeographicCoordinate!double point,
    out XY xy)
{
    xy = XY.init;
    GeodesicInverseResult!double inv;
    GeodesicQuantities!double q;

    if (!solver.tryInverse(center, point, inv, q))
        return false;

    if (!(q.scale12 > 0.0))
        return false;

    const double rho = q.reducedLength / q.scale12;
    xy.x = rho * sin(inv.initialAzimuth.radians);
    xy.y = rho * cos(inv.initialAzimuth.radians);
    return xy.x == xy.x && xy.y == xy.y;
}

bool gnomonicReverse(
    const Geodesic!double solver,
    const GeographicCoordinate!double center,
    const XY xy,
    out GeographicCoordinate!double point)
{
    point = GeographicCoordinate!double.init;

    const double a = solver.ellipsoid.semiMajorAxis;
    double rho = hypot(xy.x, xy.y);
    const bool little = rho <= a;

    double s = a * atan(rho / a);
    if (!little)
        rho = 1.0 / rho;

    const auto azi0 = Angle!double.fromRadians(atan2(xy.x, xy.y));
    const auto line = GeodesicLine!double.fromGeodesic(solver, center, azi0);

    enum size_t maxIterations = 20;
    const double tolerance = 0.01 * sqrt(double.epsilon) * a;

    foreach (_; 0 .. maxIterations)
    {
        GeodesicDirectResult!double pos;
        GeodesicQuantities!double q;

        if (!line.tryPosition(s, pos, q))
            return false;

        const double ds =
            little
                ? (q.reducedLength - rho * q.scale12) * q.scale12
                : (rho * q.reducedLength - q.scale12) * q.reducedLength;

        if (!(ds == ds))
            return false;

        s -= ds;

        if (abs(ds) < tolerance)
        {
            GeodesicDirectResult!double finalPos;
            if (!line.tryPosition(s, finalPos))
                return false;
            point = finalPos.position;
            return true;
        }
    }

    return false;
}

struct ProbeResult
{
    GeographicCoordinate!double foot;
    double alongTrack;
    double signedCrossTrack;
    GeographicCoordinate!double segmentNearest;
    double segmentNearestDistance;
    int segmentClass;
}

bool solveProbe(
    const Geodesic!double solver,
    const GeographicCoordinate!double a,
    const GeographicCoordinate!double b,
    const GeographicCoordinate!double c,
    out ProbeResult result)
{
    result = ProbeResult.init;

    const auto segment = solver.inverse(a, b);

    if (segment.distance == 0.0)
        return false;

    const auto fromStart = solver.inverse(a, c);
    if (fromStart.distance == 0.0)
    {
        result.foot = a;
        result.alongTrack = 0.0;
        result.signedCrossTrack = 0.0;
        result.segmentNearest = a;
        result.segmentNearestDistance = 0.0;
        result.segmentClass = 1;
        return true;
    }

    const auto fromEnd = solver.inverse(b, c);
    if (fromEnd.distance == 0.0)
    {
        result.foot = b;
        result.alongTrack = segment.distance;
        result.signedCrossTrack = 0.0;
        result.segmentNearest = b;
        result.segmentNearestDistance = 0.0;
        result.segmentClass = 2;
        return true;
    }

    GeographicCoordinate!double center = c;

    foreach (k; 0 .. 2)
    {
        XY pa, pb, pc;
        if (!gnomonicForward(solver, center, a, pa)
            || !gnomonicForward(solver, center, b, pb))
            return false;

        if (k == 0)
            pc = XY(0.0, 0.0);
        else if (!gnomonicForward(solver, center, c, pc))
            return false;

        const double dx = pb.x - pa.x;
        const double dy = pb.y - pa.y;
        const double denom = dx * dx + dy * dy;
        if (!(denom > 0.0))
            return false;

        const double dot = pc.x * dx + pc.y * dy;
        const double cross = pa.x * pb.y - pa.y * pb.x;
        const XY foot2d = XY(
            (dot * dx + cross * dy) / denom,
            (dot * dy - cross * dx) / denom);

        GeographicCoordinate!double next;
        if (!gnomonicReverse(solver, center, foot2d, next))
            return false;
        center = next;
    }

    const auto invAB = segment;
    const auto invAO = solver.inverse(a, center);
    const double deltaA =
        wrapPi(invAO.initialAzimuth.radians - invAB.initialAzimuth.radians);
    const double along =
        cos(deltaA) >= 0.0 ? invAO.distance : -invAO.distance;

    const auto line =
        GeodesicLine!double.fromGeodesic(
            solver, a, invAB.initialAzimuth);
    const auto lineAtFoot = line.position(along);
    const auto invOC = solver.inverse(center, c);

    double cross = 0.0;
    if (invOC.distance != 0.0)
    {
        const double delta =
            wrapPi(
                invOC.initialAzimuth.radians
                    - lineAtFoot.finalAzimuth.radians);
        const double side = sin(delta);
        cross =
            side > 0.0
                ? invOC.distance
                : side < 0.0
                    ? -invOC.distance
                    : 0.0;
    }

    GeographicCoordinate!double nearest = center;
    int klass = 0;
    if (along <= 0.0)
    {
        nearest = a;
        klass = 1;
    }
    else if (along >= invAB.distance)
    {
        nearest = b;
        klass = 2;
    }

    const auto invNearest = solver.inverse(nearest, c);

    result.foot = center;
    result.alongTrack = along;
    result.signedCrossTrack = cross;
    result.segmentNearest = nearest;
    result.segmentNearestDistance = invNearest.distance;
    result.segmentClass = klass;
    return true;
}

struct Case
{
    string name;
    double latA, lonA, latB, lonB, latC, lonC;
}

void main()
{
    const solver =
        Geodesic!double.fromEllipsoid(
            Ellipsoid!double.fromInverseFlattening(
                6_378_137.0,
                298.257223563));

    Case[] cases = [
        Case("ordinary interior", 48.0, 10.0, 48.0, 20.0, 49.2, 15.0),
        Case("right side", 40.0, -75.0, 42.0, -60.0, 38.0, -66.0),
        Case("before start", 48.0, 10.0, 48.0, 12.0, 48.4, 8.0),
        Case("after end", 48.0, 10.0, 48.0, 12.0, 47.7, 14.0),
        Case("antimeridian", 15.0, 175.0, 18.0, -175.0, 20.0, 179.0),
        Case("near equator", 0.0, -20.0, 0.0, 20.0, -2.0, 3.0),
        Case("on track", 0.0, -20.0, 0.0, 20.0, 0.0, 3.0),
        Case("at start", 10.0, 10.0, 12.0, 20.0, 10.0, 10.0),
        Case("at end", 10.0, 10.0, 12.0, 20.0, 12.0, 20.0),
        Case("reversed track", 42.0, -60.0, 40.0, -75.0, 38.0, -66.0),
    ];

    size_t failures = 0;

    foreach (item; cases)
    {
        const a = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(item.latA),
            Longitude!double.fromDegrees(item.lonA));
        const b = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(item.latB),
            Longitude!double.fromDegrees(item.lonB));
        const c = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(item.latC),
            Longitude!double.fromDegrees(item.lonC));

        ProbeResult actual;
        if (!solveProbe(solver, a, b, c, actual))
        {
            stderr.writefln("FAIL %-18s D solver failed", item.name);
            ++failures;
            continue;
        }

        double rFootLat, rFootLon, rAlong, rCross;
        double rSegLat, rSegLon, rSegDistance;
        int rClass;

        const int ok =
            m5_47_reference(
                solver.ellipsoid.semiMajorAxis,
                solver.ellipsoid.flattening,
                a.latitude.radians,
                a.longitude.radians,
                b.latitude.radians,
                b.longitude.radians,
                c.latitude.radians,
                c.longitude.radians,
                &rFootLat,
                &rFootLon,
                &rAlong,
                &rCross,
                &rSegLat,
                &rSegLon,
                &rSegDistance,
                &rClass);

        if (!ok)
        {
            stderr.writefln("FAIL %-18s reference failed", item.name);
            ++failures;
            continue;
        }

        const double footLatErr =
            abs(actual.foot.latitude.radians - rFootLat);
        const double footLonErr =
            abs(wrapPi(actual.foot.longitude.radians - rFootLon));
        const double alongErr = abs(actual.alongTrack - rAlong);
        const double crossErr = abs(actual.signedCrossTrack - rCross);
        const double segLatErr =
            abs(actual.segmentNearest.latitude.radians - rSegLat);
        const double segLonErr =
            abs(wrapPi(actual.segmentNearest.longitude.radians - rSegLon));
        const double segDistErr =
            abs(actual.segmentNearestDistance - rSegDistance);

        bool geometricCheck = true;

        if (abs(actual.signedCrossTrack) > 1.0e-6)
        {
            const auto invAB = solver.inverse(a, b);
            const auto line =
                GeodesicLine!double.fromGeodesic(
                    solver, a, invAB.initialAzimuth);
            const auto lineAtFoot =
                line.position(actual.alongTrack);
            const auto invFootTarget =
                solver.inverse(actual.foot, c);
            const double rightAngleError =
                abs(
                    abs(
                        wrapPi(
                            invFootTarget.initialAzimuth.radians
                                - lineAtFoot.finalAzimuth.radians))
                        - cast(double) PI / 2.0);
            geometricCheck =
                rightAngleError < 3e-10;
        }

        if (actual.segmentClass == 0)
        {
            geometricCheck =
                geometricCheck
                && abs(
                    actual.segmentNearestDistance
                        - abs(actual.signedCrossTrack))
                    < 2e-5;
        }

        const bool pass =
            footLatErr < 2e-12
            && footLonErr < 2e-12
            && alongErr < 2e-5
            && crossErr < 2e-5
            && segLatErr < 2e-12
            && segLonErr < 2e-12
            && segDistErr < 2e-5
            && actual.segmentClass == rClass
            && geometricCheck;

        stderr.writefln(
            "%s %-18s foot=(%.2e,%.2e) along=%.3e cross=%.3e "
            ~ "segment=(%.2e,%.2e,%.3e) class=%s",
            pass ? "PASS" : "FAIL",
            item.name,
            footLatErr,
            footLonErr,
            alongErr,
            crossErr,
            segLatErr,
            segLonErr,
            segDistErr,
            actual.segmentClass);

        if (!pass)
            ++failures;
    }

    if (failures)
    {
        stderr.writefln("M5 #47 INTERCEPTION PROBE FAIL: %s case(s)", failures);
        import core.stdc.stdlib : exit;
        exit(1);
    }

    stderr.writeln("M5 #47 INTERCEPTION PROBE PASS");
}
