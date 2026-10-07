module m5_46_d_solver;

import geodesy;
import std.math : PI, abs, atan2, atanh, cos, copysign, sin, sqrt;
import std.stdio : writefln, writeln;

extern(C) int m5_46_reference(
    double,double,double,double,double,double,double,double,
    int*,double*,double*,double*,double*);

private double wrapPi(double x)
{
    const double tau=2.0*cast(double)PI;
    x%=tau;
    if (x>=cast(double)PI) x-=tau;
    if (x< -cast(double)PI) x+=tau;
    return x;
}

private double authalicRadius(const Geodesic!double solver)
{
    const double a=solver.ellipsoid.semiMajorAxis;
    const double f=solver.ellipsoid.flattening;
    const double e2=f*(2.0-f);
    if (e2==0.0) return a;
    const double e=sqrt(e2);
    const double r2=
        a*a*0.5*(1.0 + (1.0-e2)/e*atanh(e));
    return sqrt(r2);
}

private struct P
{
    double x;
    double y;
    int c;
}

private struct Seg
{
    GeographicCoordinate!double a;
    GeographicCoordinate!double b;
    double length;
    GeodesicLine!double line;
}

private bool basic(
    const Geodesic!double solver,
    const Seg xseg,
    const Seg yseg,
    const double rR,
    const P seed,
    out P p)
{
    p=seed;
    const double eps=3.0*double.epsilon;
    const double tol=cast(double)PI*rR*
        (double.epsilon ^^ 0.75);

    foreach (_;0..100)
    {
        GeodesicDirectResult!double px,py;
        if (!xseg.line.tryPosition(p.x,px) ||
            !yseg.line.tryPosition(p.y,py))
            return false;

        GeodesicInverseResult!double inv;
        if (!solver.tryInverse(px.position,py.position,inv))
            return false;

        const double z=inv.distance;
        const double zr=z/rR;
        const double sinz=sin(zr);
        const double cosz=cos(zr);

        const double X=wrapPi(
            inv.initialAzimuth.radians-px.finalAzimuth.radians);
        const double Y=wrapPi(
            inv.finalAzimuth.radians-py.finalAzimuth.radians);
        double sign=wrapPi(Y-X)>=0.0 ? 1.0 : -1.0;

        const double sinX=sin(sign*X), cosX=cos(sign*X);
        const double sinY=sin(sign*Y), cosY=cos(sign*Y);

        double dx,dy;
        int c=0;

        if (z <= eps*rR)
        {
            dx=dy=0.0;
            if (abs(sinX-sinY)<=eps && abs(cosX-cosY)<=eps) c=1;
            else if (abs(sinX+sinY)<=eps && abs(cosX+cosY)<=eps) c=-1;
        }
        else if (abs(sinX)<=eps && abs(sinY)<=eps)
        {
            c=cosX*cosY>0 ? 1 : -1;
            dx= cosX*z/2.0;
            dy=-cosY*z/2.0;
        }
        else
        {
            dx=rR*atan2(
                sinY*sinz,
                sinY*cosX*cosz-cosY*sinX);
            dy=rR*atan2(
                sinX*sinz,
                -sinX*cosY*cosz+cosX*sinY);
        }

        p.x+=dx;
        p.y+=dy;
        p.c=c;

        if (c!=0 || abs(dx)+abs(dy)<=tol)
            return true;
    }
    return false;
}

private enum Kind { none, point, overlap }

private struct Result
{
    Kind kind;
    GeographicCoordinate!double p0;
    GeographicCoordinate!double p1;
}

private bool inRange(double v,double hi,double tol)
{
    return v>=-tol && v<=hi+tol;
}

private Result classify(const Seg xseg,const Seg yseg,const P p)
{
    enum double tol=1e-7;
    Result r;

    if (p.c==0)
    {
        if (!inRange(p.x,xseg.length,tol) ||
            !inRange(p.y,yseg.length,tol))
            return r;

        const double sx=
            p.x<0?0:p.x>xseg.length?xseg.length:p.x;
        r.kind=Kind.point;
        r.p0=xseg.line.position(sx).position;
        r.p1=r.p0;
        return r;
    }

    const double xa=p.x+p.c*(0.0-p.y);
    const double xb=p.x+p.c*(yseg.length-p.y);
    const double lo0=xa<xb?xa:xb;
    const double hi0=xa>xb?xa:xb;
    double lo=lo0>0?lo0:0;
    double hi=hi0<xseg.length?hi0:xseg.length;

    if (hi<lo-tol) return r;
    if (lo<0) lo=0;
    if (hi>xseg.length) hi=xseg.length;

    if (abs(hi-lo)<=tol)
    {
        r.kind=Kind.point;
        r.p0=xseg.line.position((lo+hi)/2).position;
        r.p1=r.p0;
        return r;
    }

    r.kind=Kind.overlap;
    r.p0=xseg.line.position(lo).position;
    r.p1=xseg.line.position(hi).position;
    return r;
}

private Result solve(
    const Geodesic!double solver,
    const GeographicCoordinate!double a0,
    const GeographicCoordinate!double a1,
    const GeographicCoordinate!double b0,
    const GeographicCoordinate!double b1)
{
    const ia=solver.inverse(a0,a1);
    const ib=solver.inverse(b0,b1);
    if (ia.distance==0 || ib.distance==0) return Result.init;

    const Seg xs=Seg(a0,a1,ia.distance,
        GeodesicLine!double.fromGeodesic(solver,a0,ia.initialAzimuth));
    const Seg ys=Seg(b0,b1,ib.distance,
        GeodesicLine!double.fromGeodesic(solver,b0,ib.initialAzimuth));

    const double rR=authalicRadius(solver);
    const P[5] seeds=[
        P(xs.length/2,ys.length/2,0),
        P(0,0,0),
        P(xs.length,0,0),
        P(0,ys.length,0),
        P(xs.length,ys.length,0)
    ];

    Result best;
    foreach(seed;seeds)
    {
        P p;
        if (!basic(solver,xs,ys,rR,seed,p)) continue;
        const auto r=classify(xs,ys,p);
        if (r.kind==Kind.overlap) return r;
        if (r.kind==Kind.point) return r;
    }
    return best;
}

private double coordError(
    GeographicCoordinate!double a,
    GeographicCoordinate!double b)
{
    const double dlat=abs(a.latitude.radians-b.latitude.radians);
    const double dlon=abs(wrapPi(
        a.longitude.radians-b.longitude.radians));
    return dlat>dlon?dlat:dlon;
}

private GeographicCoordinate!double gc(
    const double lat,
    const double lon)
{
    return GeographicCoordinate!double.fromComponents(
        Latitude!double.fromDegrees(lat),
        Longitude!double.fromDegrees(lon));
}

private struct Case
{
    string name;
    double a1lat,a1lon,a2lat,a2lon,b1lat,b1lon,b2lat,b2lon;
}

void main()
{
    const solver=Geodesic!double.fromEllipsoid(wgs84!double());
    Case[] cases=[
        Case("crossing",0,-10,0,10,-10,0,10,0),
        Case("shared endpoint",0,-10,0,0,0,0,10,0),
        Case("separate",0,-10,0,-5,10,5,10,10),
        Case("overlap same",0,-10,0,10,0,-5,0,15),
        Case("overlap reverse",0,-10,0,10,0,15,0,-5),
        Case("contained",0,-10,0,10,0,-5,0,5),
        Case("coincident disjoint",0,-10,0,-5,0,5,0,10),
        Case("antimeridian",0,170,0,-170,-10,180,10,180),
        Case("oblique",35,-20,55,30,50,-15,30,25),
        Case("near parallel",10,-30,10,30,10.1,-30,10.1,30)
    ];

    size_t failures=0;
    foreach(tc;cases)
    {
        const a0=gc(tc.a1lat,tc.a1lon), a1=gc(tc.a2lat,tc.a2lon);
        const b0=gc(tc.b1lat,tc.b1lon), b1=gc(tc.b2lat,tc.b2lon);

        const actual=solve(solver,a0,a1,b0,b1);

        int rk;
        double rlat0,rlon0,rlat1,rlon1;
        const int ok=m5_46_reference(
            tc.a1lat,tc.a1lon,tc.a2lat,tc.a2lon,
            tc.b1lat,tc.b1lon,tc.b2lat,tc.b2lon,
            &rk,&rlat0,&rlon0,&rlat1,&rlon1);

        if (!ok) { writefln("FAIL %-20s oracle",tc.name); ++failures; continue; }

        const Kind expected=
            rk==0?Kind.none:rk==1?Kind.point:Kind.overlap;
        bool pass=actual.kind==expected;

        if (pass && expected!=Kind.none)
        {
            const auto rp0=gc(rlat0,rlon0);
            const auto rp1=gc(rlat1,rlon1);
            if (expected==Kind.point)
                pass=coordError(actual.p0,rp0)<3e-11;
            else
            {
                const bool same=
                    coordError(actual.p0,rp0)<3e-11 &&
                    coordError(actual.p1,rp1)<3e-11;
                const bool reversed=
                    coordError(actual.p0,rp1)<3e-11 &&
                    coordError(actual.p1,rp0)<3e-11;
                pass=same||reversed;
            }
        }

        writefln("%s %-20s actual=%s expected=%s",
            pass?"PASS":"FAIL",tc.name,actual.kind,expected);
        if(!pass) ++failures;
    }

    if(failures)
    {
        writefln("M5 #46 D SOLVER PROBE FAIL: %s",failures);
        assert(0);
    }
    writeln("M5 #46 D SOLVER PROBE PASS");
}
