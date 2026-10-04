#include <GeographicLib/GeodesicExact.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>


static_assert(
    sizeof(double) == sizeof(std::uint64_t),
    "GEO-E exact oracle requires 64-bit double");


double doubleFromBits(std::uint64_t bits)
{
    double value;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}


int main()
{
    if (!std::numeric_limits<double>::is_iec559)
    {
        std::cerr << "IEEE-754 binary64 required\n";
        return 2;
    }

    const double pi = std::acos(-1.0);
    const double toDegrees = 180.0 / pi;
    const double toRadians = pi / 180.0;

    std::cout << std::setprecision(17);

    std::uint64_t aBits;
    std::uint64_t fBits;
    std::uint64_t lat1Bits;
    std::uint64_t lon1Bits;
    std::uint64_t lat2Bits;
    std::uint64_t lon2Bits;
    std::uint64_t distanceBits;
    std::uint64_t azi1Bits;
    std::uint64_t azi2Bits;

    while (
        std::cin
        >> aBits
        >> fBits
        >> lat1Bits
        >> lon1Bits
        >> lat2Bits
        >> lon2Bits
        >> distanceBits
        >> azi1Bits
        >> azi2Bits)
    {
        const double a = doubleFromBits(aBits);
        const double f = doubleFromBits(fBits);
        const double lat1 = doubleFromBits(lat1Bits);
        const double lon1 = doubleFromBits(lon1Bits);
        const double lat2 = doubleFromBits(lat2Bits);
        const double lon2 = doubleFromBits(lon2Bits);
        const double candidateDistance =
            doubleFromBits(distanceBits);
        const double candidateAzi1 =
            doubleFromBits(azi1Bits);

        /*
         * The candidate final azimuth is transported to make the wire format
         * explicitly represent the full candidate result, even though the
         * oracle output below derives its own final azimuth from the exact
         * direct path.
         */
        (void) doubleFromBits(azi2Bits);

        GeographicLib::GeodesicExact geodesic(a, f);

        double exactDistance =
            std::numeric_limits<double>::quiet_NaN();
        double exactAzi1 =
            std::numeric_limits<double>::quiet_NaN();
        double exactAzi2 =
            std::numeric_limits<double>::quiet_NaN();

        geodesic.Inverse(
            lat1 * toDegrees,
            lon1 * toDegrees,
            lat2 * toDegrees,
            lon2 * toDegrees,
            exactDistance,
            exactAzi1,
            exactAzi2);

        double directLat2 =
            std::numeric_limits<double>::quiet_NaN();
        double directLon2 =
            std::numeric_limits<double>::quiet_NaN();
        double directAzi2 =
            std::numeric_limits<double>::quiet_NaN();

        geodesic.Direct(
            lat1 * toDegrees,
            lon1 * toDegrees,
            candidateAzi1 * toDegrees,
            candidateDistance,
            directLat2,
            directLon2,
            directAzi2);

        std::cout
            << exactDistance
            << ' '
            << directLat2 * toRadians
            << ' '
            << directLon2 * toRadians
            << ' '
            << directAzi2 * toRadians
            << '\n';
    }

    return 0;
}
