/**
 * PM-C reverse numerical characterization.
 *
 * q = (N - FN) / a
 *
 * Compare equivalent inverse Pseudo-Mercator latitude formulations.
 *
 * Research-only. This does not define the accepted projected-coordinate
 * domain or a public API.
 */
module pm_reverse_probe;

import std.math :
    PI_2,
    abs,
    asin,
    atan,
    exp,
    isFinite,
    sinh,
    tanh;

import std.stdio :
    write,
    writeln,
    writefln;

private T r1(T)(const T q)
{
    return T(PI_2) -
        T(2) * atan(exp(-q));
}

private T r2(T)(const T q)
{
    return atan(sinh(q));
}

private T r3(T)(const T q)
{
    return asin(tanh(q));
}

private T r4(T)(const T q)
{
    return T(2) * atan(tanh(q / T(2)));
}

private T oddError(T)(
    const T positive,
    const T negative)
{
    return isFinite(positive) &&
           isFinite(negative)
        ? abs(positive + negative)
        : T.nan;
}

private void emitValue(T)(
    const string scalarName,
    const string caseName,
    const T q)
{
    const T r1p = r1(q);
    const T r1n = r1(-q);

    const T r2p = r2(q);
    const T r2n = r2(-q);

    const T r3p = r3(q);
    const T r3n = r3(-q);

    const T r4p = r4(q);
    const T r4n = r4(-q);

    const T pole = T(PI_2);

    write(
        scalarName, '\t',
        T.mant_dig, '\t',
        caseName, '\t');

    writefln(
        "%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%s\t%s\t%s\t%s\t"
        ~ "%s\t%s\t%s\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%.40g",
        q,

        r1p, r1n,
        r2p, r2n,
        r3p, r3n,
        r4p, r4n,

        isFinite(r1p),
        isFinite(r2p),
        isFinite(r3p),
        isFinite(r4p),

        r1p == pole,
        r2p == pole,
        r3p == pole,
        r4p == pole,

        oddError(r1p, r1n),
        oddError(r2p, r2n),
        oddError(r3p, r3n),
        oddError(r4p, r4n));
}

private void emitRealQ(T)(
    const string scalarName,
    const string label,
    const real q)
{
    emitValue!T(
        scalarName,
        label,
        T(q));
}

private bool positivePole(T, alias candidate)(
    const T q)
{
    return candidate!T(q) == T(PI_2);
}

private bool negativePole(T, alias candidate)(
    const T magnitude)
{
    return candidate!T(-magnitude) == -T(PI_2);
}

private T firstPoleThreshold(
    T,
    alias candidate,
    bool negative = false)()
{
    T lo = T(0);
    T hi = T(1);

    bool hit(const T q)
    {
        static if (negative)
            return negativePole!(T, candidate)(q);
        else
            return positivePole!(T, candidate)(q);
    }

    while (!hit(hi))
    {
        lo = hi;
        hi *= T(2);

        if (!isFinite(hi))
            return T.infinity;
    }

    /*
     * Floating-point bisection until there is no representable midpoint
     * between lo and hi through ordinary arithmetic.
     */
    foreach (_; 0 .. T.mant_dig + 16)
    {
        const T mid =
            lo + (hi - lo) / T(2);

        if (mid == lo || mid == hi)
            break;

        if (hit(mid))
            hi = mid;
        else
            lo = mid;
    }

    return hi;
}

private void emitThresholds(T)(
    const string scalarName)
{
    writefln(
        "THRESHOLD\t%s\t%d\tR1\t%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        firstPoleThreshold!(T, r1, false)(),
        firstPoleThreshold!(T, r1, true)());

    writefln(
        "THRESHOLD\t%s\t%d\tR2\t%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        firstPoleThreshold!(T, r2, false)(),
        firstPoleThreshold!(T, r2, true)());

    writefln(
        "THRESHOLD\t%s\t%d\tR3\t%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        firstPoleThreshold!(T, r3, false)(),
        firstPoleThreshold!(T, r3, true)());

    writefln(
        "THRESHOLD\t%s\t%d\tR4\t%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        firstPoleThreshold!(T, r4, false)(),
        firstPoleThreshold!(T, r4, true)());
}

private void probeScalar(T)(
    const string scalarName)
{
    emitValue!T(
        scalarName,
        "zero",
        T(0));

    emitRealQ!T(
        scalarName,
        "q_1e-18",
        1.0e-18L);

    emitRealQ!T(
        scalarName,
        "q_1e-12",
        1.0e-12L);

    emitRealQ!T(
        scalarName,
        "q_1e-9",
        1.0e-9L);

    emitRealQ!T(
        scalarName,
        "q_1e-6",
        1.0e-6L);

    emitRealQ!T(
        scalarName,
        "q_0_1",
        0.1L);

    emitRealQ!T(
        scalarName,
        "q_1",
        1.0L);

    /*
     * WebMercatorQuad square bound:
     *
     *   |q| = pi
     */
    emitRealQ!T(
        scalarName,
        "q_pi",
        3.141592653589793238462643383279502884L);

    /*
     * Approximate normalized northings associated with selected
     * high latitudes from the PM-B oracle study.
     */
    emitRealQ!T(
        scalarName,
        "q_lat_88",
        4.0481254186831252214L);

    emitRealQ!T(
        scalarName,
        "q_lat_89",
        4.7413487603646925104L);

    emitRealQ!T(
        scalarName,
        "q_10",
        10.0L);

    emitRealQ!T(
        scalarName,
        "q_15",
        15.0L);

    emitRealQ!T(
        scalarName,
        "q_17",
        17.0L);

    emitRealQ!T(
        scalarName,
        "q_18",
        18.0L);

    emitRealQ!T(
        scalarName,
        "q_20",
        20.0L);

    emitRealQ!T(
        scalarName,
        "q_30",
        30.0L);

    emitRealQ!T(
        scalarName,
        "q_35",
        35.0L);

    emitRealQ!T(
        scalarName,
        "q_37",
        37.0L);

    emitRealQ!T(
        scalarName,
        "q_40",
        40.0L);

    emitRealQ!T(
        scalarName,
        "q_45",
        45.0L);

    emitRealQ!T(
        scalarName,
        "q_50",
        50.0L);

    emitRealQ!T(
        scalarName,
        "q_80",
        80.0L);

    emitRealQ!T(
        scalarName,
        "q_100",
        100.0L);

    emitRealQ!T(
        scalarName,
        "q_500",
        500.0L);

    emitRealQ!T(
        scalarName,
        "q_700",
        700.0L);

    emitRealQ!T(
        scalarName,
        "q_710",
        710.0L);

    emitRealQ!T(
        scalarName,
        "q_1000",
        1000.0L);

    emitRealQ!T(
        scalarName,
        "q_10000",
        10000.0L);

    emitValue!T(
        scalarName,
        "q_half_max",
        T.max / T(2));

    emitValue!T(
        scalarName,
        "q_max",
        T.max);

    emitThresholds!T(scalarName);
}

void main()
{
    writeln(
        "scalar\tmant_dig\tcase\tq\t"
        ~ "r1_pos\tr1_neg\t"
        ~ "r2_pos\tr2_neg\t"
        ~ "r3_pos\tr3_neg\t"
        ~ "r4_pos\tr4_neg\t"
        ~ "r1_finite\tr2_finite\t"
        ~ "r3_finite\tr4_finite\t"
        ~ "r1_pos_exact_pole\t"
        ~ "r2_pos_exact_pole\t"
        ~ "r3_pos_exact_pole\t"
        ~ "r4_pos_exact_pole\t"
        ~ "r1_odd_abs\tr2_odd_abs\t"
        ~ "r3_odd_abs\tr4_odd_abs");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
