#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Intersect.hpp>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace {

struct Case {
    std::string name;
    double a;
    double f;
    double latX;
    double lonX;
    double aziX;
    double latY;
    double lonY;
    double aziY;
    double p0x;
    double p0y;
    double radius;
};

double authalicRadius(double a, double f) {
    const double e2 = f * (2.0 - f);
    if (e2 == 0.0)
        return a;
    const double e = std::sqrt(e2);
    return std::sqrt(
        a * a * 0.5
        * (1.0 + (1.0 - e2) / e * std::atanh(e)));
}

double deltaFor(double a, double f) {
    const double d = GeographicLib::Math::pi() * authalicRadius(a, f);
    return d * std::pow(std::numeric_limits<double>::epsilon(), 1.0 / 5.0);
}

double rank(const GeographicLib::Intersect::Point& p,
            const GeographicLib::Intersect::Point& p0) {
    return std::abs(p.first - p0.first) + std::abs(p.second - p0.second);
}

void emitCase(const Case& tc) {
    const GeographicLib::Geodesic geod(tc.a, tc.f);
    const GeographicLib::Intersect inter(geod);
    const GeographicLib::Intersect::Point p0(tc.p0x, tc.p0y);

    std::vector<int> coincidence;
    const auto points = inter.All(
        tc.latX, tc.lonX, tc.aziX,
        tc.latY, tc.lonY, tc.aziY,
        tc.radius, coincidence, p0);

    const double delta = deltaFor(tc.a, tc.f);

    std::cout
        << "CASE\t" << tc.name
        << "\t" << std::setprecision(17) << tc.a
        << "\t" << tc.f
        << "\t" << tc.p0x
        << "\t" << tc.p0y
        << "\t" << tc.radius
        << "\t" << delta
        << "\t" << points.size()
        << "\n";

    for (std::size_t i = 0; i < points.size(); ++i) {
        std::cout
            << "POINT\t" << tc.name
            << "\t" << i
            << "\t" << std::setprecision(17) << points[i].first
            << "\t" << points[i].second
            << "\t" << coincidence[i]
            << "\t" << rank(points[i], p0)
            << "\n";
    }
}

Case boundaryCase(const std::string& name, bool inside) {
    constexpr double a = 6378137.0;
    constexpr double f = 1.0 / 298.257223563;

    const GeographicLib::Geodesic geod(a, f);
    const GeographicLib::Intersect inter(geod);

    int c = 0;
    const auto next = inter.Next(0.0, 0.0, 30.0, 120.0, &c);
    const double nextRank = std::abs(next.first) + std::abs(next.second);
    const double margin = 4.0 * deltaFor(a, f);

    return Case{
        name, a, f,
        0.0, 0.0, 30.0,
        0.0, 0.0, 120.0,
        0.0, 0.0,
        inside ? nextRank + margin : std::max(0.0, nextRank - margin)
    };
}

} // namespace

int main() {
    constexpr double wgsA = 6378137.0;
    constexpr double wgsF = 1.0 / 298.257223563;
    constexpr double sphereA = 6371000.0;

    std::vector<Case> cases = {
        {"wgs84_ordinary", wgsA, wgsF,
         0.0, -20.0, 45.0, 10.0, 20.0, -60.0,
         0.0, 0.0, 50000000.0},

        {"wgs84_symmetric_origin", wgsA, wgsF,
         0.0, 0.0, 45.0, 0.0, 0.0, 135.0,
         0.0, 0.0, 50000000.0},

        {"wgs84_near_parallel", wgsA, wgsF,
         10.0, 20.0, 45.0, 11.0, 21.0, 45.1,
         0.0, 0.0, 70000000.0},

        {"wgs84_polar", wgsA, wgsF,
         82.0, -40.0, 20.0, 80.0, 100.0, 145.0,
         0.0, 0.0, 50000000.0},

        {"wgs84_reverse", wgsA, wgsF,
         -25.0, 70.0, -35.0, 5.0, -110.0, 145.0,
         1000000.0, -500000.0, 50000000.0},

        {"wgs84_coincident_parallel", wgsA, wgsF,
         0.0, 0.0, 90.0, 0.0, 0.0, 90.0,
         0.0, 0.0, 50000000.0},

        {"wgs84_coincident_antiparallel", wgsA, wgsF,
         0.0, 0.0, 90.0, 0.0, 0.0, -90.0,
         0.0, 0.0, 50000000.0},

        {"sphere_ordinary", sphereA, 0.0,
         0.0, -20.0, 45.0, 10.0, 20.0, -60.0,
         0.0, 0.0, 50000000.0},

        {"sphere_near_parallel", sphereA, 0.0,
         15.0, -30.0, 60.0, 16.0, -29.0, 60.1,
         0.0, 0.0, 70000000.0},

        {"sphere_symmetric_origin", sphereA, 0.0,
         0.0, 0.0, 45.0, 0.0, 0.0, 135.0,
         0.0, 0.0, 50000000.0},

        {"sphere_coincident_parallel", sphereA, 0.0,
         0.0, 0.0, 90.0, 0.0, 0.0, 90.0,
         0.0, 0.0, 50000000.0}
    };

    cases.push_back(boundaryCase("wgs84_boundary_outside", false));
    cases.push_back(boundaryCase("wgs84_boundary_inside", true));

    std::cout << "FORMAT\tm5-106-r106.1\t1\n";

    try {
        for (const auto& tc : cases)
            emitCase(tc);
    } catch (const std::exception& e) {
        std::cerr << "oracle failure: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
