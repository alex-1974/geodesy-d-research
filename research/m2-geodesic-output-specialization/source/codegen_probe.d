module geodesy.internal.output_specialization_codegen_probe;

import geodesy.internal.geodesic_lengths :
    geodesicLengthDistance,
    geodesicLengthReducedLength,
    geodesicLengthScales,
    geodesicLengths;

private alias W = double;

extern(C) pragma(inline, false)
double probe_geodesic_length_distance(
    W eps,
    W ep2,
    W sigma12,
    W sinSigma1,
    W cosSigma1,
    W dn1,
    W cosBeta1,
    W sinSigma2,
    W cosSigma2,
    W dn2,
    W cosBeta2)
    pure nothrow @safe @nogc
{
    const result =
        geodesicLengths!(
            W,
            6,
            geodesicLengthDistance)(
                eps,
                ep2,
                sigma12,
                sinSigma1,
                cosSigma1,
                dn1,
                cosBeta1,
                sinSigma2,
                cosSigma2,
                dn2,
                cosBeta2);

    return result.s12b;
}

extern(C) pragma(inline, false)
double probe_geodesic_length_reduced(
    W eps,
    W ep2,
    W sigma12,
    W sinSigma1,
    W cosSigma1,
    W dn1,
    W cosBeta1,
    W sinSigma2,
    W cosSigma2,
    W dn2,
    W cosBeta2)
    pure nothrow @safe @nogc
{
    const result =
        geodesicLengths!(
            W,
            6,
            geodesicLengthReducedLength)(
                eps,
                ep2,
                sigma12,
                sinSigma1,
                cosSigma1,
                dn1,
                cosBeta1,
                sinSigma2,
                cosSigma2,
                dn2,
                cosBeta2);

    return result.m12b + result.m0;
}

extern(C) pragma(inline, false)
double probe_geodesic_length_scales(
    W eps,
    W ep2,
    W sigma12,
    W sinSigma1,
    W cosSigma1,
    W dn1,
    W cosBeta1,
    W sinSigma2,
    W cosSigma2,
    W dn2,
    W cosBeta2)
    pure nothrow @safe @nogc
{
    const result =
        geodesicLengths!(
            W,
            6,
            geodesicLengthScales)(
                eps,
                ep2,
                sigma12,
                sinSigma1,
                cosSigma1,
                dn1,
                cosBeta1,
                sinSigma2,
                cosSigma2,
                dn2,
                cosBeta2);

    return result.M12 + result.M21;
}

extern(C) pragma(inline, false)
double probe_geodesic_length_full(
    W eps,
    W ep2,
    W sigma12,
    W sinSigma1,
    W cosSigma1,
    W dn1,
    W cosBeta1,
    W sinSigma2,
    W cosSigma2,
    W dn2,
    W cosBeta2)
    pure nothrow @safe @nogc
{
    const result =
        geodesicLengths!(
            W,
            6,
            geodesicLengthDistance
                | geodesicLengthReducedLength
                | geodesicLengthScales)(
                    eps,
                    ep2,
                    sigma12,
                    sinSigma1,
                    cosSigma1,
                    dn1,
                    cosBeta1,
                    sinSigma2,
                    cosSigma2,
                    dn2,
                    cosBeta2);

    return
        result.s12b
        + result.m12b
        + result.m0
        + result.M12
        + result.M21;
}
