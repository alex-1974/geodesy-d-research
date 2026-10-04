/**
 * PM-C reverse representability probe.
 *
 * Emit the scalar representation of +pi/2 and the immediately adjacent
 * representable latitude toward the equator.
 *
 * These values allow the independent oracle to determine the continuous
 * q-boundary at which a correctly rounded inverse latitude should first
 * become the represented pole.
 *
 * Research-only.
 */
module pm_reverse_rounding_probe;

import std.math :
    PI_2,
    nextDown;

import std.stdio :
    writeln,
    writefln;

private void probeScalar(T)(
    const string scalarName)
{
    const T pole = T(PI_2);
    const T interior = nextDown(pole);

    const T negativePole = -pole;
    const T negativeInterior = -interior;

    writefln(
        "%s\t%d\t%.40g\t%.40g\t%.40g\t%.40g",
        scalarName,
        T.mant_dig,
        pole,
        interior,
        negativePole,
        negativeInterior);
}

void main()
{
    writeln(
        "scalar\tmant_dig\t"
        ~ "positive_pole\tpositive_interior\t"
        ~ "negative_pole\tnegative_interior");

    probeScalar!float("float");
    probeScalar!double("double");
    probeScalar!real("real");
}
