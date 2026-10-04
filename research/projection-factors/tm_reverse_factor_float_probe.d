module geodesy.projection.projection_factor_reverse_float_probe;

import std.conv : to;
import std.math : isFinite;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.angle : Latitude, Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geographic : GeographicCoordinate;
import geodesy.projected : ProjectedCoordinate;
import geodesy.projection.transverse_mercator :
    TransverseMercator;


/*
 * FLOAT-R1 research probe.
 *
 * All public projection, geographic, projected and factor values use float.
 * Output angular values remain in their represented float radians.  The Python
 * harness converts them to degrees in double precision for comparison so that
 * an additional float degrees conversion does not contaminate the experiment.
 */
int main(string[] args)
{
    if (args.length != 8)
    {
        writefln(
            "usage: %s A F LAT0_DEG LON0_DEG K0 FALSE_E FALSE_N",
            args[0]);
        return 2;
    }

    const float semiMajorAxis =
        args[1].to!float;
    const float flattening =
        args[2].to!float;
    const float latitudeOfNaturalOriginDegrees =
        args[3].to!float;
    const float longitudeOfNaturalOriginDegrees =
        args[4].to!float;
    const float scaleFactorAtNaturalOrigin =
        args[5].to!float;
    const float falseEasting =
        args[6].to!float;
    const float falseNorthing =
        args[7].to!float;

    const latitudeOfNaturalOrigin =
        Latitude!float.fromDegrees(
            latitudeOfNaturalOriginDegrees);

    const longitudeOfNaturalOrigin =
        Longitude!float.fromDegrees(
            longitudeOfNaturalOriginDegrees);

    const ellipsoid =
        Ellipsoid!float.fromFlattening(
            semiMajorAxis,
            flattening);

    const projection =
        TransverseMercator!float.fromParameters(
            ellipsoid,
            latitudeOfNaturalOrigin,
            longitudeOfNaturalOrigin,
            scaleFactorAtNaturalOrigin,
            falseEasting,
            falseNorthing);

    /*
     * Return the actual represented public profile.
     *
     * In particular, LAT0/LON0 are emitted as their stored float radians,
     * rather than by converting them back to float degrees.
     */
    writefln(
        "PROFILE\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g",
        cast(double) semiMajorAxis,
        cast(double) flattening,
        cast(double) latitudeOfNaturalOrigin.radians,
        cast(double) longitudeOfNaturalOrigin.radians,
        cast(double) scaleFactorAtNaturalOrigin,
        cast(double) falseEasting,
        cast(double) falseNorthing);

    foreach (line; stdin.byLineCopy())
    {
        const fields =
            line.strip.split;

        if (fields.length == 0)
            continue;

        if (fields.length != 2)
        {
            writefln("BAD_INPUT");
            return 2;
        }

        const float latitudeDegrees =
            fields[0].to!float;
        const float longitudeDegrees =
            fields[1].to!float;

        const latitude =
            Latitude!float.fromDegrees(
                latitudeDegrees);

        const longitude =
            Longitude!float.fromDegrees(
                longitudeDegrees);

        const source =
            GeographicCoordinate!float.fromComponents(
                latitude,
                longitude);

        ProjectedCoordinate!float projected;

        if (!projection.tryForward(source, projected))
        {
            writefln("FORWARD_REJECT");
            continue;
        }

        GeographicCoordinate!float reversed;

        if (!projection.tryReverse(projected, reversed))
        {
            writefln("REVERSE_REJECT");
            continue;
        }

        float convergenceBRadians;
        float pointScaleB;

        if (!projection.researchTryReverseFactors(
                projected,
                convergenceBRadians,
                pointScaleB))
        {
            writefln("B_REJECT");
            continue;
        }

        float convergenceARadians;
        float pointScaleA;

        if (!projection.researchTryForwardFactors(
                reversed,
                convergenceARadians,
                pointScaleA))
        {
            writefln("A_REJECT");
            continue;
        }

        if (!isFinite(projected.easting)
            || !isFinite(projected.northing)
            || !isFinite(reversed.latitude.radians)
            || !isFinite(reversed.longitude.radians)
            || !isFinite(convergenceBRadians)
            || !isFinite(pointScaleB)
            || !isFinite(convergenceARadians)
            || !isFinite(pointScaleA)
            || !(pointScaleB > 0.0f)
            || !(pointScaleA > 0.0f))
        {
            writefln("NONFINITE");
            return 1;
        }

        /*
         * Keep all float-valued results as their raw represented values.
         * %.17g after promotion to double round-trips every binary32 value.
         *
         * Fields:
         *   E N
         *   reverse-lat-rad reverse-lon-rad
         *   gamma-B-rad k-B
         *   gamma-A-rad k-A
         */
        writefln(
            "OK\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g",
            cast(double) projected.easting,
            cast(double) projected.northing,
            cast(double) reversed.latitude.radians,
            cast(double) reversed.longitude.radians,
            cast(double) convergenceBRadians,
            cast(double) pointScaleB,
            cast(double) convergenceARadians,
            cast(double) pointScaleA);
    }

    return 0;
}
