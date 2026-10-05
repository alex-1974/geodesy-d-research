#include <GeographicLib/Geodesic.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_area_reference_inverse(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double latitude2Radians,
    double longitude2Radians,
    double* signedArea)
{
    if (!signedArea)
        return 0;

    try
    {
        GeographicLib::Geodesic geodesic(a, f);

        double distance = 0.0;
        double azimuth1 = 0.0;
        double azimuth2 = 0.0;
        double reducedLength = 0.0;
        double scale12 = 0.0;
        double scale21 = 0.0;
        double area = 0.0;

        geodesic.GenInverse(
            latitude1Radians * degreePerRadian,
            longitude1Radians * degreePerRadian,
            latitude2Radians * degreePerRadian,
            longitude2Radians * degreePerRadian,
            GeographicLib::Geodesic::AREA,
            distance,
            azimuth1,
            azimuth2,
            reducedLength,
            scale12,
            scale21,
            area);

        *signedArea = area;

        return std::isfinite(area) ? 1 : 0;
    }
    catch (...)
    {
        return 0;
    }
}
