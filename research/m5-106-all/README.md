# M5 #106 R106.1 — GeographicLib All reference corpus

Production issue: alex-1974/geodesy-d#106

This slice establishes the external reference corpus for enumerating all
intersections of two oriented geodesics within an L1 displacement radius.

## Scope

This is deliberately a **reference-only** slice. It does not yet implement the
D algorithm or choose the final workspace representation.

The oracle is GeographicLib 2.7 `Intersect::All`. For each case the probe
records:

- ellipsoid `a` and `f`;
- reference displacement pair `p0=(x0,y0)`;
- requested L1 radius;
- GeographicLib's prepared comparison tolerance `delta`;
- ordered displacements `(x,y)`;
- coincidence indicator `c`;
- L1 rank `abs(x-x0)+abs(y-y0)`.

The verifier independently checks the semantic invariants we intend to preserve
in geodesy-d:

1. every result lies within the requested L1 radius;
2. order is ascending rank, then `x`, then `y`;
3. no two results are duplicates within `delta`;
4. coincidence is one of -1, 0, +1;
5. boundary-radius paired cases differ when the next intersection is moved
   just outside vs just inside the radius.

## Corpus

The fixed corpus covers:

- WGS84 ordinary crossing;
- WGS84 common-origin symmetric crossing;
- WGS84 near-parallel geodesics;
- WGS84 polar geometry;
- WGS84 reversed directions;
- WGS84 coincident parallel and antiparallel geodesics;
- spherical ordinary, near-parallel, symmetric, and coincident geometry;
- dynamic boundary-radius cases constructed from GeographicLib `Next`.

The probe prints TSV to stdout. CI stores the generated corpus in its job log,
so every oracle revision is inspectable and reproducible.

## Run

Requires an installed GeographicLib 2.7:

```bash
GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7 \
  bash research/m5-106-all/run.sh
```

R106.2 will use this corpus to qualify D-native tiling, duplicate handling,
ordering, and coincident conjugate enumeration.
