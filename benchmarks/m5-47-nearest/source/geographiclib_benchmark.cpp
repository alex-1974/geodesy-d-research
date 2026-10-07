#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Gnomonic.hpp>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>

namespace {
struct Case {
    double latA, lonA, latB, lonB, latC, lonC;
};

double wrapPi(double x) {
    const double pi = std::acos(-1.0);
    const double tau = 2.0 * pi;
    x = std::fmod(x, tau);
    if (x >= pi) x -= tau;
    if (x < -pi) x += tau;
    return x;
}

bool solve(
    const GeographicLib::Geodesic& geod,
    const GeographicLib::Gnomonic& gnom,
    const Case& item,
    double& nearestDistance,
    double& alongTrack,
    double& signedCrossTrack)
{
    double sAB, aziAB1, aziAB2;
    geod.Inverse(
        item.latA, item.lonA,
        item.latB, item.lonB,
        sAB, aziAB1, aziAB2);

    if (!(sAB > 0.0))
        return false;

    double centerLat = item.latC;
    double centerLon = item.lonC;

    for (int k = 0; k < 2; ++k) {
        double ax, ay, bx, by, cx, cy;
        gnom.Forward(centerLat, centerLon, item.latA, item.lonA, ax, ay);
        gnom.Forward(centerLat, centerLon, item.latB, item.lonB, bx, by);

        if (k == 0) {
            cx = 0.0;
            cy = 0.0;
        } else {
            gnom.Forward(centerLat, centerLon, item.latC, item.lonC, cx, cy);
        }

        if (!(std::isfinite(ax) && std::isfinite(ay)
              && std::isfinite(bx) && std::isfinite(by)
              && std::isfinite(cx) && std::isfinite(cy)))
            return false;

        const double dx = bx - ax;
        const double dy = by - ay;
        const double denom = dx * dx + dy * dy;

        if (!(denom > 0.0))
            return false;

        const double dot = cx * dx + cy * dy;
        const double cross = ax * by - ay * bx;

        const double ox =
            (dot * dx + cross * dy) / denom;

        const double oy =
            (dot * dy - cross * dx) / denom;

        double azi, rk;
        gnom.Reverse(
            centerLat, centerLon,
            ox, oy,
            centerLat, centerLon,
            azi, rk);

        if (!(std::isfinite(centerLat)
              && std::isfinite(centerLon)))
            return false;
    }

    double sAO, aziAO1, aziAO2;
    geod.Inverse(
        item.latA, item.lonA,
        centerLat, centerLon,
        sAO, aziAO1, aziAO2);

    const double deltaA =
        wrapPi(
            (aziAO1 - aziAB1)
            * std::acos(-1.0) / 180.0);

    alongTrack =
        std::cos(deltaA) >= 0.0
            ? sAO
            : -sAO;

    const auto line =
        geod.Line(
            item.latA,
            item.lonA,
            aziAB1,
            GeographicLib::GeodesicLine::STANDARD
                | GeographicLib::GeodesicLine::DISTANCE_IN);

    double tmpLat, tmpLon, lineAzi;
    line.Position(
        alongTrack,
        tmpLat,
        tmpLon,
        lineAzi);

    double sOC, aziOC1, aziOC2;
    geod.Inverse(
        centerLat, centerLon,
        item.latC, item.lonC,
        sOC, aziOC1, aziOC2);

    if (sOC == 0.0) {
        signedCrossTrack = 0.0;
    } else {
        const double delta =
            wrapPi(
                (aziOC1 - lineAzi)
                * std::acos(-1.0) / 180.0);

        const double side = std::sin(delta);

        signedCrossTrack =
            side > 0.0
                ? sOC
                : side < 0.0
                    ? -sOC
                    : 0.0;
    }

    double nearestLat = centerLat;
    double nearestLon = centerLon;

    if (alongTrack <= 0.0) {
        nearestLat = item.latA;
        nearestLon = item.lonA;
    } else if (alongTrack >= sAB) {
        nearestLat = item.latB;
        nearestLon = item.lonB;
    }

    double na1, na2;
    geod.Inverse(
        nearestLat, nearestLon,
        item.latC, item.lonC,
        nearestDistance, na1, na2);

    return std::isfinite(nearestDistance)
        && std::isfinite(alongTrack)
        && std::isfinite(signedCrossTrack);
}
}

int main()
{
    const GeographicLib::Geodesic geod(
        6378137.0,
        1.0 / 298.257223563);

    const GeographicLib::Gnomonic gnom(geod);

    constexpr std::array<Case, 6> cases = {{
        {48.0, 10.0, 48.0, 20.0, 49.2, 15.0},
        {40.0, -75.0, 42.0, -60.0, 38.0, -66.0},
        {48.0, 10.0, 48.0, 12.0, 48.4, 8.0},
        {48.0, 10.0, 48.0, 12.0, 47.7, 14.0},
        {15.0, 175.0, 18.0, -175.0, 20.0, 179.0},
        {0.0, -20.0, 0.0, 20.0, -2.0, 3.0},
    }};

    constexpr std::size_t warmupRounds = 16;
    constexpr std::size_t timedRounds = 256;

    double checksum = 0.0;

    for (std::size_t r = 0; r < warmupRounds; ++r) {
        for (const auto& item : cases) {
            double d, a, c;
            if (!solve(geod, gnom, item, d, a, c))
                return 2;

            checksum += d + a * 1.0e-6 + c * 1.0e-6;
        }
    }

    const auto start =
        std::chrono::steady_clock::now();

    for (std::size_t r = 0; r < timedRounds; ++r) {
        for (const auto& item : cases) {
            double d, a, c;
            if (!solve(geod, gnom, item, d, a, c))
                return 3;

            checksum += d + a * 1.0e-6 + c * 1.0e-6;
        }
    }

    const auto end =
        std::chrono::steady_clock::now();

    constexpr std::size_t operations =
        timedRounds * cases.size();

    const double elapsedNs =
        std::chrono::duration<double, std::nano>(
            end - start).count();

    std::printf("implementation=GeographicLib\n");
    std::printf("operations=%zu\n", operations);
    std::printf("ns_per_op=%.6f\n", elapsedNs / operations);
    std::printf("checksum=%.12f\n", checksum);
    return 0;
}
