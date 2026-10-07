# M5 #47 — nearest-point / cross-track interception probe

Production issue: alex-1974/geodesy-d#47

This research probe tests whether the accepted #68 geodesic-line surface is
sufficient to implement exact ellipsoidal interception without adding a public
gnomonic projection or a second geodesic kernel.

## Reference method

The solver follows Karney, *Algorithms for geodesics*, Section 8.

For a projection centered at O, GeographicLib's ellipsoidal gnomonic forward
map is constructed from the inverse geodesic C->P:

- rho = m12 / M12
- x = rho * sin(azi1)
- y = rho * cos(azi1)

The reverse map is a Newton solve along a prepared geodesic line using m12 and
M12. This is exactly the differential state added to geodesy-d GeodesicLine by
M5 #68.

The interception iteration projects A, B, C about the current O, solves the
Euclidean perpendicular foot in the gnomonic plane, reverses that point back to
the ellipsoid, and repeats.

No spherical cross-track formula is used by the accepted ellipsoidal path.

## Semantics under test

### Oriented supporting line

A and B define the shortest geodesic from A toward B and its local infinite
extension.

- along-track distance is signed from A in the A->B orientation;
- cross-track distance is positive to the **right** of the oriented line and
  negative to the left;
- the returned intercept is a local perpendicular foot on that supporting
  geodesic;
- global infinite-line uniqueness is not promised on the closed ellipsoid.

### Bounded segment

The same supporting-line intercept is computed first.

- if along-track < 0, the nearest segment point is A;
- if along-track > sAB, the nearest segment point is B;
- otherwise the intercept is interior;
- nearest distance to the bounded segment is always unsigned;
- signed cross-track is an interior supporting-line quantity. Endpoint-clamped
  results are classified explicitly rather than pretending the endpoint
  distance is perpendicular cross-track.

This distinction is intentional and is part of the API-admission experiment.

## Scope of this probe

The probe uses only public geodesy-d operations:

- Geodesic.tryInverse(..., quantities)
- GeodesicLine.fromGeodesic
- GeodesicLine.tryPosition(..., quantities)

If this differential probe passes, production #47 can keep the gnomonic
machinery package/private and expose only nearest-point semantics.

## Reference

- Karney, *Algorithms for geodesics*, Section 8.
- GeographicLib Gnomonic implementation, v2.7.
- GeographicLib support discussion: general cross-track should use the
  interception problem; the reduced-length azimuth-difference expression is
  only a near-track approximation.
