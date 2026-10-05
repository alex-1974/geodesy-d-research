#include <GeographicLib/Geodesic.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_direct_quantities_reference(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians,
    double* reducedLength,
    double* scale12,
    double* scale21,
    double* signedArea)
{
    if (!latitude2Radians || !longitude2Radians || !azimuth2Radians
        || !reducedLength || !scale12 || !scale21 || !signedArea)
        return 0;

    try
    {
        GeographicLib::Geodesic geodesic(a, f);

        double lat2 = 0.0;
        double lon2 = 0.0;
        double azi2 = 0.0;
        double m12 = 0.0;
        double M12 = 0.0;
        double M21 = 0.0;
        double S12 = 0.0;

        geodesic.Direct(
            latitude1Radians * degreePerRadian,
            longitude1Radians * degreePerRadian,
            azimuth1Radians * degreePerRadian,
            distance,
            lat2,
            lon2,
            azi2,
            m12,
            M12,
            M21,
            S12);

        *latitude2Radians = lat2 / degreePerRadian;
        *longitude2Radians = lon2 / degreePerRadian;
        *azimuth2Radians = azi2 / degreePerRadian;
        *reducedLength = m12;
        *scale12 = M12;
        *scale21 = M21;
        *signedArea = S12;

        return std::isfinite(lat2)
            && std::isfinite(lon2)
            && std::isfinite(azi2)
            && std::isfinite(m12)
            && std::isfinite(M12)
            && std::isfinite(M21)
            && std::isfinite(S12)
            ? 1
            : 0;
    }
    catch (...)
    {
        return 0;
    }
}
