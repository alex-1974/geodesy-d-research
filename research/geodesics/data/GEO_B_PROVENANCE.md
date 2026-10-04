# GEO-B WGS84 reference-vector provenance

Status: partial GEO-B corpus

This directory contains a deterministic subset of the official GeographicLib
`GeodTest.dat` high-precision WGS84 geodesic test data.

## Upstream dataset

Source:

https://sourceforge.net/projects/geographiclib/files/testdata/GeodTest.dat.gz

Observed download on 2026-09-18:

```text
compressed SHA-256
3f5bb237cfb04fceb8eab60e75d6ef9dd6eb8bf436a7a9dc13ceffa682ad593c

uncompressed SHA-256
c1cabdddbcd7d5cfc6e6111db4608fa55be292b15ba2c5bcd6372a178848c692

line count
500000
```

The source dataset has ten whitespace-separated fields:

```text
lat1 lon1 azi1 lat2 lon2 azi2 s12 a12 m12 S12
```

Angles are in degrees. `s12` and `m12` use the WGS84 linear unit (metres);
`S12` is area in square metres.

The subset file adds two leading tab-separated provenance fields:

```text
source_line category
```

The remaining ten fields are copied textually from the selected original
source lines, preserving their published decimal precision.

## Selection policy

The official dataset is divided into documented 50,000/100,000-case blocks:

```text
1-100000       random
100001-150000  nearly-antipodal
150001-200000  short-distance
200001-250000  one-end-near-pole
250001-300000  opposite-poles
300001-350000  nearly-meridional
350001-400000  nearly-equatorial
400001-450000  between-vertices
450001-500000  ending-near-vertices
```

For each targeted 50,000-case block, the first, midpoint, and last source rows
are retained. Three deterministic examples are also retained for each of
ordinary-short, ordinary-regional, and intercontinental distance classes from
the random block.

This produces 33 fixed WGS84 reference rows.

The committed subset file itself is pinned as:

```text
SHA-256
bfeacb45d43538626fd4d0283f686dd26ee4f8f2760827cd8ed19da6ad00aab5
```

## Additional published smoke examples

The GEO-B validator also checks two examples published in the GeographicLib
documentation:

```text
Wellington -> Salamanca inverse
start = (-41.32, 174.81)
end   = (40.96, -5.50)
published distance = 19959679.267 m

Perth direct
start = (-32.06, 115.74)
azi1  = 225 deg
s12   = 20000000 m
published endpoint = (32.11195529, -63.95925278)
```

These examples are intentionally checked only to the precision published in
the documentation.

## Analytical sphere cases

The validator additionally checks exact great-circle cases derived
analytically from spherical geometry. These are not external reference rows;
they satisfy GEO-B's hand-derived spherical-case requirement.

## Precision rule

The validator parses reference decimal strings directly into D `real`.
Python is used only to build and launch the D validation probe. This prevents
the high-precision reference text from being silently rounded through Python
binary64 before comparison with a wide D `real`.

## Remaining GEO-B work

This WGS84 + analytical-sphere corpus does not by itself complete GEO-B.

A separate high-precision corpus is still required for a supported synthetic
ellipsoid with flattening near the contract boundary:

```text
f = 0.01
```

That corpus should be generated independently with a high-precision
GeographicLib/MPFR configuration or another suitably independent
high-precision method, with generator version/configuration and hashes pinned.

