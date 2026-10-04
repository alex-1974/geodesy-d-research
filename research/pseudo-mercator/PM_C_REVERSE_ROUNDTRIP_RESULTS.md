# PM-C — reverse and round-trip numerical study

Status: PASS

## Question

Select the reverse normalized Pseudo-Mercator formulation to pair with the
PM-B forward candidate and characterize the representability limits of the
forward/reverse mapping before fixing the production domain.

The accepted PM-B forward candidate is:

    q = asinh(tan(phi))

where:

    q = (N - FN) / a

PM-C investigates the reverse mapping from q to ellipsoidal source latitude.

No public API or production-domain decision is introduced by PM-C.

## Reverse candidates

The investigated inverse forms were:

    R1 = pi/2 - 2 * atan(exp(-q))

    R2 = atan(sinh(q))

    R3 = asin(tanh(q))

    R4 = 2 * atan(tanh(q/2))

They are analytically equivalent in exact arithmetic over their mathematical
domain but differ significantly in floating-point behaviour.

## Environment

Observed scalar precision on the Linux x86-64 research host:

    float   mant_dig = 24
    double  mant_dig = 53
    real    mant_dig = 64

Compilers:

- DMD 2.111.0
- LDC 1.41.0, D frontend 2.111.0

High-precision validation used mpmath with substantially greater precision than
any scalar under test.

## R1 result

R1 is rejected:

    pi/2 - 2 * atan(exp(-q))

The subtraction against pi/2 causes severe cancellation for small q.

Observed examples include:

- `float` q values of approximately 1e-18, 1e-12, and 1e-9 returning zero;
- `double` small-q relative error reaching 1.0;
- `real` showing the same cancellation mechanism at smaller absolute scale;
- loss of odd symmetry in multiple scalar/case combinations.

Although R1 directly resembles the published inverse equation, it is not a
suitable general floating-point implementation for this kernel.

## R2 result

R2 is accepted as the PM-C reverse candidate:

    phi = atan(sinh(q))

Observed properties:

- DMD and LDC produced identical deterministic output;
- no non-finite latitude result occurred for the tested finite q corpus;
- small-q behaviour is strong;
- high-latitude behaviour is strong;
- positive and negative exact-pole thresholds are symmetric for every tested
  scalar type.

High-precision oracle comparison found representative worst errors of roughly:

    float    ~1.37 ULP
    double   ~1.21 ULP
    real     ~2.0 ULP

in the direct reverse candidate corpus.

These values include deliberately adversarial cases and are not production
domain limits.

## R3 result

R3 is rejected:

    phi = asin(tanh(q))

`tanh(q)` reaches exactly +/-1 long before the ideal inverse result becomes
indistinguishable from the represented pole.

Observed positive exact-pole thresholds were approximately:

    float     8.67
    double   19.01
    real     22.79

with different negative thresholds.

The formulation therefore loses representable latitude information
prematurely and asymmetrically.

## R4 result

R4 was retained as a useful control but is not selected:

    phi = 2 * atan(tanh(q/2))

It avoids the small-q cancellation of R1 and the very early saturation of R3.

Its ordinary-domain accuracy is competitive with R2.

However:

- it provides no decisive accuracy advantage in the intended bounded domain;
- its observed positive and negative exact-pole thresholds are asymmetric;
- its representability behaviour is less clean than R2.

The additional formulation is therefore not justified for the common kernel.

## Correct-rounding pole boundaries

PM-C separately characterized when the exact inverse latitude crosses the
midpoint between the represented scalar pole and the immediately adjacent
interior latitude.

The theoretical continuous q boundaries were approximately:

    float    18.65051822637035
    double   36.99070499328281
    real     45.67575754881112

These theoretical boundaries are north/south symmetric.

Observed R2 exact-pole thresholds were approximately:

    float    17.32868003845215
    double   36.99070499328281
    real     45.74771391695639

The `double` R2 transition is approximately 0.51 q-ULP beyond the continuous
midpoint and is effectively ideal on the representable q grid.

`float` reaches the represented pole earlier than the continuous boundary.

`real` reaches it somewhat later than the continuous boundary.

These scalar-dependent limits are retained as evidence for PM-D. They do not
justify a more complicated reverse formulation in PM-C.

## Forward to reverse round trip

The accepted candidate pair was tested as:

    phi
      -> asinh(tan(phi))
      -> atan(sinh(q))
      -> returned phi

DMD and LDC produced identical output for the complete deterministic
round-trip corpus.

Observed maximum input-latitude error:

### Through WebMercatorQuad latitude

    float    1 ULP
    double   1 ULP
    real     1 ULP

### Through 88 degrees

    float    1 ULP
    double   1 ULP
    real     1 ULP

### Through 89 degrees

    float    1 ULP
    double   1 ULP
    real     1 ULP

### Full tested open-pole stress corpus

    float    2 ULP
    double   1 ULP
    real     1 ULP

The open-pole stress corpus is diagnostic and does not define the production
latitude domain.

## Reverse to forward round trip

The reverse direction was tested as:

    q
      -> atan(sinh(q))
      -> asinh(tan(phi))
      -> returned q

This round trip must be interpreted differently from the latitude round trip.

A finite scalar latitude has much less representational resolution in q as the
pole is approached. Eventually increasingly large intervals of q map to the
same representable latitude.

Therefore a large `q -> phi -> q` error near the exact-pole threshold does not
by itself indicate an inaccurate inverse formula. It demonstrates loss of
information in the intermediate scalar latitude representation.

Within the bounded high-latitude corpus, observed worst input-q ULP errors
were:

    range                  float   double   real

    WebMercatorQuad        4       4        4
    through 88 degrees     8       4        7
    through 89 degrees     8       5       15

The associated absolute errors remain very small.

Immediately before pole saturation the q round-trip error becomes very large.
This is expected representational collapse and is retained as input to PM-D.

## Exact represented pole is not a valid forward probe

A represented scalar `T(PI_2)` is not necessarily identical to mathematical
pi/2.

In particular, for some scalar/compiler-platform combinations the represented
value may lie slightly beyond the mathematical pole.

Applying the forward formula to such a value can therefore evaluate tangent on
the other side of its singularity and reverse the sign of q.

Consequently:

- `forward(T(PI_2))` must not be used to infer valid projection semantics;
- transcendental-function output must not define latitude validity;
- the production forward path requires an explicit mathematical/domain policy;
- exact pole and boundary handling belongs to PM-D.

## Compiler result

The complete deterministic round-trip corpus contained 348 rows per compiler.

Observed result:

    DMD differing numeric fields: 0
    LDC differing numeric fields: 0

The selected F2/R2 pair is therefore compiler-stable in the tested
environment.

## PM-C decision

PM-C accepts the numerical kernel pair:

    forward:
        q = asinh(tan(phi))

    reverse:
        phi = atan(sinh(q))

R1, R3, and R4 are not carried forward as production candidates.

PM-C deliberately does not decide:

- the supported production latitude interval;
- whether approximately 88 degrees becomes a hard kernel limit;
- whether EPSG:3857 area-of-use bounds constrain the mathematical kernel;
- whether the WebMercatorQuad cutoff constrains the mathematical kernel;
- which finite projected northings are accepted by checked reverse operations;
- exact pole acceptance or rejection semantics;
- longitude wrapping or antimeridian behaviour.

Those questions belong to PM-D.
