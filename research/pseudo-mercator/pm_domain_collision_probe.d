/**
 * PM-D public-representation boundary collision study.
 *
 * Research-only.
 *
 * Questions:
 *
 * 1. Can the last representable legal longitude east of the principal sheet
 *    round to the same public easting as the excluded mathematical +pi edge?
 *
 * 2. Can the last legal latitude inside +/-88 degrees collapse onto the
 *    represented +/-88 degree northing boundary?
 *
 * 3. Can the first projected value outside the northing boundary reverse to a
 *    represented Latitude<T> which still appears to be inside the domain?
 *
 * 4. Does residual-aware longitude reconstruction reproduce the original
 *    normalized public Longitude<T>?
 */
module pm_domain_collision_probe;

import geodesy.angle :
    Latitude,
    Longitude;

import std.math :
    PI,
    asinh,
    atan,
    nextDown,
    nextUp,
    sinh,
    tan;

import std.stdio :
    writeln,
    writefln;


private real rp()
{
    return cast(real) PI;
}


private void twoSum(T)(
    const T a,
    const T b,
    out T sum,
    out T residual)
{
    sum = a + b;

    const T z = sum - a;

    residual =
        (a - (sum - z))
        + (b - z);
}


private T normalizeRadians(T)(
    const T radians)
{
    const T p = cast(T) PI;
    const T twoP = cast(T) 2 * p;

    T result = radians;

    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    return result;
}


private T longitudeDifference(T)(
    const T longitude,
    const T longitude0)
{
    T sum;
    T residual;

    twoSum(
        longitude,
        -longitude0,
        sum,
        residual);

    const T p = cast(T) PI;
    const T twoP = cast(T) 2 * p;

    if (sum > p
        || (sum == p
            && residual >= cast(T) 0))
    {
        sum -= twoP;
    }
    else if (sum < -p
        || (sum == -p
            && residual < cast(T) 0))
    {
        sum += twoP;
    }

    return normalizeRadians(
        sum + residual);
}


private T addLongitude(T)(
    const T longitude0,
    const T delta)
{
    T sum;
    T residual;

    twoSum(
        longitude0,
        delta,
        sum,
        residual);

    return normalizeRadians(
        sum + residual);
}


private void emitEastingCollision(T)(
    const string scalarName,
    const string profileName,
    const T a,
    const T falseEasting)
{
    /*
     * Public T stores pi approximately.
     *
     * The exact canonical endpoint -pi should be lifted semantically to
     * working precision rather than by blindly widening T(-pi).
     *
     * The closest ordinary legal east-side public delta is represented here
     * by nextDown(T(pi)).
     */
    const T publicPi =
        cast(T) PI;

    const T legalEastDelta =
        nextDown(publicPi);

    const real ar =
        cast(real) a;

    const real fer =
        cast(real) falseEasting;

    const T westBoundary =
        cast(T) (
            fer
            - ar * rp());

    const T eastExcluded =
        cast(T) (
            fer
            + ar * rp());

    const T legalEast =
        cast(T) (
            fer
            + ar * cast(real) legalEastDelta);

    const bool eastCollision =
        legalEast == eastExcluded;

    const real reverseLegalEastDelta =
        (
            cast(real) legalEast
            - fer
        ) / ar;

    const real reverseExcludedDelta =
        (
            cast(real) eastExcluded
            - fer
        ) / ar;

    writefln(
        "EAST\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%s\t"
        ~ "%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        profileName,
        publicPi,
        legalEastDelta,
        westBoundary,
        legalEast,
        eastExcluded,
        eastCollision,
        reverseLegalEastDelta,
        reverseExcludedDelta);
}


private void emitNorthingCollision(T)(
    const string scalarName,
    const string profileName,
    const T a,
    const T falseNorthing)
{
    Latitude!T northLatitude;

    if (!Latitude!T.tryFromDegrees(
            cast(T) 88,
            northLatitude))
    {
        writeln(
            "FAIL latitude construction");
        return;
    }

    const T northPhi =
        northLatitude.radians;

    const T northInsidePhi =
        nextDown(northPhi);

    const T southPhi =
        -northPhi;

    const T southInsidePhi =
        nextUp(southPhi);

    const real ar =
        cast(real) a;

    const real fnr =
        cast(real) falseNorthing;

    const real northQ =
        asinh(
            tan(
                cast(real) northPhi));

    const real northInsideQ =
        asinh(
            tan(
                cast(real) northInsidePhi));

    const real southQ =
        asinh(
            tan(
                cast(real) southPhi));

    const real southInsideQ =
        asinh(
            tan(
                cast(real) southInsidePhi));

    const T northBoundary =
        cast(T) (
            fnr
            + ar * northQ);

    const T northInside =
        cast(T) (
            fnr
            + ar * northInsideQ);

    const T southBoundary =
        cast(T) (
            fnr
            + ar * southQ);

    const T southInside =
        cast(T) (
            fnr
            + ar * southInsideQ);

    const T firstNorthOutside =
        nextUp(northBoundary);

    const T firstSouthOutside =
        nextDown(southBoundary);

    const real qNorthOutside =
        (
            cast(real) firstNorthOutside
            - fnr
        ) / ar;

    const real qSouthOutside =
        (
            cast(real) firstSouthOutside
            - fnr
        ) / ar;

    const T reversedNorthOutsidePhi =
        cast(T) atan(
            sinh(qNorthOutside));

    const T reversedSouthOutsidePhi =
        cast(T) atan(
            sinh(qSouthOutside));

    const bool northBoundaryCollision =
        northInside
        == northBoundary;

    const bool southBoundaryCollision =
        southInside
        == southBoundary;

    const bool northOutsideLooksInside =
        reversedNorthOutsidePhi
        <= northPhi;

    const bool southOutsideLooksInside =
        reversedSouthOutsidePhi
        >= southPhi;

    writefln(
        "NORTH\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s\t%s",
        scalarName,
        T.mant_dig,
        profileName,
        northPhi,
        northInsidePhi,
        northInside,
        northBoundary,
        northBoundaryCollision,
        firstNorthOutside,
        reversedNorthOutsidePhi,
        northOutsideLooksInside,
        southBoundaryCollision);

    writefln(
        "SOUTH\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s",
        scalarName,
        T.mant_dig,
        profileName,
        southPhi,
        southInsidePhi,
        southInside,
        southBoundary,
        southBoundaryCollision,
        firstSouthOutside,
        reversedSouthOutsidePhi,
        southOutsideLooksInside);
}


private void emitLongitudeParity(T)(
    const string scalarName,
    const string label,
    const T longitude0Degrees,
    const T longitudeDegrees)
{
    Longitude!T longitude0;
    Longitude!T longitude;

    if (!Longitude!T.tryFromDegrees(
            longitude0Degrees,
            longitude0)
        || !Longitude!T.tryFromDegrees(
            longitudeDegrees,
            longitude))
    {
        writeln(
            "FAIL longitude construction");
        return;
    }

    const T delta =
        longitudeDifference(
            longitude.radians,
            longitude0.radians);

    const T recoveredRadians =
        addLongitude(
            longitude0.radians,
            delta);

    Longitude!T recovered;

    if (!Longitude!T.tryFromRadians(
            recoveredRadians,
            recovered))
    {
        writeln(
            "FAIL longitude recovery");
        return;
    }

    const T expected =
        longitude.normalized.radians;

    const T actual =
        recovered.normalized.radians;

    writefln(
        "LON\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s",
        scalarName,
        T.mant_dig,
        label,
        longitude0.radians,
        longitude.radians,
        delta,
        expected,
        actual,
        expected == actual);
}


private void probeScalar(T)(
    const string scalarName)
{
    emitEastingCollision!T(
        scalarName,
        "unit",
        cast(T) 1,
        cast(T) 0);

    emitEastingCollision!T(
        scalarName,
        "wgs84_zero",
        cast(T) 6_378_137,
        cast(T) 0);

    emitEastingCollision!T(
        scalarName,
        "wgs84_offset",
        cast(T) 6_378_137,
        cast(T) 500_000);

    emitNorthingCollision!T(
        scalarName,
        "unit",
        cast(T) 1,
        cast(T) 0);

    emitNorthingCollision!T(
        scalarName,
        "wgs84_zero",
        cast(T) 6_378_137,
        cast(T) 0);

    emitNorthingCollision!T(
        scalarName,
        "wgs84_offset",
        cast(T) 6_378_137,
        cast(T) -2_000_000);

    emitLongitudeParity!T(
        scalarName,
        "zero_to_east180",
        cast(T) 0,
        cast(T) 180);

    emitLongitudeParity!T(
        scalarName,
        "zero_to_west180",
        cast(T) 0,
        cast(T) -180);

    emitLongitudeParity!T(
        scalarName,
        "cross_east",
        cast(T) 179.75,
        cast(T) -179.75);

    emitLongitudeParity!T(
        scalarName,
        "cross_west",
        cast(T) -179.75,
        cast(T) 179.75);

    emitLongitudeParity!T(
        scalarName,
        "170_to_minus10",
        cast(T) 170,
        cast(T) -10);

    emitLongitudeParity!T(
        scalarName,
        "minus170_to_10",
        cast(T) -170,
        cast(T) 10);

    emitLongitudeParity!T(
        scalarName,
        "90_to_minus90",
        cast(T) 90,
        cast(T) -90);

    emitLongitudeParity!T(
        scalarName,
        "minus90_to_90",
        cast(T) -90,
        cast(T) 90);
}


void main()
{
    writeln(
        "# PM-D boundary collision probe");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
