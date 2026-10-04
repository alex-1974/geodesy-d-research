# PM-B — forward numerical study

Status: PASS

## Question

Select a numerically suitable normalized forward northing formulation for the
bounded Pseudo-Mercator kernel without yet fixing the production latitude
domain.

The normalized mathematical quantity is:

    q(phi) = N / a

The primary candidates investigated were:

    F1 = log(tan(pi/4 + phi/2))
    F2 = asinh(tan(phi))
    F3 = asinh(sin(phi) / cos(phi))
    F4 = sign(phi) *
         (log1p(sin(abs(phi))) - log(cos(abs(phi))))
    F5 = atanh(sin(phi))

All candidates are research-only. No public API is introduced by PM-B.

## Environment

Observed scalar precision on the Linux x86-64 research host:

    float   mant_dig = 24
    double  mant_dig = 53
    real    mant_dig = 64

Compilers:

- DMD 2.111.0
- LDC 1.41.0, D frontend 2.111.0

Independent numerical oracle:

- mpmath 1.3.0
- 250–300 decimal digit working precision for near-pole checks
- analytical identity cross-check between
  `asinh(tan(phi))` and `log(tan(pi/4 + phi/2))`

## F1 result

F1 is rejected.

The `pi/4 + phi/2` formulation loses odd symmetry and becomes strongly
ill-conditioned near the poles.

Observed examples include:

- large positive/negative asymmetry close to +/-pi/2;
- approximately 0.595 absolute odd-symmetry error for `double` one ULP below
  the represented positive pole neighbourhood;
- approximately 0.405 odd-symmetry error for `real` in the corresponding
  probe;
- NaN / infinity failure for a `float` latitude whose degree-to-radian
  conversion rounded beyond +pi/2.

F1 provides no advantage over F2 that justifies retaining it as a production
candidate.

## F2 result

F2 is the accepted PM-B forward candidate:

    q(phi) = asinh(tan(phi))

Properties observed in the deterministic corpus:

- exact odd symmetry in all valid tested rows;
- byte-identical DMD and LDC outputs;
- no non-finite results for represented inputs inside the tested open-pole
  domain;
- strong agreement with the high-precision oracle over ordinary and high
  latitudes.

Representative worst ULP-scaled errors through 88 degrees:

    scalar   worst observed
    float    ~1.245 ULP
    double   ~0.732 ULP
    real     ~0.564 ULP

The full representable open-pole stress corpus exposes a separate issue:

- `float` reaches approximately 43 ULP error in an extreme near-pole case;
- `real` reaches a much larger error immediately adjacent to the represented
  pi/2 neighbourhood.

These extreme results do not invalidate F2 for the bounded projection kernel.
They are input to PM-D, which must determine the supported production latitude
domain.

## F3 result

F3 is rejected as the common production formulation despite excellent results
under LDC:

    q(phi) = asinh(sin(phi) / cos(phi))

Under LDC it remains highly accurate through the extreme open-pole stress
corpus.

Under DMD, however, the same source expression diverges substantially near the
pole for `double` and `real`.

Backend diagnostics localize the difference:

- DMD emits x87 `fsin` and `fcos` for the tested `std.math` path;
- LDC does not emit those instructions for the same expressions;
- direct `core.stdc.math` / libm `sin`, `cos`, `sinl`, and `cosl` calls agree
  with the LDC values in the critical cases;
- the tiny cosine error under DMD is magnified by division as cosine approaches
  zero.

The compiler-dependent behaviour makes F3 unsuitable as the portable common
kernel even though one compiler produces excellent near-pole results.

## F4 result

F4 is rejected:

    sign(phi) *
        (log1p(sin(abs(phi))) - log(cos(abs(phi))))

It preserves structural odd symmetry but has poor small-angle relative/ULP
behaviour caused by cancellation and is also affected by the compiler-specific
trigonometric behaviour seen in F3.

It provides no useful overall tradeoff relative to F2.

## F5 result

F5 is rejected:

    atanh(sin(phi))

`sin(phi)` rounds to exactly 1 well before the mathematical pole for some
scalar/case combinations.

Consequences include:

- early positive infinity;
- many non-finite extreme near-pole observations;
- substantially worse high-latitude error before saturation.

F5 is therefore not suitable for the bounded kernel.

## Backend diagnostic

A dedicated probe compared:

- `std.math` trigonometric operations;
- direct `core.stdc.math` / C-libm operations;
- DMD optimized and unoptimized builds;
- LDC optimized and unoptimized builds.

Optimization level did not explain the observed differences.

The relevant generated-code distinction on the research host was:

    DMD: fsin, fcos, fptan observed
    LDC:             fptan observed

This explains why F3/F4 diverge between compilers while F2 remains
compiler-stable in the deterministic study.

The result is implementation/platform evidence, not a requirement that all
future platforms use the same backend instructions.

## Domain observation

A `float` source angle nominally created from 89.999999 degrees rounded to a
represented radian value greater than mathematical +pi/2.

F2 still returned a finite value because tangent is periodic.

Therefore:

- transcendental behaviour must not define projection validity;
- production forward projection requires an explicit latitude-domain check;
- exact latitude boundary semantics belong to PM-D.

## PM-B decision

PM-B accepts:

    normalizedNorthing(phi) = asinh(tan(phi))

as the forward numerical candidate to carry into later research gates.

This decision is conditional on the bounded-domain contract to be resolved by
PM-D.

PM-B deliberately does not:

- accept the full mathematical open-pole interval as the production domain;
- adopt the WebMercatorQuad latitude cutoff;
- adopt the EPSG:3857 area of use as the mathematical kernel domain;
- introduce compiler-specific trigonometric branches;
- call C libm directly from production code;
- introduce a public projection API.

The extreme near-pole results are retained as evidence for the subsequent
domain-policy gate rather than optimized away during PM-B.
