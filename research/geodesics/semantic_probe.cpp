#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicExact.hpp>

#ifdef HAVE_PROJ_GEODESIC
#include <geodesic.h>
#endif

#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>

namespace {

struct EllipsoidCase
{
    const char* name;
    double a;
    double f;
};

struct InverseCase
{
    const char* name;
    double lat1;
    double lon1;
    double lat2;
    double lon2;
};

struct DirectCase
{
    const char* name;
    double lat1;
    double lon1;
    double azi1;
    double distance;
};

void printValue(const char* name, double value)
{
    std::cout
        << "|" << name << "=" << std::setprecision(17) << value
        << "|" << name << "_signbit=" << (std::signbit(value) ? 1 : 0);
}

template <class GeodesicType>
void runInverse(
    const char* implementation,
    const EllipsoidCase& e,
    const InverseCase& c,
    const GeodesicType& geod)
{
    double distance = std::numeric_limits<double>::quiet_NaN();
    double azi1 = std::numeric_limits<double>::quiet_NaN();
    double azi2 = std::numeric_limits<double>::quiet_NaN();

    geod.Inverse(
        c.lat1,
        c.lon1,
        c.lat2,
        c.lon2,
        distance,
        azi1,
        azi2);

    std::cout
        << "INV"
        << "|ellipsoid=" << e.name
        << "|case=" << c.name
        << "|impl=" << implementation;

    printValue("s12", distance);
    printValue("azi1", azi1);
    printValue("azi2", azi2);

    std::cout << "\n";
}

template <class GeodesicType>
void runDirect(
    const char* implementation,
    const EllipsoidCase& e,
    const DirectCase& c,
    const GeodesicType& geod)
{
    double lat2 = std::numeric_limits<double>::quiet_NaN();
    double lon2 = std::numeric_limits<double>::quiet_NaN();
    double azi2 = std::numeric_limits<double>::quiet_NaN();

    geod.Direct(
        c.lat1,
        c.lon1,
        c.azi1,
        c.distance,
        lat2,
        lon2,
        azi2);

    std::cout
        << "DIR"
        << "|ellipsoid=" << e.name
        << "|case=" << c.name
        << "|impl=" << implementation;

    printValue("lat2", lat2);
    printValue("lon2", lon2);
    printValue("azi2", azi2);

    std::cout << "\n";
}

#ifdef HAVE_PROJ_GEODESIC

void runProjInverse(
    const EllipsoidCase& e,
    const InverseCase& c)
{
    geod_geodesic geod;
    geod_init(&geod, e.a, e.f);

    double distance = std::numeric_limits<double>::quiet_NaN();
    double azi1 = std::numeric_limits<double>::quiet_NaN();
    double azi2 = std::numeric_limits<double>::quiet_NaN();

    geod_inverse(
        &geod,
        c.lat1,
        c.lon1,
        c.lat2,
        c.lon2,
        &distance,
        &azi1,
        &azi2);

    std::cout
        << "INV"
        << "|ellipsoid=" << e.name
        << "|case=" << c.name
        << "|impl=PROJ";

    printValue("s12", distance);
    printValue("azi1", azi1);
    printValue("azi2", azi2);

    std::cout << "\n";
}

void runProjDirect(
    const EllipsoidCase& e,
    const DirectCase& c)
{
    geod_geodesic geod;
    geod_init(&geod, e.a, e.f);

    double lat2 = std::numeric_limits<double>::quiet_NaN();
    double lon2 = std::numeric_limits<double>::quiet_NaN();
    double azi2 = std::numeric_limits<double>::quiet_NaN();

    geod_direct(
        &geod,
        c.lat1,
        c.lon1,
        c.azi1,
        c.distance,
        &lat2,
        &lon2,
        &azi2);

    std::cout
        << "DIR"
        << "|ellipsoid=" << e.name
        << "|case=" << c.name
        << "|impl=PROJ";

    printValue("lat2", lat2);
    printValue("lon2", lon2);
    printValue("azi2", azi2);

    std::cout << "\n";
}

#endif

} // namespace

int main()
{
    const double pi = std::acos(-1.0);

    const EllipsoidCase ellipsoids[] = {
        {
            "WGS84",
            6378137.0,
            1.0 / 298.257223563
        },
        {
            "SPHERE",
            6371000.0,
            0.0
        }
    };

    const InverseCase inverseCases[] = {
        {
            "coincident_positive_zero",
            +0.0, +0.0,
            +0.0, +0.0
        },
        {
            "coincident_signed_zero",
            -0.0, -0.0,
            +0.0, +0.0
        },
        {
            "coincident_generic",
            10.0, 20.0,
            10.0, 20.0
        },
        {
            "coincident_mixed_signed_zero",
            +0.0, -0.0,
            -0.0, +0.0
        },
        {
            "north_pole_same_surface_point",
            90.0, 0.0,
            90.0, 123.0
        },
        {
            "south_pole_same_surface_point",
            -90.0, 0.0,
            -90.0, -123.0
        },
        {
            "equator_one_degree",
            0.0, 0.0,
            0.0, 1.0
        },
        {
            "same_meridian",
            10.0, 20.0,
            20.0, 20.0
        },
        {
            "same_point_antimeridian_alias",
            10.0, 180.0,
            10.0, -180.0
        },
        {
            "same_point_antimeridian_reverse_alias",
            10.0, -180.0,
            10.0, 180.0
        },
        {
            "near_antipodal",
            0.5, 0.0,
            -0.5, 179.999999
        },
        {
            "exact_antipodal_equator",
            0.0, 0.0,
            0.0, 180.0
        },
        {
            "exact_antipodal_equator_negative_180",
            0.0, 0.0,
            0.0, -180.0
        },
        {
            "exact_antipodal_equator_signed_zero",
            -0.0, +0.0,
            +0.0, -180.0
        },
        {
            "antipodal_generic",
            10.0, 20.0,
            -10.0, -160.0
        },
        {
            "opposite_poles",
            90.0, 0.0,
            -90.0, 0.0
        },
        {
            "opposite_poles_antimeridian_alias",
            90.0, 180.0,
            -90.0, -180.0
        },
        {
            "opposite_poles_arbitrary_longitudes",
            90.0, 37.0,
            -90.0, -123.0
        },
        {
            "north_pole_to_equator",
            90.0, 40.0,
            0.0, 40.0
        },
        {
            "south_pole_to_equator",
            -90.0, 40.0,
            0.0, 40.0
        }
    };

    const DirectCase directCases[] = {
        {
            "zero_distance_positive_zero",
            0.0, 0.0,
            0.0,
            +0.0
        },
        {
            "zero_distance_negative_zero",
            0.0, 0.0,
            0.0,
            -0.0
        },
        {
            "zero_distance_azimuth_positive_180",
            0.0, 0.0,
            180.0,
            0.0
        },
        {
            "zero_distance_azimuth_negative_180",
            0.0, 0.0,
            -180.0,
            0.0
        },
        {
            "zero_distance_azimuth_positive_360",
            0.0, 0.0,
            360.0,
            0.0
        },
        {
            "zero_distance_azimuth_negative_360",
            0.0, 0.0,
            -360.0,
            0.0
        },
        {
            "equator_east",
            0.0, 0.0,
            90.0,
            1000000.0
        },
        {
            "equator_east_negative_distance",
            0.0, 0.0,
            90.0,
            -1000000.0
        },
        {
            "azimuth_positive_180",
            10.0, 20.0,
            180.0,
            1000000.0
        },
        {
            "azimuth_negative_180",
            10.0, 20.0,
            -180.0,
            1000000.0
        },
        {
            "azimuth_positive_540",
            10.0, 20.0,
            540.0,
            1000000.0
        },
        {
            "azimuth_negative_540",
            10.0, 20.0,
            -540.0,
            1000000.0
        },
        {
            "azimuth_positive_zero",
            10.0, 20.0,
            +0.0,
            1000000.0
        },
        {
            "azimuth_negative_zero",
            10.0, 20.0,
            -0.0,
            1000000.0
        },
        {
            "cross_antimeridian_east",
            0.0, 179.9,
            90.0,
            50000.0
        },
        {
            "antimeridian_start_positive_180",
            0.0, 180.0,
            90.0,
            50000.0
        },
        {
            "antimeridian_start_negative_180",
            0.0, -180.0,
            90.0,
            50000.0
        },
        {
            "north_pole_start",
            90.0, 0.0,
            90.0,
            1000000.0
        },
        {
            "south_pole_start",
            -90.0, 0.0,
            90.0,
            1000000.0
        },
        {
            "half_scale_circumference",
            23.0, -17.0,
            37.0,
            pi * 6378137.0
        }
    };

    std::cout
        << "# GEO-A semantic probe\n"
        << "# numeric format: decimal double + IEEE signbit\n";

    #ifdef HAVE_PROJ_GEODESIC
    std::cout << "# PROJ geodesic API: enabled\n";
    #else
    std::cout << "# PROJ geodesic API: unavailable\n";
    #endif

    for (const auto& e : ellipsoids)
    {
        const GeographicLib::Geodesic series(e.a, e.f);
        const GeographicLib::GeodesicExact exact(e.a, e.f);

        for (const auto& c : inverseCases)
        {
            runInverse("GeographicLib", e, c, series);
            runInverse("GeographicLibExact", e, c, exact);

            #ifdef HAVE_PROJ_GEODESIC
            runProjInverse(e, c);
            #endif
        }

        for (const auto& c : directCases)
        {
            DirectCase scaled = c;

            if (std::string(c.name) == "half_scale_circumference")
                scaled.distance = pi * e.a;

            runDirect("GeographicLib", e, scaled, series);
            runDirect("GeographicLibExact", e, scaled, exact);

            #ifdef HAVE_PROJ_GEODESIC
            runProjDirect(e, scaled);
            #endif
        }
    }

    return 0;
}
