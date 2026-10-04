module direct_probe;

import std.conv : to;
import std.stdio : stdin, stdout;
import std.string : split, strip;

import geodesy.angle :
    Angle,
    Latitude,
    Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geodesic :
    Geodesic,
    GeodesicDirectResult;
import geodesy.geographic : GeographicCoordinate;


version (ProbeFloat)
    alias Scalar = float;
else version (ProbeReal)
    alias Scalar = real;
else
    alias Scalar = double;


void main()
{
    foreach (line; stdin.byLineCopy())
    {
        const fields = line.strip.split;

        if (fields.length == 0)
            continue;

        if (fields.length != 6)
        {
            stdout.writeln("FAIL");
            continue;
        }

        const Scalar a = fields[0].to!Scalar;
        const Scalar f = fields[1].to!Scalar;
        const Scalar lat1 = fields[2].to!Scalar;
        const Scalar lon1 = fields[3].to!Scalar;
        const Scalar azi1 = fields[4].to!Scalar;
        const Scalar s12 = fields[5].to!Scalar;

        const ellipsoid =
            Ellipsoid!Scalar.fromFlattening(a, f);

        const solver =
            Geodesic!Scalar.fromEllipsoid(ellipsoid);

        const start =
            GeographicCoordinate!Scalar.fromComponents(
                Latitude!Scalar.fromDegrees(lat1),
                Longitude!Scalar.fromDegrees(lon1));

        GeodesicDirectResult!Scalar result;

        if (!solver.tryDirect(
                start,
                Angle!Scalar.fromDegrees(azi1),
                s12,
                result))
        {
            stdout.writeln("FAIL");
            continue;
        }

        stdout.writefln(
            "%.21g %.21g %.21g",
            result.position.latitude.degrees,
            result.position.longitude.degrees,
            result.finalAzimuth.degrees);
    }
}
