module m5_106_workspace_validation;

import geodesy;

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

private enum EnumerationStatus
{
    success,
    invalidInput,
    workspaceTooSmall,
    numericalFailure
}

private struct Enumeration
{
    size_t written;
    size_t total;
    bool truncated;
    size_t requiredTiles;
    size_t minimumFoundCapacity;
}

private struct Workspace
{
    P[] starts;
    bool[] skip;
    P[] found;
    P[] coincidentCenters;
}

private double l1(const P p)
    pure nothrow @safe @nogc
{
    return abs(p.x) + abs(p.y);
}

private double l1(const P a, const P b)
    pure nothrow @safe @nogc
{
    return abs(a.x - b.x) + abs(a.y - b.y);
}

private bool eq(const P a, const P b, const double delta)
    pure nothrow @safe @nogc
{
    return l1(a, b) <= delta;
}

private bool lessRank(const P a, const P b, const P p0)
    pure nothrow @safe @nogc
{
    const double da = l1(a, p0);
    const double db = l1(b, p0);

    if (da != db)
        return da < db;
    if (a.x != b.x)
        return a.x < b.x;
    return a.y < b.y;
}

private double twoSum(
    const double u,
    const double v,
    out double error)
    pure nothrow @safe @nogc
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
    pure nothrow @safe @nogc
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
    pure nothrow @safe @nogc
{
    const double s = sin(angle);
    const double c = cos(angle);
    const double se = sin(correction);
    const double ce = cos(correction);
    sine = s * ce + c * se;
    cosine = c * ce - s * se;
}

private double authalicRadius(const Geodesic!double solver)
    pure nothrow @safe @nogc
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
    pure nothrow @safe @nogc
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

        double errorX;
        double errorY;
        double errorXY;

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

        const double XY = angleDiff(X, Y, errorXY);
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
        int coincidence;

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

private P fixCoincident(
    const P p0,
    const P p,
    const int forced = 0)
    pure nothrow @safe @nogc
{
    const int c = forced != 0 ? forced : p.c;

    if (c == 0)
        return p;

    const double shift =
        ((p0.x + c * p0.y) - (p.x + c * p.y)) / 2.0;

    return P(
        p.x + shift,
        p.y + c * shift,
        c);
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
    pure nothrow @safe @nogc
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

private bool allSpacing(
    const Geodesic!double solver,
    const double rR,
    out double t1,
    out double d3,
    out double delta,
    out double d)
    pure nothrow @safe @nogc
{
    const double a = solver.ellipsoid.semiMajorAxis;
    const double f = solver.ellipsoid.flattening;

    if (f < 0.0)
        return false;

    d = cast(double) PI * rR;
    t1 = cast(double) PI * a * (1.0 - f);
    delta = d * pow(double.epsilon, 0.2);
    d3 = t1 - delta;

    return d3 > 0.0;
}

private bool containsEq(
    const P[] values,
    const size_t count,
    const P q,
    const double delta)
    pure nothrow @safe @nogc
{
    foreach (i; 0 .. count)
    {
        if (eq(values[i], q, delta))
            return true;
    }

    return false;
}

private void removeCoincidentLine(
    P[] values,
    ref size_t count,
    const P p0,
    const P q,
    const int c,
    const double delta)
    pure nothrow @safe @nogc
{
    size_t outIndex;

    foreach (i; 0 .. count)
    {
        const P p = values[i];

        if (!eq(fixCoincident(p0, p, c), q, delta))
            values[outIndex++] = p;
    }

    count = outIndex;
}

private bool appendPoint(
    P[] values,
    ref size_t count,
    const P value)
    pure nothrow @safe @nogc
{
    if (count >= values.length)
        return false;

    values[count++] = value;
    return true;
}

private void updateSkip(
    bool[] skip,
    const P[] starts,
    const size_t from,
    const P point,
    const double threshold)
    pure nothrow @safe @nogc
{
    foreach (i; from .. starts.length)
    {
        if (!skip[i] && l1(point, starts[i]) < threshold)
            skip[i] = true;
    }
}

private void sortByRank(
    P[] values,
    const size_t count,
    const P p0)
    pure nothrow @safe @nogc
{
    foreach (i; 1 .. count)
    {
        const P value = values[i];
        size_t j = i;

        while (j > 0 && lessRank(value, values[j - 1], p0))
        {
            values[j] = values[j - 1];
            --j;
        }

        values[j] = value;
    }
}

private EnumerationStatus enumerateAllWorkspace(
    const Geodesic!double solver,
    const GeodesicLine!double lineX,
    const GeodesicLine!double lineY,
    const double radius,
    const P p0,
    scope P[] output,
    ref Workspace workspace,
    out Enumeration enumeration)
    pure nothrow @safe @nogc
{
    enumeration = Enumeration.init;

    if (!solver.isValid
        || !lineX.isValid
        || !lineY.isValid
        || !(radius >= 0.0))
        return EnumerationStatus.invalidInput;

    const double rR = authalicRadius(solver);

    double t1;
    double d3max;
    double delta;
    double d;

    if (!allSpacing(
            solver,
            rR,
            t1,
            d3max,
            delta,
            d))
        return EnumerationStatus.invalidInput;

    const double maxdistx = radius + delta;
    size_t tiles =
        cast(size_t) ceil(maxdistx / d3max);

    if (tiles == 0)
        tiles = 1;

    const size_t requiredTiles =
        tiles * tiles + (tiles - 1) % 2;

    enumeration.requiredTiles = requiredTiles;

    if (workspace.starts.length < requiredTiles
        || workspace.skip.length < requiredTiles)
        return EnumerationStatus.workspaceTooSmall;

    const size_t n = tiles - 1;
    const double spacing = maxdistx / tiles;

    size_t startCount;
    workspace.starts[startCount++] = p0;

    for (long i = -cast(long) n;
         i <= cast(long) n;
         i += 2)
    {
        for (long j = -cast(long) n;
             j <= cast(long) n;
             j += 2)
        {
            if (i == 0 && j == 0)
                continue;

            workspace.starts[startCount++] =
                P(
                    p0.x
                        + spacing
                            * cast(double) (i + j)
                            / 2.0,
                    p0.y
                        + spacing
                            * cast(double) (i - j)
                            / 2.0,
                    0);
        }
    }

    if (startCount != requiredTiles)
        return EnumerationStatus.numericalFailure;

    foreach (i; 0 .. requiredTiles)
        workspace.skip[i] = false;

    size_t foundCount;
    size_t coincidentCount;
    int coincidenceOrientation;

    const double skipThreshold =
        2.0 * t1 - spacing - delta;

    foreach (k; 0 .. requiredTiles)
    {
        if (workspace.skip[k])
            continue;

        P q;

        if (!basic(
                solver,
                lineX,
                lineY,
                rR,
                workspace.starts[k],
                q))
            return EnumerationStatus.numericalFailure;

        if (containsEq(
                workspace.found,
                foundCount,
                q,
                delta))
            continue;

        if (coincidenceOrientation != 0
            && containsEq(
                workspace.coincidentCenters,
                coincidentCount,
                fixCoincident(
                    p0,
                    q,
                    coincidenceOrientation),
                delta))
            continue;

        if (q.c != 0)
        {
            coincidenceOrientation = q.c;
            q = fixCoincident(p0, q);

            if (!appendPoint(
                    workspace.coincidentCenters,
                    coincidentCount,
                    q))
            {
                enumeration.minimumFoundCapacity =
                    coincidentCount + 1;
                return EnumerationStatus.workspaceTooSmall;
            }

            removeCoincidentLine(
                workspace.found,
                foundCount,
                p0,
                q,
                coincidenceOrientation,
                delta);

            const double s0 = q.x;

            GeodesicDirectResult!double position;
            GeodesicQuantities!double baseQ;

            if (!lineX.tryPosition(
                    s0,
                    position,
                    baseQ))
                return EnumerationStatus.numericalFailure;

            foreach (sign; [-1.0, 1.0])
            {
                double sa;
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
                        return EnumerationStatus.numericalFailure;

                    sa = absolute - s0;

                    qc =
                        P(
                            q.x + sa,
                            q.y
                                + coincidenceOrientation * sa,
                            coincidenceOrientation);

                    if (!containsEq(
                            workspace.found,
                            foundCount,
                            qc,
                            delta))
                    {
                        if (!appendPoint(
                                workspace.found,
                                foundCount,
                                qc))
                        {
                            enumeration.minimumFoundCapacity =
                                foundCount + 1;
                            return EnumerationStatus.workspaceTooSmall;
                        }
                    }

                    updateSkip(
                        workspace.skip[0 .. requiredTiles],
                        workspace.starts[0 .. requiredTiles],
                        k + 1,
                        qc,
                        skipThreshold);
                }
                while (l1(qc, p0) <= maxdistx);
            }
        }

        if (!containsEq(
                workspace.found,
                foundCount,
                q,
                delta))
        {
            if (!appendPoint(
                    workspace.found,
                    foundCount,
                    q))
            {
                enumeration.minimumFoundCapacity =
                    foundCount + 1;
                return EnumerationStatus.workspaceTooSmall;
            }
        }

        updateSkip(
            workspace.skip[0 .. requiredTiles],
            workspace.starts[0 .. requiredTiles],
            k + 1,
            q,
            skipThreshold);
    }

    size_t retainedCount;

    foreach (i; 0 .. foundCount)
    {
        const P p = workspace.found[i];

        if (l1(p, p0) <= radius)
            workspace.found[retainedCount++] = p;
    }

    foundCount = retainedCount;

    sortByRank(
        workspace.found,
        foundCount,
        p0);

    const size_t written =
        output.length < foundCount
            ? output.length
            : foundCount;

    foreach (i; 0 .. written)
        output[i] = workspace.found[i];

    enumeration.written = written;
    enumeration.total = foundCount;
    enumeration.truncated = written < foundCount;
    enumeration.minimumFoundCapacity = foundCount;

    return EnumerationStatus.success;
}

private GeographicCoordinate!double gc(
    const double lat,
    const double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
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

    const solver =
        Geodesic!double.fromEllipsoid(ellipsoid);

    GeodesicLine!double lineX;
    GeodesicLine!double lineY;

    if (!GeodesicLine!double.tryFromGeodesic(
            solver,
            gc(item.latX, item.lonX),
            Angle!double.fromDegrees(item.aziX),
            lineX)
        || !GeodesicLine!double.tryFromGeodesic(
            solver,
            gc(item.latY, item.lonY),
            Angle!double.fromDegrees(item.aziY),
            lineY))
    {
        writefln("FAIL %-31s line preparation", item.name);
        return false;
    }

    P[64] startsStorage;
    bool[64] skipStorage;
    P[128] foundStorage;
    P[64] coincidentStorage;
    P[64] outputStorage;

    Workspace workspace =
        Workspace(
            startsStorage[],
            skipStorage[],
            foundStorage[],
            coincidentStorage[]);

    Enumeration enumeration;

    const auto status =
        enumerateAllWorkspace(
            solver,
            lineX,
            lineY,
            item.radius,
            P(item.p0x, item.p0y, 0),
            outputStorage[],
            workspace,
            enumeration);

    if (status != EnumerationStatus.success)
    {
        writefln(
            "FAIL %-31s workspace status=%s tiles=%s minFound=%s",
            item.name,
            status,
            enumeration.requiredTiles,
            enumeration.minimumFoundCapacity);
        return false;
    }

    double[64] xs;
    double[64] ys;
    int[64] cs;
    size_t expectedCount;

    const int rc =
        m5_106_reference(
            ellipsoid.semiMajorAxis,
            ellipsoid.flattening,
            item.latX,item.lonX,item.aziX,
            item.latY,item.lonY,item.aziY,
            item.p0x,item.p0y,item.radius,
            64,
            &expectedCount,
            xs.ptr,ys.ptr,cs.ptr);

    if (rc != 1
        || enumeration.total != expectedCount
        || enumeration.written != expectedCount
        || enumeration.truncated)
    {
        writefln(
            "FAIL %-31s count/status total=%s expected=%s written=%s truncated=%s rc=%s",
            item.name,
            enumeration.total,
            expectedCount,
            enumeration.written,
            enumeration.truncated,
            rc);
        return false;
    }

    bool[64] matched;
    double maxError = 0.0;
    const P p0 = P(item.p0x, item.p0y, 0);

    foreach (p; outputStorage[0 .. enumeration.written])
    {
        const double tolerance =
            2e-4 > 128.0 * double.epsilon * (1.0 + l1(p, p0))
                ? 2e-4
                : 128.0 * double.epsilon * (1.0 + l1(p, p0));

        size_t bestIndex = size_t.max;
        double bestError = double.infinity;

        foreach (i; 0 .. expectedCount)
        {
            if (matched[i] || p.c != cs[i])
                continue;

            const double err =
                abs(p.x - xs[i]) + abs(p.y - ys[i]);

            if (err < bestError)
            {
                bestError = err;
                bestIndex = i;
            }
        }

        if (bestIndex == size_t.max
            || bestError > tolerance)
        {
            writefln(
                "FAIL %-31s unmatched err=%.3e",
                item.name,
                bestError);
            return false;
        }

        matched[bestIndex] = true;

        if (bestError > maxError)
            maxError = bestError;
    }

    /*
     * Zero-output count query: same full enumeration, no result storage.
     */
    Enumeration countOnly;
    const auto countStatus =
        enumerateAllWorkspace(
            solver,
            lineX,
            lineY,
            item.radius,
            p0,
            null,
            workspace,
            countOnly);

    if (countStatus != EnumerationStatus.success
        || countOnly.total != expectedCount
        || countOnly.written != 0
        || countOnly.truncated != (expectedCount != 0))
    {
        writefln(
            "FAIL %-31s zero-output total=%s expected=%s written=%s truncated=%s status=%s",
            item.name,
            countOnly.total,
            expectedCount,
            countOnly.written,
            countOnly.truncated,
            countStatus);
        return false;
    }

    /*
     * Deliberately short output must succeed and return the canonical prefix.
     */
    P[2] shortOutput;
    Enumeration shortResult;
    const auto shortStatus =
        enumerateAllWorkspace(
            solver,
            lineX,
            lineY,
            item.radius,
            p0,
            shortOutput[],
            workspace,
            shortResult);

    const size_t expectedWritten =
        expectedCount < shortOutput.length
            ? expectedCount
            : shortOutput.length;

    if (shortStatus != EnumerationStatus.success
        || shortResult.total != expectedCount
        || shortResult.written != expectedWritten
        || shortResult.truncated != (expectedWritten < expectedCount))
    {
        writefln(
            "FAIL %-31s truncation total=%s written=%s expectedWritten=%s truncated=%s status=%s",
            item.name,
            shortResult.total,
            shortResult.written,
            expectedWritten,
            shortResult.truncated,
            shortStatus);
        return false;
    }

    foreach (i; 0 .. expectedWritten)
    {
        if (shortOutput[i] != outputStorage[i])
        {
            writefln(
                "FAIL %-31s truncated prefix mismatch at %s",
                item.name,
                i);
            return false;
        }
    }

    writefln(
        "PASS %-31s total=%3s tiles=%2s max_l1_err=%.3e",
        item.name,
        enumeration.total,
        enumeration.requiredTiles,
        maxError);

    return true;
}

private bool qualifyWorkspaceTooSmall()
{
    const solver =
        Geodesic!double.fromEllipsoid(wgs84!double());

    GeodesicLine!double lineX;
    GeodesicLine!double lineY;

    if (!GeodesicLine!double.tryFromGeodesic(
            solver,
            gc(10,20),
            Angle!double.fromDegrees(45),
            lineX)
        || !GeodesicLine!double.tryFromGeodesic(
            solver,
            gc(11,21),
            Angle!double.fromDegrees(45.1),
            lineY))
        return false;

    P[2] tinyStarts;
    bool[2] tinySkip;
    P[2] tinyFound;
    P[2] tinyCoincident;
    P[1] output;

    Workspace tiny =
        Workspace(
            tinyStarts[],
            tinySkip[],
            tinyFound[],
            tinyCoincident[]);

    Enumeration result;

    const auto status =
        enumerateAllWorkspace(
            solver,
            lineX,
            lineY,
            70_000_000.0,
            P(0,0,0),
            output[],
            tiny,
            result);

    const bool pass =
        status == EnumerationStatus.workspaceTooSmall
        && result.requiredTiles > tinyStarts.length;

    writefln(
        "%s workspace-too-small requiredTiles=%s available=%s",
        pass ? "PASS" : "FAIL",
        result.requiredTiles,
        tinyStarts.length);

    return pass;
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
            -25,70,-35, 5,-110,145,
            1_000_000,-500_000,50_000_000),
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
            0,0,30, 0,0,120,
            0,0,39_924_025.252815932),
        Case("wgs84_boundary_inside",false,
            0,0,30, 0,0,120,
            0,0,40_042_530.068560898)
    ];

    size_t failures;

    foreach (item; cases)
    {
        if (!compareCase(item))
            ++failures;
    }

    if (!qualifyWorkspaceTooSmall())
        ++failures;

    if (failures)
    {
        writefln(
            "R106.3 WORKSPACE QUALIFICATION FAIL: %s",
            failures);
        assert(0);
    }

    writeln("R106.3 WORKSPACE QUALIFICATION PASS");
}
