/**
 * PM-B backend diagnostic.
 *
 * Compare D std.math/core.math trig results with direct C libm calls.
 * Research-only: this does not define production behaviour.
 */
module pm_trig_backend_probe;

import dmath = std.math;
import cmath = core.stdc.math;

import std.stdio : write, writeln, writefln;

private T cSin(T)(const T x)
{
    static if (is(T == float))
        return cmath.sinf(x);
    else static if (is(T == double))
        return cmath.sin(x);
    else static if (is(T == real))
        return cmath.sinl(x);
    else
        static assert(0);
}

private T cCos(T)(const T x)
{
    static if (is(T == float))
        return cmath.cosf(x);
    else static if (is(T == double))
        return cmath.cos(x);
    else static if (is(T == real))
        return cmath.cosl(x);
    else
        static assert(0);
}

private T cTan(T)(const T x)
{
    static if (is(T == float))
        return cmath.tanf(x);
    else static if (is(T == double))
        return cmath.tan(x);
    else static if (is(T == real))
        return cmath.tanl(x);
    else
        static assert(0);
}

private void emit(T)(
    const string scalarName,
    const string caseName,
    const T phi)
{
    const T ds = dmath.sin(phi);
    const T cs = cSin(phi);

    const T dc = dmath.cos(phi);
    const T cc = cCos(phi);

    const T dt = dmath.tan(phi);
    const T ct = cTan(phi);

    const T dr = ds / dc;
    const T cr = cs / cc;

    const T df3 = dmath.asinh(dr);
    const T cf3 = dmath.asinh(cr);

    write(
        scalarName, '\t',
        T.mant_dig, '\t',
        caseName, '\t');

    writefln(
        "%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t%.40g\t"
        ~ "%.40g\t%.40g\t%.40g",
        phi,
        ds, cs,
        dc, cc,
        dt, ct,
        dmath.abs(ds - cs),
        dmath.abs(dc - cc),
        dmath.abs(dt - ct),
        dr, cr, dmath.abs(dr - cr),
        df3, cf3, dmath.abs(df3 - cf3));
}

private void emitDegrees(T)(
    const string scalarName,
    const string label,
    const real degrees)
{
    emit!T(
        scalarName,
        label,
        T(degrees) * T(dmath.PI) / T(180));
}

private void probeScalar(T)(const string scalarName)
{
    emitDegrees!T(scalarName, "deg_85", 85.0L);
    emitDegrees!T(scalarName, "deg_88", 88.0L);
    emitDegrees!T(scalarName, "deg_89", 89.0L);
    emitDegrees!T(scalarName, "deg_89_99", 89.99L);
    emitDegrees!T(scalarName, "deg_89_999999", 89.999999L);

    T phi = T(dmath.PI_2);

    foreach (size_t step; 1 .. 65_537)
    {
        phi = dmath.nextDown(phi);

        if (
            step == 1 ||
            step == 2 ||
            step == 4 ||
            step == 16 ||
            step == 256 ||
            step == 1024 ||
            step == 65_536)
        {
            import std.conv : to;

            emit!T(
                scalarName,
                "pole_minus_" ~ step.to!string ~ "_ulp",
                phi);
        }
    }
}

void main()
{
    writeln(
        "scalar\tmant_dig\tcase\tphi\t"
        ~ "d_sin\tc_sin\t"
        ~ "d_cos\tc_cos\t"
        ~ "d_tan\tc_tan\t"
        ~ "sin_abs_diff\tcos_abs_diff\ttan_abs_diff\t"
        ~ "d_ratio\tc_ratio\tratio_abs_diff\t"
        ~ "d_f3\tc_f3\tf3_abs_diff");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
