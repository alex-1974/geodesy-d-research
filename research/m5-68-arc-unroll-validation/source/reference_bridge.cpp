#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;
}

extern "C"
int geodesic_line_reference_general_position(
    double a,
    double f,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    int arcMode,
    int longUnroll,
    double input,
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
        double s12 = 0.0;
        double m12 = 0.0;
        double M12 = 0.0;
        double M21 = 0.0;
        double S12 = 0.0;

        unsigned outmask =
            GeographicLib::GeodesicLine::LATITUDE
            | GeographicLib::GeodesicLine::LONGITUDE
            | GeographicLib::GeodesicLine::AZIMUTH;

        if (longUnroll)
            outmask |= GeographicLib::GeodesicLine::LONG_UNROLL;

        const double a12 =
            line.GenPosition(
                arcMode != 0,
                arcMode != 0
                    ? input * degreePerRadian
                    : input,
                outmask,
                lat2,
                lon2,
                azi2,
                s12,
                m12,
                M12,
                M21,
                S12);

        *latitude2Radians =
            lat2 / degreePerRadian;

        *longitude2Radians =
            lon2 / degreePerRadian;

        *azimuth2Radians =
            azi2 / degreePerRadian;

        return std::isfinite(a12)
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
