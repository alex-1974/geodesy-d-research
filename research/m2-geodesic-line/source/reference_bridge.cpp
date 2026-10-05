#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_line_reference_position(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians)
{
    if (!latitude2Radians || !longitude2Radians || !azimuth2Radians)
        return 0;

    try
    {
        GeographicLib::Geodesic geodesic(a, f);

        const auto line =
            geodesic.Line(
                latitude1Radians * degreePerRadian,
                longitude1Radians * degreePerRadian,
                azimuth1Radians * degreePerRadian,
                GeographicLib::Geodesic::STANDARD
                    | GeographicLib::Geodesic::DISTANCE_IN);

        double lat2 = 0.0;
        double lon2 = 0.0;
        double azi2 = 0.0;

        const double arc =
            line.Position(
                distance,
                lat2,
                lon2,
                azi2);

        *latitude2Radians =
            lat2 / degreePerRadian;

        *longitude2Radians =
            lon2 / degreePerRadian;

        *azimuth2Radians =
            azi2 / degreePerRadian;

        return std::isfinite(arc)
            && std::isfinite(lat2)
            && std::isfinite(lon2)
            && std::isfinite(azi2)
            ? 1
            : 0;
    }
    catch (...)
    {
        return 0;
    }
}
