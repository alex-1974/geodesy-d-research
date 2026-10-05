module codegen_probe;

import geodesy;

extern(C) @nogc nothrow
bool probe_direct_lean(
    ref const Geodesic!double solver,
    GeographicCoordinate!double start,
    Angle!double azimuth,
    double distance,
    out GeodesicDirectResult!double result)
{
    return solver.tryDirect(start, azimuth, distance, result);
}

extern(C) @nogc nothrow
bool probe_direct_quantities(
    ref const Geodesic!double solver,
    GeographicCoordinate!double start,
    Angle!double azimuth,
    double distance,
    out GeodesicDirectResult!double result,
    out GeodesicQuantities!double quantities)
{
    return solver.tryDirect(start, azimuth, distance, result, quantities);
}

extern(C) @nogc nothrow
bool probe_inverse_lean(
    ref const Geodesic!double solver,
    GeographicCoordinate!double start,
    GeographicCoordinate!double end,
    out GeodesicInverseResult!double result)
{
    return solver.tryInverse(start, end, result);
}

extern(C) @nogc nothrow
bool probe_inverse_quantities(
    ref const Geodesic!double solver,
    GeographicCoordinate!double start,
    GeographicCoordinate!double end,
    out GeodesicInverseResult!double result,
    out GeodesicQuantities!double quantities)
{
    return solver.tryInverse(start, end, result, quantities);
}
