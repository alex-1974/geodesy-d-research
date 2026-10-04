# GEO-C — GeographicLib Exact differential validation provenance

Status: **PASS**

Acceptance run UTC: `2026-09-18T23:54:41Z`

Repository state at acceptance:

- repository: `https://github.com/alex-1974/geodesy-d`
- branch: `research/geodesics`
- pre-acceptance HEAD: `cd5c1345ad53984e6fff850802418f5bb0c3d0ee`

## Purpose

GEO-C validates the public direct/inverse geodesic API against a numerically
distinct GeographicLib `GeodesicExact` oracle over multiple scalar types,
ellipsoids, scales, ordinary cases, and targeted difficult cases.

The accepted validation consists of two complementary gates:

1. a large public-API differential corpus for `float`, `double`, and `real`;
2. a separate wide-`real` precision qualification using inputs which are not
   preserved by a binary64 round trip and a 512-bit MPFR GeographicLib build.

The production geodesic implementation has no runtime dependency on
GeographicLib.

## Toolchain

Acceptance was executed with:

- DMD `2.111.0`;
- LDC `1.41.0`, based on DMD `2.111.0`, LLVM `19.1.7`;
- Python `3.14.4`;
- GeographicLib `GeodSolve` `2.7`.

Primary bulk oracle:

- `/usr/bin/GeodSolve`
- GeographicLib `2.7`
- `GeodesicExact` selected with `-E`
- SHA-256:
  `0ea217df1a0eeaff408cbc5aa4dfbdbf2f9d55e5df52369889d87b269368cded`

Wide-`real` oracle:

- GeographicLib `2.7` MPFR build;
- `GeodesicExact` selected with `-E`;
- runtime precision: 512 bits;
- linked against MPFR and GMP;
- SHA-256:
  `fe45fa1675845f13da126c8e905c229902d60d8cf0b3091fc0f30d9c3268ea88`

## Accepted validators

- `research/geodesics/geoc_public_probe.d`
  - SHA-256:
    `5a90fe00c9e2a1bdd11b99cfe64f85f0e5853d9440d61636c91dd4dd9a2ac1ff`
- `research/geodesics/validate_geoc_exact.py`
  - SHA-256:
    `ffcfc03e5eeaaee5793d90804d5e3f028e808cb2030b04a3c62c3a234acbba59`
- `research/geodesics/validate_geoc_wide_real.py`
  - SHA-256:
    `f540b80b6687cd64a0c4058a1b6c5cc7d55b4bfaecd3908c4e8b8a390c7bfb78`

Bulk fixed seed:

- `0x47454F51`

Wide-`real` fixed seed:

- `0x47454F52`

## Bulk corpus

The accepted bulk corpus uses ten profiles:

1. sphere;
2. WGS84;
3. GRS80;
4. International 1924;
5. Airy 1830;
6. near-sphere synthetic ellipsoid;
7. synthetic `f = 0.005`;
8. synthetic `f = 0.01`;
9. unit-scale ellipsoid;
10. large-scale ellipsoid.

For every public scalar (`float`, `double`, `real`):

- generated cases per profile and operation: `4000`;
- fixed Direct cases per profile: `15`;
- fixed Inverse cases per profile: `16`;
- Direct comparisons per scalar: `40150`;
- Inverse comparisons per scalar: `40160`.

The complete corpus was accepted independently under both DMD and LDC.

The corpus includes ordinary random cases, short paths, polar cases,
dateline cases, near-antipodal cases, exact/cardinal fixed cases, and scale
variants.

## Direction-error conditioning

Inverse azimuth is not uniformly conditioned over the full problem domain.

The accepted validator therefore uses:

- ordinary sufficiently long cases:
  absolute Earth-fixed tangent-direction error;
- very short cases:
  `(s / a) * direction_error`;
- deliberately near-antipodal cases:
  `antipodal_defect * direction_error`.

Raw azimuth error remains diagnostic where the coordinate frame or inverse
problem is ill-conditioned.

Distance and Exact-Direct closure remain independently checked.

This conditioning policy was introduced only in the validator.  No production
geodesic-core change was required to close GEO-C.

## Bulk acceptance maxima

The following are the worst observed values across the accepted DMD/LDC runs.

### `float`

- Direct endpoint separation / `a`: `1.190403782142e-07`
- Direct tangent error: `2.3677176119508157e-07`
- Inverse distance error / `a`: `1.644926500857143e-07`
- Inverse closure / `a`: `1.644926500857143e-07`
- ordinary conditioned Inverse tangent: `1.1920929009292861e-07`
- short-path transverse metric: `1.17142650271436e-12`
- near-antipodal conditioned metric: `1.1396490471998431e-11`

### `double`

- Direct endpoint separation / `a`: `4.3399780254277194e-14`
- Direct tangent error: `4.3298623456710684e-14`
- Inverse distance error / `a`: `4.9980020122575297e-11`
- Inverse closure / `a`: `3.2141046829191662e-15`
- ordinary conditioned Inverse tangent: `4.6853055897983778e-14`
- short-path transverse metric: `4.650457197031982e-16`
- near-antipodal conditioned metric: `4.3700078801542664e-16`

### `real`

- Direct endpoint separation / `a`: `2.7126347361518257e-15`
- Direct tangent error: `2.9594524856965341e-15`
- Inverse distance error / `a`: `4.9980020122575297e-11`
- Inverse closure / `a`: `3.135993914626388e-15`
- ordinary conditioned Inverse tangent: `3.1317650480499891e-14`
- short-path transverse metric: `5.3375353202937623e-16`
- near-antipodal conditioned metric: `5.2913552484059929e-16`

The approximately `5e-11` normalized Inverse-distance maximum in the bulk
runner is associated with the text-interface/reference path at unit scale and
does not dominate endpoint closure or the separate high-precision `real`
qualification.

## Wide-`real` qualification

Eight representative profiles were tested with:

- `250` Direct cases/profile;
- `250` Inverse cases/profile;
- `2000` Direct comparisons/compiler;
- `2000` Inverse comparisons/compiler.

All generated input scalars were deliberately chosen so that their decimal
values are not preserved by a Python/binary64 round trip:

- DMD: `16000 / 16000`;
- LDC: `16000 / 16000`.

Candidate and oracle results are compared using Python `Decimal`; the numerical
results are not intentionally reduced through Python `float` before
comparison.

Acceptance limit:

- `2e-16`

Worst observed value across DMD and LDC:

- Direct endpoint separation / `a`: `1.74935867990959837e-18`
- Direct final azimuth: `3.94142505748065181e-18`
- Inverse distance error / `a`: `4.72716596467215087e-19`
- Inverse initial azimuth: `1.78039275144095870e-18`
- Inverse final azimuth: `1.88302078203776862e-18`

Result:

- DMD wide-`real`: **PASS**
- LDC wide-`real`: **PASS**

## Acceptance result

Bulk public differential validation:

- DMD: **PASS**
- LDC: **PASS**

Wide-`real` MPFR-512 qualification:

- DMD: **PASS**
- LDC: **PASS**

Therefore **GEO-C is PASS**.

This closes GEO-C only.  It does not by itself close the independent GEO-D,
GEO-E, GEO-F, or GEO-G gates and does not change ADR-0008 from Proposed to
Accepted.

## Acceptance log

Committed execution log:

`research/geodesics/data/geoc_acceptance_20260918T235441Z.log`

SHA-256:

`6effc59f7c9af2d40073a49bc2d73bb583bb391205f1ec228abc0020d2f130de`
