/**
 * GEO-C probe for the internal canonical inverse geodesic solver.
 *
 * Input, one case per line:
 *
 *     a f beta1 beta2 lambda12
 *
 * Angles are radians. beta1/beta2 must already satisfy the canonical inverse
 * domain expected by geodesicCanonicalInverse.
 *
 * Output:
 *
 *     s12 azi1 azi2 iterations shortLine
 *
 * where s12 uses the same linear unit as a and azimuths are radians.
 */
module geodesy.research.inverse_solver_probe;

import std.conv :
    to;

import std.math :
    atan2,
    cos,
    sin,
    sqrt;

import std.stdio :
    stdin,
    writefln;

import std.string :
    split,
    strip;

import geodesy.internal.geodesic_inverse_solver :
    geodesicCanonicalInverse;

import geodesy.internal.geodesic_series :
    fillGeodesicA3x,
    fillGeodesicC3x;


void main()
{
    foreach (line; stdin.byLineCopy())
    {
        const fields =
            line.strip.split;

        if (fields.length != 5)
            continue;

        const double a =
            fields[0].to!double;

        const double f =
            fields[1].to!double;

        const double beta1 =
            fields[2].to!double;

        const double beta2 =
            fields[3].to!double;

        const double lambda12 =
            fields[4].to!double;

        const double f1 =
            1.0 - f;

        const double e2 =
            f * (2.0 - f);

        const double ep2 =
            e2 / (f1 * f1);

        const double n =
            f / (2.0 - f);

        const double b =
            a * f1;

        const double sinBeta1 =
            sin(beta1);

        const double cosBeta1 =
            cos(beta1);

        const double sinBeta2 =
            sin(beta2);

        const double cosBeta2 =
            cos(beta2);

        const double dn1 =
            sqrt(
                1.0
                + ep2
                    * sinBeta1
                    * sinBeta1);

        const double dn2 =
            sqrt(
                1.0
                + ep2
                    * sinBeta2
                    * sinBeta2);

        double[8] a3x;
        double[28] c3x;

        fillGeodesicA3x!(
            double,
            6)(
                n,
                a3x);

        fillGeodesicC3x!(
            double,
            6)(
                n,
                c3x);

        const result =
            geodesicCanonicalInverse!(
                double,
                6)(
                    f,
                    f1,
                    ep2,
                    n,
                    a3x,
                    c3x,
                    sinBeta1,
                    cosBeta1,
                    dn1,
                    sinBeta2,
                    cosBeta2,
                    dn2,
                    lambda12,
                    sin(lambda12),
                    cos(lambda12));

        writefln(
            "%.17g %.17g %.17g %u %s",
            b * result.s12b,
            atan2(
                result.sinAlpha1,
                result.cosAlpha1),
            atan2(
                result.sinAlpha2,
                result.cosAlpha2),
            result.iterations,
            result.shortLine ? "1" : "0");
    }
}
