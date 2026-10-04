# PM-E1C1A — Pseudo-Mercator Forward Differential Results

## Status

**PASS — forward differential characterization complete.**

PM-E1C1A establishes the current research forward kernel against an
independent high-precision oracle and a secondary PROJ reference over the
accepted PM-D domain.

This result does **not** by itself:

- close the complete PM-E1C1 independent-differential gate,
- define the final public accuracy contract,
- select the production API,
- establish cross-platform guarantees for D `real`,
- or promote the research kernel into production source.

The corresponding reverse differential work remains separate.

---

## Scope

The tested forward method is EPSG method 1024,
Popular Visualisation Pseudo-Mercator:

- `E = FE + a * Δλ`
- `N = FN + a * q`
- `q = asinh(tan(phi))`

subject to the previously accepted PM-D policy:

- represented forward latitude domain: closed `[-88°, +88°]`,
- principal longitude difference: `[-pi, +pi)`,
- exact represented `+pi` tie canonicalizes to `-pi`,
- represented public boundary values own endpoint semantics,
- Northing reverse classification occurs before inverse evaluation.

The corpus tests the mathematical projection kernel only. It does not add
WebMercatorQuad tile policy or EPSG:3857 CRS machinery.

---

## Test corpus

The machine-readable PM-E1C0 differential driver was exercised with:

- 264 forward requests,
- 88 `float` cases,
- 88 `double` cases,
- 88 `real` cases,
- 0 rejects,
- 0 errors.

Profiles cover:

- unit-scale and WGS84-scale semi-major axes,
- zero and non-zero false origins,
- longitude origins near the antimeridian,
- ordinary interior points,
- wrap/cross-sheet cases,
- points near represented east/west sheet limits,
- WebMercatorQuad latitude for comparison,
- represented `±88°` PM-D boundaries,
- exact antimeridian ties.

DMD and LDC differential output is byte-identical on the current research
host.

---

## Independent oracle

The primary numerical reference is the Python high-precision validator:

`validate_pm_e1c1_forward.py`

It reconstructs the represented public scalar inputs and evaluates an
independent high-precision forward oracle.

For Northing, the oracle uses the EPSG literal expression

`log(tan(pi / 4 + phi / 2))`

rather than reusing the selected D implementation expression
`asinh(tan(phi))`.

PROJ `webmerc` is retained as a secondary external reference over the common
policy domain. PROJ is not treated as authority for PM-D endpoint policy.

---

## Final forward accuracy matrix

| Scalar | Easting correctly rounded | Northing correctly rounded | Maximum rounded-output delta |
|---|---:|---:|---:|
| `float` | 88 / 88 | 88 / 88 | 0 ULP |
| `double` | 88 / 88 | 88 / 88 | 0 ULP |
| `real` | 88 / 88 | 86 / 88 | 1 ULP Northing |

Maximum total oracle error in local output ULP:

| Scalar | Easting | Northing |
|---|---:|---:|
| `float` | 0.4501918554 | 0.4985317901 |
| `double` | 0.4993845295 | 0.4410199068 |
| `real` | 0.4695136547 | 1.2524348843 |

The two remaining correctly-rounded-output mismatches are:

- `real__offset_m170__near_west_sheet`, Northing, 1 ULP
- `real__offset_m179_75__near_west_sheet`, Northing, 1 ULP

Both have absolute Northing error approximately:

`1.77981701814660501e-14`

No Easting mismatch remains in the final corpus.

---

## Secondary PROJ comparison

For compatible `double` cases:

- ordinary compatible cases: 71,
- intentional PM-D policy skips: 1,
- maximum absolute D-vs-PROJ Easting difference:
  approximately `1.02445482172851562e-8 m`,
- maximum absolute D-vs-PROJ Northing difference:
  approximately `1.86264515649414062e-9 m`.

The D implementation is judged against the independent high-precision oracle,
not against bitwise agreement with PROJ.

A larger D-vs-PROJ difference is therefore not considered a regression when
the D result is closer to, or correctly rounded relative to, the independent
oracle.

---

# Easting investigation

## Baseline observation

The original forward Easting path showed:

- `float`: 88 / 88 correctly rounded,
- `double`: 76 / 88,
- `real`: 70 / 88.

All significant `double` Easting errors occurred in wrapped cases.

An analytical error model localized the dominant source to finite-precision
representation of the `2*pi` period used during longitude reduction.

---

## Split-period experiment

Replacing the single rounded `2*pi` period with a high/low representation
improved Easting to:

- `float`: 88 / 88,
- `double`: 86 / 88,
- `real`: 82 / 88.

The remaining errors were at most 1 correctly-rounded-output ULP.

This established period reduction as the dominant first-order error source.

---

## Longitude-delta expansion experiment

Retaining the longitude difference as a high/low expansion, without retaining
the multiplication residual, produced no further improvement over split-period
reduction:

- `float`: 88 / 88,
- `double`: 86 / 88,
- `real`: 82 / 88.

Therefore the residual longitude component alone was not sufficient.

---

## Error-free product experiment

A non-FMA Dekker/Veltkamp-style `twoProduct` path was then used to retain the
multiplication residual.

Combined with split-period longitude reduction and the retained high/low
longitude difference, this produced:

- `float`: 88 / 88,
- `double`: 88 / 88,
- `real`: 88 / 88.

DMD/LDC differential output remained byte-identical.

This isolates multiplication rounding as the second-order error source after
period reduction.

---

## Collapsed-delta minimality experiment

To determine whether carrying the high/low longitude difference through the
multiplication was necessary, the expansion was deliberately collapsed back
to one `WorkingScalar` immediately before `twoProduct`.

The result regressed to:

- `float`: 88 / 88,
- `double`: 86 / 88,
- `real`: 82 / 88.

Affected rows were exactly the expected wrap/seam-sensitive cases.

Therefore both of the following are required by the current research evidence:

1. split/high-low `2*pi` period reduction with retained longitude-difference
   residual,
2. multiplication-residual retention through `twoProduct`.

The longitude expansion is not removable without losing the demonstrated
correct-rounding behavior.

---

## FMA experiment

FMA variants were tested separately.

Results:

- FMA Easting did not improve Easting accuracy.
- FMA Northing reduced some aggregate `double` error but did not solve the
  correctly-rounded-output problem.
- FMA variants introduced DMD/LDC differences for `real`.

FMA is therefore rejected for the current research kernel.

---

# Northing investigation

## Baseline

With ordinary `q = asinh(tan(phi))` followed by the original affine operation,
Northing correctly-rounded counts were:

- `float`: 88 / 88,
- `double`: 72 / 88,
- `real`: 84 / 88.

---

## Compensated affine stage

A non-FMA compensated affine path using `twoProduct` and `twoSum` was tested.

Results:

- `float`: 88 / 88,
- `double`: 72 / 88,
- `real`: 86 / 88.

Aggregate error improved for `double` and `real`, but `double` still retained
16 one-ULP output mismatches.

---

## q decomposition

The actual D-computed `q` was instrumented in the same differential driver so
that no D-side decimal reparse was required.

After treating the exact mathematical `phi = 0` case as exactly `q = 0`, the
decomposition established:

### `float`

The WorkingScalar is `double`.

`q` was not always correctly rounded to binary64 for the represented float
latitude, including selected ±45° and WebMercatorQuad-latitude cases.

Nevertheless all public float Northings were correctly rounded because the
final float representation absorbs those smaller internal differences.

### `double`

`q` was correctly rounded in all 88 corpus cases.

The compensated affine implementation also produced, in all 88 cases, the
correctly rounded public result for the already rounded `q_D`.

Despite that, only 72 / 88 values matched the correctly rounded result of the
full mathematical composition.

This demonstrates intermediate-rounding information loss:

correctly rounding `q` to binary64 is not sufficient to guarantee correctly
rounding `FN + a*q` relative to the unrounded transcendental result.

### `real`

The same mechanism was observed:

- `q`: 88 / 88 correctly rounded,
- affine result for stored `q_D`: 88 / 88,
- full mathematical composition: 86 / 88.

Thus the remaining two `real` cases are not caused by a badly rounded F2
result or by the affine implementation.

---

## Extended internal evaluation for `double`

For public `double`, the complete

`represented latitude -> q -> affine Northing`

chain was evaluated internally in D `real`, with the result rounded to public
`double` only at the end.

On the current Linux/x86 research host this changed Northing from:

- 72 / 88 correctly rounded

to:

- 88 / 88 correctly rounded.

Only the 16 previously mismatching `double` Northing rows changed.

No float, real, or Easting row changed.

DMD/LDC differential output remained byte-identical.

This is the selected research path for `double`.

### Platform qualification

This result depends on `real` providing greater precision than `double` on the
current research platform.

It must **not** yet be interpreted as a portable production guarantee.

The representation and precision of D `real` require explicit PM-G platform
qualification before this technique can become a production assumption.

---

## Native-real split-q experiment

A native-`real` residual experiment attempted to avoid materializing the full
transcendental value as one scalar by evaluating the identity

`q = atanh(sin(phi))`

through separated `log1p` terms and carrying both terms into the affine stage.

This was decisively worse:

- normal PM-E1B probe: 24 failures,
- `real` correctly-rounded Northing: 30 / 88,
- maximum rounded-output error: 49 ULP.

The approach is rejected.

No further native-specialized `real` algebra is justified by PM-E1C1A.

The current two one-ULP `real` Northing cases remain the measured research
bound unless a future concrete consumer requires stronger behavior.

---

# Boundary consistency

PM-D requires authoritative public Northing limits to be exactly the represented
values generated by forwarding represented `±88°` latitude with the same
operation state and numerical path.

After widening the public-`double` Northing path internally to `real`, the
prepared double boundary anchors were updated to use the identical widened
evaluation path.

Explicit validation covered:

- 18 parameter/scalar profiles,
- 36 forward endpoint rows,
- all `float`, `double`, and `real` profiles,
- north and south represented boundaries.

Result:

- 0 boundary mismatches,
- every represented `+88°` forward Northing equals the prepared north anchor,
- every represented `-88°` forward Northing equals the prepared south anchor,
- DMD/LDC anchor output is byte-identical.

---

# Regression gates

After selecting the final PM-E1C1A forward candidate:

## PM-E1A

The represented-Easting-domain probe still contains 72 profiles.

DMD and LDC output remains byte-identical.

The previously accepted PM-E1A conclusions therefore remain intact.

## PM-E1B

The complete research kernel probe reports:

`RESULT failures=0`

for both DMD and LDC.

The complete normal probe output is byte-identical between the two compilers.

## PM-E1C1A

The 264-case differential corpus reports:

- 264 `FOK`,
- 0 `REJECT`,
- 0 `ERROR`.

DMD and LDC differential output is byte-identical.

---

# Selected research algorithm

The current research candidate therefore uses:

## Easting

- residual-aware longitude difference,
- high/low representation of the wrapped longitude difference,
- split/high-low `2*pi` period handling,
- non-FMA error-free `twoProduct`,
- compensated summation through false Easting,
- represented-endpoint policy from PM-D / PM-E1A.

## Northing

### `float`

- public float latitude,
- `WorkingScalar!float == double`,
- F2 `asinh(tan(phi))`,
- compensated affine product/sum,
- final public float rounding.

### `double`

- public double latitude,
- complete `phi -> q -> affine Northing` evaluation in `real`,
- compensated affine product/sum in `real`,
- final public double rounding,
- boundary-anchor preparation through the same widened path.

### `real`

- F2 `asinh(tan(phi))`,
- compensated affine product/sum,
- final public real result,
- measured residual bound of two one-ULP Northing cases in the current corpus.

---

# Explicit non-decisions

PM-E1C1A does not decide:

- the public projection type name or constructor surface,
- checked versus throwing public APIs,
- whether operation state publicly stores an ellipsoid or only derived
  Pseudo-Mercator parameters,
- production source placement,
- a final public accuracy guarantee,
- portable use of `real` as an extended type,
- use of external multiprecision,
- WebMercatorQuad tile policy,
- EPSG:3857 CRS ownership,
- reverse differential acceptance.

These remain for later gates.

---

# Conclusion

PM-E1C1A forward differential characterization is accepted.

The causal numerical chain is now established:

### Easting

finite-period reduction error
-> split `2*pi`
-> retained high/low longitude difference
-> retained product residual
-> correctly rounded corpus Easting for all tested scalar types.

### Northing

intermediate q rounding
-> compensated affine analysis
-> correctly-rounded-q decomposition
-> widened complete chain for public `double`
-> correctly rounded corpus Northing for `float` and `double`
-> two remaining one-ULP `real` cases.

The current research kernel is suitable to carry forward into the next
Pseudo-Mercator research gate, subject to the explicit non-decisions above.
