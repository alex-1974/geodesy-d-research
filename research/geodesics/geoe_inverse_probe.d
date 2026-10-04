module geodesy.research.geoe_inverse_probe;

/**
 * GEO-E diagnostic probe for the internal inverse dispatcher.
 *
 * Input, one case per line:
 *
 *     a_bits f_bits lat1_bits lon1_bits lat2_bits lon2_bits
 *
 * Every field is the decimal spelling of an IEEE-754 binary64 bit pattern.
 * The selected mode reconstructs the represented public-scalar input exactly.
 *
 * Output:
 *
 *     distance azi1 azi2 sigma12 iterations dispatchKind startKind
 *     bracketMidpointCount converged
 */

import std.conv : to;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.internal.geodesic_inverse_dispatch :
    geodesicInverseDispatch;

import geodesy.internal.geodesic_series :
    fillGeodesicA3x,
    fillGeodesicC3x;


private union DoubleBits
{
    ulong bits;
    double value;
}


private double doubleFromBits(const string field)
{
    DoubleBits value;
    value.bits = field.to!ulong;
    return value.value;
}


private W representedValue(W, bool publicFloat)(const string field)
{
    const double source = doubleFromBits(field);

    static if (publicFloat)
        return cast(W) cast(float) source;
    else
        return cast(W) source;
}


private void solve(W, int order, bool publicFloat)(const string[] fields)
{
    if (fields.length != 6)
        return;

    const W a = representedValue!(W, publicFloat)(fields[0]);
    const W f = representedValue!(W, publicFloat)(fields[1]);

    const W latitude1 =
        representedValue!(W, publicFloat)(fields[2]);
    const W longitude1 =
        representedValue!(W, publicFloat)(fields[3]);
    const W latitude2 =
        representedValue!(W, publicFloat)(fields[4]);
    const W longitude2 =
        representedValue!(W, publicFloat)(fields[5]);

    const W f1 = cast(W) 1 - f;
    const W b = a * f1;
    const W e2 = f * (cast(W) 2 - f);
    const W ep2 = e2 / (f1 * f1);
    const W n = f / (cast(W) 2 - f);

    W[8] a3x;
    W[28] c3x;

    fillGeodesicA3x!(W, order)(
        n,
        a3x);

    fillGeodesicC3x!(W, order)(
        n,
        c3x);

    const result =
        geodesicInverseDispatch!(
            W,
            order)(
                a,
                f,
                f1,
                b,
                ep2,
                n,
                a3x,
                c3x,
                latitude1,
                longitude1,
                latitude2,
                longitude2);

    writefln(
        "%.17g %.17g %.17g %.17g %u %u %u %u %u",
        cast(double) result.distance,
        cast(double) result.initialAzimuth,
        cast(double) result.finalAzimuth,
        cast(double) result.sigma12,
        result.iterations,
        cast(uint) result.kind,
        cast(uint) result.startKind,
        result.bracketMidpointCount,
        result.converged ? 1u : 0u);
}


void main(string[] args)
{
    if (args.length != 2)
        return;

    foreach (line; stdin.byLineCopy())
    {
        const fields = line.strip.split;

        if (fields.length == 0)
            continue;

        switch (args[1])
        {
            case "float":
                /*
                 * Public float uses double working precision / order 6.
                 * Scalarize the wire value to float before widening.
                 */
                solve!(double, 6, true)(fields);
                break;

            case "double":
                solve!(double, 6, false)(fields);
                break;

            case "real":
                static if (real.mant_dig <= 53)
                    solve!(real, 6, false)(fields);
                else static if (real.mant_dig <= 64)
                    solve!(real, 7, false)(fields);
                else
                    solve!(real, 8, false)(fields);
                break;

            default:
                return;
        }
    }
}
