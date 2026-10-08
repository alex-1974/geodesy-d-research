#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>
#include <cmath>

extern "C" int r69_closest(
    double a, double f,
    double latX, double lonX, double aziX,
    double latY, double lonY, double aziY,
    double x0, double y0,
    double* x, double* y, int* coincidence)
{
    if (!x || !y || !coincidence) return 0;

    try {
        const GeographicLib::Geodesic geod(a, f);
        const GeographicLib::Intersect inter(geod);
        int c = 0;
        const auto p = inter.Closest(
            latX, lonX, aziX,
            latY, lonY, aziY,
            GeographicLib::Intersect::Point(x0,y0),
            &c);

        *x = p.first;
        *y = p.second;
        *coincidence = c;

        return std::isfinite(*x) && std::isfinite(*y);
    } catch (...) {
        return 0;
    }
}
