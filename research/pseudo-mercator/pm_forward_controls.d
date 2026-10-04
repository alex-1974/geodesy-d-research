/**
 * PM-B control study.
 *
 * Distinguish errors caused by the analytical form from errors caused by
 * individual transcendental implementations near +/-pi/2.
 *
 * Research-only. No production-domain or API decision is made here.
 */
module pm_forward_controls;

import std.math :
    PI,
    PI_2,
    PI_4,
    abs,
    asinh,
    atanh,
    cos,
    isFinite,
    log,
    log1p,
    nextDown,
    sin,
    tan;

import std.stdio : write, writeln, writefln;

private T f2(T)(const T phi)
{
    return asinh(tan(phi));
}

private T f3(T)(const T phi)
{
    return asinh(sin(phi) / cos(phi));
}

private T f4(T)(const T phi)
{
    /*
     * log(sec(phi) + tan(phi))
     *   = log((1 + sin(phi)) / cos(phi))
     *
     * Evaluate only on |phi| and restore the sign so that odd symmetry is
     * structural rather than dependent on cancellation near the south pole.
     */
    if (phi == T(0))
        return phi;

    const bool negative = phi < T(0);
    const T a = negative ? -phi : phi;

    const T value =
        log1p(sin(a)) - log(cos(a));

    return negative ? -value : value;
}

private T f5(T)(const T phi)
{
    return atanh(sin(phi));
}

private T oddError(T)(const T positive, const T negative)
{
    return isFinite(positive) && isFinite(negative)
        ? abs(positive + negative)
        : T.nan;
}

private void emitValue(T)(
    const string scalarName,
    const string caseName,
    const T phi)
{
    const T negativePhi = -phi;

    const T f2p = f2(phi);
    const T f2n = f2(negativePhi);

    const T f3p = f3(phi);
    const T f3n = f3(negativePhi);

    const T f4p = f4(phi);
    const T f4n = f4(negativePhi);

    const T f5p = f5(phi);
    const T f5n = f5(negativePhi);

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
        ~ "%.40g\t%.40g\t%.40g\t%.40g",
        phi,
        f2p, f2n,
        f3p, f3n,
        f4p, f4n,
        f5p, f5n,
        isFinite(f2p),
        isFinite(f3p),
        isFinite(f4p),
        isFinite(f5p),
        oddError(f2p, f2n),
        oddError(f3p, f3n),
        oddError(f4p, f4n),
        oddError(f5p, f5n));
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
    emitDegrees!T(scalarName, "deg_88",        88.0L);
    emitDegrees!T(scalarName, "deg_89",        89.0L);
    emitDegrees!T(scalarName, "deg_89_9",      89.9L);
    emitDegrees!T(scalarName, "deg_89_99",     89.99L);
    emitDegrees!T(scalarName, "deg_89_9999",   89.9999L);
    emitDegrees!T(scalarName, "deg_89_999999", 89.999999L);

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
        ~ "f2_pos\tf2_neg\t"
        ~ "f3_pos\tf3_neg\t"
        ~ "f4_pos\tf4_neg\t"
        ~ "f5_pos\tf5_neg\t"
        ~ "f2_pos_finite\tf3_pos_finite\t"
        ~ "f4_pos_finite\tf5_pos_finite\t"
        ~ "f2_odd_abs\tf3_odd_abs\t"
        ~ "f4_odd_abs\tf5_odd_abs");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
