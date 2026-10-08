# R69.5 — performance and API admission decision

## Candidate public domain

Research R69.1–R69.4 supports a deliberately narrow first public prolate
domain:

    -0.01 <= flattening < 1

with the existing upper oblate bound retained.

This does **not** admit the R69.2 stress model f=-0.05. That case remains
research evidence only because the current direct-distance inversion explicitly
omits the broader-flattening correction used by GeographicLib outside the
small-|f| profile.

## Proposed public semantics

Ellipsoid!T should become a rotational-ellipsoid value type instead of an
oblate-only value type.

Required semantic changes:

- tryFromFlattening accepts -0.01 <= f < 1 only if the library chooses to bind
  Ellipsoid to the geodesic solver domain; otherwise Ellipsoid may admit the
  wider mathematically representable -1 < f < 1 and Geodesic remains the
  narrower admission gate.
- tryFromAxes must accept b > a for prolate ellipsoids.
- inverse flattening must explicitly document negative values for prolate
  ellipsoids. Zero inverse flattening remains invalid because it does not encode
  a finite flattening.
- derived e2, ep2, and n become signed and their documentation must say so.

Preferred API split:

1. Ellipsoid!T represents any finite rotational ellipsoid with a > 0 and
   -1 < f < 1.
2. Geodesic!T admits the numerically qualified subset -0.01 <= f <= 0.01 for
   the current Karney-series implementation.
3. Higher-level geodesic families inherit Geodesic!T admission only after their
   permanent differential gates are added.

This keeps representation separate from algorithm admission.

## Required production mathematics

The research delta is small and isolated:

- signed authalic area/radius:
  - e2 > 0: atanh branch;
  - e2 < 0: atan branch;
- prolate Closest spacing:
  - t1 = 2 * distpolar(90)
  - d1 = pi*a*(1-f)/2
- prolate Next spacing:
  - t1 = 2 * distpolar(90)
  - t3 = 2 * inverse((0,0),(90,0))
  - d2 = 2*t3/3
- prolate All:
  - t4 = polarb()
  - d3 = t4 - delta

Direct, Inverse, prepared line, nearest, polygon, and the enumeration kernel do
not require replacement algorithms in the qualified interval.

## Production admission gate

Before public admission:

- permanent GeographicLib 2.7 direct/inverse differential;
- permanent advanced quantities and polygon differential;
- permanent nearest differential;
- permanent Closest/Next/All differential;
- DMD 2.111 / LDC 1.41;
- float/double/platform-real;
- WGS84/sphere regression;
- hosted performance smoke;
- CPU-pinned XPS qualification.

The public domain must not change until these production gates are green.
