# geodesy-d benchmarks

This directory contains reproducible microbenchmarks for the public numerical
kernels of `geodesy-d`.

The primary benchmark configuration is an optimised LDC build:

~~~sh
cd benchmarks
dub run --build=release --compiler=ldc2 --force
~~~

DMD is also expected to compile and run the benchmark suite:

~~~sh
cd benchmarks
dub run --build=release --compiler=dmd --force
~~~

Input generation is intentionally performed outside timed sections.

The benchmark executable measures bulk throughput through the non-throwing
public hot-path API for the v0.1 numerical kernels:

- EPSG 9602 geographic/geocentric conversion;
- EPSG 1031 geocentric translation;
- EPSG 1033 Position Vector Helmert transformation;
- EPSG 1032 Coordinate Frame Helmert transformation.

It also reports simple harness floors for coordinate access and result
fingerprinting. These are context measurements and are not automatically
subtracted from the kernel timings.

See `../docs/PERFORMANCE.md` for the benchmark and performance policy.
