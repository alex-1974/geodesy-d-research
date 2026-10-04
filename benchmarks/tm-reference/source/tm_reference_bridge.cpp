#include <GeographicLib/TransverseMercator.hpp>
#include <GeographicLib/TransverseMercatorExact.hpp>
#include <proj.h>

#include <cmath>
#include <cstddef>
#include <stdexcept>

namespace {
constexpr double kA = 6378137.0;
constexpr double kF = 1.0 / 298.257223563;
constexpr double kK0 = 0.9996;
constexpr double kLon0Deg = 15.0;
constexpr double kFalseEasting = 500000.0;
constexpr double kFalseNorthing = 0.0;
constexpr double kPi = 3.141592653589793238462643383279502884;
constexpr double kDegToRad = kPi / 180.0;
constexpr double kRadToDeg = 180.0 / kPi;

struct TmReferences {
    GeographicLib::TransverseMercator series;
    GeographicLib::TransverseMercatorExact exact;
    PJ_CONTEXT* context;
    PJ* proj;

    TmReferences()
        : series(kA, kF, kK0, false, false),
          exact(kA, kF, kK0, false),
          context(nullptr),
          proj(nullptr)
    {
        context = proj_context_create();
        if (!context)
            throw std::runtime_error("proj_context_create failed");

        proj = proj_create(
            context,
            "+proj=tmerc +lat_0=0 +lon_0=15 +k_0=0.9996 "
            "+x_0=500000 +y_0=0 +ellps=WGS84 +units=m "
            "+algo=poder_engsager");

        if (!proj) {
            proj_context_destroy(context);
            context = nullptr;
            throw std::runtime_error("proj_create tmerc failed");
        }
    }

    ~TmReferences()
    {
        if (proj)
            proj_destroy(proj);
        if (context)
            proj_context_destroy(context);
    }

    TmReferences(const TmReferences&) = delete;
    TmReferences& operator=(const TmReferences&) = delete;
};

bool finitePair(double a, double b)
{
    return std::isfinite(a) && std::isfinite(b);
}

template <class Projection>
int geographiclibForward(
    const Projection& projection,
    std::size_t count,
    const double* latitudeDeg,
    const double* longitudeDeg,
    double* easting,
    double* northing) noexcept
{
    try {
        for (std::size_t i = 0; i < count; ++i) {
            double x = 0;
            double y = 0;
            projection.Forward(kLon0Deg, latitudeDeg[i], longitudeDeg[i], x, y);
            x += kFalseEasting;
            y += kFalseNorthing;
            if (!finitePair(x, y))
                return 0;
            easting[i] = x;
            northing[i] = y;
        }
        return 1;
    } catch (...) {
        return 0;
    }
}

template <class Projection>
int geographiclibReverse(
    const Projection& projection,
    std::size_t count,
    const double* easting,
    const double* northing,
    double* latitudeDeg,
    double* longitudeDeg) noexcept
{
    try {
        for (std::size_t i = 0; i < count; ++i) {
            double lat = 0;
            double lon = 0;
            projection.Reverse(
                kLon0Deg,
                easting[i] - kFalseEasting,
                northing[i] - kFalseNorthing,
                lat,
                lon);
            if (!finitePair(lat, lon))
                return 0;
            latitudeDeg[i] = lat;
            longitudeDeg[i] = lon;
        }
        return 1;
    } catch (...) {
        return 0;
    }
}
} // namespace

extern "C" {

void* tm_refs_create() noexcept
{
    try {
        return new TmReferences();
    } catch (...) {
        return nullptr;
    }
}

void tm_refs_destroy(void* handle) noexcept
{
    delete static_cast<TmReferences*>(handle);
}

int tm_refs_series_forward(void* handle, std::size_t count,
    const double* latitudeDeg, const double* longitudeDeg,
    double* easting, double* northing) noexcept
{
    if (!handle || !latitudeDeg || !longitudeDeg || !easting || !northing)
        return 0;
    const auto* refs = static_cast<TmReferences*>(handle);
    return geographiclibForward(refs->series, count, latitudeDeg, longitudeDeg, easting, northing);
}

int tm_refs_series_reverse(void* handle, std::size_t count,
    const double* easting, const double* northing,
    double* latitudeDeg, double* longitudeDeg) noexcept
{
    if (!handle || !easting || !northing || !latitudeDeg || !longitudeDeg)
        return 0;
    const auto* refs = static_cast<TmReferences*>(handle);
    return geographiclibReverse(refs->series, count, easting, northing, latitudeDeg, longitudeDeg);
}

int tm_refs_exact_forward(void* handle, std::size_t count,
    const double* latitudeDeg, const double* longitudeDeg,
    double* easting, double* northing) noexcept
{
    if (!handle || !latitudeDeg || !longitudeDeg || !easting || !northing)
        return 0;
    const auto* refs = static_cast<TmReferences*>(handle);
    return geographiclibForward(refs->exact, count, latitudeDeg, longitudeDeg, easting, northing);
}

int tm_refs_exact_reverse(void* handle, std::size_t count,
    const double* easting, const double* northing,
    double* latitudeDeg, double* longitudeDeg) noexcept
{
    if (!handle || !easting || !northing || !latitudeDeg || !longitudeDeg)
        return 0;
    const auto* refs = static_cast<TmReferences*>(handle);
    return geographiclibReverse(refs->exact, count, easting, northing, latitudeDeg, longitudeDeg);
}

int tm_refs_proj_forward(void* handle, std::size_t count,
    const double* latitudeDeg, const double* longitudeDeg,
    double* easting, double* northing) noexcept
{
    if (!handle || !latitudeDeg || !longitudeDeg || !easting || !northing)
        return 0;
    auto* refs = static_cast<TmReferences*>(handle);
    proj_errno_reset(refs->proj);
    for (std::size_t i = 0; i < count; ++i) {
        PJ_COORD input = proj_coord(
            longitudeDeg[i] * kDegToRad,
            latitudeDeg[i] * kDegToRad,
            0,
            0);
        const PJ_COORD output = proj_trans(refs->proj, PJ_FWD, input);
        if (!finitePair(output.xy.x, output.xy.y))
            return 0;
        easting[i] = output.xy.x;
        northing[i] = output.xy.y;
    }
    return proj_errno(refs->proj) == 0 ? 1 : 0;
}

int tm_refs_proj_reverse(void* handle, std::size_t count,
    const double* easting, const double* northing,
    double* latitudeDeg, double* longitudeDeg) noexcept
{
    if (!handle || !easting || !northing || !latitudeDeg || !longitudeDeg)
        return 0;
    auto* refs = static_cast<TmReferences*>(handle);
    proj_errno_reset(refs->proj);
    for (std::size_t i = 0; i < count; ++i) {
        PJ_COORD input = proj_coord(easting[i], northing[i], 0, 0);
        const PJ_COORD output = proj_trans(refs->proj, PJ_INV, input);
        const double lon = output.lp.lam * kRadToDeg;
        const double lat = output.lp.phi * kRadToDeg;
        if (!finitePair(lat, lon))
            return 0;
        latitudeDeg[i] = lat;
        longitudeDeg[i] = lon;
    }
    return proj_errno(refs->proj) == 0 ? 1 : 0;
}

} // extern "C"
