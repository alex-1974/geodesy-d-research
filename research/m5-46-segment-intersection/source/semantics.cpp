#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>

namespace {
enum class Kind { none, point, overlap };

const char* name(Kind k) {
    switch (k) {
    case Kind::none: return "none";
    case Kind::point: return "point";
    case Kind::overlap: return "overlap";
    }
    return "invalid";
}

struct Result {
    Kind kind;
    double x0;
    double x1;
    double y0;
    double y1;
    int coincidence;
    int segmode;
};

Result classify(
    double sx,
    double sy,
    double x,
    double y,
    int c,
    int segmode)
{
    constexpr double tol = 1e-7;

    if (c == 0) {
        if (segmode != 0)
            return {Kind::none, 0, 0, 0, 0, c, segmode};
        return {Kind::point, x, x, y, y, c, segmode};
    }

    const double xa = x + c * (0.0 - y);
    const double xb = x + c * (sy - y);
    const double yMappedLo = std::min(xa, xb);
    const double yMappedHi = std::max(xa, xb);

    const double lo = std::max(0.0, yMappedLo);
    const double hi = std::min(sx, yMappedHi);

    if (hi < lo - tol)
        return {Kind::none, 0, 0, 0, 0, c, segmode};

    const double clo = std::max(0.0, std::min(sx, lo));
    const double chi = std::max(0.0, std::min(sx, hi));

    const double ylo = y + c * (clo - x);
    const double yhi = y + c * (chi - x);

    if (std::fabs(chi - clo) <= tol)
        return {Kind::point, clo, clo, ylo, ylo, c, segmode};

    return {Kind::overlap, clo, chi, ylo, yhi, c, segmode};
}

struct Case {
    const char* label;
    double ax1, ay1, ax2, ay2;
    double bx1, by1, bx2, by2;
    Kind expected;
};

bool run(const Case& tc) {
    const GeographicLib::Geodesic geod =
        GeographicLib::Geodesic::WGS84();
    const GeographicLib::Intersect intersect(geod);

    double sx, az1, az2, sy;
    geod.Inverse(tc.ax1, tc.ay1, tc.ax2, tc.ay2, sx, az1, az2);
    geod.Inverse(tc.bx1, tc.by1, tc.bx2, tc.by2, sy, az1, az2);

    int segmode = 99;
    int c = 0;
    const auto p =
        intersect.Segment(
            tc.ax1, tc.ay1, tc.ax2, tc.ay2,
            tc.bx1, tc.by1, tc.bx2, tc.by2,
            segmode, &c);

    const Result r =
        classify(sx, sy, p.first, p.second, c, segmode);

    const bool pass = r.kind == tc.expected;

    std::printf(
        "%s %-22s kind=%s c=%d segmode=%d x=[%.3f,%.3f] y=[%.3f,%.3f]\n",
        pass ? "PASS" : "FAIL",
        tc.label,
        name(r.kind),
        c,
        segmode,
        r.x0,
        r.x1,
        r.y0,
        r.y1);

    return pass;
}
}

int main() {
    const std::array<Case, 8> cases = {{
        {"crossing", 0,-10, 0,10, -10,0, 10,0, Kind::point},
        {"shared endpoint", 0,-10, 0,0, 0,0, 10,0, Kind::point},
        {"separate", 0,-10, 0,-5, 10,5, 10,10, Kind::none},
        {"overlap same", 0,-10, 0,10, 0,-5, 0,15, Kind::overlap},
        {"overlap reverse", 0,-10, 0,10, 0,15, 0,-5, Kind::overlap},
        {"contained", 0,-10, 0,10, 0,-5, 0,5, Kind::overlap},
        {"coincident disjoint", 0,-10, 0,-5, 0,5, 0,10, Kind::none},
        {"antimeridian crossing", 0,170, 0,-170, -10,180, 10,180, Kind::point},
    }};

    int failures = 0;
    for (const auto& tc : cases)
        failures += run(tc) ? 0 : 1;

    std::printf(
        failures ? "M5 #46 SEMANTICS PROBE FAIL: %d\n"
                 : "M5 #46 SEMANTICS PROBE PASS\n",
        failures);

    return failures ? 1 : 0;
}
