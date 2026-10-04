/**
 * Batch probe for differential validation of the public topocentric API.
 *
 * This program intentionally imports only public geodesy modules. It does not
 * access package/private working kernels.
 *
 * Invocation:
 *
 *   geodesy_topocentric_probe OP a f origin1 origin2 origin3
 *
 * OP:
 *   9836f  origin = X0 Y0 Z0; input  = X Y Z;       output = E N U
 *   9836r  origin = X0 Y0 Z0; input  = E N U;       output = X Y Z
 *   9837f  origin = lat lon h; input = lat lon h;   output = E N U
 *   9837r  origin = lat lon h; input = E N U;       output = lat lon h
 *
 * Angles at the process boundary are degrees.
 */
module geodesy_topocentric_probe;

import std.conv : to;
import std.stdio : stdin, stderr, writefln;
import std.string : split, strip;

import geodesy.angle :
    Latitude,
    Longitude;
import geodesy.ellipsoid :
    Ellipsoid;
import geodesy.geocentric :
    GeocentricCoordinate;
import geodesy.geodetic :
    GeodeticCoordinate;
import geodesy.topocentric :
    TopocentricCoordinate,
    TopocentricFrame;


version (TopocentricRealProbe)
    alias ProbeScalar = real;
else
    alias ProbeScalar = double;


private bool parseTriple(
    const string line,
    out ProbeScalar a,
    out ProbeScalar b,
    out ProbeScalar c)
{
    const fields = line.strip.split;

    if (fields.length != 3)
        return false;

    try
    {
        a = fields[0].to!ProbeScalar;
        b = fields[1].to!ProbeScalar;
        c = fields[2].to!ProbeScalar;
    }
    catch (Exception)
    {
        return false;
    }

    return true;
}


int main(string[] args)
{
    if (args.length != 7)
    {
        stderr.writefln(
            "usage: %s OP a f origin1 origin2 origin3",
            args[0]);
        return 2;
    }

    const operation = args[1];

    ProbeScalar semiMajorAxis;
    ProbeScalar flattening;
    ProbeScalar origin1;
    ProbeScalar origin2;
    ProbeScalar origin3;

    try
    {
        semiMajorAxis = args[2].to!ProbeScalar;
        flattening = args[3].to!ProbeScalar;
        origin1 = args[4].to!ProbeScalar;
        origin2 = args[5].to!ProbeScalar;
        origin3 = args[6].to!ProbeScalar;
    }
    catch (Exception)
    {
        stderr.writefln(
            "invalid command-line numeric argument");
        return 2;
    }

    Ellipsoid!ProbeScalar ellipsoid;

    if (!Ellipsoid!ProbeScalar.tryFromFlattening(
        semiMajorAxis,
        flattening,
        ellipsoid))
    {
        stderr.writefln("invalid ellipsoid");
        return 3;
    }

    TopocentricFrame!ProbeScalar frame;

    if (operation == "9836f"
        || operation == "9836r")
    {
        GeocentricCoordinate!ProbeScalar origin;

        if (!GeocentricCoordinate!ProbeScalar.tryFromComponents(
                origin1,
                origin2,
                origin3,
                origin)
            || !TopocentricFrame!ProbeScalar.tryFromGeocentricOrigin(
                ellipsoid,
                origin,
                frame))
        {
            stderr.writefln(
                "failed to prepare geocentric-origin frame");
            return 3;
        }
    }
    else if (operation == "9837f"
        || operation == "9837r")
    {
        Latitude!ProbeScalar latitude;
        Longitude!ProbeScalar longitude;
        GeodeticCoordinate!ProbeScalar origin;

        if (!Latitude!ProbeScalar.tryFromDegrees(
                origin1,
                latitude)
            || !Longitude!ProbeScalar.tryFromDegrees(
                origin2,
                longitude)
            || !GeodeticCoordinate!ProbeScalar.tryFromComponents(
                latitude,
                longitude,
                origin3,
                origin)
            || !TopocentricFrame!ProbeScalar.tryFromGeodeticOrigin(
                ellipsoid,
                origin,
                frame))
        {
            stderr.writefln(
                "failed to prepare geodetic-origin frame");
            return 3;
        }
    }
    else
    {
        stderr.writefln(
            "unknown operation: %s",
            operation);
        return 2;
    }

    size_t row = 0;

    foreach (line; stdin.byLineCopy())
    {
        ++row;

        if (line.strip.length == 0)
            continue;

        ProbeScalar a;
        ProbeScalar b;
        ProbeScalar c;

        if (!parseTriple(
            line,
            a,
            b,
            c))
        {
            stderr.writefln(
                "invalid input row %s",
                row);
            return 4;
        }

        if (operation == "9836f")
        {
            GeocentricCoordinate!ProbeScalar source;
            TopocentricCoordinate!ProbeScalar result;

            if (!GeocentricCoordinate!ProbeScalar.tryFromComponents(
                    a,
                    b,
                    c,
                    source)
                || !frame.tryGeocentricToTopocentric(
                    source,
                    result))
            {
                stderr.writefln(
                    "9836 forward failed at row %s",
                    row);
                return 5;
            }

            writefln(
                "%.36g %.36g %.36g",
                result.east,
                result.north,
                result.up);
        }
        else if (operation == "9836r")
        {
            TopocentricCoordinate!ProbeScalar source;
            GeocentricCoordinate!ProbeScalar result;

            if (!TopocentricCoordinate!ProbeScalar.tryFromComponents(
                    a,
                    b,
                    c,
                    source)
                || !frame.tryTopocentricToGeocentric(
                    source,
                    result))
            {
                stderr.writefln(
                    "9836 reverse failed at row %s",
                    row);
                return 5;
            }

            writefln(
                "%.36g %.36g %.36g",
                result.x,
                result.y,
                result.z);
        }
        else if (operation == "9837f")
        {
            Latitude!ProbeScalar latitude;
            Longitude!ProbeScalar longitude;
            GeodeticCoordinate!ProbeScalar source;
            TopocentricCoordinate!ProbeScalar result;

            if (!Latitude!ProbeScalar.tryFromDegrees(
                    a,
                    latitude)
                || !Longitude!ProbeScalar.tryFromDegrees(
                    b,
                    longitude)
                || !GeodeticCoordinate!ProbeScalar.tryFromComponents(
                    latitude,
                    longitude,
                    c,
                    source)
                || !frame.tryGeodeticToTopocentric(
                    source,
                    result))
            {
                stderr.writefln(
                    "9837 forward failed at row %s",
                    row);
                return 5;
            }

            writefln(
                "%.36g %.36g %.36g",
                result.east,
                result.north,
                result.up);
        }
        else
        {
            TopocentricCoordinate!ProbeScalar source;
            GeodeticCoordinate!ProbeScalar result;

            if (!TopocentricCoordinate!ProbeScalar.tryFromComponents(
                    a,
                    b,
                    c,
                    source)
                || !frame.tryTopocentricToGeodetic(
                    source,
                    result))
            {
                stderr.writefln(
                    "9837 reverse failed at row %s",
                    row);
                return 5;
            }

            writefln(
                "%.36g %.36g %.36g",
                result.latitude.degrees,
                result.longitude.degrees,
                result.ellipsoidalHeight);
        }
    }

    return 0;
}
