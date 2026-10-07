#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Gnomonic.hpp>

#include <cmath>

namespace {
constexpr double degreePerRadian =
    57.295779513082320876798154814105;

double wrapPi(double x) {
    const double pi = std::acos(-1.0);
    const double tau = 2.0 * pi;
    x = std::fmod(x, tau);
    if (x >= pi) x -= tau;
    if (x < -pi) x += tau;
    return x;
}
}

extern "C"
int m5_47_reference(
    double a,
    double f,
    double latA,
    double lonA,
    double latB,
    double lonB,
    double latC,
    double lonC,
    double* footLat,
    double* footLon,
    double* alongTrack,
    double* signedCrossTrack,
    double* segmentNearestLat,
    double* segmentNearestLon,
    double* segmentNearestDistance,
    int* segmentClass)
{
    if (!footLat || !footLon || !alongTrack || !signedCrossTrack
        || !segmentNearestLat || !segmentNearestLon
        || !segmentNearestDistance || !segmentClass)
        return 0;

    try {
        GeographicLib::Geodesic geod(a, f);
        GeographicLib::Gnomonic gnom(geod);

        const double latAd = latA * degreePerRadian;
        const double lonAd = lonA * degreePerRadian;
        const double latBd = latB * degreePerRadian;
        const double lonBd = lonB * degreePerRadian;
        const double latCd = latC * degreePerRadian;
        const double lonCd = lonC * degreePerRadian;

        double centerLat = latCd;
        double centerLon = lonCd;

        for (int k = 0; k < 2; ++k) {
            double ax, ay, bx, by, cx, cy;
            gnom.Forward(centerLat, centerLon, latAd, lonAd, ax, ay);
            gnom.Forward(centerLat, centerLon, latBd, lonBd, bx, by);

            if (k == 0) {
                cx = 0.0;
                cy = 0.0;
            } else {
                gnom.Forward(centerLat, centerLon, latCd, lonCd, cx, cy);
            }

            if (!(std::isfinite(ax) && std::isfinite(ay)
                  && std::isfinite(bx) && std::isfinite(by)
                  && std::isfinite(cx) && std::isfinite(cy)))
                return 0;

            const double dx = bx - ax;
            const double dy = by - ay;
            const double denom = dx * dx + dy * dy;
            if (!(denom > 0.0) || !std::isfinite(denom))
                return 0;

            const double dot = cx * dx + cy * dy;
            const double cross = ax * by - ay * bx;
            const double ox = (dot * dx + cross * dy) / denom;
            const double oy = (dot * dy - cross * dx) / denom;

            double azi, rk;
            gnom.Reverse(centerLat, centerLon, ox, oy,
                         centerLat, centerLon, azi, rk);
            if (!(std::isfinite(centerLat) && std::isfinite(centerLon)))
                return 0;
        }

        *footLat = centerLat / degreePerRadian;
        *footLon = centerLon / degreePerRadian;

        double sAB, aziAB1, aziAB2;
        geod.Inverse(latAd, lonAd, latBd, lonBd, sAB, aziAB1, aziAB2);

        double sAO, aziAO1, aziAO2;
        geod.Inverse(latAd, lonAd, centerLat, centerLon,
                     sAO, aziAO1, aziAO2);

        const double deltaA =
            wrapPi((aziAO1 - aziAB1) / degreePerRadian);

        const double along =
            std::cos(deltaA) >= 0.0 ? sAO : -sAO;
        *alongTrack = along;

        const auto line =
            geod.Line(latAd, lonAd, aziAB1,
                      GeographicLib::GeodesicLine::STANDARD
                      | GeographicLib::GeodesicLine::DISTANCE_IN);

        double tmpLat, tmpLon, lineAzi;
        line.Position(along, tmpLat, tmpLon, lineAzi);

        double sOC, aziOC1, aziOC2;
        geod.Inverse(centerLat, centerLon, latCd, lonCd,
                     sOC, aziOC1, aziOC2);

        if (sOC == 0.0) {
            *signedCrossTrack = 0.0;
        } else {
            const double delta =
                wrapPi((aziOC1 - lineAzi) / degreePerRadian);
            const double side = std::sin(delta);
            *signedCrossTrack =
                side > 0.0 ? sOC : side < 0.0 ? -sOC : 0.0;
        }

        double nearestLat = centerLat;
        double nearestLon = centerLon;
        int klass = 0;

        if (along < 0.0) {
            nearestLat = latAd;
            nearestLon = lonAd;
            klass = 1;
        } else if (along > sAB) {
            nearestLat = latBd;
            nearestLon = lonBd;
            klass = 2;
        }

        double nearestDistance, na1, na2;
        geod.Inverse(nearestLat, nearestLon, latCd, lonCd,
                     nearestDistance, na1, na2);

        *segmentNearestLat = nearestLat / degreePerRadian;
        *segmentNearestLon = nearestLon / degreePerRadian;
        *segmentNearestDistance = nearestDistance;
        *segmentClass = klass;

        return std::isfinite(*alongTrack)
            && std::isfinite(*signedCrossTrack)
            && std::isfinite(*segmentNearestDistance);
    } catch (...) {
        return 0;
    }
}
