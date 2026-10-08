# R69.4c — prolate intersection Next

GeographicLib 2.7 uses a separate prolate Next spacing:
- t1 = 2 * distpolar(90)
- t3 = t5 = 2 * inverse((0,0),(90,0))
- d2 = 2*t3/3

This research-only patch preserves the R69.4b prolate authalic and Closest
changes and adds only this Next spacing branch. Differential comparison uses
GeographicLib 2.7 Intersect::Next for f=-1/300 and f=-0.01.

Because Next frequently has equidistant minima, validation accepts either the
same displacement representative or the same minimal L1 rank and coincidence.
