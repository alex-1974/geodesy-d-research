# M5 #47 nearest-point performance benchmark

This benchmark compares the admitted geodesy-d bounded segment nearest-point
operation against GeographicLib 2.7 implementing the same Karney gnomonic
interception semantics.

The timed corpus contains interior, endpoint-clamped, antimeridian, and
equatorial cases. Both implementations rebuild the finite segment geometry for
each operation; neither receives a pre-prepared segment object.

The benchmark is intentionally run on the XPS rather than used as a hosted-CI
performance gate.

Example:

~~~bash
GEODESY_D_REPO=../geodesy-d \
GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7/install \
DC=ldc2 \
M5_47_CPU=2 \
M5_47_RUNS=12 \
bash benchmarks/m5-47-nearest/run.sh
~~~

D is compiled with:

~~~text
-release -O3 -enable-inlining -mcpu=native
~~~

C++ is compiled with:

~~~text
-O3 -march=native -DNDEBUG
~~~

The reported ratio is descriptive evidence. Any substantial gap should be
profiled before accepting #47; it must not be hidden by relaxing a threshold.
