module m5_105_next_validation;

import geodesy;

import std.math :
    PI,
    abs,
    atan2,
    atanh,
    cos,
    copysign,
    pow,
    sin,
    sqrt;
import std.stdio : writefln, writeln;

extern(C)
int m5_105_reference(
    double,double,double,double,double,double,
    double*,double*,int*,double*,double*);

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
        cast(double) PI * rR
        * pow(double.epsilon, 0.75);

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
        const double zr = z / rR;
        const double sinz = sin(zr);
        const double cosz = cos(zr);

        double errorX;
        double errorY;

        const double X =
            angleDiff(
                px.finalAzimuth.radians,
                inv.initialAzimuth.radians,
                errorX);

        const double Y =
            angleDiff(
                py.finalAzimuth.radians,
                inv.finalAzimuth.radians,
                errorY);

        double errorXY;

        const double XY =
            angleDiff(
                X,
                Y,
                errorXY);

        const double sign =
            copysign(
                1.0,
                XY + errorXY + errorY - errorX);

        double sinX;
        double cosX;
        double sinY;
        double cosY;

        sinCosCorrected(sign * X, sign * errorX, sinX, cosX);
        sinCosCorrected(sign * Y, sign * errorY, sinY, cosY);

        double dx;
        double dy;
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
        else if (abs(sinX) <= eps
            && abs(sinY) <= eps)
        {
            coincidence = cosX * cosY > 0.0 ? 1 : -1;
            dx = cosX * z / 2.0;
            dy = -cosY * z / 2.0;
        }
        else
        {
            dx =
                rR * atan2(
                    sinY * sinz,
                    sinY * cosX * cosz
                        - cosY * sinX);

            dy =
                rR * atan2(
                    sinX * sinz,
                    -sinX * cosY * cosz
                        + cosX * sinY);
        }

        p.x += dx;
        p.y += dy;
        p.c = coincidence;

        if (coincidence != 0
            || abs(dx) + abs(dy) <= tol)
            return true;
    }

    return false;
}

private P fixCoincident(const P p0, const P p)
{
    if (p.c == 0)
        return p;

    const double shift =
        (
            (p0.x + p.c * p0.y)
            - (p.x + p.c * p.y)
        ) / 2.0;

    return P(
        p.x + shift,
        p.y + p.c * shift,
        p.c);
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
            m13 * baseScale12
            - baseM12 * M13;

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
            semi
                ? 1.0 - M23 * M32
                : M32;

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

private bool conjugateFromOrigin(
    const GeodesicLine!double line,
    const double tolerance,
    const double initial,
    const bool semi,
    out double distance)
{
    return conjugateDistance(
        line,
        tolerance,
        initial,
        semi,
        0.0,
        1.0,
        1.0,
        distance);
}

private bool conjdist(
    const Geodesic!double solver,
    const double rR,
    const double aziDegrees,
    out double s,
    out double asymmetry)
{
    const auto line =
        GeodesicLine!double.fromGeodesic(
            solver,
            gc(0.0, 0.0),
            Angle!double.fromDegrees(aziDegrees));

    const double d = cast(double) PI * rR;
    const double tolerance =
        d * pow(double.epsilon, 0.75);

    if (!conjugateFromOrigin(
            line,
            tolerance,
            d,
            false,
            s))
        return false;

    P crossing;

    if (!basic(
            solver,
            line,
            line,
            rR,
            P(s / 2.0, -3.0 * s / 2.0, 0),
            crossing))
        return false;

    asymmetry =
        l1(crossing) - 2.0 * s;

    return true;
}

private bool distoblique(
    const Geodesic!double solver,
    const double rR,
    out double distance)
{
    double s0;
    double ds0;
    double s1;
    double ds1;

    double azi0 = 46.0;
    double azi1 = 44.0;

    if (!conjdist(solver, rR, azi0, s0, ds0)
        || !conjdist(solver, rR, azi1, s1, ds1))
        return false;

    double bestDistance = s1;
    double bestError = abs(ds1);

    foreach (_; 0 .. 10)
    {
        if (ds1 == ds0)
            break;

        const double nextAzi =
            (azi0 * ds1 - azi1 * ds0)
            / (ds1 - ds0);

        azi0 = azi1;
        s0 = s1;
        ds0 = ds1;

        azi1 = nextAzi;

        if (!conjdist(
                solver,
                rR,
                azi1,
                s1,
                ds1))
            return false;

        if (abs(ds1) < bestError)
        {
            bestError = abs(ds1);
            bestDistance = s1;

            if (ds1 == 0.0)
                break;
        }
    }

    distance = bestDistance;
    return true;
}

private bool nextSpacing(
    const Geodesic!double solver,
    const double rR,
    out double t1,
    out double d2,
    out double delta,
    out double d)
{
    const double a =
        solver.ellipsoid.semiMajorAxis;

    const double f =
        solver.ellipsoid.flattening;

    d =
        cast(double) PI * rR;

    t1 =
        cast(double) PI
        * a
        * (1.0 - f);

    delta =
        d * pow(double.epsilon, 0.2);

    double t3;

    if (f == 0.0)
    {
        t3 = d;
    }
    else
    {
        if (!distoblique(
                solver,
                rR,
                t3))
            return false;
    }

    d2 =
        2.0 * t3 / 3.0;

    return d2 < 2.0 * t1;
}

private bool nextIntersection(
    const Geodesic!double solver,
    const GeographicCoordinate!double origin,
    const Angle!double aziX,
    const Angle!double aziY,
    out P result)
{
    const auto lineX =
        GeodesicLine!double.fromGeodesic(
            solver,
            origin,
            aziX);

    const auto lineY =
        GeodesicLine!double.fromGeodesic(
            solver,
            origin,
            aziY);

    const double rR =
        authalicRadius(solver);

    double t1;
    double d2;
    double delta;
    double d;

    if (!nextSpacing(
            solver,
            rR,
            t1,
            d2,
            delta,
            d))
        return false;

    const int[8] ix =
        [-1,-1,1,1,-2,0,2,0];

    const int[8] iy =
        [-1,1,-1,1,0,2,0,-2];

    bool[8] skip;

    const P zero =
        P(0.0, 0.0, 0);

    bool haveBest = false;
    P best;

    foreach (n; 0 .. 8)
    {
        if (skip[n])
            continue;

        P q;

        if (!basic(
                solver,
                lineX,
                lineY,
                rR,
                P(ix[n] * d2, iy[n] * d2, 0),
                q))
            return false;

        q =
            fixCoincident(
                zero,
                q);

        const bool zeroPoint =
            l1(q, zero) <= delta;

        if (q.c == 0
            && zeroPoint)
            continue;

        if (q.c != 0
            && zeroPoint)
        {
            foreach (sign; [-1.0, 1.0])
            {
                double s;

                if (!conjugateFromOrigin(
                        lineX,
                        d * pow(double.epsilon, 0.75),
                        sign * d,
                        false,
                        s))
                    return false;

                const P candidate =
                    P(
                        s,
                        q.c * s,
                        q.c);

                if (!haveBest
                    || l1(candidate) < l1(best))
                {
                    best = candidate;
                    haveBest = true;
                }
            }
        }
        else if (!haveBest
            || l1(q) < l1(best))
        {
            best = q;
            haveBest = true;
        }

        foreach (sign; [-1,0,1])
        {
            if ((q.c == 0 && sign != 0)
                || (zeroPoint && sign == 0))
                continue;

            const P shifted =
                q.c != 0
                    ? P(
                        q.x + sign * d2,
                        q.y + q.c * sign * d2,
                        q.c)
                    : q;

            foreach (m; n + 1 .. 8)
            {
                if (l1(
                        shifted,
                        P(
                            ix[m] * d2,
                            iy[m] * d2,
                            0))
                    < 2.0 * t1
                        - d2
                        - delta)
                {
                    skip[m] = true;
                }
            }
        }
    }

    if (!haveBest)
        return false;

    result = best;
    return true;
}

private double coordinateError(
    const GeographicCoordinate!double a,
    const GeographicCoordinate!double b)
{
    const double dlat =
        abs(a.latitude.radians
            - b.latitude.radians);

    const double dlon =
        abs(
            wrapPi(
                a.longitude.radians
                - b.longitude.radians));

    return dlat > dlon ? dlat : dlon;
}

private struct Case
{
    string name;
    bool sphere;
    double lat;
    double lon;
    double aziX;
    double aziY;
}

void main()
{
    Case[] cases = [
        Case("ordinary",false,0,0,30,120),
        Case("equator orthogonal",false,0,0,0,90),
        Case("near parallel",false,10,20,45,45.1),
        Case("polar",false,82,-40,20,145),
        Case("reverse directions",false,-25,70,-35,140),
        Case("coincident same",false,0,0,90,90),
        Case("coincident reverse",false,0,0,90,-90),
        Case("sphere ordinary",true,0,0,30,120),
        Case("sphere near parallel",true,15,-30,60,60.1),
        Case("sphere coincident",true,0,0,90,90)
    ];

    size_t failures;

    foreach (item; cases)
    {
        const ellipsoid =
            item.sphere
                ? Ellipsoid!double.sphere(6_371_000.0)
                : wgs84!double();

        const solver =
            Geodesic!double.fromEllipsoid(
                ellipsoid);

        const origin =
            gc(item.lat,item.lon);

        const aziX =
            Angle!double.fromDegrees(item.aziX);

        const aziY =
            Angle!double.fromDegrees(item.aziY);

        P actual;

        if (!nextIntersection(
                solver,
                origin,
                aziX,
                aziY,
                actual))
        {
            writefln(
                "FAIL %-22s D solver failed",
                item.name);
            ++failures;
            continue;
        }

        double rx;
        double ry;
        double rlat;
        double rlon;
        int rc;

        if (!m5_105_reference(
                ellipsoid.semiMajorAxis,
                ellipsoid.flattening,
                item.lat,
                item.lon,
                item.aziX,
                item.aziY,
                &rx,
                &ry,
                &rc,
                &rlat,
                &rlon))
        {
            writefln(
                "FAIL %-22s oracle failed",
                item.name);
            ++failures;
            continue;
        }

        const auto lineX =
            GeodesicLine!double.fromGeodesic(
                solver,
                origin,
                aziX);

        const auto lineY =
            GeodesicLine!double.fromGeodesic(
                solver,
                origin,
                aziY);

        const auto actualX =
            lineX.position(actual.x);

        const auto actualY =
            lineY.position(actual.y);

        const double crossingAngle =
            abs(
                wrapPi(
                    actualY.finalAzimuth.radians
                    - actualX.finalAzimuth.radians));

        const double sinCrossing =
            abs(sin(crossingAngle));

        const double conditioning =
            ellipsoid.semiMajorAxis
            * 512.0
            * double.epsilon
            / (sinCrossing > 1e-15
                ? sinCrossing
                : 1e-15);

        const double displacementTolerance =
            conditioning > 5e-5
                ? conditioning
                : 5e-5;

        const double positionTolerance =
            displacementTolerance
            / ellipsoid.semiMajorAxis
            * 2.0;

        const double xerr =
            abs(actual.x - rx);

        const double yerr =
            abs(actual.y - ry);

        const double poserr =
            coordinateError(
                actualX.position,
                gc(rlat,rlon));

        const bool pass =
            xerr < displacementTolerance
            && yerr < displacementTolerance
            && poserr < positionTolerance
            && actual.c == rc
            && l1(actual) > 0.0;

        writefln(
            "%s %-22s x=%.3e y=%.3e pos=%.3e c=%s/%s",
            pass ? "PASS" : "FAIL",
            item.name,
            xerr,
            yerr,
            poserr,
            actual.c,
            rc);

        if (!pass)
            ++failures;
    }

    if (failures)
    {
        writefln(
            "M5 #105 NEXT PROBE FAIL: %s",
            failures);
        assert(0);
    }

    writeln("M5 #105 NEXT PROBE PASS");
}
