#include <GeographicLib/Geodesic.hpp>
#include <cmath>

extern "C" int r69_direct(
    double a, double f,
    double lat1, double lon1, double azi1, double s12,
    double* lat2, double* lon2, double* azi2)
{
    if (!lat2 || !lon2 || !azi2) return 0;
    try {
        GeographicLib::Geodesic geod(a, f);
        geod.Direct(lat1, lon1, azi1, s12, *lat2, *lon2, *azi2);
        return std::isfinite(*lat2) && std::isfinite(*lon2)
            && std::isfinite(*azi2);
    } catch (...) {
        return 0;
    }
}

extern "C" int r69_inverse(
    double a, double f,
    double lat1, double lon1, double lat2, double lon2,
    double* s12, double* azi1, double* azi2)
{
    if (!s12 || !azi1 || !azi2) return 0;
    try {
        GeographicLib::Geodesic geod(a, f);
        geod.Inverse(lat1, lon1, lat2, lon2, *s12, *azi1, *azi2);
        return std::isfinite(*s12) && std::isfinite(*azi1)
            && std::isfinite(*azi2);
    } catch (...) {
        return 0;
    }
}
