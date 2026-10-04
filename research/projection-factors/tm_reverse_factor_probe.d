module geodesy.projection.projection_factor_reverse_probe;

import std.conv : to;
import std.math : PI, isFinite;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.angle : Latitude, Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geographic : GeographicCoordinate;
import geodesy.projected : ProjectedCoordinate;
import geodesy.projection.transverse_mercator :
    TransverseMercator;


private double degrees(const double radians)
{
    return radians * 180.0 / cast(double) PI;
}


int main(string[] args)
{
    if (args.length != 8)
    {
        writefln(
            "usage: %s A F LAT0 LON0 K0 FALSE_E FALSE_N",
            args[0]);
        return 2;
    }

    const double semiMajorAxis =
        args[1].to!double;
    const double flattening =
        args[2].to!double;
    const double latitudeOfNaturalOrigin =
        args[3].to!double;
    const double longitudeOfNaturalOrigin =
        args[4].to!double;
    const double scaleFactorAtNaturalOrigin =
        args[5].to!double;
    const double falseEasting =
        args[6].to!double;
    const double falseNorthing =
        args[7].to!double;

    const ellipsoid =
        Ellipsoid!double.fromFlattening(
            semiMajorAxis,
            flattening);

    const projection =
        TransverseMercator!double.fromParameters(
            ellipsoid,
            Latitude!double.fromDegrees(
                latitudeOfNaturalOrigin),
            Longitude!double.fromDegrees(
                longitudeOfNaturalOrigin),
            scaleFactorAtNaturalOrigin,
            falseEasting,
            falseNorthing);

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

        const double latitude =
            fields[0].to!double;
        const double longitude =
            fields[1].to!double;

        const source =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude),
                Longitude!double.fromDegrees(longitude));

        ProjectedCoordinate!double projected;

        if (!projection.tryForward(source, projected))
        {
            writefln("FORWARD_REJECT");
            continue;
        }

        GeographicCoordinate!double reversed;

        if (!projection.tryReverse(projected, reversed))
        {
            writefln("REVERSE_REJECT");
            continue;
        }

        double convergenceBRadians;
        double pointScaleB;

        if (!projection.researchTryReverseFactors(
                projected,
                convergenceBRadians,
                pointScaleB))
        {
            writefln("B_REJECT");
            continue;
        }

        double convergenceARadians;
        double pointScaleA;

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
            || !isFinite(reversed.latitude.degrees)
            || !isFinite(reversed.longitude.degrees)
            || !isFinite(convergenceBRadians)
            || !isFinite(pointScaleB)
            || !isFinite(convergenceARadians)
            || !isFinite(pointScaleA)
            || !(pointScaleB > 0.0)
            || !(pointScaleA > 0.0))
        {
            writefln("NONFINITE");
            return 1;
        }

        writefln(
            "OK\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g\t%.17g",
            projected.easting,
            projected.northing,
            reversed.latitude.degrees,
            reversed.longitude.degrees,
            degrees(convergenceBRadians),
            pointScaleB,
            degrees(convergenceARadians),
            pointScaleA);
    }

    return 0;
}
