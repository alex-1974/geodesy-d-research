#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>
#include <cmath>
#include <cstddef>
#include <vector>

extern "C" std::size_t r69_all(
    double a, double f,
    double latX, double lonX, double aziX,
    double latY, double lonY, double aziY,
    double maxdist, double x0, double y0,
    double* xs, double* ys, int* cs,
    std::size_t capacity)
{
    if (!xs || !ys || !cs) return 0;

    try {
        const GeographicLib::Geodesic geod(a,f);
        const GeographicLib::Intersect inter(geod);
        std::vector<int> coincidence;
        const auto points=inter.All(
            latX,lonX,aziX,
            latY,lonY,aziY,
            maxdist,
            coincidence,
            GeographicLib::Intersect::Point(x0,y0));

        if (points.size()>capacity || coincidence.size()!=points.size())
            return 0;

        for(std::size_t i=0;i<points.size();++i) {
            xs[i]=points[i].first;
            ys[i]=points[i].second;
            cs[i]=coincidence[i];
        }

        return points.size();
    } catch (...) {
        return 0;
    }
}
