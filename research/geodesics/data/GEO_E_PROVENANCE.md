# GEO-E adversarial inverse/convergence provenance

## Status

**PASS**

GEO-E validates inverse-solver robustness, convergence, deterministic behavior,
internal path selection, safeguarded Newton behavior, and agreement with the
independent GeographicLib `GeodesicExact` oracle over the supported production
domain.

The instrumentation added for GEO-E is internal to `geodesy-d`; no public API
or DUB dependency surface is changed.

## Repository baseline

The accepted GEO-E work started from:

```text
branch: research/geodesics
HEAD before GEO-E commit:
cf60a80b5ee87df0a68ad3a78455f554e20e0ce2
```

The public branch baseline remained:

```text
origin/main:
3f244a20d86032b53236c369632a735e5975354e
```

The latest GitHub CI push run on that `main` commit was successful before
formal GEO-E closure.

## Accepted executions

### Full diagnostic/adversarial acceptance

Timestamp:

```text
2026-09-19T09:27:06Z
```

Log:

```text
research/geodesics/data/geoe_acceptance_20260919T092706Z.log
```

SHA-256:

```text
9c2c714bf613f301201d5c74302699e26718a6e7a12c48a1287af7133c261aad
```

Final marker:

```text
GEO-E FINAL ACCEPTANCE EXECUTION: PASS
```

### Identical-corpus exact-oracle acceptance

Timestamp and SHA-256 are injected by the closure script after the completed
oracle run:

```text
timestamp: 20260919T094714Z
log:
research/geodesics/data/geoe_exact_acceptance_20260919T094714Z.log
SHA-256:
f67ca368e02b9afc73c1ff88bb24b0a21d4f84b3683792cd243db71231454883
```

Final marker:

```text
GEO-E IDENTICAL-CORPUS EXACT-ORACLE ACCEPTANCE: PASS
```

## Toolchain

```text
DMD          2.111.0
LDC          1.41.0
D frontend   2.111.0
LLVM         19.1.7
Python       3.14.4
GeographicLib 2.7
platform     x86_64 Linux
```

The x86-64 `real` path uses a 64-bit mantissa and geodesic series order 7.

## Internal instrumentation

GEO-E adds internal diagnostic state sufficient to observe the production
inverse solver without altering its public contract:

```text
GeodesicInverseStartKind
    none
    shortLine
    spherical
    antipodal
    antipodalAstroid

uint iterations
uint bracketMidpointCount
bool converged
```

The diagnostics are propagated through the internal start, canonical solver,
and dispatcher result structures.

Source hashes at acceptance:

```text
source/geodesy/internal/geodesic_inverse_start.d
fb22499a77bdc73350d7cb45f39213ba71efa6004122e1d8291a64c9a871fae1

source/geodesy/internal/geodesic_inverse_solver.d
097d7895f853a76894a5112a17b6c07449b816bc4c0ad61354023c3fc08f1615

source/geodesy/internal/geodesic_inverse_dispatch.d
cb7185e7c5310ded31542f1d846773d17f3decb46d41fe49f3f3a0fd772fb473
```

No solver tolerance, series order, supported domain, convergence criterion, or
public result semantic was changed to obtain the GEO-E evidence.

## Harness

Accepted research harness hashes:

```text
research/geodesics/geoe_inverse_probe.d
a2cb861a2aea890e6161ca46b2b82fe33be805dd355f1bd62e31fc1f46132482

research/geodesics/validate_geoe_adversarial.py
ecfe9c75a6c589645487054ed6fa7c883dcca29a49cef0b5c921af69a5fbdd4b

research/geodesics/search_geoe_bracket.py
351cdb23ce20ab247f36e9a7cee22ea3560e83fc5f771e8b77c3b92442709fec

research/geodesics/geoe_exact_probe.cpp
1ce92be5435e2b78aea5632738b91f0f44db7a777060c18dac6cf76d0f009377

research/geodesics/validate_geoe_exact_adversarial.py
8488084d914680ed0d4fc126eb331f5e812ac8f31c2e733056adbb0fffd6f541
```

Candidate input transport uses exact IEEE-754 binary64 bit patterns. Public
`float` is scalarized to float before working-precision widening. Public
`double` is represented directly. Public `real` uses the exact binary64 subset
for this external-oracle gate; wider-real numerical qualification is already
covered by GEO-C MPFR evidence.

## Adversarial corpus

Deterministic seed:

```text
0x47454F45
```

Profiles:

```text
sphere
near-sphere
WGS84
mid-f (f = 0.005)
max-f
unit-scale
```

Required adversarial classes exercised densely:

```text
nearly coincident
nearly polar
near-equatorial
near-meridional
longitude difference near pi
latitude2 near -latitude1
oblate near-antipodal astroid transition
exact ambiguous antipodal cases
```

Each scalar/profile population contains:

```text
2000 cases per adversarial class
16007 cases total
```

Per compiler:

```text
16007 * 3 scalars * 6 profiles
= 288126 diagnostic cases
```

Every diagnostic payload is executed twice identically, so the accepted
DMD+LDC deterministic diagnostic evidence comprises:

```text
288126 * 2 repeats * 2 compilers
= 1152504 solver executions
```

## Path coverage

The full DMD and LDC runs produced identical global path counts per compiler:

```text
dispatcher:
    coincidence       6684
    meridian         14742
    equator             18
    generalShort     11852
    generalNewton   254830

start:
    none              21444
    shortLine         11852
    spherical        206849
    antipodal         24322
    antipodalAstroid  23659
```

The Astroid start is therefore not merely present in source; it is directly
exercised by the accepted adversarial corpus.

## Safeguarded Newton evidence

The full accepted corpus observes the bracket-midpoint fallback directly.

Worst accepted behavior under both DMD and LDC:

```text
max solver iterations:        12
max bracket midpoint count:   10
worst case:
    scalar:       double
    profile:      WGS84
    case:         longitude-near-pi-1436
    dispatcher:   generalNewton
    start:        spherical
```

This closes the GEO-E requirement to observe whether bracket/bisection
safeguarding is used.

A separate targeted search using seed `0x47454F4542524143` examined:

```text
250000 cases/scalar/compiler
3 scalars
2 compilers
= 1500000 cases
```

That search found no bracket hits and no non-convergence, with a maximum of six
iterations. This is not contradictory: its biased search distribution differs
from the larger structured GEO-E corpus, which does contain reproducible
bracket-triggering longitude-near-pi cases.

## Convergence and determinism

Across the full accepted adversarial run:

```text
non-convergence:                 0
deterministic repeat mismatches: 0
```

DMD and LDC produce the same global path counts and the same observed maxima.

## Independent exact-oracle agreement

The identical GEO-E adversarial corpus was then checked directly against
`GeographicLib::GeodesicExact`.

Per compiler:

```text
288126 exact-oracle comparisons
```

Across DMD + LDC:

```text
576252 exact-oracle comparisons
```

Accepted global maxima under both compilers:

```text
normalized inverse distance error
    3.1478910906506436e-15

exact-direct endpoint closure angle
    3.0324792329808581e-15 rad

well-conditioned final forward azimuth error
    1.6651835466063858e-10 rad
```

The exact-direct closure check uses the candidate initial azimuth and distance
to avoid rejecting a different but valid branch at geometrically non-unique
antipodal solutions.

The existing independent dispatcher validator was also retained as a separate
regression corpus:

```text
2352 cases/compiler
DMD: PASS
LDC: PASS
max solver iterations: 5
```

## Iteration-limit justification

Production constants remain:

```text
maxNewtonIterations = 20
maxIterations =
    20 + W.mant_dig + 10
```

For double working precision this gives a hard limit of 83 iterations. For the
accepted x86-64 64-bit-mantissa `real` path it gives 94.

The largest observed accepted workload required 12 total solver iterations and
10 safeguarded midpoint steps. The primary Newton window therefore still
exceeds the observed total by eight iterations, while the mantissa-dependent
hard cap provides a substantially larger defensive fallback margin.

The production limits are therefore retained unchanged. GEO-E provides
measured evidence for the limit rather than reducing it to the empirical
maximum.

## Public/dependency boundary

The GEO-E diagnostics remain internal implementation detail.

GEO-E does not add:

- a public geodesic API name;
- a public result field;
- a DUB dependency;
- a GeographicLib runtime dependency;
- a PROJ runtime dependency.

GeographicLib is used only as an external validation oracle.

## Conclusion

GEO-E is **PASS**.

The inverse solver demonstrates deterministic bounded convergence over the
required adversarial classes, exercises all dispatcher and starting-strategy
classes, directly exercises the safeguarded bracket-midpoint path, and agrees
with the independent exact oracle on the identical adversarial corpus.

GEO-F and GEO-G remain independent mandatory gates. ADR-0008 therefore remains
`Proposed`.
