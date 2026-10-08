#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

extern "C"
int m5_106_reference(
    double a, double f,
    double latX, double lonX, double aziX,
    double latY, double lonY, double aziY,
    double p0x, double p0y, double radius,
    std::size_t capacity,
    std::size_t* count,
    double* xs, double* ys, int* cs)
{
    if (!count)
        return 0;

    try {
        const GeographicLib::Geodesic geod(a, f);
        const GeographicLib::Intersect inter(geod);
        std::vector<int> coincidence;
        const auto points = inter.All(
            latX, lonX, aziX,
            latY, lonY, aziY,
            std::max(0.0, radius),
            coincidence,
            GeographicLib::Intersect::Point(p0x, p0y));

        *count = points.size();

        if (points.size() > capacity)
            return 2;

        if ((!points.empty()) && (!xs || !ys || !cs))
            return 0;

        for (std::size_t i = 0; i < points.size(); ++i) {
            xs[i] = points[i].first;
            ys[i] = points[i].second;
            cs[i] = coincidence[i];
        }

        return 1;
    } catch (...) {
        return 0;
    }
}
