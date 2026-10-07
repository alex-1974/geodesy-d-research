# M5 #103 bounded segment-intersection performance

Compares the public geodesy-d bounded geodesic segment intersection operation
with GeographicLib 2.7 `Intersect::Segment`.

The workload includes crossing, shared endpoint, disjoint, same/reverse overlap,
antimeridian, oblique and polar cases. GeographicLib's `Intersect` object is
prepared once outside the timed loop; geodesy-d uses its public stateless
operation with a prepared `Geodesic` solver.

Hosted CI is a build/smoke check only. Final evidence is a CPU-pinned XPS run
with 12 separate processes.

Example:

~~~bash
GEODESY_D_REPO=../geodesy-d \
GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7/install \
DC=ldc2 \
M5_103_CPU=2 \
M5_103_RUNS=12 \
bash benchmarks/m5-103-intersection/run.sh
~~~


## Current qualified candidate

~~~text
b3905e4cbe39c9f7359dfd79553566acb4d454fa
~~~

This candidate adds a one-sided triangle-inequality rejection after the
midpoint solve. It can only prove `none` early; all other cases retain the
existing conservative corner fallback.
