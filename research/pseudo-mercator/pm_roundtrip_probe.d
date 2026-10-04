/**
 * PM-C forward/reverse round-trip characterization.
 *
 * Accepted PM-B forward candidate:
 *
 *     q = asinh(tan(phi))
 *
 * Leading PM-C reverse candidate:
 *
 *     phi = atan(sinh(q))
 *
 * Research-only. No production-domain or public-API decision is made here.
 */
module pm_roundtrip_probe;

import std.math :
    PI,
    PI_2,
    abs,
    asinh,
    atan,
    isFinite,
    nextDown,
    nextUp,
    sinh,
    tan;

import std.stdio :
    write,
    writeln,
    writefln;


private T forwardQ(T)(const T phi)
{
    return asinh(tan(phi));
}


private T reversePhi(T)(const T q)
{
    return atan(sinh(q));
}


private void emitPhi(T)(
    const string scalarName,
    const string caseName,
    const T phi)
{
    const T q = forwardQ(phi);
    const T returned = reversePhi(q);

    const T error =
        isFinite(q) && isFinite(returned)
        ? abs(returned - phi)
        : T.nan;

    write("PHI\t");

    writefln(
        "%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%.40g\t"
        ~ "%s\t%s\t%s\t%s",
        scalarName,
        T.mant_dig,
        caseName,
        phi,
        q,
        returned,
        error,
        returned == phi,
        isFinite(q),
        isFinite(returned),
        returned == T(PI_2)
            || returned == -T(PI_2));
}


private void emitPhiPair(T)(
    const string scalarName,
    const string caseName,
    const T magnitude)
{
    emitPhi!T(
        scalarName,
        caseName ~ "_pos",
        magnitude);

    emitPhi!T(
        scalarName,
        caseName ~ "_neg",
        -magnitude);
}


private void emitDegrees(T)(
    const string scalarName,
    const string caseName,
    const real degrees)
{
    const T phi =
        T(degrees) * T(PI) / T(180);

    emitPhiPair!T(
        scalarName,
        caseName,
        phi);
}


private void emitQ(T)(
    const string scalarName,
    const string caseName,
    const T q)
{
    const T phi = reversePhi(q);
    const T returned = forwardQ(phi);

    const T error =
        isFinite(phi) && isFinite(returned)
        ? abs(returned - q)
        : T.nan;

    write("Q\t");

    writefln(
        "%s\t%d\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%.40g\t"
        ~ "%s\t%s\t%s\t%s",
        scalarName,
        T.mant_dig,
        caseName,
        q,
        phi,
        returned,
        error,
        returned == q,
        isFinite(phi),
        isFinite(returned),
        phi == T(PI_2)
            || phi == -T(PI_2));
}


private void emitQPair(T)(
    const string scalarName,
    const string caseName,
    const T magnitude)
{
    emitQ!T(
        scalarName,
        caseName ~ "_pos",
        magnitude);

    emitQ!T(
        scalarName,
        caseName ~ "_neg",
        -magnitude);
}


private bool positivePole(T)(
    const T q)
{
    return reversePhi(q) == T(PI_2);
}


private T firstPositivePoleThreshold(T)()
{
    T lo = T(0);
    T hi = T(1);

    while (!positivePole(hi))
    {
        lo = hi;
        hi *= T(2);

        if (!isFinite(hi))
            return T.infinity;
    }

    foreach (_; 0 .. T.mant_dig + 16)
    {
        const T mid =
            lo + (hi - lo) / T(2);

        if (mid == lo || mid == hi)
            break;

        if (positivePole(mid))
            hi = mid;
        else
            lo = mid;
    }

    return hi;
}


private void probePhi(T)(
    const string scalarName)
{
    emitPhiPair!T(
        scalarName,
        "zero",
        T(0));

    emitDegrees!T(
        scalarName,
        "deg_1e-12",
        1.0e-12L);

    emitDegrees!T(
        scalarName,
        "deg_1e-9",
        1.0e-9L);

    emitDegrees!T(
        scalarName,
        "deg_1",
        1.0L);

    emitDegrees!T(
        scalarName,
        "deg_45",
        45.0L);

    emitDegrees!T(
        scalarName,
        "deg_80",
        80.0L);

    emitDegrees!T(
        scalarName,
        "deg_85",
        85.0L);

    emitDegrees!T(
        scalarName,
        "deg_webmercatorquad",
        85.0511287798066L);

    emitDegrees!T(
        scalarName,
        "deg_88",
        88.0L);

    emitDegrees!T(
        scalarName,
        "deg_89",
        89.0L);

    emitDegrees!T(
        scalarName,
        "deg_89_9",
        89.9L);

    emitDegrees!T(
        scalarName,
        "deg_89_99",
        89.99L);

    emitDegrees!T(
        scalarName,
        "deg_89_9999",
        89.9999L);

    emitDegrees!T(
        scalarName,
        "deg_89_999999",
        89.999999L);

    /*
     * Stress values relative to scalar-rounded PI_2.
     *
     * These labels deliberately say scalar_pi2_nextdown rather than
     * "pole minus N ULP": T(PI_2) itself need not equal mathematical pi/2.
     */
    T phi = T(PI_2);
    size_t nextReport = 1;

    foreach (size_t step; 1 .. 65_537)
    {
        phi = nextDown(phi);

        if (step == nextReport)
        {
            import std.conv : to;

            emitPhiPair!T(
                scalarName,
                "scalar_pi2_nextdown_"
                    ~ step.to!string,
                phi);

            if (nextReport < 65_536)
                nextReport *= 2;
        }
    }
}


private void probeQ(T)(
    const string scalarName)
{
    emitQPair!T(
        scalarName,
        "q_zero",
        T(0));

    foreach (value; [
        1.0e-18L,
        1.0e-12L,
        1.0e-9L,
        1.0e-6L,
        0.1L,
        1.0L,
        3.141592653589793238462643383279502884L,
        4.0481254186831252214L,
        4.7413487603646925104L,
        10.0L,
        15.0L,
        17.0L,
        18.0L,
        20.0L,
        30.0L,
        35.0L,
        37.0L,
        40.0L,
        45.0L,
        50.0L,
        100.0L
    ])
    {
        import std.conv : to;

        emitQPair!T(
            scalarName,
            "q_" ~ value.to!string,
            T(value));
    }

    /*
     * Characterize the exact R2 scalar saturation neighbourhood.
     */
    const T threshold =
        firstPositivePoleThreshold!T();

    emitQPair!T(
        scalarName,
        "r2_threshold_prev",
        nextDown(threshold));

    emitQPair!T(
        scalarName,
        "r2_threshold",
        threshold);

    emitQPair!T(
        scalarName,
        "r2_threshold_next",
        nextUp(threshold));

    emitQPair!T(
        scalarName,
        "q_half_max",
        T.max / T(2));

    emitQPair!T(
        scalarName,
        "q_max",
        T.max);
}


private void probeScalar(T)(
    const string scalarName)
{
    probePhi!T(scalarName);
    probeQ!T(scalarName);
}


void main()
{
    writeln(
        "path\tscalar\tmant_dig\tcase\t"
        ~ "input\tintermediate\treturned\tabs_error\t"
        ~ "exact_return\t"
        ~ "intermediate_finite\t"
        ~ "returned_finite\t"
        ~ "intermediate_exact_pole");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
