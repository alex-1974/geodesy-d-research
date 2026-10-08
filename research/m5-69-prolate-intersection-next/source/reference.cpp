#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>
#include <cmath>

extern "C" int r69_next(
    double a, double f,
    double lat, double lon,
    double aziX, double aziY,
    double* x, double* y, int* coincidence)
{
    if (!x || !y || !coincidence) return 0;
    try {
        const GeographicLib::Geodesic geod(a,f);
        const GeographicLib::Intersect inter(geod);
        int c=0;
        const auto p=inter.Next(lat,lon,aziX,aziY,&c);
        *x=p.first; *y=p.second; *coincidence=c;
        return std::isfinite(*x)&&std::isfinite(*y);
    } catch (...) { return 0; }
}
