/**
 * PM-D domain / representation characterization.
 *
 * Research-only.
 *
 * Candidate semantic contract:
 *
 *   latitude:           [-88 deg, +88 deg]
 *   longitude delta:    [-pi, +pi)
 *   normalized northing [-q88, +q88]
 *   normalized easting  [-pi, +pi)
 *
 * The probe characterizes scalar representations of those mathematical
 * boundaries. It does not implement a public projection.
 */
module pm_domain_probe;

import geodesy.angle :
    Latitude,
    Longitude;

import std.math :
    PI,
    asinh,
    nextDown,
    nextUp,
    tan;

import std.stdio :
    writeln,
    writefln;


private T pi(T)()
{
    return cast(T) PI;
}


private T q88(T)()
{
    const T phi =
        Latitude!T.fromDegrees(
            cast(T) 88).radians;

    return asinh(tan(phi));
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


private T normalizeDelta(T)(
    const T longitude,
    const T longitude0)
{
    /*
     * Match the already accepted Transverse Mercator antimeridian policy.
     *
     * The residual matters at an exactly represented +/-pi tie: public
     * longitudes may have been rounded independently before subtraction.
     */
    T sum;
    T residual;

    twoSum(
        longitude,
        -longitude0,
        sum,
        residual);

    const T p = pi!T;
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

    T result =
        sum + residual;

    /*
     * Inputs are public Longitude<T> values, hence at most one period away.
     * Preserve the unique half-open [-pi,+pi) representation.
     */
    if (result >= p)
        result -= twoP;
    else if (result < -p)
        result += twoP;

    return result;
}


private void emitLatitudeBoundary(T)(
    const string scalarName)
{
    const T northPhi =
        Latitude!T.fromDegrees(
            cast(T) 88).radians;

    const T southPhi =
        Latitude!T.fromDegrees(
            cast(T) -88).radians;

    const T northQ =
        asinh(tan(northPhi));

    const T southQ =
        asinh(tan(southPhi));

    writefln(
        "LAT\t%s\t%d\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        northPhi,
        southPhi,
        northQ,
        southQ,
        nextDown(northQ),
        nextUp(northQ),
        nextDown(southQ),
        nextUp(southQ));
}


private void emitLinearProfile(T)(
    const string scalarName,
    const string profileName,
    const T a,
    const T falseEasting,
    const T falseNorthing)
{
    const T p = pi!T;
    const T q = q88!T();

    const T west =
        falseEasting - a * p;

    const T eastExclusive =
        falseEasting + a * p;

    const T south =
        falseNorthing - a * q;

    const T north =
        falseNorthing + a * q;

    writefln(
        "LINEAR\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        profileName,
        a,
        falseEasting,
        falseNorthing,
        west,
        nextDown(west),
        eastExclusive,
        nextDown(eastExclusive),
        south,
        nextDown(south),
        nextUp(south),
        north,
        nextDown(north),
        nextUp(north));
}


private void emitLongitudeCase(T)(
    const string scalarName,
    const string label,
    const real longitude0Degrees,
    const real longitudeDegrees)
{
    const Longitude!T longitude0 =
        Longitude!T.fromDegrees(
            cast(T) longitude0Degrees);

    const Longitude!T longitude =
        Longitude!T.fromDegrees(
            cast(T) longitudeDegrees);

    const T delta =
        normalizeDelta(
            longitude.radians,
            longitude0.radians);

    /*
     * Reconstruct the longitude through the public Longitude type's
     * half-open canonical representation.
     */
    T reconstructed =
        longitude0.radians + delta;

    const T p = pi!T;
    const T twoP = cast(T) 2 * p;

    if (reconstructed >= p)
        reconstructed -= twoP;
    else if (reconstructed < -p)
        reconstructed += twoP;

    const Longitude!T recovered =
        Longitude!T.fromRadians(
            reconstructed).normalized;

    writefln(
        "LON\t%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        label,
        longitude0.radians,
        longitude.radians,
        delta,
        delta / p,
        recovered.radians,
        recovered.normalized.radians);
}


private void probeScalar(T)(
    const string scalarName)
{
    emitLatitudeBoundary!T(
        scalarName);

    emitLinearProfile!T(
        scalarName,
        "unit",
        cast(T) 1,
        cast(T) 0,
        cast(T) 0);

    emitLinearProfile!T(
        scalarName,
        "wgs84_zero",
        cast(T) 6_378_137,
        cast(T) 0,
        cast(T) 0);

    emitLinearProfile!T(
        scalarName,
        "wgs84_offsets",
        cast(T) 6_378_137,
        cast(T) 500_000,
        cast(T) -2_000_000);

    emitLongitudeCase!T(
        scalarName,
        "zero_to_east180",
        0,
        180);

    emitLongitudeCase!T(
        scalarName,
        "zero_to_west180",
        0,
        -180);

    emitLongitudeCase!T(
        scalarName,
        "cross_antimeridian_east",
        179.75L,
        -179.75L);

    emitLongitudeCase!T(
        scalarName,
        "cross_antimeridian_west",
        -179.75L,
        179.75L);

    emitLongitudeCase!T(
        scalarName,
        "lambda0_170_to_minus10",
        170,
        -10);

    emitLongitudeCase!T(
        scalarName,
        "lambda0_minus170_to_10",
        -170,
        10);

    emitLongitudeCase!T(
        scalarName,
        "lambda0_90_to_minus90",
        90,
        -90);

    emitLongitudeCase!T(
        scalarName,
        "lambda0_minus90_to_90",
        -90,
        90);
}


void main()
{
    writeln(
        "# PM-D domain representability probe");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
