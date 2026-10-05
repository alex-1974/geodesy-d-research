# M2 direct geodesic quantities validation

This experiment validates geodesy-d PR #63 against pinned GeographicLib 2.7
through the public direct API:

```d
tryDirect(start, azimuth, distance, out result, out quantities)
```

Validated outputs:

- endpoint latitude/longitude;
- final forward azimuth;
- reduced length `m12`;
- geodesic scales `M12`, `M21`;
- signed area contribution `S12`.

## Result

All selected cases pass after separating the direct signed-area formula from
the inverse signed-area formula:

| case | lat abs | lon abs | azi abs | m12 abs | M12 abs | M21 abs | S12 abs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary eastward | 0 | 5.551e-17 | 0 | 1.746e-10 | 2.220e-16 | 2.220e-16 | 0 |
| ordinary negative | 1.110e-16 | 2.776e-17 | 2.220e-16 | 1.746e-10 | 3.331e-16 | 3.331e-16 | 9.766e-4 |
| very short | 0 | 0 | 0 | 5.599e-14 | 0 | 0 | 0 |
| zero distance | 0 | 0 | 0 | 1.437e-13 | 0 | 0 | 1.981e-7 |
| antimeridian crossing | 0 | 4.441e-16 | 2.220e-16 | 0 | 0 | 0 | 9.766e-4 |
| north-pole start | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| sphere | 0 | 2.220e-16 | 1.110e-16 | 0 | 1.110e-16 | 1.110e-16 | 9.766e-4 |
| sphere negative | 2.776e-17 | 0 | 2.220e-16 | 2.328e-10 | 1.110e-16 | 1.110e-16 | 1.465e-3 |
| f=0.01 boundary | 2.220e-16 | 5.551e-17 | 0 | 9.313e-10 | 1.110e-16 | 1.110e-16 | 7.812e-3 |
| scaled ellipsoid | 2.220e-16 | 4.441e-16 | 1.110e-16 | 7.276e-12 | 1.110e-16 | 1.110e-16 | 0 |

The first oracle run showed that endpoint, azimuth, m12, M12, and M21 were
already correct, but S12 was wrong because the inverse-specific area
restoration formula had been reused. GeographicLib uses a different stable
alpha12 construction in GeodesicLine::GenPosition. geodesy-d now mirrors that
separation with a dedicated direct area kernel while sharing C4 series support.

This validates positive, negative, and zero signed distance; very short paths;
antimeridian crossing; pole starts; spheres; the f=0.01 support boundary; and
scale-invariant ellipsoid units.
