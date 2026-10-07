#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>
#include <algorithm>
#include <cmath>

extern "C"
int m5_46_reference(
    double ax1,double ay1,double ax2,double ay2,
    double bx1,double by1,double bx2,double by2,
    int* kind,
    double* lat0,double* lon0,double* lat1,double* lon1)
{
    if (!kind || !lat0 || !lon0 || !lat1 || !lon1) return 0;
    try {
        const auto geod = GeographicLib::Geodesic::WGS84();
        const GeographicLib::Intersect inter(geod);

        double sx,az1,az2,sy;
        geod.Inverse(ax1,ay1,ax2,ay2,sx,az1,az2);
        geod.Inverse(bx1,by1,bx2,by2,sy,az1,az2);
        if (!(sx > 0) || !(sy > 0)) return 0;

        int segmode=99,c=0;
        const auto p=inter.Segment(
            ax1,ay1,ax2,ay2,bx1,by1,bx2,by2,segmode,&c);

        auto lineX=geod.InverseLine(
            ax1,ay1,ax2,ay2,
            GeographicLib::GeodesicLine::STANDARD |
            GeographicLib::GeodesicLine::DISTANCE_IN);

        if (c==0) {
            if (segmode!=0) { *kind=0; return 1; }
            double azi;
            lineX.Position(p.first,*lat0,*lon0,azi);
            *lat1=*lat0; *lon1=*lon0; *kind=1; return 1;
        }

        const double xa=p.first + c*(0.0-p.second);
        const double xb=p.first + c*(sy-p.second);
        const double lo=std::max(0.0,std::min(xa,xb));
        const double hi=std::min(sx,std::max(xa,xb));
        const double tol=1e-7;
        if (hi < lo-tol) { *kind=0; return 1; }

        double azi;
        if (std::fabs(hi-lo)<=tol) {
            lineX.Position((lo+hi)/2,*lat0,*lon0,azi);
            *lat1=*lat0; *lon1=*lon0; *kind=1; return 1;
        }

        lineX.Position(lo,*lat0,*lon0,azi);
        lineX.Position(hi,*lat1,*lon1,azi);
        *kind=2;
        return 1;
    } catch (...) { return 0; }
}
