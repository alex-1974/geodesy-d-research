# GEO-B synthetic f=0.01 high-precision provenance

Status: GEO-B boundary-ellipsoid reference corpus

## Purpose

This corpus supplies the high-precision non-WGS84 reference vectors required
for the supported flattening boundary:

```text
a = 7000000
f = 0.01
```

It complements the official GeographicLib WGS84 `GeodTest.dat` subset stored
in `geodtest_wgs84_subset.tsv`.

## Oracle

The vectors were generated on 2026-09-18 with:

```text
GeographicLib 2.7
source commit:
475cbde5b8528a6294dfeb054bc177d90be9f7bb

CMake:
GEOGRAPHICLIB_PRECISION=5

runtime:
GEOGRAPHICLIB_DIGITS=512

GeodSolve:
-E
-e 7000000 0.01
-f
-p 35
```

`GEOGRAPHICLIB_PRECISION=5` selects the variable-precision MPFR/mpreal
configuration. The executable was dynamically linked to the system MPFR and
GMP libraries.

Oracle executable SHA-256:

```text
fe45fa1675845f13da126c8e905c229902d60d8cf0b3091fc0f30d9c3268ea88
```

The exact geodesic mode (`-E`) uses GeographicLib's elliptic-integral
`GeodesicExact` formulation rather than the ordinary Karney geodesic series
used by geodesy-d.

## Corpus

The committed TSV contains 26 fixed cases:

```text
12 direct
14 inverse
```

Coverage includes:

- ordinary short, regional, and intercontinental geodesics;
- equatorial and meridional cases;
- near-polar cases;
- dateline crossing;
- very short geodesics;
- a long direct case within the ordinary direct-distance profile;
- near-equatorial and near-meridional inverse cases;
- two near-antipodal inverse cases;
- exact antipodal and opposite-pole ambiguous inverse cases;
- one negative direct distance.

The TSV stores the full high-precision `GeodSolve -f` result for each case:

```text
lat1 lon1 azi1 lat2 lon2 azi2 s12 a12 m12 M12 M21 S12
```

Dataset SHA-256:

```text
38f42a336f7ef55edfac38fe408d96e0775b30953441c2a713f469d31088167e
```

## Validation semantics

Direct rows validate the endpoint position and Earth-fixed endpoint tangent
direction against the MPFR Exact reference.

Inverse rows validate shortest distance and independent direct reconstruction
of the endpoint.

For mathematically non-unique inverse rows, the reference azimuth pair is not
normative. geodesy-d may select another deterministic valid shortest geodesic.

The committed data is sufficient to run the GEO-B gate later without MPFR or
GeographicLib installed. MPFR is required only to regenerate the corpus.
