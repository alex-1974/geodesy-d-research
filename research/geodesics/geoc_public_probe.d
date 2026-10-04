module geodesy.research.geoc_public_probe;

import std.conv : to;
import std.stdio : stdin, writefln;
import std.string : split, strip;

import geodesy.angle : Angle, Latitude, Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geodesic :
    Geodesic,
    GeodesicDirectResult,
    GeodesicInverseResult;
import geodesy.geographic : GeographicCoordinate;

private void solveDirect(T)(const string[] fields)
{
    if (fields.length != 7)
        return;

    const T a = fields[1].to!T;
    const T f = fields[2].to!T;
    const T latitudeDegrees = fields[3].to!T;
    const T longitudeDegrees = fields[4].to!T;
    const T azimuthDegrees = fields[5].to!T;
    const T distance = fields[6].to!T;

    const ellipsoid = Ellipsoid!T.fromFlattening(a, f);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    const start = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromDegrees(latitudeDegrees),
        Longitude!T.fromDegrees(longitudeDegrees));

    const initialAzimuth = Angle!T.fromDegrees(azimuthDegrees);

    GeodesicDirectResult!T result;

    if (!solver.tryDirect(
            start,
            initialAzimuth,
            distance,
            result))
    {
        writefln("FAIL");
        return;
    }

    writefln(
        "D %.21g %.21g %.21g %.21g %.21g %.21g %.21g",
        cast(real) start.latitude.radians,
        cast(real) start.longitude.radians,
        cast(real) initialAzimuth.radians,
        cast(real) distance,
        cast(real) result.position.latitude.radians,
        cast(real) result.position.longitude.radians,
        cast(real) result.finalAzimuth.radians);
}

private void solveInverse(T)(const string[] fields)
{
    if (fields.length != 7)
        return;

    const T a = fields[1].to!T;
    const T f = fields[2].to!T;
    const T latitude1Degrees = fields[3].to!T;
    const T longitude1Degrees = fields[4].to!T;
    const T latitude2Degrees = fields[5].to!T;
    const T longitude2Degrees = fields[6].to!T;

    const ellipsoid = Ellipsoid!T.fromFlattening(a, f);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    const start = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromDegrees(latitude1Degrees),
        Longitude!T.fromDegrees(longitude1Degrees));

    const end = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromDegrees(latitude2Degrees),
        Longitude!T.fromDegrees(longitude2Degrees));

    GeodesicInverseResult!T result;

    if (!solver.tryInverse(start, end, result))
    {
        writefln("FAIL");
        return;
    }

    writefln(
        "I %.21g %.21g %.21g %.21g %.21g %.21g %.21g",
        cast(real) start.latitude.radians,
        cast(real) start.longitude.radians,
        cast(real) end.latitude.radians,
        cast(real) end.longitude.radians,
        cast(real) result.distance,
        cast(real) result.initialAzimuth.radians,
        cast(real) result.finalAzimuth.radians);
}

private void solve(T)(const string line)
{
    const fields = line.strip.split;

    if (fields.length == 0)
        return;

    switch (fields[0])
    {
        case "D":
            solveDirect!T(fields);
            break;

        case "I":
            solveInverse!T(fields);
            break;

        default:
            return;
    }
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
