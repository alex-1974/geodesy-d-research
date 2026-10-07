# M5 #68 — advanced GeodesicLine qualification

Independent qualification for production issue alex-1974/geodesy-d#68 and
production PR #100.

The oracle is pinned to GeographicLib 2.7 and directly exercises the prepared
line general-position implementation for:

- distance-mode positions;
- auxiliary-sphere arc-mode positions;
- canonical longitude;
- longitude unrolling across multiple complete revolutions;
- reduced length `m12`;
- geodesic scales `M12` and `M21`;
- signed area `S12`.

Cases cover ordinary WGS 84 lines, antimeridian/multi-revolution behavior,
sphere, negative direction, and the current supported flattening boundary
`f = 0.01`.

The validation intentionally compares the additive #68 API while leaving the
existing lean distance-only `tryPosition(distance, result)` path separate.

Run with:

~~~bash
GEODESY_D_REPO=../geodesy-d \
GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7/install \
DC=ldc2 \
bash research/m5-68-qualification/run.sh
~~~
