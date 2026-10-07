#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Intersect.hpp>

#include <cmath>

extern "C"
int m5_104_reference(
    double a,
    double f,
    double latX,
    double lonX,
    double aziX,
    double latY,
    double lonY,
    double aziY,
    double p0x,
    double p0y,
    double* x,
    double* y,
    int* coincidence,
    double* lat,
    double* lon)
{
    if (!x || !y || !coincidence || !lat || !lon)
        return 0;

    try {
        const GeographicLib::Geodesic geod(a, f);
        const GeographicLib::Intersect inter(geod);

        int c = 0;
        const auto p =
            inter.Closest(
                latX, lonX, aziX,
                latY, lonY, aziY,
                GeographicLib::Intersect::Point(p0x, p0y),
                &c);

        const auto line =
            geod.Line(
                latX, lonX, aziX,
                GeographicLib::GeodesicLine::STANDARD
                    | GeographicLib::GeodesicLine::DISTANCE_IN);

        double finalAzi;
        line.Position(p.first, *lat, *lon, finalAzi);

        *x = p.first;
        *y = p.second;
        *coincidence = c;

        return std::isfinite(*x)
            && std::isfinite(*y)
            && std::isfinite(*lat)
            && std::isfinite(*lon);
    } catch (...) {
        return 0;
    }
}
