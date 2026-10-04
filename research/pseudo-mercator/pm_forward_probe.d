/**
 * PM-B research probe.
 *
 * Compare analytically equivalent normalized Pseudo-Mercator northing forms:
 *
 *   F1(phi) = log(tan(pi/4 + phi/2))
 *   F2(phi) = asinh(tan(phi))
 *
 * This is research-only code. It is not a production implementation and does
 * not define the accepted projection domain.
 */
module pm_forward_probe;

import std.math :
    PI,
    PI_2,
    PI_4,
    abs,
    asinh,
    isFinite,
    log,
    nextDown,
    tan;
import std.stdio : write, writeln, writefln;

private T f1(T)(const T phi)
{
    return log(tan(T(PI_4) + phi / T(2)));
}

private T f2(T)(const T phi)
{
    return asinh(tan(phi));
}

private void emitValue(T)(
    const string scalarName,
    const string caseName,
    const T phi)
{
    const T negativePhi = -phi;

    const T f1Positive = f1(phi);
    const T f1Negative = f1(negativePhi);
    const T f2Positive = f2(phi);
    const T f2Negative = f2(negativePhi);

    const T f1OddError =
        isFinite(f1Positive) && isFinite(f1Negative)
            ? abs(f1Positive + f1Negative)
            : T.nan;

    const T f2OddError =
        isFinite(f2Positive) && isFinite(f2Negative)
            ? abs(f2Positive + f2Negative)
            : T.nan;

    const T positiveDifference =
        isFinite(f1Positive) && isFinite(f2Positive)
            ? abs(f1Positive - f2Positive)
            : T.nan;

    const T negativeDifference =
        isFinite(f1Negative) && isFinite(f2Negative)
            ? abs(f1Negative - f2Negative)
            : T.nan;

    write(
        scalarName, '\t',
        T.mant_dig, '\t',
        caseName, '\t');

    writefln(
        "%.40g\t%.40g\t%.40g\t%.40g\t%.40g\t"
        ~ "%s\t%s\t%s\t%s\t"
        ~ "%.40g\t%.40g\t%.40g\t%.40g",
        phi,
        f1Positive,
        f1Negative,
        f2Positive,
        f2Negative,
        isFinite(f1Positive),
        isFinite(f1Negative),
        isFinite(f2Positive),
        isFinite(f2Negative),
        f1OddError,
        f2OddError,
        positiveDifference,
        negativeDifference);
}

private void emitDegrees(T)(
    const string scalarName,
    const string label,
    const real degrees)
{
    const T phi =
        T(degrees) * T(PI) / T(180);

    emitValue!T(
        scalarName,
        label,
        phi);
}

private void probeScalar(T)(const string scalarName)
{
    /*
     * Ordinary and practically interesting latitudes.
     *
     * These are characterization points only. Their presence here does not
     * make any of them an accepted production boundary.
     */
    emitValue!T(scalarName, "equator", T(0));

    emitDegrees!T(scalarName, "deg_1e-12", 1.0e-12L);
    emitDegrees!T(scalarName, "deg_1e-9",  1.0e-9L);
    emitDegrees!T(scalarName, "deg_1",     1.0L);
    emitDegrees!T(scalarName, "deg_45",    45.0L);
    emitDegrees!T(scalarName, "deg_80",    80.0L);
    emitDegrees!T(scalarName, "deg_85",    85.0L);

    emitDegrees!T(
        scalarName,
        "deg_webmercatorquad",
        85.0511287798066L);

    emitDegrees!T(scalarName, "deg_88",       88.0L);
    emitDegrees!T(scalarName, "deg_89",       89.0L);
    emitDegrees!T(scalarName, "deg_89_9",     89.9L);
    emitDegrees!T(scalarName, "deg_89_99",    89.99L);
    emitDegrees!T(scalarName, "deg_89_9999",  89.9999L);
    emitDegrees!T(scalarName, "deg_89_999999", 89.999999L);

    /*
     * Representation-driven pole approach.
     *
     * Start from the scalar representation of pi/2 and repeatedly move toward
     * zero. Powers of two give a logarithmically widening view of the
     * near-pole floating-point neighbourhood.
     */
    T phi = T(PI_2);
    size_t nextReport = 1;

    foreach (size_t step; 1 .. 65_537)
    {
        phi = nextDown(phi);

        if (step == nextReport)
        {
            import std.conv : to;

            emitValue!T(
                scalarName,
                "pole_minus_" ~ step.to!string ~ "_ulp",
                phi);

            if (nextReport < 65_536)
                nextReport *= 2;
        }
    }
}

void main()
{
    writeln(
        "scalar\tmant_dig\tcase\tphi_rad\t"
        ~ "f1_pos\tf1_neg\tf2_pos\tf2_neg\t"
        ~ "f1_pos_finite\tf1_neg_finite\t"
        ~ "f2_pos_finite\tf2_neg_finite\t"
        ~ "f1_odd_abs\tf2_odd_abs\t"
        ~ "candidate_abs_diff_pos\tcandidate_abs_diff_neg");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
