# M5 #68 — Arc mode and longitude-unroll differential validation

Production issue: alex-1974/geodesy-d#68
Production draft PR: alex-1974/geodesy-d#100

This research slice validates the additive prepared-line arc and
longitude-unroll surface against GeographicLib 2.7.

## Oracle

The C++ bridge uses GeographicLib 2.7 `GeodesicLine::GenPosition` with:

- arc mode on/off;
- `LONG_UNROLL` on/off;
- latitude, longitude, and forward azimuth output.

The D side exercises the public `GeodesicLine!double` methods from the
production feature branch.

## Cases

The corpus includes:

- ordinary WGS 84 lines;
- antimeridian crossings;
- exact sphere;
- negative arc/distance;
- multiple complete encirclements;
- accepted +180 degree start representation;
- flattening boundary f = 0.01.

The key unroll assertion compares longitude directly without modulo reduction.
Canonical longitude and azimuth comparisons use angular equivalence.

## Run

~~~bash
GEODESY_D_REPO=../geodesy-d \
GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7 \
DC=ldc2 \
CXX=g++ \
bash research/m5-68-arc-unroll-validation/run.sh
~~~
