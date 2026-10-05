#include <GeographicLib/Geodesic.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_quantities_reference_inverse(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double latitude2Radians,
    double longitude2Radians,
    double* reducedLength,
    double* scale12,
    double* scale21,
    double* signedArea)
{
    if (!reducedLength || !scale12 || !scale21 || !signedArea)
        return 0;

    try
    {
        GeographicLib::Geodesic geodesic(a, f);

        double distance = 0.0;
        double azimuth1 = 0.0;
        double azimuth2 = 0.0;
        double m12 = 0.0;
        double M12 = 0.0;
        double M21 = 0.0;
        double S12 = 0.0;

        geodesic.GenInverse(
            latitude1Radians * degreePerRadian,
            longitude1Radians * degreePerRadian,
            latitude2Radians * degreePerRadian,
            longitude2Radians * degreePerRadian,
            GeographicLib::Geodesic::DISTANCE
                | GeographicLib::Geodesic::REDUCEDLENGTH
                | GeographicLib::Geodesic::GEODESICSCALE
                | GeographicLib::Geodesic::AREA,
            distance,
            azimuth1,
            azimuth2,
            m12,
            M12,
            M21,
            S12);

        *reducedLength = m12;
        *scale12 = M12;
        *scale21 = M21;
        *signedArea = S12;

        return std::isfinite(m12)
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
