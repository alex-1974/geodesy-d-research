/**
 * GEO-C probe for the full internal inverse geodesic dispatcher.
 *
 * Input, one case per line:
 *
 *     a f lat1 lon1 lat2 lon2
 *
 * All angles are radians.
 *
 * Output:
 *
 *     s12 azi1 azi2 sigma12 iterations kind
 *
 * where s12 uses the same linear unit as a and all angles are radians.
 */
module geodesy.research.inverse_dispatch_probe;

import std.conv : to;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.internal.geodesic_inverse_dispatch :
    geodesicInverseDispatch;

import geodesy.internal.geodesic_series :
    fillGeodesicA3x,
    fillGeodesicC3x;


void main()
{
    foreach (line; stdin.byLineCopy())
    {
        const fields =
            line.strip.split;

        if (fields.length != 6)
            continue;

        const double a =
            fields[0].to!double;

        const double f =
            fields[1].to!double;

        const double latitude1 =
            fields[2].to!double;

        const double longitude1 =
            fields[3].to!double;

        const double latitude2 =
            fields[4].to!double;

        const double longitude2 =
            fields[5].to!double;

        const double f1 =
            1.0 - f;

        const double b =
            a * f1;

        const double e2 =
            f * (2.0 - f);

        const double ep2 =
            e2 / (f1 * f1);

        const double n =
            f / (2.0 - f);

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
            geodesicInverseDispatch!(
                double,
                6)(
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
            "%.17g %.17g %.17g %.17g %u %u",
            result.distance,
            result.initialAzimuth,
            result.finalAzimuth,
            result.sigma12,
            result.iterations,
            cast(uint) result.kind);
    }
}
