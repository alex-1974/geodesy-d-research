# M5 #68 — Advanced GeodesicLine architecture probe

Production issue: alex-1974/geodesy-d#68

This research branch evaluates the storage/API architecture for the additive
advanced prepared-line slice before production code is changed.

## Questions

The admitted #68 slice contains three related capabilities:

1. auxiliary-sphere arc-mode position input;
2. longitude-unrolled position output;
3. advanced position quantities `m12`, `M12`, `M21`, and `S12`.

The production `GeodesicLine!T` must keep its current distance-only hot path
lean. This probe therefore compares the actual current line size with modeled
advanced storage alternatives.

## Semantics fixed before implementation

### Arc input

Arc mode is auxiliary-sphere arc `a12 = sigma12`, not geographic central
angle and not an ellipsoidal distance disguised as an angle.

The arc-path implementation should enter the common line-position kernel at
`sigma12` and bypass distance -> tau -> sigma inversion.

### Longitude unrolling

Production `Longitude!T` is intentionally restricted to [-pi,+pi].
Unrolled longitude can exceed this range after antimeridian crossings and
multiple encirclements, so it must use a separate additive result field.

The likely carrier is unrestricted finite `Angle!T`, named
`unrolledLongitude`, while the ordinary public geographic position remains
canonical.

### Advanced quantities

The existing direct advanced-quantity path computes C2 and C4 work on demand.
For a prepared advanced line, the useful line-specific state is substantially
smaller than retaining the complete ellipsoid C4x table.

Candidate prepared additions are:

- epsilon / ep2;
- start dn1 and cos(beta1);
- start azimuth sine/cosine;
- A2/B2 or equivalent reduced-length/scales state;
- line-specific C2 coefficients;
- line-specific C4 coefficients and B41;
- ellipsoid factors required by S12.

The exact minimum is a result of the implementation experiment, not assumed in
advance.

## Architecture alternatives

A. **Expand GeodesicLine**

Every line stores all advanced state.

Advantage: one type.
Cost: all current callers pay larger object/preparation cost even when they
only use distance positions.

B. **Separate AdvancedGeodesicLine**

Keep `GeodesicLine!T` unchanged and provide an explicitly advanced prepared
value containing the additional state.

Advantage: preserves the existing hot-path/storage contract.
Cost: second public prepared type and some base-state duplication/composition.

C. **Templated internal storage, semantic public wrappers**

Use one compile-time internal storage template with basic/advanced capability
specialization, while exposing intentional public types rather than a runtime
mask.

This is the preferred direction to test because D can erase unused state and
code at compile time.

## Run

From the research checkout:

~~~bash
GEODESY_D_REPO=../geodesy-d \
DC=ldc2 \
bash research/m5-68-advanced-geodesic-line/run.sh
~~~

Also compile with the minimum DMD baseline:

~~~bash
GEODESY_D_REPO=../geodesy-d \
DC=dmd-2.111.0 \
bash research/m5-68-advanced-geodesic-line/run.sh
~~~

The probe reports production and modeled object sizes for float/double/real.

## External reference semantics

- GeographicLib C geodesic API: `GEOD_ARCMODE`,
  `GEOD_LONG_UNROLL`, reduced length, scales, and area are selectable
  capabilities of prepared-line position evaluation.
- `LONG_UNROLL` returns longitude so that lon2-lon1 records how many times
  and in which direction the geodesic encircles the ellipsoid.
- The research intentionally does not copy GeographicLib's public runtime
  capability-mask API. D compile-time specialization is preferred.
