# M6.1 — Physical geodesy library boundary

Issue: alex-1974/geodesy-d#50

## Question

Where should `geodesy-d` stop and data-driven physical geodesy begin?

The immediate design pressure is normal gravity, geoid undulation, disturbing
potential, gravity-field models, spherical harmonics, interpolation, and large
external model datasets such as EGM96/EGM2008.

## Reference libraries

This slice compares:

- GeographicLib 2.7 `NormalGravity` and `GravityModel`;
- Orekit `ReferenceEllipsoid`, `Geoid`, and spherical-harmonic provider
  interfaces;
- PROJ's external grid/resource model as an additional data-boundary reference.

## Preliminary conclusion

Admit **reference-ellipsoid normal gravity** to `geodesy-d`, but do not make
`Ellipsoid!T` itself own physical constants.

Recommended layering:

```text
Ellipsoid!T
    geometric rotational ellipsoid
        |
        v
NormalGravityModel!T
    Ellipsoid!T
    GM
    angularVelocity
    prepared invariants
        |
        +--> surface normal gravity
        +--> normal potential
        +--> gravity above/below ellipsoid
        +--> geocentric normal acceleration
        |
        v
future gravity-model interface/library
    spherical harmonics / disturbing potential
    external model metadata
    coefficient readers
        |
        v
future geoid layer
    geoid undulation / height anomaly
    tide-system metadata
    interpolation / evaluation policy
        |
        v
external datasets
    EGM96 / EGM2008 / regional grids / coefficients
```

The wider data/model layers should not be embedded into the core package merely
for convenience.

See `ARCHITECTURE.md` for the detailed comparison and API recommendation.
