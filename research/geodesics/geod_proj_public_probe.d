module geodesy.research.geod_proj_public_probe;

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


private ulong bitsFromDouble(const double source)
{
    DoubleBits value;
    value.value = source;
    return value.bits;
}


private T publicValue(T)(const string field)
{
    /*
     * The wire value is an exact IEEE-754 binary64 bit pattern.
     *
     * float  : binary64 -> public float
     * double : binary64 -> public double
     * real   : binary64 -> exact widening to public real
     */
    return cast(T) doubleFromBits(field);
}


private void auditTransport(T)(const string[] fields)
{
    if (fields.length != 2)
        return;

    const double source = doubleFromBits(fields[1]);
    const T represented = cast(T) source;
    const double roundTrip = cast(double) represented;

    writefln("B %s", bitsFromDouble(roundTrip));
}


private void solveDirect(T)(const string[] fields)
{
    if (fields.length != 7)
        return;

    const T a = publicValue!T(fields[1]);
    const T f = publicValue!T(fields[2]);
    const T latitudeRadians = publicValue!T(fields[3]);
    const T longitudeRadians = publicValue!T(fields[4]);
    const T azimuthRadians = publicValue!T(fields[5]);
    const T distance = publicValue!T(fields[6]);

    const ellipsoid = Ellipsoid!T.fromFlattening(a, f);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    const start = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromRadians(latitudeRadians),
        Longitude!T.fromRadians(longitudeRadians));

    const initialAzimuth = Angle!T.fromRadians(azimuthRadians);

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

    /*
     * GEO-D compares against PROJ's binary64 API.  Candidate values are
     * therefore observed at the binary64 interoperability boundary.
     */
    writefln(
        "D %.17g %.17g %.17g %.17g %.17g %.17g %.17g",
        cast(double) start.latitude.radians,
        cast(double) start.longitude.radians,
        cast(double) initialAzimuth.radians,
        cast(double) distance,
        cast(double) result.position.latitude.radians,
        cast(double) result.position.longitude.radians,
        cast(double) result.finalAzimuth.radians);
}


private void solveInverse(T)(const string[] fields)
{
    if (fields.length != 7)
        return;

    const T a = publicValue!T(fields[1]);
    const T f = publicValue!T(fields[2]);
    const T latitude1Radians = publicValue!T(fields[3]);
    const T longitude1Radians = publicValue!T(fields[4]);
    const T latitude2Radians = publicValue!T(fields[5]);
    const T longitude2Radians = publicValue!T(fields[6]);

    const ellipsoid = Ellipsoid!T.fromFlattening(a, f);
    const solver = Geodesic!T.fromEllipsoid(ellipsoid);

    const start = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromRadians(latitude1Radians),
        Longitude!T.fromRadians(longitude1Radians));

    const end = GeographicCoordinate!T.fromComponents(
        Latitude!T.fromRadians(latitude2Radians),
        Longitude!T.fromRadians(longitude2Radians));

    GeodesicInverseResult!T result;

    if (!solver.tryInverse(start, end, result))
    {
        writefln("FAIL");
        return;
    }

    writefln(
        "I %.17g %.17g %.17g %.17g %.17g %.17g %.17g",
        cast(double) start.latitude.radians,
        cast(double) start.longitude.radians,
        cast(double) end.latitude.radians,
        cast(double) end.longitude.radians,
        cast(double) result.distance,
        cast(double) result.initialAzimuth.radians,
        cast(double) result.finalAzimuth.radians);
}


private void solve(T)(const string line)
{
    const fields = line.strip.split;

    if (fields.length == 0)
        return;

    switch (fields[0])
    {
        case "B":
            auditTransport!T(fields);
            break;

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
