# R69.4b — prolate intersection Closest

This slice isolates the Closest member of the oriented intersection family.

For GeographicLib 2.7 and f < 0, the constructor changes the Closest search
geometry relative to the oblate branch:

- initial meridional half-period: pi * a * (1-f);
- polar semi-conjugate distance is computed by distpolar(90);
- prolate swaps the two primary spacing roles;
- therefore Closest uses
  - t1 = 2 * distpolar(90)
  - d1 = pi * a * (1-f) / 2.

The research patch also gives the intersection authalic-radius helper the same
real-valued e2 < 0 atan branch already identified in R69.4.

No production source is modified.

The differential corpus covers f=-1/300 and f=-0.01 with ordinary,
reference-offset, near-parallel, polar, and reverse-reference cases against
GeographicLib 2.7 Intersect::Closest.
