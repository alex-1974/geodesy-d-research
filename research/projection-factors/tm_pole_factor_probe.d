module geodesy.projection.tm_pole_factor_probe;

import std.math : fabs;
import std.stdio : writefln;

import geodesy.angle : Latitude, Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geographic : GeographicCoordinate;
import geodesy.projected : ProjectedCoordinate;
import geodesy.projection.transverse_mercator :
    TransverseMercator;


private enum double[] longitudeDegrees = [
    -180.0,
    -120.0,
    -45.0,
    15.0,
    45.0,
    75.0,
    120.0,
    180.0,
];


private bool sameProjected(T)(
    const ProjectedCoordinate!T a,
    const ProjectedCoordinate!T b)
{
    return a.easting == b.easting
        && a.northing == b.northing;
}


private bool runProfile(T)(
    const string name,
    const Ellipsoid!T ellipsoid,
    const T k0)
{
    const latitudeOfOrigin =
        Latitude!T.fromDegrees(cast(T) 0);

    const longitudeOfOrigin =
        Longitude!T.fromDegrees(cast(T) 15);

    const projection =
        TransverseMercator!T.fromParameters(
            ellipsoid,
            latitudeOfOrigin,
            longitudeOfOrigin,
            k0,
            cast(T) 500_000,
            cast(T) -2_000_000);

    bool pass = true;

    writefln("");
    writefln(
        "=== %s / %s ===",
        name,
        T.stringof);

    foreach (const poleDegrees; [-90.0, 90.0])
    {
        bool haveReference = false;
        ProjectedCoordinate!T referenceProjected;

        foreach (const longitudeDegreesValue; longitudeDegrees)
        {
            const source =
                GeographicCoordinate!T.fromComponents(
                    Latitude!T.fromDegrees(
                        cast(T) poleDegrees),
                    Longitude!T.fromDegrees(
                        cast(T) longitudeDegreesValue));

            ProjectedCoordinate!T projected;

            const bool forwardOk =
                projection.tryForward(
                    source,
                    projected);

            T forwardGamma;
            T forwardScale;

            const bool forwardFactorOk =
                projection.researchTryForwardFactors(
                    source,
                    forwardGamma,
                    forwardScale);

            if (!forwardOk || !forwardFactorOk)
            {
                writefln(
                    "FAIL forward: pole=%+.0f lon=%+.0f "
                    ~ "forward=%s factors=%s",
                    poleDegrees,
                    longitudeDegreesValue,
                    forwardOk,
                    forwardFactorOk);
                pass = false;
                continue;
            }

            if (!haveReference)
            {
                referenceProjected = projected;
                haveReference = true;
            }
            else if (!sameProjected(
                    referenceProjected,
                    projected))
            {
                writefln(
                    "FAIL projected pole depends on longitude: "
                    ~ "pole=%+.0f lon=%+.0f",
                    poleDegrees,
                    longitudeDegreesValue);
                pass = false;
            }

            if (forwardGamma != cast(T) 0)
            {
                writefln(
                    "FAIL forward gamma: pole=%+.0f lon=%+.0f "
                    ~ "gamma=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) forwardGamma);
                pass = false;
            }

            if (forwardScale != k0)
            {
                writefln(
                    "FAIL forward scale: pole=%+.0f lon=%+.0f "
                    ~ "scale=%.17g expected=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) forwardScale,
                    cast(double) k0);
                pass = false;
            }

            GeographicCoordinate!T reversed;

            const bool reverseOk =
                projection.tryReverse(
                    projected,
                    reversed);

            T reverseGamma;
            T reverseScale;

            const bool reverseFactorOk =
                projection.researchTryReverseFactors(
                    projected,
                    reverseGamma,
                    reverseScale);

            if (!reverseOk || !reverseFactorOk)
            {
                writefln(
                    "FAIL reverse: pole=%+.0f lon=%+.0f "
                    ~ "reverse=%s factors=%s",
                    poleDegrees,
                    longitudeDegreesValue,
                    reverseOk,
                    reverseFactorOk);
                pass = false;
                continue;
            }

            if (reverseGamma != cast(T) 0)
            {
                writefln(
                    "FAIL reverse gamma: pole=%+.0f lon=%+.0f "
                    ~ "gamma=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) reverseGamma);
                pass = false;
            }

            if (reverseScale != k0)
            {
                writefln(
                    "FAIL reverse scale: pole=%+.0f lon=%+.0f "
                    ~ "scale=%.17g expected=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) reverseScale,
                    cast(double) k0);
                pass = false;
            }

            if (
                forwardGamma != reverseGamma
                || forwardScale != reverseScale)
            {
                writefln(
                    "FAIL forward/reverse factor mismatch: "
                    ~ "pole=%+.0f lon=%+.0f",
                    poleDegrees,
                    longitudeDegreesValue);
                pass = false;
            }

            /*
             * Reverse already defines the canonical pole longitude as lon0.
             * Compare represented radians, not decimal degrees.
             */
            if (
                reversed.longitude.radians
                != longitudeOfOrigin.radians)
            {
                writefln(
                    "FAIL reverse canonical longitude: "
                    ~ "pole=%+.0f lon=%+.0f "
                    ~ "actual=%.17g expected=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) reversed.longitude.radians,
                    cast(double) longitudeOfOrigin.radians);
                pass = false;
            }

            if (
                fabs(
                    cast(double) reversed.latitude.degrees
                    - poleDegrees)
                != 0.0)
            {
                writefln(
                    "FAIL reverse latitude: "
                    ~ "pole=%+.0f lon=%+.0f actual=%.17g",
                    poleDegrees,
                    longitudeDegreesValue,
                    cast(double) reversed.latitude.degrees);
                pass = false;
            }
        }

        writefln(
            "pole=%+.0f represented E/N=%.17g %.17g",
            poleDegrees,
            cast(double) referenceProjected.easting,
            cast(double) referenceProjected.northing);
    }

    if (pass)
        writefln("RESULT %s / %s: PASS", name, T.stringof);
    else
        writefln("RESULT %s / %s: FAIL", name, T.stringof);

    return pass;
}


int main()
{
    bool pass = true;

    pass = runProfile!float(
        "sphere",
        Ellipsoid!float.fromFlattening(
            6_371_000.0f,
            0.0f),
        0.9996f) && pass;

    pass = runProfile!double(
        "sphere",
        Ellipsoid!double.fromFlattening(
            6_371_000.0,
            0.0),
        0.9996) && pass;

    pass = runProfile!float(
        "WGS84",
        Ellipsoid!float.fromInverseFlattening(
            6_378_137.0f,
            cast(float) 298.257223563),
        0.9996f) && pass;

    pass = runProfile!double(
        "WGS84",
        Ellipsoid!double.fromInverseFlattening(
            6_378_137.0,
            298.257223563),
        0.9996) && pass;

    writefln("");
    writefln(
        "PF-A OVERALL RESULT: %s",
        pass ? "PASS" : "FAIL");

    return pass ? 0 : 1;
}
