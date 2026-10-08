module r69_prolate_performance;

import geodesy;
import core.time : MonoTime;
import std.conv : to;
import std.stdio : writeln;

private GeographicCoordinate!double gc(double lat,double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

int main(string[] args)
{
    if(args.length != 4) return 2;

    const string mode=args[1];
    const double f=to!double(args[2]);
    const size_t rounds=to!size_t(args[3]);
    enum double a=6_378_137.0;

    const solver=Geodesic!double.fromEllipsoid(
        Ellipsoid!double.fromFlattening(a,f));

    if(!solver.isValid) return 3;

    double checksum = 0.0;
    const start=MonoTime.currTime;

    if(mode=="direct")
    {
        foreach(i;0..rounds)
        {
            GeodesicDirectResult!double r;
            const double s=2_000_000.0 + cast(double)(i % 97) * 123.0;
            if(!solver.tryDirect(
                gc(12.5,-33.0),
                Angle!double.fromDegrees(47.0),
                s,r)) return 4;
            checksum += r.position.latitude.degrees
                + r.position.longitude.degrees
                + r.finalAzimuth.degrees;
        }
    }
    else if(mode=="inverse")
    {
        foreach(i;0..rounds)
        {
            GeodesicInverseResult!double r;
            const double d=cast(double)(i % 89) * 0.001;
            if(!solver.tryInverse(
                gc(10.0+d,20.0),
                gc(-25.0,130.0-d),r)) return 5;
            checksum += r.distance
                + r.initialAzimuth.degrees
                + r.finalAzimuth.degrees;
        }
    }
    else if(mode=="intersection_prepare")
    {
        foreach(_;0..rounds)
        {
            GeodesicIntersectionSolver!double intersector;
            if(!GeodesicIntersectionSolver!double.tryFromGeodesic(
                solver,intersector)) return 6;
            checksum += intersector.isValid ? 1.0 : 0.0;
        }
    }
    else return 7;

    const elapsed=(MonoTime.currTime-start).total!"nsecs";
    const double ns=cast(double)elapsed / cast(double)rounds;

    writeln("mode=",mode);
    writeln("f=",f);
    writeln("rounds=",rounds);
    writeln("ns_per_op=",ns);
    writeln("checksum=",checksum);
    return 0;
}
