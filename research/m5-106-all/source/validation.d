module m5_106_all_validation;

import geodesy;

import std.algorithm : sort;
import std.array : array;
import std.math :
    PI, abs, atan2, atanh, ceil, cos, copysign, pow, sin, sqrt;
import std.stdio : writefln, writeln;

extern(C)
int m5_106_reference(
    double,double,
    double,double,double,
    double,double,double,
    double,double,double,
    size_t,
    size_t*,
    double*,double*,int*);

private struct P
{
    double x;
    double y;
    int c;
}

private double l1(const P p)
{
    return abs(p.x) + abs(p.y);
}

private double l1(const P a, const P b)
{
    return abs(a.x - b.x) + abs(a.y - b.y);
}

private bool eq(const P a, const P b, const double delta)
{
    return l1(a, b) <= delta;
}

private bool lessRank(const P a, const P b, const P p0)
{
    const double da = l1(a, p0);
    const double db = l1(b, p0);
    if (da != db)
        return da < db;
    if (a.x != b.x)
        return a.x < b.x;
    return a.y < b.y;
}

private double wrapPi(double value)
{
    const double period = 2.0 * cast(double) PI;
    value %= period;
    if (value >= cast(double) PI)
        value -= period;
    else if (value < -cast(double) PI)
        value += period;
    return value;
}

private double twoSum(
    const double u,
    const double v,
    out double error)
{
    const double s = u + v;
    const double up = s - v;
    const double vpp = s - up;
    const double du = up - u;
    const double dv = vpp - v;
    error = s != 0.0 ? -(du + dv) : s;
    return s;
}

private double angleDiff(
    const double x,
    const double y,
    out double error)
{
    const double period = 2.0 * cast(double) PI;
    double d = twoSum((-x) % period, y % period, error);
    double correction;
    d = twoSum(d % period, error, correction);
    error = correction;

    if (d > cast(double) PI)
        d -= period;
    else if (d < -cast(double) PI)
        d += period;

    if (d == 0.0 || abs(d) == cast(double) PI)
        d = copysign(d, error == 0.0 ? y - x : -error);

    return d;
}

private void sinCosCorrected(
    const double angle,
    const double correction,
    out double sine,
    out double cosine)
{
    const double s = sin(angle);
    const double c = cos(angle);
    const double se = sin(correction);
    const double ce = cos(correction);
    sine = s * ce + c * se;
    cosine = c * ce - s * se;
}

private GeographicCoordinate!double gc(double lat, double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private double authalicRadius(const Geodesic!double solver)
{
    const double a = solver.ellipsoid.semiMajorAxis;
    const double f = solver.ellipsoid.flattening;
    const double e2 = f * (2.0 - f);

    if (e2 == 0.0)
        return a;

    const double e = sqrt(e2);
    return sqrt(
        a * a * 0.5
        * (1.0 + (1.0 - e2) / e * atanh(e)));
}

private bool basic(
    const Geodesic!double solver,
    const GeodesicLine!double lineX,
    const GeodesicLine!double lineY,
    const double rR,
    const P seed,
    out P p)
{
    p = seed;
    const double eps = 3.0 * double.epsilon;
    const double tol =
        cast(double) PI * rR * pow(double.epsilon, 0.75);

    foreach (_; 0 .. 100)
    {
        GeodesicDirectResult!double px;
        GeodesicDirectResult!double py;
        if (!lineX.tryPosition(p.x, px)
            || !lineY.tryPosition(p.y, py))
            return false;

        GeodesicInverseResult!double inv;
        if (!solver.tryInverse(px.position, py.position, inv))
            return false;

        const double z = inv.distance;
        const double sinz = sin(z / rR);
        const double cosz = cos(z / rR);

        double errorX, errorY, errorXY;
        const double X = angleDiff(
            px.finalAzimuth.radians,
            inv.initialAzimuth.radians,
            errorX);
        const double Y = angleDiff(
            py.finalAzimuth.radians,
            inv.finalAzimuth.radians,
            errorY);
        const double XY = angleDiff(X, Y, errorXY);
        const double sign =
            copysign(1.0, XY + errorXY + errorY - errorX);

        double sinX, cosX, sinY, cosY;
        sinCosCorrected(sign * X, sign * errorX, sinX, cosX);
        sinCosCorrected(sign * Y, sign * errorY, sinY, cosY);

        double dx, dy;
        int coincidence = 0;

        if (z <= eps * rR)
        {
            dx = dy = 0.0;
            if (abs(sinX - sinY) <= eps
                && abs(cosX - cosY) <= eps)
                coincidence = 1;
            else if (abs(sinX + sinY) <= eps
                && abs(cosX + cosY) <= eps)
                coincidence = -1;
        }
        else if (abs(sinX) <= eps && abs(sinY) <= eps)
        {
            coincidence = cosX * cosY > 0.0 ? 1 : -1;
            dx = cosX * z / 2.0;
            dy = -cosY * z / 2.0;
        }
        else
        {
            dx = rR * atan2(
                sinY * sinz,
                sinY * cosX * cosz - cosY * sinX);
            dy = rR * atan2(
                sinX * sinz,
                -sinX * cosY * cosz + cosX * sinY);
        }

        p.x += dx;
        p.y += dy;
        p.c = coincidence;

        if (coincidence != 0 || abs(dx) + abs(dy) <= tol)
            return true;
    }

    return false;
}

private P fixCoincident(const P p0, const P p, int forced = 0)
{
    const int c = forced != 0 ? forced : p.c;
    if (c == 0)
        return p;

    const double shift =
        ((p0.x + c * p0.y) - (p.x + c * p.y)) / 2.0;

    return P(p.x + shift, p.y + c * shift, c);
}

private bool conjugateDistance(
    const GeodesicLine!double line,
    const double tolerance,
    const double initial,
    const bool semi,
    const double baseM12,
    const double baseScale12,
    const double baseScale21,
    out double distance)
{
    double s = initial;

    foreach (_; 0 .. 100)
    {
        GeodesicDirectResult!double position;
        GeodesicQuantities!double q;
        if (!line.tryPosition(s, position, q))
            return false;

        const double m13 = q.reducedLength;
        const double M13 = q.scale12;
        const double M31 = q.scale21;

        const double m23 =
            m13 * baseScale12 - baseM12 * M13;
        const double M23 =
            M13 * baseScale21
            + (baseM12 == 0.0
                ? 0.0
                : (1.0 - baseScale12 * baseScale21)
                    * m13 / baseM12);
        const double M32 =
            M31 * baseScale12
            + (m13 == 0.0
                ? 0.0
                : (1.0 - M13 * M31)
                    * baseM12 / m13);

        const double denominator =
            semi ? 1.0 - M23 * M32 : M32;
        if (denominator == 0.0)
            return false;

        const double ds =
            semi
                ? m23 * M23 / denominator
                : -m23 / denominator;

        if (!(ds == ds))
            return false;

        s += ds;

        if (abs(ds) <= tolerance)
        {
            distance = s;
            return true;
        }
    }

    return false;
}

private bool allSpacing(
    const Geodesic!double solver,
    const double rR,
    out double t1,
    out double d3,
    out double delta,
    out double d)
{
    const double a = solver.ellipsoid.semiMajorAxis;
    const double f = solver.ellipsoid.flattening;

    if (f < 0.0)
        return false;

    d = cast(double) PI * rR;
    t1 = cast(double) PI * a * (1.0 - f);
    delta = d * pow(double.epsilon, 0.2);

    // For the sphere and oblate scope of geodesy-d #106, GeographicLib's
    // t4 is t1 (sphere: both are pi*a). Thus d3 = t4 - delta.
    d3 = t1 - delta;

    return d3 > 0.0;
}

private bool containsEq(const P[] values, const P q, const double delta)
{
    foreach (p; values)
        if (eq(p, q, delta))
            return true;
    return false;
}

private void removeCoincidentLine(
    ref P[] values,
    const P p0,
    const P q,
    const int c,
    const double delta)
{
    size_t outIndex;
    foreach (p; values)
    {
        if (!eq(fixCoincident(p0, p, c), q, delta))
            values[outIndex++] = p;
    }
    values.length = outIndex;
}

private bool enumerateAll(
    const Geodesic!double solver,
    const GeographicCoordinate!double startX,
    const Angle!double aziX,
    const GeographicCoordinate!double startY,
    const Angle!double aziY,
    const double radius,
    const P p0,
    out P[] result)
{
    result = null;
    if (radius < 0.0)
        return false;

    const auto lineX =
        GeodesicLine!double.fromGeodesic(solver, startX, aziX);
    const auto lineY =
        GeodesicLine!double.fromGeodesic(solver, startY, aziY);

    const double rR = authalicRadius(solver);

    double t1, d3max, delta, d;
    if (!allSpacing(solver, rR, t1, d3max, delta, d))
        return false;

    const double maxdistx = radius + delta;
    const int m = cast(int) ceil(maxdistx / d3max);
    const int tiles = m > 0 ? m : 1;
    const int m2 = tiles * tiles + (tiles - 1) % 2;
    const int n = tiles - 1;
    const double spacing = maxdistx / tiles;

    P[] start;
    start.reserve(m2);
    start ~= p0;

    for (int i = -n; i <= n; i += 2)
    {
        for (int j = -n; j <= n; j += 2)
        {
            if (i == 0 && j == 0)
                continue;
            start ~= P(
                p0.x + spacing * (i + j) / 2.0,
                p0.y + spacing * (i - j) / 2.0,
                0);
        }
    }

    if (start.length != cast(size_t) m2)
        return false;

    bool[] skip;
    skip.length = start.length;

    P[] found;
    P[] coincidentCenters;
    int coincidenceOrientation = 0;

    foreach (k; 0 .. start.length)
    {
        if (skip[k])
            continue;

        P q;
        if (!basic(solver, lineX, lineY, rR, start[k], q))
            return false;

        if (containsEq(found, q, delta))
            continue;

        if (coincidenceOrientation != 0
            && containsEq(
                coincidentCenters,
                fixCoincident(p0, q, coincidenceOrientation),
                delta))
            continue;

        P[] added;

        if (q.c != 0)
        {
            coincidenceOrientation = q.c;
            q = fixCoincident(p0, q);
            coincidentCenters ~= q;

            removeCoincidentLine(
                found,
                p0,
                q,
                coincidenceOrientation,
                delta);

            const double s0 = q.x;
            GeodesicDirectResult!double pos;
            GeodesicQuantities!double baseQ;
            if (!lineX.tryPosition(s0, pos, baseQ))
                return false;

            foreach (sign; [-1.0, 1.0])
            {
                double sa = 0.0;
                P qc;
                do
                {
                    double absolute;
                    if (!conjugateDistance(
                            lineX,
                            d * pow(double.epsilon, 0.75),
                            s0 + sa + sign * d,
                            false,
                            baseQ.reducedLength,
                            baseQ.scale12,
                            baseQ.scale21,
                            absolute))
                        return false;

                    sa = absolute - s0;
                    qc = P(
                        q.x + sa,
                        q.y + coincidenceOrientation * sa,
                        coincidenceOrientation);

                    if (!containsEq(found, qc, delta))
                        found ~= qc;
                    added ~= qc;
                }
                while (l1(qc, p0) <= maxdistx);
            }
        }

        if (!containsEq(found, q, delta))
            found ~= q;
        added ~= q;

        foreach (p; added)
        {
            foreach (l; k + 1 .. start.length)
            {
                if (!skip[l]
                    && l1(p, start[l])
                        < 2.0 * t1 - spacing - delta)
                    skip[l] = true;
            }
        }
    }

    size_t outIndex;
    foreach (p; found)
    {
        if (l1(p, p0) <= radius)
            found[outIndex++] = p;
    }
    found.length = outIndex;

    sort!((a, b) => lessRank(a, b, p0))(found);

    result = found;
    return true;
}

private struct Case
{
    string name;
    bool sphere;
    double latX, lonX, aziX;
    double latY, lonY, aziY;
    double p0x, p0y, radius;
}

private bool compareCase(const Case item)
{
    const ellipsoid =
        item.sphere
            ? Ellipsoid!double.sphere(6_371_000.0)
            : wgs84!double();

    const solver = Geodesic!double.fromEllipsoid(ellipsoid);
    const P p0 = P(item.p0x, item.p0y, 0);

    P[] actual;
    if (!enumerateAll(
            solver,
            gc(item.latX, item.lonX),
            Angle!double.fromDegrees(item.aziX),
            gc(item.latY, item.lonY),
            Angle!double.fromDegrees(item.aziY),
            item.radius,
            p0,
            actual))
    {
        writefln("FAIL %-31s D enumeration failed", item.name);
        return false;
    }

    enum size_t capacity = 64;
    double[capacity] xs;
    double[capacity] ys;
    int[capacity] cs;
    size_t expectedCount;

    const int rc = m5_106_reference(
        ellipsoid.semiMajorAxis,
        ellipsoid.flattening,
        item.latX,item.lonX,item.aziX,
        item.latY,item.lonY,item.aziY,
        item.p0x,item.p0y,item.radius,
        capacity,
        &expectedCount,
        xs.ptr,ys.ptr,cs.ptr);

    if (rc != 1)
    {
        writefln(
            "FAIL %-31s oracle failed rc=%s count=%s",
            item.name, rc, expectedCount);
        return false;
    }

    if (actual.length != expectedCount)
    {
        writefln(
            "FAIL %-31s count actual=%s expected=%s",
            item.name, actual.length, expectedCount);
        return false;
    }

    double maxError;
    foreach (i, p; actual)
    {
        const double err = abs(p.x - xs[i]) + abs(p.y - ys[i]);
        if (err > maxError)
            maxError = err;

        const double tolerance =
            2e-4 > 128.0 * double.epsilon * (1.0 + l1(p, p0))
                ? 2e-4
                : 128.0 * double.epsilon * (1.0 + l1(p, p0));

        if (err > tolerance || p.c != cs[i])
        {
            writefln(
                "FAIL %-31s point=%s err=%.3e c=%s/%s",
                item.name, i, err, p.c, cs[i]);
            return false;
        }
    }

    writefln(
        "PASS %-31s count=%3s max_l1_err=%.3e",
        item.name, actual.length, maxError);
    return true;
}

void main()
{
    Case[] cases = [
        Case("wgs84_ordinary",false,
            0,-20,45, 10,20,-60, 0,0,50_000_000),
        Case("wgs84_symmetric_origin",false,
            0,0,45, 0,0,135, 0,0,50_000_000),
        Case("wgs84_near_parallel",false,
            10,20,45, 11,21,45.1, 0,0,70_000_000),
        Case("wgs84_polar",false,
            82,-40,20, 80,100,145, 0,0,50_000_000),
        Case("wgs84_reverse",false,
            -25,70,-35, 5,-110,145, 1_000_000,-500_000,50_000_000),
        Case("wgs84_coincident_parallel",false,
            0,0,90, 0,0,90, 0,0,50_000_000),
        Case("wgs84_coincident_antiparallel",false,
            0,0,90, 0,0,-90, 0,0,50_000_000),
        Case("sphere_ordinary",true,
            0,-20,45, 10,20,-60, 0,0,50_000_000),
        Case("sphere_near_parallel",true,
            15,-30,60, 16,-29,60.1, 0,0,70_000_000),
        Case("sphere_symmetric_origin",true,
            0,0,45, 0,0,135, 0,0,50_000_000),
        Case("sphere_coincident_parallel",true,
            0,0,90, 0,0,90, 0,0,50_000_000),
        Case("wgs84_boundary_outside",false,
            0,0,30, 0,0,120, 0,0,39_924_025.252815932),
        Case("wgs84_boundary_inside",false,
            0,0,30, 0,0,120, 0,0,40_042_530.068560898)
    ];

    size_t failures;
    foreach (item; cases)
        if (!compareCase(item))
            ++failures;

    if (failures)
    {
        writefln("R106.2 ALL DIFFERENTIAL FAIL: %s", failures);
        assert(0);
    }

    writeln("R106.2 ALL DIFFERENTIAL PASS");
}
