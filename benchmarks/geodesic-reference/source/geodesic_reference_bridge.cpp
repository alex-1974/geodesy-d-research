#include <GeographicLib/Geodesic.hpp>
#include <proj.h>

#include <cmath>
#include <cstdio>
#include <new>
#include <stdexcept>

namespace
{
constexpr double radPerDegree =
    0.017453292519943295769236907684886;

struct GeodesicReferences
{
    GeographicLib::Geodesic geographiclib;
    PJ_CONTEXT* context = nullptr;
    PJ* proj = nullptr;

    GeodesicReferences(double a, double f)
        : geographiclib(a, f)
    {
        context = proj_context_create();

        if (!context)
            throw std::runtime_error(
                "proj_context_create failed");

        char definition[256];

        if (f == 0.0)
        {
            std::snprintf(
                definition,
                sizeof(definition),
                "+proj=longlat +a=%.17g +b=%.17g",
                a,
                a);
        }
        else
        {
            std::snprintf(
                definition,
                sizeof(definition),
                "+proj=longlat +a=%.17g +rf=%.17g",
                a,
                1.0 / f);
        }

        proj = proj_create(
            context,
            definition);

        if (!proj)
        {
            proj_context_destroy(context);
            context = nullptr;

            throw std::runtime_error(
                "proj_create failed");
        }
    }

    ~GeodesicReferences()
    {
        if (proj)
            proj_destroy(proj);

        if (context)
            proj_context_destroy(context);
    }

    GeodesicReferences(
        const GeodesicReferences&) = delete;

    GeodesicReferences& operator=(
        const GeodesicReferences&) = delete;
};
}

extern "C"
{

void* geodesic_reference_create(
    double a,
    double f)
{
    try
    {
        return new GeodesicReferences(a, f);
    }
    catch (...)
    {
        return nullptr;
    }
}

void geodesic_reference_destroy(void* handle)
{
    delete static_cast<GeodesicReferences*>(handle);
}


int geodesic_reference_direct(
    void* handle,
    double latitude1Degrees,
    double longitude1Degrees,
    double azimuth1Degrees,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians)
{
    if (!handle
        || !latitude2Radians
        || !longitude2Radians
        || !azimuth2Radians)
        return 0;

    try
    {
        double latitude2Degrees;
        double longitude2Degrees;
        double azimuth2Degrees;

        static_cast<GeodesicReferences*>(
            handle)->geographiclib.Direct(
                latitude1Degrees,
                longitude1Degrees,
                azimuth1Degrees,
                distance,
                latitude2Degrees,
                longitude2Degrees,
                azimuth2Degrees);

        *latitude2Radians =
            latitude2Degrees * radPerDegree;

        *longitude2Radians =
            longitude2Degrees * radPerDegree;

        *azimuth2Radians =
            azimuth2Degrees * radPerDegree;

        return
            std::isfinite(*latitude2Radians)
            && std::isfinite(*longitude2Radians)
            && std::isfinite(*azimuth2Radians);
    }
    catch (...)
    {
        return 0;
    }
}


int geodesic_reference_inverse(
    void* handle,
    double latitude1Degrees,
    double longitude1Degrees,
    double latitude2Degrees,
    double longitude2Degrees,
    double* distance,
    double* azimuth1Radians,
    double* azimuth2Radians)
{
    if (!handle
        || !distance
        || !azimuth1Radians
        || !azimuth2Radians)
        return 0;

    try
    {
        double azimuth1Degrees;
        double azimuth2Degrees;

        static_cast<GeodesicReferences*>(
            handle)->geographiclib.Inverse(
                latitude1Degrees,
                longitude1Degrees,
                latitude2Degrees,
                longitude2Degrees,
                *distance,
                azimuth1Degrees,
                azimuth2Degrees);

        *azimuth1Radians =
            azimuth1Degrees * radPerDegree;

        *azimuth2Radians =
            azimuth2Degrees * radPerDegree;

        return
            std::isfinite(*distance)
            && std::isfinite(*azimuth1Radians)
            && std::isfinite(*azimuth2Radians);
    }
    catch (...)
    {
        return 0;
    }
}


/*
 * PROJ direct API.
 *
 * Inputs and angular outputs are radians.
 * The third output is the forward azimuth at point 2.
 */
int geodesic_proj_direct(
    void* handle,
    double latitude1Radians,
    double longitude1Radians,
    double azimuth1Radians,
    double distance,
    double* latitude2Radians,
    double* longitude2Radians,
    double* azimuth2Radians)
{
    if (!handle
        || !latitude2Radians
        || !longitude2Radians
        || !azimuth2Radians)
        return 0;

    auto* refs =
        static_cast<GeodesicReferences*>(handle);

    const PJ_COORD start =
        proj_coord(
            longitude1Radians,
            latitude1Radians,
            0.0,
            0.0);

    const PJ_COORD result =
        proj_geod_direct(
            refs->proj,
            start,
            azimuth1Radians,
            distance);

    *longitude2Radians = result.v[0];
    *latitude2Radians = result.v[1];
    *azimuth2Radians = result.v[2];

    return
        std::isfinite(*latitude2Radians)
        && std::isfinite(*longitude2Radians)
        && std::isfinite(*azimuth2Radians);
}


/*
 * PROJ 9.7.1 inverse API.
 *
 * Input coordinates are radians.
 *
 * proj_geod() calls geod_inverse() internally and returns its azimuth
 * outputs without converting them back to radians.  Therefore:
 *
 *     result[0] = distance in metres
 *     result[1] = forward azimuth at point 1 in degrees
 *     result[2] = forward azimuth at point 2 in degrees
 *
 * Keep these native outputs here.  Numerical preflight performs the unit
 * conversion; the timed kernel deliberately measures the native PROJ API.
 */
int geodesic_proj_inverse(
    void* handle,
    double latitude1Radians,
    double longitude1Radians,
    double latitude2Radians,
    double longitude2Radians,
    double* distance,
    double* azimuth1Degrees,
    double* azimuth2Degrees)
{
    if (!handle
        || !distance
        || !azimuth1Degrees
        || !azimuth2Degrees)
        return 0;

    auto* refs =
        static_cast<GeodesicReferences*>(handle);

    const PJ_COORD start =
        proj_coord(
            longitude1Radians,
            latitude1Radians,
            0.0,
            0.0);

    const PJ_COORD end =
        proj_coord(
            longitude2Radians,
            latitude2Radians,
            0.0,
            0.0);

    const PJ_COORD result =
        proj_geod(
            refs->proj,
            start,
            end);

    *distance = result.v[0];
    *azimuth1Degrees = result.v[1];
    *azimuth2Degrees = result.v[2];

    return
        std::isfinite(*distance)
        && std::isfinite(*azimuth1Degrees)
        && std::isfinite(*azimuth2Degrees);
}

}
