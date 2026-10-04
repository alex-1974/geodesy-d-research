# PM-G3 — Pseudo-Mercator Production / Research Equivalence

## Status

**PASS — production behaviour is equivalent to the qualified research kernel.**

PM-G3 validates that extracting the qualified research algorithm into
`geodesy.projection.pseudo_mercator` did not change the numerical or represented
domain behaviour selected by PM-E and PM-G0.

## Gate

The durable runner is:

~~~text
tools/validate-pseudo-mercator-equivalence.sh
~~~

It compiles:

- the PM-E1 research kernel in `PseudoMercatorDifferential` mode; and
- the production differential driver using `PseudoMercator!T`.

Both drivers are then fed through the same PM-E1C1 forward and reverse oracle
programs.

## Baseline compilers

PM-G3 was executed with:

~~~text
DMD 2.111.0
LDC 1.41.0
~~~

Both runs completed with:

~~~text
RESULT: PM-G3A PASS
~~~

## Forward equivalence

For each compiler both research and production execute:

~~~text
requests: 264
FOK:      264
REJECT:     0
ERROR:      0
~~~

The runner verifies byte identity for:

- generated forward corpus input;
- raw differential-driver output;
- high-precision oracle report.

Result:

~~~text
PASS: forward corpus/output/report byte-identical
~~~

The oracle characterization is therefore unchanged.

### float

~~~text
easting   88 / 88 correctly rounded
northing  88 / 88 correctly rounded
~~~

### double

~~~text
easting   88 / 88 correctly rounded
northing  88 / 88 correctly rounded
~~~

### real

~~~text
easting   88 / 88 correctly rounded
northing  86 / 88 correctly rounded
maximum northing delta: 1 ULP
~~~

The two known real northing cases remain exactly:

~~~text
real__offset_m170__near_west_sheet
real__offset_m179_75__near_west_sheet
~~~

No production-only forward mismatch exists.

## Reverse equivalence

For each compiler both research and production execute:

~~~text
profiles:           18
reverse requests:  378
expected accepted: 306
expected rejected:  72
ROK:                 306
REJECT:               72
ERROR:                 0
protocol failures:     0
~~~

The generated reverse input corpus is byte-identical.

The production driver deliberately does not expose the research-only collapsed
`eastDelta` diagnostic field. The runner therefore removes only that field
from research raw output before comparing the protocol records.

After that normalization:

~~~text
PASS: reverse corpus/output/report equivalent
~~~

The complete oracle reports are byte-identical without normalization.

### Longitude contract

For every scalar:

~~~text
longitude contract matches:       102 / 102
east endpoint policy matches:       12 / 12
non-east longitude oracle matches:  90 / 90
~~~

### Latitude characterization

~~~text
float   102 / 102 correctly rounded
double  102 / 102 correctly rounded
real     90 / 102 correctly rounded
real maximum sparse delta: 2 ULP
~~~

The twelve real sparse reverse-latitude cases are the same cases already
qualified in PM-E1C1B. No production-only reverse mismatch exists.

## Endpoint policy

The equivalence corpus includes the PM-G0 represented east-endpoint policy.

Production and research therefore agree that:

~~~text
exact represented east easting
    -> exact prepared eastLegalLongitude
~~~

rather than reconstructing that identity from one collapsed east delta.

## Compiler parity

DMD 2.111.0:

~~~text
PASS: forward corpus/output/report byte-identical
PASS: reverse corpus/output/report equivalent
RESULT: PM-G3A PASS
~~~

LDC 1.41.0:

~~~text
PASS: forward corpus/output/report byte-identical
PASS: reverse corpus/output/report equivalent
RESULT: PM-G3A PASS
~~~

## Decision

**PM-G3 passes.**

The production extraction preserves the already qualified research behaviour.
No numerical, domain, endpoint, scalar, or oracle-result divergence was found.

## Next gate

~~~text
PM-G4 — controlled compiler matrix
~~~

PM-G4 validates the production implementation and accepted public contracts over
the full controlled DMD/LDC compiler matrix.
