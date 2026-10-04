# Pseudo-Mercator research

Status: PM-G5 platform / release / regression acceptance PASS — Pseudo-Mercator ACCEPTED

## Goal

Qualify the smallest bounded Pseudo-Mercator mathematical projection kernel
needed by geodesy-d consumers before any public API or production
implementation is accepted.

The target method is EPSG coordinate operation method 1024,
Popular Visualisation Pseudo-Mercator.

This research does not define a CRS database, EPSG lookup layer, web-tile
scheme, zoom model, imagery cache, or map renderer.

## Authoritative semantic baseline

Primary references:

- IOGP Publication 373-7-2, Guidance Note 7 part 2,
  section 3.2.1.2, Popular Visualisation Pseudo-Mercator;
- EPSG coordinate operation method 1024;
- EPSG projected CRS 3857 as the principal real-world consumer profile;
- IOGP Publication 373-23, Web Mercator;
- PROJ `webmerc` as an independent production implementation;
- OGC WebMercatorQuad only for demonstrating the ownership boundary between
  projection mathematics and tile-matrix policy.

For ellipsoidal latitude phi and longitude lambda, EPSG method 1024 uses the
semi-major axis a as the radius in the spherical-form equations:

    E = FE + a * (lambda - lambda0)
    N = FN + a * ln(tan(pi/4 + phi/2))

The reverse operation derives:

    D = (FN - N) / a
    phi = pi/2 - 2 * atan(exp(D))
    lambda = (E - FE) / a + lambda0

The latitude of natural origin is not used by the method equations. EPSG
includes the parameter for completeness in CRS labelling, but it must have the
value zero.

The method is not conformal when ellipsoidal geographic coordinates are used.
Meridional and parallel scale differ. Therefore
ConformalProjectionFactors!T is not applicable to this projection.

## Method, CRS, and tile-policy separation

Three concepts must remain distinct:

1. EPSG method 1024 is projection mathematics.
2. EPSG:3857 is a concrete WGS 84 projected CRS using that method.
3. WebMercatorQuad / slippy-map bounds and zoom/tile addressing are consumer
   policy layered on projected coordinates.

In particular, the approximately 85.0511287798 degree WebMercatorQuad latitude
cutoff is not automatically the domain of the geodesy-d projection kernel.

No XYZ/TMS tile addressing, zoom level, pixel size, tile extent, tile URL, or
raster concern belongs in this research slice.

## PM-D domain decision

PM-D adopts the represented closed forward latitude domain:

    -88 degrees <= phi <= +88 degrees

The geographic poles are outside the supported method domain.

The normalized northing boundary is derived from the represented public
+/-88-degree forward points. Reverse must classify projected northing against
those represented forward boundaries before inverse-latitude rounding can hide
an out-of-domain input.

The approximately +/-85.06-degree EPSG:3857 area of use and the approximately
+/-85.0511287798-degree WebMercatorQuad cutoff remain CRS/consumer policy and
are not geodesy-d kernel limits.

See `PM_D_DOMAIN_POLICY.md`.


## PM-D longitude policy decision

Pseudo-Mercator uses the existing geodesy-d principal longitude convention:

    -pi <= deltaLambda < +pi

An exact represented +pi tie canonicalizes to -pi.

The mathematical principal easting sheet is therefore:

    FE - a*pi <= E < FE + a*pi

The open east boundary must not be pre-rounded to public scalar T and used as a
raw comparison limit. PM-D demonstrated a `float`/WGS84 representation
collision where a legal east-side point and the excluded mathematical +pi
boundary round to the same public easting.

Reverse therefore classifies the longitude difference reconstructed from the
represented easting in working precision.

If a legal point and an excluded mathematical boundary are indistinguishable
after public scalar rounding, the legal represented value remains accepted.

Reverse longitude output is canonicalized to `[-pi,+pi)`.

Bit-identical recovery of every independently rounded public longitude is not a
PM-D requirement; numerical round-trip accuracy is validated by PM-E.

See `PM_D_DOMAIN_POLICY.md`.


## Numerical candidates

Forward northing candidates to compare include at minimum:

    F1 = log(tan(pi/4 + phi/2))
    F2 = asinh(tan(phi))

They are analytically equivalent inside the open-pole domain but need not have
identical floating-point behaviour.

Inverse candidates must include the literal EPSG exponential form and at least
one overflow-safe formulation. Research must characterize when a finite
projected northing rounds to an exact represented pole for float, double, and
real.

Production code must not be selected solely because a formula is shorter or is
used by another implementation.

## Parameterization question

The coordinate equations depend on:

- semi-major axis a from the ellipsoid of the source geographic CRS;
- longitude of natural origin lambda0;
- false easting FE;
- false northing FN.

The semi-major axis is therefore projection input state derived from the
ellipsoid, not an EPSG method parameter analogous to lambda0, FE, or FN.

Flattening does not enter the forward/reverse coordinate equations, although
the source coordinates are ellipsoidal and flattening matters to distortion
properties.

Research must decide whether the public prepared projection accepts a complete
Ellipsoid!T or only the minimum radius-like state. The answer must follow
geodesy-d ownership and API consistency rather than implementation convenience.

The unused zero latitude-of-natural-origin parameter must not become public
state without a concrete interoperability reason.

## Working public-name question

`PseudoMercator` is the current research working name because it describes the
EPSG projection method without implying ownership of WebMercatorQuad tile
policy or a fixed EPSG:3857 CRS.

`WebMercator` remains a candidate only if the API-design gate demonstrates that
the narrower consumer meaning is preferable.

No alias is admitted during research.

## Validation profiles

The validation program must cover at least:

- the published EPSG/IOGP method example;
- WGS 84 / EPSG:3857-like zero-origin cases;
- non-zero longitude of natural origin;
- non-zero false easting and northing;
- spherical and ellipsoidal Earth models sharing the same semi-major axis;
- at least one synthetic ellipsoid with a different semi-major axis;
- equator and central meridian;
- antimeridian and wrap-around cases;
- northern and southern high latitudes;
- domain/boundary probes;
- float, double, and real where the platform provides a wider real;
- DMD and LDC.

PROJ `+proj=webmerc` is an interoperability oracle, not the only oracle.
An independent high-precision analytic implementation is required.

## Research gates

PM-A — semantic contract and ownership boundary
    Freeze the method identity, non-goals, reference sources, and unresolved
    questions. No production API.

PM-B — numerical forward study — PASS
    `asinh(tan(phi))` accepted as the portable forward numerical candidate
    after DMD/LDC, high-precision oracle, alternative-form and backend
    characterization. See `PM_B_FORWARD_RESULTS.md`.

PM-C — numerical reverse and round-trip study — PASS
    `atan(sinh(q))` accepted as the portable reverse numerical candidate.
    Forward/reverse round trips and scalar representability limits are
    characterized in `PM_C_REVERSE_ROUNDTRIP_RESULTS.md`.

PM-D — domain and longitude-policy gate — PASS
    +/-88 degrees accepted as the represented closed latitude boundary.
    Principal longitude difference is [-pi,+pi), projected northing is checked
    against represented forward boundaries, and easting uses working-precision
    principal-sheet classification. See `PM_D_DOMAIN_POLICY.md`.

PM-E — independent differential validation — PASS
    PM-E0 PASS: local PROJ `webmerc` is qualified as a numerical differential
    reference over the shared supported domain. Exact +pi endpoint policy is
    intentionally treated separately from numerical agreement.
    See `PM_E0_PROJ_QUALIFICATION.md`.

    PM-E1A PASS: represented easting-domain behaviour is characterized.
    Working-precision classification is primary; exact represented west and
    legal-east endpoint anchors handle the remaining rounding collisions
    without general domain slack. See `PM_E1A_EASTING_DOMAIN_RESULTS.md`.

    PM-E1B PASS: the complete D research kernel composes the accepted
    PM-B/PM-C formulas with the PM-D/PM-E1A domain classifiers. The
    deterministic 18-profile / 144-round-trip corpus has zero failures and
    byte-identical DMD/LDC output. See `PM_E1B_KERNEL_RESULTS.md`.

    PM-E1C0 PASS: the accepted PM-E1B kernel has a versioned machine-readable
    differential driver. Normal E1B behaviour remains byte-identical across
    DMD/LDC; the driver smoke corpus is also byte-identical and preserves the
    +pi -> -pi principal-sheet tie.
    See `PM_E1C0_DIFFERENTIAL_DRIVER.md`.

    PM-E1C1A PASS: representation-aware forward differential validation is
    complete against an independent high-precision analytical oracle.
    Easting is correctly rounded for all tested float/double/real cases;
    Northing is correctly rounded for all float and double cases and 86/88
    real cases, with exactly two remaining 1-ULP real Northing cases.
    See `PM_E1C1_FORWARD_RESULTS.md`.

    PM-E1C1B PASS: representation-aware reverse differential validation is
    complete against an independent high-precision analytical inverse.
    `float` and `double` are correctly rounded throughout the qualified
    differential corpus. `real` has a two-ULP sparse-corpus maximum and a
    three-ULP observed maximum over the 714656-case exact composed corpus.
    Differential and exact-corpus outputs are byte-identical across the
    controlled DMD 2.111/2.112.1/2.113 and LDC 1.41/1.42/1.43 matrix.
    Signed zero is preserved. The selected `real` path uses R6 plus the
    optimized quotient-residual / `sech(q)` correction.
    See `PM_E1C1_REVERSE_RESULTS.md`.

    PM-E is complete. PM-F public API is accepted. PM-G0 production endpoint
    qualification, PM-G1 production module extraction, PM-G2 public API /
    aggregate / runtime contracts, and PM-G3 research-kernel equivalence are
    complete; PM-G4 controlled compiler matrix validation and PM-G5 platform / release / regression acceptance are complete.

PM-F — public API gate — PASS
    The accepted surface is documented in `PM_F_PUBLIC_API.md`.

    `PseudoMercator!T` is a prepared value type with checked/throwing
    preparation, intentionally invalid `.init`, read-only defining
    properties, `tryForward` / `forward`, and `tryReverse` / `reverse`.

    The public parameter set is `Ellipsoid!T`, longitude of natural origin,
    false easting, and false northing.

    No latitude-of-natural-origin parameter, scale-factor parameter,
    projection-factor API, one-shot free projection helpers, WebMercator
    alias, CRS object, or tile policy is admitted.

    Receiver semantics and future free-function parameter ordering follow the
    workspace UFCS policy without duplicating member/free API.

PM-G — production/platform acceptance — PASS

    PM-G0 — production endpoint qualification — PASS
        `PM_G0_ENDPOINT_RESULTS.md` qualifies actual-principal-branch
        finite-lattice endpoint derivation and exact prepared east-longitude
        reverse identity.

        The durable endpoint gate covers 8682 origins and 51975 endpoint
        round-trip checks per compiler with zero failures across the controlled
        DMD 2.111/2.112.1/2.113 and LDC 1.41/1.42/1.43 matrix. All six outputs
        are byte-identical.

    PM-G1 — production module extraction — PASS
        `source/geodesy/projection/pseudo_mercator.d` implements only the
        accepted PM-F surface and qualified PM-E/PM-G0 numerical/domain
        semantics.

        Baseline validation on commit 76fbc3a passes module unittests under
        DMD 2.111.0 and LDC 1.41.0 (6 modules each), and full repository
        `dub test` under both compilers (22 modules each).

        See `PM_G1_PRODUCTION_EXTRACTION.md`.

    PM-G2 — public API / aggregate / runtime contracts — PASS
        Root aggregate exposure, positive public API and named-argument
        contracts, checked-operation attributes, runtime failure/boundary
        semantics, and rejected WebMercator/factor surfaces are validated
        under DMD 2.111.0 and LDC 1.41.0.

        The dedicated PM-G2 runtime validator passes for float/double/real
        under both compilers. Full repository `dub test` also remains green
        under both compilers.

        See `PM_G2_API_RUNTIME_RESULTS.md`.

    PM-G3 — research-kernel equivalence — PASS
        The production differential driver reproduces the qualified PM-E1C1
        forward and reverse corpus/results under DMD 2.111.0 and LDC 1.41.0.

        Forward input, raw driver output, and oracle reports are byte-identical.
        Reverse input and oracle reports are byte-identical; normalized raw
        reverse output is equivalent after removing the research-only
        `eastDelta` observability field.

        The production path preserves the exact same known real-scalar
        characterization: 86/88 correctly-rounded forward northings with two
        1-ULP cases, and 90/102 correctly-rounded sparse reverse latitudes with
        a 2-ULP maximum. No new production mismatch exists.

        See `PM_G3_EQUIVALENCE_RESULTS.md`.

    PM-G4 — controlled compiler matrix — PASS
        The production implementation passes public API contracts, PM-G2
        API/runtime contracts, PM-G3 production/research equivalence, and the
        full repository test suite across DMD 2.111.0/2.112.1/2.113.0 and
        LDC 1.41.0/1.42.0/1.43.0. The matrix completed with six controlled
        compilers and zero failed checks.

        See `PM_G4_COMPILER_MATRIX_RESULTS.md`.

    PM-G5 — platform / release / regression acceptance — PASS
        Release builds, repository regression, external DUB consumer/package
        exposure, research-leakage audit, x86_64 Linux platform/real-width
        evidence, and final documentation consistency all pass.

        See `PM_G5_RESULTS.md`.

        Pseudo-Mercator is accepted on the research branch. Integration into
        main, versioning, and release remain separate actions.

## Explicit non-goals for this slice

- no CRS registry or EPSG lookup;
- no EPSG:3857 CRS object;
- no automatic CRS conversion pipeline;
- no WKT or PROJJSON;
- no WebMercatorQuad object;
- no XYZ/TMS addressing;
- no zoom levels or pixel coordinates;
- no tile clipping policy;
- no imagery/raster dependency;
- no projection-factor API;
- no general Jacobian/Tissot abstraction;
- no performance optimization before correctness and API acceptance.

## PM-A exit criteria

PM-A is complete when:

- authoritative semantics are reproducibly documented;
- method / CRS / tile-policy ownership is explicit;
- the non-conformal nature of EPSG:1024 is recorded;
- the domain question remains explicit rather than being silently answered by
  the WebMercatorQuad cutoff;
- numerical candidates and validation oracles are identified;
- no production API or implementation has been introduced.
