# PM-G0 — Pseudo-Mercator Production Endpoint Qualification

## Status

**PASS — production east-endpoint semantics and derivation are qualified.**

PM-G0 resolves the represented east-endpoint question before the accepted PM-F
API is extracted into production code.

No production module is introduced by this gate.

The next gate is:

~~~text
PM-G1 — production module extraction — ACTIVE
~~~

## Problem

PM-E1A established that the east side must use the greatest represented legal
forward endpoint rather than blindly admitting the rounded mathematical
`+pi` sheet boundary.

Its characterization helper searched a fixed neighbourhood of 4096 public
longitude values around a rounded opposite meridian. PM-E1A explicitly treated
that scan as research evidence rather than a production algorithm.

Later PM-E1C1 longitude work retained the longitude difference as a high/low
expansion, made the principal-sheet decision on that expansion, preserved
split-period residuals, and used compensated reverse reconstruction.

PM-G0 therefore re-qualified the endpoint against the actual selected principal
branch.

## Selected endpoint derivation

After `longitudeDifferenceParts()` has reduced the longitude difference onto
the selected principal sheet, the eastward side is classified from the retained
expansion:

~~~d
if (high > 0)
    return true;

if (high < 0)
    return false;

return low >= 0;
~~~

For ordinary origins the transition is bracketed on the public `T` lattice and
bisected until:

~~~d
nextUp(lower) == upper
~~~

with explicit `nextUp` / `nextDown` progress guards.

The result is therefore:

~~~text
lower = greatest represented legal eastward longitude
upper = immediate represented successor on the westward branch
~~~

There is no fixed ULP search radius.

## Exact +/-pi origin seam

Public `+pi` and `-pi` normalize to the same `-pi` origin. At that origin
the sheet transition is at public zero, so the final legal eastward longitude
is exactly:

~~~d
nextDown(cast(T) 0)
~~~

On the controlled platform:

~~~text
float   -1.40129846432481707092372958328991613128e-45
double  -4.940656458412465441765687928682213723651e-324
real    -3.645199531882474602528405933619419816399e-4951
~~~

The immediate successor is zero and belongs to the westward side.

## Reverse endpoint identity

The first seam reverse probe prepared the correct endpoint but reconstructed
longitude from one collapsed east delta.

All 18 targeted +/-pi requests were accepted, but none reconstructed the exact
prepared legal public longitude.

The selected rule is therefore:

~~~text
exact represented east endpoint
    -> prepared eastLegalLongitude
~~~

not reconstruction through one collapsed `eastLegalDelta`.

The prepared public longitude is an authoritative reverse identity.

## Targeted qualification

The actual-principal-branch candidate passed 99 targeted profiles with zero hard
failures.

Comparison with the historical PM-E1A fixed-radius oracle produced 33
mismatches. In each mismatch the historical candidate's immediate successor was
still legal, while the PM-G0 candidate's immediate successor was already on the
westward branch.

The historical oracle was therefore non-maximal in those cases.

## Dense endpoint qualification

A 0.125-degree global origin grid plus immediate represented neighbours around
cardinal longitudes produced:

~~~text
float   origins=2894
double  origins=2894
real    origins=2894
total   origins=8682
failures=0
~~~

The durable `PseudoMercatorG0Endpoint` mode checks the stronger invariant:

~~~text
prepared legal longitude
    -> forward
    -> represented east endpoint
    -> reverse
    -> exact same prepared legal longitude
    -> forward
    -> exact same represented east endpoint
~~~

Per scalar:

~~~text
float   origins=2894  checks=17325  failures=0
double  origins=2894  checks=17325  failures=0
real    origins=2894  checks=17325  failures=0
~~~

Combined:

~~~text
origins=8682
checks=51975
failures=0
~~~

## Controlled compiler matrix

The durable endpoint gate passes:

~~~text
DMD 2.111.0    PASS
DMD 2.112.1    PASS
DMD 2.113.0    PASS
LDC 1.41.0     PASS
LDC 1.42.0     PASS
LDC 1.43.0     PASS
~~~

All six outputs are byte-identical. Diagnostic DMD 2.112.0 also passes with the
same 8682-origin / 51975-check result.

This qualifies the PM-G0 algorithm only; it does not replace the later
production compiler/platform gate.

## Forward regression

PM-E1C1A remains unchanged:

~~~text
requests: 264
FOK:      264
REJECT:     0
ERROR:      0

float   E 88/88   N 88/88
double  E 88/88   N 88/88
real    E 88/88   N 86/88, maximum 1 ULP
~~~

## Policy-aware reverse differential

PM-G0 makes the intended distinction explicit:

~~~text
ordinary represented longitude
    -> independent analytical/numerical oracle

prepared exact east endpoint
    -> represented-domain policy oracle
    -> prepared eastLegalLongitude
~~~

The reverse corpus remains:

~~~text
profiles:           18
reverse requests:  378
accepted:           306
rejected:            72
protocol failures:    0
~~~

For every scalar:

~~~text
longitude contract:          102 / 102
east endpoint policy:         12 / 12
non-east longitude oracle:    90 / 90
~~~

Latitude remains:

~~~text
float   102 / 102 correctly rounded
double  102 / 102 correctly rounded
real     90 / 102 correctly rounded, maximum 2 ULP
~~~

The twelve sparse-corpus mismatches are exclusively the already-qualified
`real` latitude cases. No east-endpoint longitude mismatch remains.

## PM-E1A supersession

PM-E1A remains valid historical evidence for the represented-domain problem.

Its fixed 4096-neighbour seam scan is superseded for production endpoint
derivation by the actual-principal-branch finite-lattice search.

The historical measurements are retained rather than rewritten.

## Production requirements established by PM-G0

PM-G1 must preserve these invariants:

1. use the qualified high/low principal-longitude reduction;
2. derive the greatest represented legal east endpoint from the actual branch;
3. define maximality by public floating-point adjacency;
4. treat exact +/-pi origins consistently with their normalized seam;
5. retain the prepared legal public east longitude as an authoritative endpoint
   identity;
6. classify prepared endpoint identities before ordinary reverse quotient
   handling;
7. reverse the exact represented east endpoint directly to that prepared public
   longitude;
8. do not use one collapsed `eastLegalDelta` as the authoritative endpoint
   inverse;
9. preserve the compensated ordinary reverse-longitude path;
10. keep the behaviour generic over `float`, `double`, and `real`.

A production implementation need not retain a separate `eastLegalDelta`
member merely because research used it during characterization.

## Decision

**PM-G0 passes.**

Selected production endpoint semantics:

~~~text
endpoint derivation:
    actual principal branch
    + public-lattice bisection
    + adjacent-value maximality

east endpoint reverse:
    exact represented easting identity
    -> prepared exact public east longitude
~~~

Rejected as production definitions:

~~~text
fixed 4096-neighbour scan
collapsed delta < pi endpoint test
reconstruction from one collapsed east delta
generic tolerance / ULP slack around the sheet boundary
~~~

## Next gate

~~~text
PM-G1 — production module extraction
~~~

PM-G1 may now implement the accepted PM-F surface in
`geodesy.projection.pseudo_mercator` using the qualified PM-E kernel and PM-G0
endpoint semantics.
