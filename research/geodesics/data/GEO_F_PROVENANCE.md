# GEO-F API/runtime contract provenance

## Status

**PASS**

GEO-F validates the public checked geodesic surface against geodesy-d's
runtime, safety, determinism, and allocation contract.

No production geodesic implementation was changed for GEO-F.

## Repository baseline

```text
branch:
research/geodesics

HEAD before GEO-F commit:
f920fb40eb75c0175b0e9b3e4001c1ce4fa00766
```

GEO-E was already closed at that baseline.

## Accepted execution

Timestamp:

```text
20260919T105217Z
```

Acceptance log:

```text
research/geodesics/data/geof_acceptance_20260919T105217Z.log
```

SHA-256:

```text
4b8f4e975af69bb6009a5c3f7895d3589b5ee05113724e04906b631ffeb404a6
```

Final marker:

```text
GEO-F API/RUNTIME ACCEPTANCE: PASS
```

## Toolchain

The accepted run uses the project's required local compiler families:

```text
DMD  2.111.0
LDC  1.41.0
D frontend 2.111.0
LLVM 19.1.7
```

Exact toolchain version output is preserved in the acceptance log.

## Permanent validation artifacts

```text
validation/geodesic_api_runtime_validation.d
SHA-256:
270c3c199138d8003e4183ed5ec3289bc57a19e7aeb5ece8535fe4dfe3b835eb

validation/api/public_api_contract.d
SHA-256:
63ff836af7828dd8d65156d464d1dd08055587bccf32b8b2f08058ed3780715e
```

The existing public API contract was extended to instantiate:

```text
Geodesic!float
Geodesic!double
Geodesic!real
GeodesicDirectResult!double
GeodesicInverseResult!double
```

and to exercise the checked and throwing public geodesic surfaces through the
aggregate `import geodesy;`.

## Checked operational contract

The permanent GEO-F runtime validator invokes the complete checked operational
surface from a function declared:

```text
pure nothrow @safe @nogc
```

The compile-time contract covers:

```text
Geodesic!T.tryFromEllipsoid
Geodesic!T.isValid
Geodesic!T.isSphere
Geodesic!T.ellipsoid
Geodesic!T.tryDirect
Geodesic!T.tryInverse

GeodesicDirectResult!T.position
GeodesicDirectResult!T.finalAzimuth

GeodesicInverseResult!T.distance
GeodesicInverseResult!T.initialAzimuth
GeodesicInverseResult!T.finalAzimuth
```

Successful compilation therefore proves that this checked path remains
`pure`, `nothrow`, `@safe`, and `@nogc`.

For geodesy-d, `@nogc` is the compile-time allocation contract used by the
existing TM-E and UTM-E runtime gates. It prevents GC allocation from entering
the checked numerical surface.

## Throwing convenience contract

`Geodesic!T.fromEllipsoid` is intentionally tested separately from an
`@safe` caller because an invalid-construction failure allocates and throws a
`GeodesyValueException`.

The accepted validator checks both:

- successful `@safe` construction;
- invalid default and unsupported-flattening construction raising exactly
  `GeodesyValueException`.

## Invalid-state and failure-result semantics

The accepted run verifies for `float`, `double`, and `real`:

- `Geodesic!T.init` is invalid;
- checked direct on an invalid solver returns `false`;
- checked inverse on an invalid solver returns `false`;
- failed direct clears a previously successful result to `.init`;
- failed inverse clears a previously successful result to `.init`;
- failed checked solver construction clears a previously valid solver;
- an invalid ellipsoid is rejected;
- `f = 0.02` is rejected outside the documented `f <= 0.01` profile;
- `NaN`, `+Inf`, and `-Inf` direct distances are rejected;
- every non-finite-distance failure clears the direct result to `.init`.

Because the component value types have zero-valued `.init`, the result-reset
checks are explicit over all public result accessors rather than relying only
on a returned boolean.

## Deterministic runtime stress

The GEO-F plan requires at least:

```text
100000 deterministic direct calls per scalar
100000 deterministic inverse calls per scalar
```

The accepted validator executes exactly that workload for each of:

```text
float
double
real
```

under both:

```text
DMD
LDC
```

Thus the accepted stress corpus contains, excluding setup/baseline calls:

```text
per compiler:
    300000 direct
    300000 inverse
    600000 checked operations

DMD + LDC:
    600000 direct
    600000 inverse
    1200000 checked operations
```

Every repeated operation must match the represented public-scalar baseline
exactly, including endpoint coordinates, distances, and azimuths.

The accepted result is:

```text
deterministic mismatches: 0
runtime failures:         0
```

## Regression checks

After the GEO-F acceptance capture, the closure run also requires:

```text
DMD unit tests
LDC unit tests
LDC release build
Ddoc/release-metadata validation
```

These are repository regression checks around the GEO-F gate; they do not
replace the gate's dedicated API/runtime evidence.

## Public/dependency boundary

GEO-F adds no production API and no runtime dependency.

The only permanent executable evidence is validation code plus the extension
of the existing compile-time public API contract.

No files under:

```text
source/
dub.sdl
dub.json
.github/
```

are changed by GEO-F.

## Conclusion

GEO-F is **PASS**.

The checked public geodesic surface satisfies the project's
`pure nothrow @safe @nogc` contract, failure paths are deterministic and
clear stale results, the throwing constructor retains its documented
`GeodesyValueException` behavior, and DMD/LDC each complete the required
deterministic runtime stress for all public scalar families.

GEO-G remains the final mandatory acceptance gate. ADR-0008 therefore remains
`Proposed`.
