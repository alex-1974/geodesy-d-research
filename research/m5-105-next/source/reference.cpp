#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Intersect.hpp>

#include <cmath>

extern "C"
int m5_105_reference(
    double a,
    double f,
    double lat,
    double lon,
    double aziX,
    double aziY,
    double* x,
    double* y,
    int* coincidence,
    double* outLat,
    double* outLon)
{
    if (!x || !y || !coincidence || !outLat || !outLon)
        return 0;

    try {
        const GeographicLib::Geodesic geod(a, f);
        const GeographicLib::Intersect inter(geod);

        int c = 0;
        const auto p = inter.Next(lat, lon, aziX, aziY, &c);

        const auto line = geod.Line(
            lat, lon, aziX,
            GeographicLib::GeodesicLine::STANDARD
                | GeographicLib::GeodesicLine::DISTANCE_IN);

        double finalAzi;
        line.Position(p.first, *outLat, *outLon, finalAzi);

        *x = p.first;
        *y = p.second;
        *coincidence = c;

        return std::isfinite(*x)
            && std::isfinite(*y)
            && std::isfinite(*outLat)
            && std::isfinite(*outLon);
    } catch (...) {
        return 0;
    }
}
