# GEO-D PROJ interoperability provenance

## Status

**PASS**

GEO-D validates interoperability between the public `geodesy-d` geodesic API
and the PROJ geodesic C API.

PROJ is used strictly as an external interoperability oracle. It is not an
independent mathematical oracle for the Karney geodesic algorithm family and
is not a build, link, runtime, or DUB dependency of `geodesy-d`.
Independent numerical correctness is established separately by GEO-B and
GEO-C.

## Accepted execution

```text
timestamp: 2026-09-19T08:40:49Z
branch:    research/geodesics
HEAD:      e9ca14b13bc7a512bd901515660a03883bcc6d52
```

Acceptance log:

```text
research/geodesics/data/geod_acceptance_20260919T084049Z.log
SHA-256:
f45eedd052cc210e54cb696c852dee104b51167e952ab5165bd978045d279d0a
```

Final result:

```text
GEO-D FINAL ACCEPTANCE EXECUTION: PASS
```

## Toolchain

```text
DMD          2.111.0
LDC          1.41.0
D frontend   2.111.0
LLVM         19.1.7
Python       3.14.4
C++          GCC 15.2.0
PROJ         9.7.1
platform     x86_64 Linux
```

Public `real` representation under both DMD and LDC:

```text
real.mant_dig = 64
real.sizeof   = 16
```

## PROJ provenance

```text
header:
/usr/include/geodesic.h
SHA-256:
a964a747bc4f388fb3a93cc9bc379aebe4cdd78b3ee909c071be711b82db4b10

library:
/usr/lib/x86_64-linux-gnu/libproj.so.25.9.7.1
SHA-256:
857bf68c4494c0cec4dae9c9fa87906350e7d2da7e082547b3ca855006797163
```

The selected PROJ geodesic interface is the double-based `geod_*` C API.

## Harness

Accepted hashes:

```text
research/geodesics/geod_proj_public_probe.d
3da8dedbaf004c8ad329c1770b87c3b1366d1df53b9baa30b192975ff3bb6a63

research/geodesics/proj_geodesic_probe.cpp
fd8dc3f43c6d2cdfe97d2d256ece0f23347f7526d0dbe7efb78a413cbc599e23

research/geodesics/validate_geod_proj.py
25a20caf6283c2e3b6972570444f4705f41a41566d2e97321d0bccd2ac3e5d6c
```

`geod_proj_public_probe.d` exercises only the public `geodesy-d` geodesic
API. Candidate inputs are transported as exact IEEE-754 binary64 bit patterns;
angular inputs are radians.

This avoids two rejected harness approaches discovered during GEO-D work:

1. reusing `geoc_public_probe.d`, whose input protocol is degrees rather than
   radians;
2. carrying the `real` interoperability corpus through decimal text, which can
   reconstruct wider x87 values instead of the intended binary64 subset.

The accepted public-`real` transport is:

```text
binary64 bits -> exact double -> exact widening to D real
```

The full corpus audit covered:

```text
128063 unique binary64 inputs per compiler
mismatches: 0
```

## Scalar representation rule

PROJ's geodesic C API is binary64-only.

GEO-D therefore validates:

```text
float
    represented public float
    -> lossless promotion to binary64 for PROJ

double
    represented public double
    -> direct PROJ comparison

real
    exact binary64-subset input
    -> exact widening to public real
    -> public Geodesic!real computation
    -> comparison at the binary64 interoperability boundary
```

Wider-than-binary64 `real` accuracy is outside GEO-D and is qualified by the
MPFR-based GEO-C evidence.

### `f = 0.01` boundary for public `real`

Exact widening of `binary64(0.01)` to x87 `real` produces a value slightly
above the more precise real-valued contract boundary `0.01`.

The GEO-D `real` maximum-flattening profile therefore uses:

```text
nextDown(binary64(0.01))
= 0.0099999999999999985
```

This is the largest binary64 flattening strictly inside the public-real
`f <= 0.01` domain. The identical represented value is supplied to PROJ.
This is a validation-input rule only; no production tolerance or support
contract changed.

## Deterministic corpus

Seed:

```text
0x47454F44
```

Profiles:

```text
sphere
WGS84
GRS80
International 1924
Airy 1830
mid-f (f = 0.005)
max-f
unit-scale
```

For each profile, operation, and public scalar:

```text
2000 generated cases
6 fixed cases
2006 total cases
```

Per compiler:

```text
16048 Direct cases per scalar
16048 Inverse cases per scalar

48144 Direct public-API cases across float/double/real
48144 Inverse public-API cases across float/double/real
96288 public-API cases total
```

Across DMD and LDC:

```text
192576 public-API differential cases
```

The deterministic populations cover ordinary, short, polar, dateline,
long-direct, and difficult near-antipodal cases, plus fixed semantic cases.

## Semantic comparison rules

Normative comparisons use:

- Direct endpoint position;
- Direct endpoint Earth-fixed tangent direction;
- Inverse normalized distance;
- Inverse initial and final Earth-fixed tangent directions for unique,
  well-conditioned solutions.

Conditioned metrics are used for very short and difficult near-antipodal
inverse cases. Coincident and geometrically non-unique shortest inverse cases
retain normative distance comparison but are excluded from azimuth equality
gates.

This semantic difference is recorded explicitly rather than hidden by harness
canonicalization.

## Accepted maxima

Worst values below are maxima across the accepted DMD/LDC full runs.

### `float`

```text
Direct endpoint                         1.1868755019338276e-07 rad
Direct tangent                          2.3509569043847252e-07 rad
Inverse normalized distance             1.5680921814951001e-07
Inverse ordinary initial tangent        1.1918681423016197e-07 rad
Inverse ordinary final tangent          1.1915453734436218e-07 rad
Inverse short conditioned initial       1.1297883976796231e-12
Inverse short conditioned final         1.1091752449609755e-12
Inverse antipodal conditioned initial   4.8476324789125197e-13
Inverse antipodal conditioned final     4.8773898522760715e-13
```

### `double`

```text
Direct endpoint                         2.5091245457854084e-14 rad
Direct tangent                          2.2578207193365125e-14 rad
Inverse normalized distance             1.1694522989991882e-15
Inverse ordinary initial tangent        9.6382483219954845e-14 rad
Inverse ordinary final tangent          9.6806215584434934e-14 rad
Inverse short conditioned initial       4.0614428773859857e-16
Inverse short conditioned final         4.0614428771824655e-16
Inverse antipodal conditioned initial   3.4020268335734630e-16
Inverse antipodal conditioned final     3.4020252788665561e-16
```

### `real` (`mant_dig == 64`, order 7)

```text
Direct endpoint                         1.4541908674370038e-15 rad
Direct tangent                          1.3499492811316325e-15 rad
Inverse normalized distance             1.1682487706193282e-15
Inverse ordinary initial tangent        1.0294625405395418e-13 rad
Inverse ordinary final tangent          1.0342102253528597e-13 rad
Inverse short conditioned initial       4.0615679691539418e-16
Inverse short conditioned final         4.0615679690828639e-16
Inverse antipodal conditioned initial   3.3669395607164810e-16
Inverse antipodal conditioned final     3.3669330631116305e-16
```

All values remain comfortably inside the GEO-D acceptance ceilings.

## Dependency boundary

The acceptance execution explicitly verified that no PROJ reference exists in
the DUB package configuration or production `source/` tree.

Therefore:

```text
PROJ is an external GEO-D validation dependency only.

PROJ is NOT a:
- DUB dependency;
- geodesy-d build dependency;
- geodesy-d link dependency;
- geodesy-d runtime dependency.
```

## Conclusion

GEO-D is **PASS**.

The evidence demonstrates public-API interoperability with PROJ 9.7.1 for all
three public scalar models, Direct and Inverse, sphere and multiple oblate
ellipsoids, including difficult near-antipodal cases.

This result does not change ADR-0008 from `Proposed` to `Accepted`. GEO-E,
GEO-F, and GEO-G remain independent mandatory gates.
