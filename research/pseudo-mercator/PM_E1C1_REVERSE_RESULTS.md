# PM-E1C1B — Pseudo-Mercator Reverse Differential Results

## Status

PM-E1C1B is accepted.

The complete PM-E independent-differential gate is therefore complete.

PM-F, the public API gate, was subsequently accepted.

PM-G0 has now qualified production east-endpoint derivation and exact prepared
endpoint identity. PM-G1 production module extraction is next.

## Purpose

PM-E1C1B qualifies the reverse half of the bounded Pseudo-Mercator research
kernel after PM-E1C1A qualified the forward half.

The gate separates:

- represented-domain and endpoint policy;
- reverse latitude numerical accuracy;
- reverse longitude numerical accuracy;
- public longitude canonicalization;
- scalar-specific working precision;
- compiler stability;
- signed-zero behaviour;
- the measured cost of the selected extended-`real` accuracy correction.

No production API is introduced by this gate.

## Independent analytical oracle

The primary high-precision latitude oracle uses the EPSG literal inverse form:

~~~text
D   = (FN - N) / a
phi = pi/2 - 2 * atan(exp(D))
~~~

This is intentionally independent of the principal research-kernel expression:

~~~text
q   = (N - FN) / a
phi = atan(sinh(q))
~~~

Projection mathematics is evaluated at high precision with `mpmath`.

The oracle starts from the represented values actually consumed by the D
differential driver.

## Representation-aware differential corpus

The reverse validator is:

~~~text
validate_pm_e1c1_reverse.py
~~~

It drives the machine-readable PM-E1C0 interface.

The principal reverse corpus contains:

~~~text
profiles:           18
reverse requests:  378
accepted:           306
rejected:            72
protocol failures:    0
~~~

Accepted cases include:

- origin;
- ordinary east/west and mixed coordinates;
- northern and southern mid/high latitudes;
- represented values immediately inside the domain;
- represented west/east endpoint anchors;
- represented north/south latitude anchors;
- corner combinations.

Rejected cases exercise represented values immediately outside the accepted
northing/easting domain.

## Sparse differential result

The final candidate produced the same result throughout the controlled compiler
matrix.

### `float`

~~~text
accepted cases:                       102
correctly rounded latitude:       102 / 102
longitude contract matches:       102 / 102
  east endpoint policy:            12 / 12
  non-east longitude oracle:       90 / 90
maximum rounded latitude delta:       0 ULP
maximum longitude contract delta:     0 ULP
~~~

### `double`

~~~text
accepted cases:                       102
correctly rounded latitude:       102 / 102
longitude contract matches:       102 / 102
  east endpoint policy:            12 / 12
  non-east longitude oracle:       90 / 90
maximum rounded latitude delta:       0 ULP
maximum longitude contract delta:     0 ULP
~~~

### `real`

~~~text
accepted cases:                       102
correctly rounded latitude:        90 / 102
longitude contract matches:       102 / 102
  east endpoint policy:            12 / 12
  non-east longitude oracle:       90 / 90
maximum rounded latitude delta:       2 ULP
maximum longitude contract delta:     0 ULP
~~~

PM-G0 refines the longitude-oracle terminology. Ordinary and west-side
represented values continue to be evaluated against the independent analytical
longitude oracle. Exact prepared east endpoints are represented-domain policy
cases evaluated against their prepared public `eastLegalLongitude`.

The twelve remaining sparse-corpus mismatches are exclusively the previously
qualified `real` latitude cases; there are no longitude-contract mismatches.

## Reverse longitude selection

Prepared represented endpoint identities are authoritative before the ordinary
quotient interval.

PM-G0 strengthens the east side of that rule: the exact represented east
easting reverses directly to the prepared public `eastLegalLongitude`.
Reconstructing that identity through one collapsed `eastLegalDelta` loses
information at principal-sheet seam collisions and is not the production rule.

For ordinary represented easting, the accepted path reconstructs the quotient
with a compensated residual.

For:

~~~text
x = E - FE
q = x / a
~~~

the error-free product supplies:

~~~text
product + productResidual = a * q
~~~

and the quotient correction is reconstructed from:

~~~text
remainder =
    (x - product)
    - productResidual

correction =
    remainder / a
~~~

The high/low quotient representation is retained through longitude addition and
principal-sheet wrapping.

Whole-sheet research characterization confirmed exact direct-subtraction
reconstruction for every qualified ordinary call in the tested corpus.

No additional sheet guard is required.

## Reverse latitude selection

### `float`

`float` retains the PM-C R2 identity in:

~~~text
WorkingScalar!float == double
~~~

using:

~~~text
phi = atan(sinh(q))
~~~

All qualified `float` differential cases are correctly rounded.

### `double`

For public `double`, widening an already-rounded binary64 quotient does not
recover the information lost during represented Northing subtraction and
division.

The selected path therefore reconstructs:

~~~text
q = (N - FN) / a
~~~

directly from represented public Northing in D `real`, evaluates R2 in `real`,
and rounds only the final latitude to `double`.

All qualified `double` differential cases are correctly rounded.

### `real`

For the tested x86 extended-precision `real`, the selected inverse expression
is R6:

~~~text
u = expm1(abs(q))

phi =
    copysign(
        2 * atan2(u, u + 2),
        q)
~~~

R6 was selected after broad direct `q -> phi` comparison against the portable
candidate family.

It also preserves signed zero through the dedicated near-zero/subnormal audit.

## `real` quotient-residual correction

The ordinary quotient:

~~~text
q = (N - FN) / a
~~~

still omits a small division residual.

The final candidate reconstructs that residual from the already-computed `q`
rather than recomputing another quotient expansion:

~~~text
product + productResidual = a * q

qRemainder =
    ((N - FN) - product)
    - productResidual

deltaQ =
    qRemainder / a
~~~

The first-order inverse correction is based on:

~~~text
dphi/dq = sech(q)
~~~

R6 has already computed:

~~~text
u = expm1(abs(q))
~~~

therefore:

~~~text
exp(abs(q)) = u + 1

sech(q) =
    2 * (u + 1)
    / ((u + 1)^2 + 1)
~~~

The selected implementation therefore reuses the R6 intermediate and avoids
an additional `cosh` evaluation.

When `deltaQ` is exactly zero, the correction is skipped so the selected R6
signed-zero behaviour is retained.

## Broad exact composed `real` corpus

The final selected path was evaluated over four exact-hex projection
geometries:

- unit semi-major axis, zero false Northing;
- WGS 84 semi-major axis, zero false Northing;
- WGS 84 semi-major axis with negative false Northing;
- WGS 84 semi-major axis with positive false Northing.

The complete exact composed corpus contains:

~~~text
714656 reverse evaluations
~~~

Observed ULP histogram:

~~~text
0 ULP    496389
1 ULP    203799
2 ULP     13954
3 ULP       514
>3 ULP        0
~~~

Observed worst case:

~~~text
3 ULP
~~~

Maximum absolute latitude error:

~~~text
1.81244182666565966e-19 rad
~~~

This is an empirical qualification bound for the tested x86
extended-precision environment and corpus.

It is not a platform-independent mathematical error proof.

## Controlled compiler matrix

The final selected research kernel was validated with:

~~~text
DMD 2.111.0
DMD 2.112.1
DMD 2.113.0

LDC 1.41.0   D frontend 2.111.0   LLVM 20.1.5
LDC 1.42.0   D frontend 2.112.1   LLVM 21.1.8
LDC 1.43.0   D frontend 2.113.0   LLVM 22.1.8
~~~

For every primary compiler:

- the differential driver built;
- the 378-case reverse run completed;
- the 714656-case exact `real` corpus completed;
- positive zero remained positive zero;
- negative zero remained negative zero.

The 378-case outputs were byte-identical across all six primary compilers.

The 714656-case outputs were also byte-identical across all six primary
compilers.

Consequently the exact-corpus ULP histogram is identical across the complete
primary compiler matrix.

DMD 2.112.0 is retained as a diagnostic intermediate version but was not
needed for numerical diagnosis because no correctness divergence occurred.

## Performance qualification

Performance was measured only after the numerical candidate was selected.

The relevant comparison is:

~~~text
baseline:
    selected R6
    without quotient-residual correction

selected:
    R6
    plus optimized quotient-residual correction
~~~

The benchmark uses the same prepared corpus in the same process and alternates
baseline-selected and selected-baseline order.

The durable benchmark mode is compiled from:

~~~text
pm_e1_kernel_probe.d
    version(PseudoMercatorReverseBenchmark)
~~~

The controlled matrix runner is:

~~~text
benchmark_pm_e1c1_reverse.py
~~~

The qualifying durable run on 2026-09-25 completed all six primary compiler
configurations with two profiles, 21 repetitions per profile, zero benchmark
failures, and one pinned logical CPU.

### Controlled LDC measurements

Median paired correction overhead:

~~~text
compiler       offset_p170    wgs84_zero

LDC 1.41.0        +3.028 %       +3.963 %
LDC 1.42.0        +4.520 %       +6.089 %
LDC 1.43.0        +5.705 %       +5.100 %
~~~

LDC release builds are the normative project performance configuration.

The selected correction is therefore retained.

### Controlled DMD measurements

Median paired correction overhead:

~~~text
compiler       offset_p170    wgs84_zero

DMD 2.111.0      +12.867 %      +16.407 %
DMD 2.112.1      +14.587 %      +16.135 %
DMD 2.113.0      +12.538 %      +15.165 %
~~~

The relative correction cost is materially higher under DMD than LDC, but
affects only the extended-`real` reverse specialization.

No DMD-specific arithmetic branch is justified.

## DMD 2.112 performance observation

A focused diagnostic identified a separate absolute-performance regression in
the common `real` reverse path under DMD 2.112.x.

Representative baseline medians:

~~~text
                 wgs84_zero     offset_p170

DMD 2.111.0       374.791        448.637 ns/op
DMD 2.112.0       390.812       1406.271 ns/op
DMD 2.112.1       367.823       1464.458 ns/op
DMD 2.113.0       392.940        449.714 ns/op
~~~

The regression boundary is therefore:

~~~text
introduced: DMD 2.112.0
present:    DMD 2.112.1
absent:     DMD 2.113.0
~~~

Factor isolation showed that the slowdown is not specific to longitude
wrapping and is not caused by the quotient-residual correction.

Under DMD 2.112.x, any tested non-trivial prepared projection parameter was
sufficient to expose approximately threefold slowdown:

- non-zero false Easting;
- non-zero false Northing;
- non-zero longitude of natural origin.

The all-zero projection-parameter profile remained near the surrounding
compiler generations.

DMD 2.113.0 returned to the DMD 2.111 performance range for all tested
factors.

This is a compiler/toolchain observation, not a Pseudo-Mercator numerical
defect.

No geodesy-d workaround is selected because:

- correctness is unaffected;
- the selected residual correction is not the root cause;
- the regression is absent again in DMD 2.113.0;
- DMD is not the normative project performance compiler.

## Rejected residual-correction form

The first residual-correction implementation recomputed a full quotient
expansion and evaluated an additional `cosh(q)`.

It retained the same observed three-ULP exact-corpus bound but measured
approximately 30--37 percent overhead under the tested LDC workload.

The final form instead:

- reuses the already-rounded `q`;
- reconstructs its quotient residual through `twoProduct`;
- reuses the R6 `expm1` intermediate to obtain `sech(q)`.

The optimized form reproduced the same exact-corpus ULP histogram while
reducing the controlled LDC correction overhead to approximately three to six
percent.

The earlier correction form is rejected.

## Regression gates

The final PM-E1C1B candidate preserves:

- PM-D represented northing/easting classification;
- PM-E1A represented easting endpoint policy;
- PM-E1B complete-kernel behaviour;
- PM-E1C0 machine-readable differential protocol;
- PM-E1C1A forward behaviour.

The normal/default research kernel retains the correction-enabled path.

The correction-disabled specialization exists only to support isolated
research benchmarking.

## Explicit non-decisions

PM-E1C1B does not decide:

- final public constructor shape;
- checked versus throwing public operation names;
- public default-state semantics;
- final production source placement;
- a platform-independent public ULP guarantee;
- whether wider-than-binary64 `real` is required on every supported platform;
- CRS registry or EPSG authority ownership;
- tile, zoom, or WebMercatorQuad policy.

Those decisions belong to PM-F and PM-G.

## PM-E1C1B decision

PM-E1C1B passes.

The selected reverse research kernel is:

~~~text
longitude:
    represented endpoint anchors
    + compensated ordinary quotient
    + retained expansion through add/wrap

latitude float:
    R2 in WorkingScalar == double

latitude double:
    represented q reconstructed in real
    + R2 in real
    + final binary64 rounding

latitude real:
    R6
    + quotient-residual reconstruction
    + first-order sech(q) correction
    + signed-zero preservation
~~~

PM-E independent differential validation is complete.

PM-F public API design was subsequently accepted.

PM-G0 production endpoint qualification is complete. PM-G1 production module
extraction is next.
