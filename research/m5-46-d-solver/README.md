# M5 #46 — D bounded-segment intersection solver probe

This probe implements only the bounded shortest-segment subset admitted by the
preceding semantics experiment.

It deliberately does not port GeographicLib's full Intersect class. The D
prototype uses:

- prepared geodesic lines from the two endpoint pairs;
- Karney's iterative local spherical correction;
- midpoint plus four segment-corner seeds;
- explicit coincidence detection;
- bounded clipping to none / point / overlap.

The experiment is differentially checked against GeographicLib 2.7. If the
reduced seed strategy fails adversarial cases, the production solver must add
the stronger spacing/tiling machinery rather than weaken correctness.
