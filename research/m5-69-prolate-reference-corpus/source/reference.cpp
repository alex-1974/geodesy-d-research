#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Constants.hpp>

#include <cmath>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

namespace {

struct DirectCase {
    std::string name;
    double a;
    double f;
    double lat1;
    double lon1;
    double azi1;
    double s12;
};

struct InverseCase {
    std::string name;
    double a;
    double f;
    double lat1;
    double lon1;
    double lat2;
    double lon2;
};

void emitDirect(const DirectCase& tc) {
    const GeographicLib::Geodesic geod(tc.a, tc.f);

    double lat2, lon2, azi2;
    const double a12 =
        geod.Direct(
            tc.lat1, tc.lon1, tc.azi1, tc.s12,
            lat2, lon2, azi2);

    std::cout
        << "DIRECT\t" << tc.name
        << "\t" << std::setprecision(17) << tc.a
        << "\t" << tc.f
        << "\t" << tc.lat1
        << "\t" << tc.lon1
        << "\t" << tc.azi1
        << "\t" << tc.s12
        << "\t" << lat2
        << "\t" << lon2
        << "\t" << azi2
        << "\t" << a12
        << "\n";
}

void emitInverse(const InverseCase& tc) {
    const GeographicLib::Geodesic geod(tc.a, tc.f);

    double s12, azi1, azi2;
    const double a12 =
        geod.Inverse(
            tc.lat1, tc.lon1,
            tc.lat2, tc.lon2,
            s12, azi1, azi2);

    std::cout
        << "INVERSE\t" << tc.name
        << "\t" << std::setprecision(17) << tc.a
        << "\t" << tc.f
        << "\t" << tc.lat1
        << "\t" << tc.lon1
        << "\t" << tc.lat2
        << "\t" << tc.lon2
        << "\t" << s12
        << "\t" << azi1
        << "\t" << azi2
        << "\t" << a12
        << "\n";
}

} // namespace

int main() {
    constexpr double a = 6378137.0;
    constexpr double mild = -1.0 / 300.0;
    constexpr double moderate = -0.01;
    constexpr double strong = -0.05;

    const std::vector<DirectCase> direct = {
        {"mild_ordinary", a, mild, 12.5, -33.0, 47.0, 2500000.0},
        {"mild_polar", a, mild, 82.0, 15.0, 170.0, 1800000.0},
        {"mild_equatorial", a, mild, 0.0, 20.0, 90.0, 12000000.0},
        {"mild_long", a, mild, -35.0, 70.0, -40.0, 19000000.0},
        {"mild_reverse", a, mild, 25.0, -120.0, 35.0, -4000000.0},

        {"moderate_ordinary", a, moderate, 12.5, -33.0, 47.0, 2500000.0},
        {"moderate_polar", a, moderate, 82.0, 15.0, 170.0, 1800000.0},
        {"moderate_equatorial", a, moderate, 0.0, 20.0, 90.0, 12000000.0},
        {"moderate_long", a, moderate, -35.0, 70.0, -40.0, 19000000.0},

        {"strong_ordinary", a, strong, 12.5, -33.0, 47.0, 2500000.0},
        {"strong_polar", a, strong, 82.0, 15.0, 170.0, 1800000.0},
        {"strong_long", a, strong, -35.0, 70.0, -40.0, 19000000.0}
    };

    const std::vector<InverseCase> inverse = {
        {"mild_ordinary", a, mild, 10.0, 20.0, -25.0, 130.0},
        {"mild_equatorial", a, mild, 0.0, 0.0, 0.0, 170.0},
        {"mild_polar", a, mild, 88.0, -40.0, 80.0, 135.0},
        {"mild_near_antipodal", a, mild, 0.01, 0.0, -0.01, 179.999},
        {"mild_near_antipodal_asym", a, mild, 15.0, 10.0, -14.999, -169.999},

        {"moderate_ordinary", a, moderate, 10.0, 20.0, -25.0, 130.0},
        {"moderate_equatorial", a, moderate, 0.0, 0.0, 0.0, 170.0},
        {"moderate_polar", a, moderate, 88.0, -40.0, 80.0, 135.0},
        {"moderate_near_antipodal", a, moderate, 0.01, 0.0, -0.01, 179.999},
        {"moderate_near_antipodal_asym", a, moderate, 15.0, 10.0, -14.999, -169.999},

        {"strong_ordinary", a, strong, 10.0, 20.0, -25.0, 130.0},
        {"strong_equatorial", a, strong, 0.0, 0.0, 0.0, 170.0},
        {"strong_polar", a, strong, 88.0, -40.0, 80.0, 135.0},
        {"strong_near_antipodal", a, strong, 0.01, 0.0, -0.01, 179.999},
        {"strong_near_antipodal_asym", a, strong, 15.0, 10.0, -14.999, -169.999}
    };

    std::cout << "FORMAT\tm5-69-r69.2\t1\n";

    try {
        for (const auto& tc : direct)
            emitDirect(tc);
        for (const auto& tc : inverse)
            emitInverse(tc);
    } catch (const std::exception& e) {
        std::cerr << "oracle failure: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
