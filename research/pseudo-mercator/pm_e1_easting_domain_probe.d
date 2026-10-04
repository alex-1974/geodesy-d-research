/**
 * PM-E1A — represented Pseudo-Mercator easting-domain characterization.
 *
 * Research-only.
 *
 * Goal:
 *
 * Translate the PM-D mathematical principal sheet
 *
 *     -pi <= deltaLambda < +pi
 *
 * plus
 *
 *     legal represented value wins
 *
 * into deterministic public-T reverse acceptance behaviour.
 */
module pm_e1_easting_domain_probe;

import geodesy.angle :
    Longitude;

import std.exception :
    enforce;

import std.math :
    PI,
    isFinite,
    nextDown,
    nextUp;

import std.stdio :
    writeln,
    writefln;


private template WorkingScalar(T)
{
    static if (is(T == float))
        alias WorkingScalar = double;
    else
        alias WorkingScalar = T;
}


private W pi(W)()
{
    return cast(W) PI;
}


private void twoSum(W)(
    const W a,
    const W b,
    out W sum,
    out W residual)
{
    sum = a + b;

    const W z =
        sum - a;

    residual =
        (a - (sum - z))
        + (b - z);
}


private T canonicalPublicRadians(T)(
    const T radians)
{
    const T p =
        cast(T) PI;

    const T twoP =
        cast(T) 2 * p;

    T result =
        radians;

    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    return result == cast(T) 0
        ? cast(T) 0
        : result;
}


private WorkingScalar!T workingCanonicalLongitude(T)(
    const T radians)
{
    alias W = WorkingScalar!T;

    const T canonical =
        canonicalPublicRadians(
            radians);

    const T publicPi =
        cast(T) PI;

    /*
     * Preserve the public scalar's exact cardinal semantics when
     * lifting into working precision.
     */
    if (canonical == cast(T) 0)
        return cast(W) 0;

    if (canonical == -publicPi)
        return -pi!W;

    const T halfPi =
        publicPi / cast(T) 2;

    if (canonical == halfPi)
        return pi!W / cast(W) 2;

    if (canonical == -halfPi)
        return -pi!W / cast(W) 2;

    return cast(W) canonical;
}


private WorkingScalar!T longitudeDifference(T)(
    const T longitude,
    const T longitude0)
{
    alias W = WorkingScalar!T;

    const W source =
        workingCanonicalLongitude!T(
            longitude);

    const W origin =
        workingCanonicalLongitude!T(
            longitude0);

    W sum;
    W residual;

    twoSum(
        source,
        -origin,
        sum,
        residual);

    const W p =
        pi!W;

    const W twoP =
        cast(W) 2 * p;

    if (sum > p
        || (sum == p
            && residual >= cast(W) 0))
    {
        sum -= twoP;
    }
    else if (sum < -p
        || (sum == -p
            && residual < cast(W) 0))
    {
        sum += twoP;
    }

    W result =
        sum + residual;

    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    return result;
}


private T forwardEasting(T)(
    const T longitude,
    const T longitude0,
    const T a,
    const T falseEasting)
{
    alias W = WorkingScalar!T;

    const W delta =
        longitudeDifference!T(
            longitude,
            longitude0);

    const W result =
        cast(W) falseEasting
        + cast(W) a * delta;

    return cast(T) result;
}


private bool validPublicLongitude(T)(
    const T radians)
{
    const T p =
        cast(T) PI;

    return isFinite(radians)
        && radians >= -p
        && radians <= p;
}


/*
 * Examine the public-longitude neighbourhood around the meridian opposite
 * longitude0.
 *
 * For fixed public scalar T, the greatest legal positive longitude
 * difference must occur in this local neighbourhood immediately before the
 * canonical +pi tie.
 */
private T representedEastMaximum(T)(
    const T longitude0,
    const T a,
    const T falseEasting,
    out WorkingScalar!T bestDelta,
    out T bestLongitude,
    out size_t bestDistance)
{
    alias W = WorkingScalar!T;

    enum size_t searchRadius = 4096;

    const W p =
        pi!W;

    const W origin =
        workingCanonicalLongitude!T(
            longitude0);

    W opposite =
        origin + p;

    const W twoP =
        cast(W) 2 * p;

    if (opposite >= p)
        opposite -= twoP;
    else if (opposite < -p)
        opposite += twoP;

    T centre =
        cast(T) opposite;

    const T publicPi =
        cast(T) PI;

    if (!validPublicLongitude(centre))
    {
        centre =
            centre > cast(T) 0
                ? publicPi
                : -publicPi;
    }

    bool found = false;

    T bestEasting =
        T.nan;

    bestDelta =
        -W.infinity;

    bestLongitude =
        T.nan;

    bestDistance =
        size_t.max;


    void considerCandidate(
        const T candidate,
        const size_t distance)
    {
        if (!validPublicLongitude(candidate))
            return;

        const W delta =
            longitudeDifference!T(
                candidate,
                longitude0);

        /*
         * Exact +pi has already canonicalized to -pi.
         *
         * Select the greatest actually representable legal positive
         * principal-sheet longitude difference.
         */
        if (!(delta >= cast(W) 0)
            || !(delta < p))
            return;

        if (!found
            || delta > bestDelta)
        {
            found = true;

            bestDelta =
                delta;

            bestLongitude =
                candidate;

            bestDistance =
                distance;

            bestEasting =
                forwardEasting!T(
                    candidate,
                    longitude0,
                    a,
                    falseEasting);
        }
    }


    void scanCentre(
        const T scanValue)
    {
        considerCandidate(
            scanValue,
            0);

        T lower =
            scanValue;

        T upper =
            scanValue;

        foreach (distance; 1 .. searchRadius + 1)
        {
            lower =
                nextDown(lower);

            upper =
                nextUp(upper);

            considerCandidate(
                lower,
                distance);

            considerCandidate(
                upper,
                distance);
        }
    }


    scanCentre(
        centre);

    /*
     * Public Longitude<T> accepts both +/-pi even though normalized
     * longitude is half-open. At that seam inspect both public
     * representations.
     */
    if (centre == -publicPi)
    {
        scanCentre(
            publicPi);
    }
    else if (centre == publicPi)
    {
        scanCentre(
            -publicPi);
    }

    enforce(
        found,
        "PM-E1A failed to locate a legal positive "
        ~ "principal-sheet longitude neighbour.");

    enforce(
        bestDistance < searchRadius,
        "PM-E1A best legal east neighbour reached the "
        ~ "search-radius boundary; enlarge or redesign the probe.");

    return bestEasting;
}


private void probeProfile(T)(
    const string scalarName,
    const string profileName,
    const real longitude0Degrees,
    const T a,
    const T falseEasting)
{
    alias W = WorkingScalar!T;

    Longitude!T origin;

    enforce(
        Longitude!T.tryFromDegrees(
            cast(T) longitude0Degrees,
            origin),
        "PM-E1A failed to construct longitude of natural origin.");

    const W p =
        pi!W;

    const W rawWest =
        cast(W) falseEasting
        - cast(W) a * p;

    const W rawEast =
        cast(W) falseEasting
        + cast(W) a * p;

    const T representedWest =
        cast(T) rawWest;

    const T representedEastEdge =
        cast(T) rawEast;

    W eastDelta;
    T eastLongitude;
    size_t eastSearchDistance;

    const T representedEastMaximumValue =
        representedEastMaximum!T(
            origin.radians,
            a,
            falseEasting,
            eastDelta,
            eastLongitude,
            eastSearchDistance);

    const T westOutside =
        nextDown(
            representedWest);

    const T eastOutside =
        nextUp(
            representedEastMaximumValue);

    const W reconstructedWest =
        (
            cast(W) representedWest
            - cast(W) falseEasting
        ) / cast(W) a;

    const W reconstructedEastMaximum =
        (
            cast(W) representedEastMaximumValue
            - cast(W) falseEasting
        ) / cast(W) a;

    const W reconstructedEastEdge =
        (
            cast(W) representedEastEdge
            - cast(W) falseEasting
        ) / cast(W) a;

    const W reconstructedWestOutside =
        (
            cast(W) westOutside
            - cast(W) falseEasting
        ) / cast(W) a;

    const W reconstructedEastOutside =
        (
            cast(W) eastOutside
            - cast(W) falseEasting
        ) / cast(W) a;

    const bool westNeedsRepresentationRescue =
        reconstructedWest < -p;

    const bool eastMaximumNeedsRepresentationRescue =
        reconstructedEastMaximum >= p;

    const bool eastMathematicalEdgeIsLegalRepresentation =
        representedEastMaximumValue
        == representedEastEdge;

    const bool westOutsideStillLooksMathematicallyInside =
        reconstructedWestOutside >= -p
        && reconstructedWestOutside < p;

    const bool eastOutsideStillLooksMathematicallyInside =
        reconstructedEastOutside >= -p
        && reconstructedEastOutside < p;

    writefln(
        "PROFILE\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%u\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%s\t%s\t%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s\t%s",
        scalarName,
        T.mant_dig,
        profileName,
        origin.radians,
        eastLongitude,
        eastDelta,
        eastSearchDistance,
        representedWest,
        representedEastMaximumValue,
        representedEastEdge,
        reconstructedWest,
        reconstructedEastMaximum,
        reconstructedEastEdge,
        westNeedsRepresentationRescue,
        eastMaximumNeedsRepresentationRescue,
        eastMathematicalEdgeIsLegalRepresentation,
        westOutside,
        eastOutside,
        westOutsideStillLooksMathematicallyInside,
        eastOutsideStillLooksMathematicallyInside);
}


private void probeScalar(T)(
    const string scalarName)
{
    foreach (longitude0Degrees; [
        0.0L,
        12.345L,
        90.0L,
        -90.0L,
        170.0L,
        -170.0L,
        179.75L,
        -179.75L
    ])
    {
        import std.conv : to;

        const string suffix =
            longitude0Degrees.to!string;

        probeProfile!T(
            scalarName,
            "unit_lon0_" ~ suffix,
            longitude0Degrees,
            cast(T) 1,
            cast(T) 0);

        probeProfile!T(
            scalarName,
            "wgs84_lon0_" ~ suffix,
            longitude0Degrees,
            cast(T) 6_378_137,
            cast(T) 0);

        probeProfile!T(
            scalarName,
            "wgs84_offset_lon0_" ~ suffix,
            longitude0Degrees,
            cast(T) 6_378_137,
            cast(T) 500_000);
    }
}


void main()
{
    writeln(
        "# PM-E1A represented easting-domain probe");

    probeScalar!float(
        "float");

    probeScalar!double(
        "double");

    probeScalar!real(
        "real");
}
