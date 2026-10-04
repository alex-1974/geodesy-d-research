module geodesy.research.public_inverse_probe;

import std.conv : to;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.angle :
    Latitude,
    Longitude;
import geodesy.ellipsoid :
    Ellipsoid;
import geodesy.geodesic :
    Geodesic,
    GeodesicInverseResult;
import geodesy.geographic :
    GeographicCoordinate;


void solve(T)(const string line)
{
    const fields =
        line.strip.split;

    if (fields.length != 6)
        return;

    const T a =
        fields[0].to!T;

    const T f =
        fields[1].to!T;

    const T latitude1Degrees =
        fields[2].to!T;

    const T longitude1Degrees =
        fields[3].to!T;

    const T latitude2Degrees =
        fields[4].to!T;

    const T longitude2Degrees =
        fields[5].to!T;

    const ellipsoid =
        Ellipsoid!T.fromFlattening(
            a,
            f);

    const solver =
        Geodesic!T.fromEllipsoid(
            ellipsoid);

    const start =
        GeographicCoordinate!T.fromComponents(
            Latitude!T.fromDegrees(
                latitude1Degrees),
            Longitude!T.fromDegrees(
                longitude1Degrees));

    const end =
        GeographicCoordinate!T.fromComponents(
            Latitude!T.fromDegrees(
                latitude2Degrees),
            Longitude!T.fromDegrees(
                longitude2Degrees));

    GeodesicInverseResult!T result;

    if (!solver.tryInverse(
            start,
            end,
            result))
    {
        writefln("FAIL");
        return;
    }

    /*
     * Echo the actually stored public coordinate radians.  The validator uses
     * these values for the oracle, so constructor/input quantization is not
     * accidentally charged to the geodesic solver.
     *
     * Cast to real before formatting.  This preserves every float/double bit
     * and all 64 significand bits of x86 extended real for decimal output.
     */
    writefln(
        "%.21g %.21g %.21g %.21g %.21g %.21g %.21g",
        cast(real) start.latitude.radians,
        cast(real) start.longitude.radians,
        cast(real) end.latitude.radians,
        cast(real) end.longitude.radians,
        cast(real) result.distance,
        cast(real) result.initialAzimuth.radians,
        cast(real) result.finalAzimuth.radians);
}


void main(string[] args)
{
    if (args.length != 2)
        return;

    foreach (line; stdin.byLineCopy())
    {
        switch (args[1])
        {
            case "float":
                solve!float(line);
                break;

            case "double":
                solve!double(line);
                break;

            case "real":
                solve!real(line);
                break;

            default:
                return;
        }
    }
}
