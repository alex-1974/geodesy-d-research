#include <geodesic.h>

#include <cmath>
#include <iomanip>
#include <iostream>

namespace {

constexpr double pi =
    3.141592653589793238462643383279502884;

double radToDeg(double value) {
    return value * (180.0 / pi);
}

double degToRad(double value) {
    return value * (pi / 180.0);
}

} // namespace

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::cout << std::setprecision(17);

    char kind = '\0';

    while (std::cin >> kind) {
        double a = 0.0;
        double f = 0.0;

        if (kind == 'D') {
            double lat1 = 0.0;
            double lon1 = 0.0;
            double azi1 = 0.0;
            double s12 = 0.0;

            if (!(std::cin >> a >> f >> lat1 >> lon1 >> azi1 >> s12)) {
                return 2;
            }

            struct geod_geodesic geod;
            geod_init(&geod, a, f);

            double lat2 = 0.0;
            double lon2 = 0.0;
            double azi2 = 0.0;

            geod_direct(
                &geod,
                radToDeg(lat1),
                radToDeg(lon1),
                radToDeg(azi1),
                s12,
                &lat2,
                &lon2,
                &azi2);

            std::cout
                << "D "
                << degToRad(lat2) << ' '
                << degToRad(lon2) << ' '
                << degToRad(azi2) << '\n';
        } else if (kind == 'I') {
            double lat1 = 0.0;
            double lon1 = 0.0;
            double lat2 = 0.0;
            double lon2 = 0.0;

            if (!(std::cin >> a >> f >> lat1 >> lon1 >> lat2 >> lon2)) {
                return 2;
            }

            struct geod_geodesic geod;
            geod_init(&geod, a, f);

            double s12 = 0.0;
            double azi1 = 0.0;
            double azi2 = 0.0;

            geod_inverse(
                &geod,
                radToDeg(lat1),
                radToDeg(lon1),
                radToDeg(lat2),
                radToDeg(lon2),
                &s12,
                &azi1,
                &azi2);

            std::cout
                << "I "
                << s12 << ' '
                << degToRad(azi1) << ' '
                << degToRad(azi2) << '\n';
        } else {
            return 3;
        }
    }

    return 0;
}
