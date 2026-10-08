# R69.4 — prolate family propagation baseline

This research slice reuses the R69.3 temporary signed-flattening source patch
and asks which higher-level geodesic families already propagate for f = -0.01
without any new mathematics.

Expected classification:

- prepared GeodesicLine: pass if it follows the already-qualified Direct core;
- nearest point on bounded segment: candidate pass;
- advanced quantities: expected blocked by signed-area/authalic formula;
- polygon accumulator: expected blocked by the same authalic-area formula;
- intersection prepared state: expected blocked by its explicit f < 0 gate.

The purpose is to separate automatic propagation from independent mathematical
work. A blocked status is an expected research result, not a regression.
