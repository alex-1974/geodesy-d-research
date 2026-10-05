#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/PolygonArea.hpp>
#include <cstddef>
#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_polygon_reference(
    double a,
    double f,
    const double* latitudesRadians,
    const double* longitudesRadians,
    std::size_t count,
    double* perimeter,
    double* signedArea)
{
    if (!perimeter || !signedArea)
        return 0;

    try
    {
        GeographicLib::Geodesic geodesic(a, f);
        GeographicLib::PolygonArea polygon(geodesic, false);

        for (std::size_t i = 0; i < count; ++i)
        {
            polygon.AddPoint(
                latitudesRadians[i] * degreePerRadian,
                longitudesRadians[i] * degreePerRadian);
        }

        double p = 0.0;
        double area = 0.0;

        polygon.Compute(false, true, p, area);

        *perimeter = p;
        *signedArea = area;

        return std::isfinite(p) && std::isfinite(area) ? 1 : 0;
    }
    catch (...)
    {
        return 0;
    }
}
