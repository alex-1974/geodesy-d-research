module m5_104_closest_validation;

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
int m5_104_reference(
    double a,
    double f,
    double latX,
    double lonX,
    double aziX,
    double latY,
    double lonY,
    double aziY,
    double p0x,
    double p0y,
    double* x,
    double* y,
    int* coincidence,
    double* lat,
    double* lon);

private struct P
{
    double x;
    double y;
    int c;
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

private double l1(const P a, const P b)
{
    return abs(a.x - b.x) + abs(a.y - b.y);
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

        const double X =
            wrapPi(
                inv.initialAzimuth.radians
                - px.finalAzimuth.radians);

        const double Y =
            wrapPi(
                inv.finalAzimuth.radians
                - py.finalAzimuth.radians);

        const double sign =
            copysign(
                1.0,
                wrapPi(Y - X));

        const double sinX = sin(sign * X);
        const double cosX = cos(sign * X);
        const double sinY = sin(sign * Y);
        const double cosY = cos(sign * Y);

        double dx;
        double dy;
        int c = 0;

        if (z <= eps * rR)
        {
            dx = dy = 0.0;

            if (abs(sinX - sinY) <= eps
                && abs(cosX - cosY) <= eps)
                c = 1;
            else if (abs(sinX + sinY) <= eps
                && abs(cosX + cosY) <= eps)
                c = -1;
        }
        else if (abs(sinX) <= eps
            && abs(sinY) <= eps)
        {
            c = cosX * cosY > 0.0 ? 1 : -1;
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
        p.c = c;

        if (c != 0
            || abs(dx) + abs(dy) <= tol)
            return true;
    }

    return false;
}

private P fixCoincident(const P p0, const P p)
{
    if (p.c == 0)
        return p;

    const double s =
        (
            (p0.x + p.c * p0.y)
            - (p.x + p.c * p.y)
        ) / 2.0;

    return P(
        p.x + s,
        p.y + p.c * s,
        p.c);
}

private bool conjugateDistance(
    const GeodesicLine!double line,
    const double tolerance,
    const double initial,
    const bool semi,
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

        /*
         * Point 2 is the line origin here: m12=0, M12=M21=1.
         * Karney eqs. 31-33 therefore simplify to:
         */
        const double m23 = m13;
        const double M23 = M13;
        const double M32 = M31;

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

private bool closestSpacing(
    const Geodesic!double solver,
    const double rR,
    out double t1,
    out double d1,
    out double delta)
{
    const double a = solver.ellipsoid.semiMajorAxis;
    const double f = solver.ellipsoid.flattening;
    const double d = cast(double) PI * rR;

    t1 =
        cast(double) PI * a * (1.0 - f);

    delta =
        d * pow(double.epsilon, 0.2);

    if (f == 0.0)
    {
        d1 = cast(double) PI * a / 2.0;
        return true;
    }

    const auto pole =
        GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(90.0),
            Longitude!double.fromDegrees(0.0));

    const auto line =
        GeodesicLine!double.fromGeodesic(
            solver,
            pole,
            Angle!double.fromDegrees(0.0));

    const double tolerance =
        d * pow(double.epsilon, 0.75);

    const double initial =
        (1.0 + f / 2.0)
        * a
        * cast(double) PI
        / 2.0;

    return conjugateDistance(
        line,
        tolerance,
        initial,
        true,
        d1);
}

private bool better(const P candidate, const P best, const P p0)
{
    const double dc = l1(candidate, p0);
    const double db = l1(best, p0);

    if (dc != db)
        return dc < db;

    if (candidate.x != best.x)
        return candidate.x < best.x;

    return candidate.y < best.y;
}

private bool closest(
    const Geodesic!double solver,
    const GeographicCoordinate!double startX,
    const Angle!double aziX,
    const GeographicCoordinate!double startY,
    const Angle!double aziY,
    const P p0,
    out P result)
{
    const auto lineX =
        GeodesicLine!double.fromGeodesic(
            solver,
            startX,
            aziX);

    const auto lineY =
        GeodesicLine!double.fromGeodesic(
            solver,
            startY,
            aziY);

    const double rR = authalicRadius(solver);

    double t1;
    double d1;
    double delta;

    if (!closestSpacing(
            solver,
            rR,
            t1,
            d1,
            delta))
        return false;

    const int[5] ix = [0, 1, -1, 0, 0];
    const int[5] iy = [0, 0, 0, 1, -1];
    bool[5] skip;

    bool haveBest = false;
    P best;

    foreach (n; 0 .. 5)
    {
        if (skip[n])
            continue;

        P q;

        if (!basic(
                solver,
                lineX,
                lineY,
                rR,
                P(
                    p0.x + ix[n] * d1,
                    p0.y + iy[n] * d1,
                    0),
                q))
            return false;

        q = fixCoincident(p0, q);

        if (haveBest
            && l1(best, q) <= delta)
            continue;

        if (l1(q, p0) < t1)
        {
            best = q;
            haveBest = true;
            break;
        }

        if (!haveBest || better(q, best, p0))
        {
            best = q;
            haveBest = true;
        }

        foreach (m; n + 1 .. 5)
        {
            const P seed =
                P(
                    p0.x + ix[m] * d1,
                    p0.y + iy[m] * d1,
                    0);

            if (l1(q, seed)
                < 2.0 * t1 - d1 - delta)
                skip[m] = true;
        }
    }

    if (!haveBest)
        return false;

    result = best;
    return true;
}

private GeographicCoordinate!double gc(
    const double lat,
    const double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private double coordinateError(
    const GeographicCoordinate!double a,
    const GeographicCoordinate!double b)
{
    const double dlat =
        abs(a.latitude.radians - b.latitude.radians);

    const double dlon =
        abs(wrapPi(
            a.longitude.radians
                - b.longitude.radians));

    return dlat > dlon ? dlat : dlon;
}

private struct Case
{
    string name;
    bool sphere;
    double latX,lonX,aziX;
    double latY,lonY,aziY;
    double p0x,p0y;
}

void main()
{
    Case[] cases = [
        Case("ordinary",false,0,-20,45,10,20,-60,0,0),
        Case("offset",false,0,-20,45,10,20,-60,2.5e6,-1.0e6),
        Case("antimeridian",false,15,175,80,-20,-175,10,0,0),
        Case("polar",false,80,-60,20,82,50,-80,0,0),
        Case("near parallel",false,10,-30,85,10.1,-30,85.1,0,0),
        Case("coincident same",false,0,0,90,0,10,90,1.0e6,-2.0e6),
        Case("coincident reverse",false,0,0,90,0,10,-90,-2.0e6,1.0e6),
        Case("sphere ordinary",true,0,-20,45,10,20,-60,0,0),
        Case("sphere offset",true,25,-40,70,-10,80,-20,3.0e6,2.0e6),
        Case("large offset",false,-20,-120,30,35,80,-110,1.5e7,-1.1e7),
        Case("reverse x",false,0,-20,225,10,20,-60,0,0),
        Case("reverse y",false,0,-20,45,10,20,120,0,0),
        Case("near coincident",false,5,-40,80,5.00001,-40.00001,80.00001,0,0),
        Case("coincident same shifted",false,0,0,90,0,10,90,8.0e6,3.0e6),
        Case("coincident reverse shifted",false,0,0,90,0,10,-90,8.0e6,-3.0e6),
        Case("polar offset",false,88,-160,40,86,30,-100,-6.0e6,4.0e6)
    ];

    size_t failures = 0;

    foreach (item; cases)
    {
        const ellipsoid =
            item.sphere
                ? Ellipsoid!double.sphere(6_371_000.0)
                : wgs84!double();

        const solver =
            Geodesic!double.fromEllipsoid(
                ellipsoid);

        P actual;

        if (!closest(
                solver,
                gc(item.latX,item.lonX),
                Angle!double.fromDegrees(item.aziX),
                gc(item.latY,item.lonY),
                Angle!double.fromDegrees(item.aziY),
                P(item.p0x,item.p0y,0),
                actual))
        {
            writefln("FAIL %-20s D solver failed",item.name);
            ++failures;
            continue;
        }

        double rx,ry,rlat,rlon;
        int rc;

        const int ok =
            m5_104_reference(
                ellipsoid.semiMajorAxis,
                ellipsoid.flattening,
                item.latX,item.lonX,item.aziX,
                item.latY,item.lonY,item.aziY,
                item.p0x,item.p0y,
                &rx,&ry,&rc,&rlat,&rlon);

        if (!ok)
        {
            writefln("FAIL %-20s oracle failed",item.name);
            ++failures;
            continue;
        }

        GeodesicLine!double lineX =
            GeodesicLine!double.fromGeodesic(
                solver,
                gc(item.latX,item.lonX),
                Angle!double.fromDegrees(item.aziX));

        const auto actualPosition =
            lineX.position(actual.x).position;

        const auto expectedPosition =
            gc(rlat,rlon);

        const double xerr=abs(actual.x-rx);
        const double yerr=abs(actual.y-ry);
        const double poserr=
            coordinateError(
                actualPosition,
                expectedPosition);

        const bool pass =
            xerr < 2e-5
            && yerr < 2e-5
            && poserr < 3e-12
            && actual.c == rc;

        writefln(
            "%s %-20s x=%.3e y=%.3e pos=%.3e c=%s/%s",
            pass?"PASS":"FAIL",
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
        writefln("M5 #104 CLOSEST PROBE FAIL: %s",failures);
        assert(0);
    }

    writeln("M5 #104 CLOSEST PROBE PASS");
}
