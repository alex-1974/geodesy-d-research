# PM-G5 — Platform / release / regression results

Status: PASS — G5A/G5B/G5C/G5D/G5E/G5F complete

## Baseline

The acceptance run was performed from:

    997d48c docs: define pseudo-mercator PM-G5 acceptance gate

with a clean worktree synchronized to:

    origin/research/pseudo-mercator

## G5A — release builds — PASS

Release-mode library builds succeeded on x86_64 with:

    DMD 2.111.0
    LDC 1.41.0

Commands:

    dub build --build=release --compiler=dmd-2.111.0 --force
    dub build --build=release --compiler=ldc-1.41.0 --force

Both built geodesy-d successfully as a library.

No Pseudo-Mercator-specific release-only compilation failure was observed.

## G5B — repository regression — PASS

Full repository unit tests:

    DMD 2.111.0    22 modules passed unittests
    LDC 1.41.0     22 modules passed unittests

Public API contract validation passed under both compilers, including the
Pseudo-Mercator negative contracts:

    WebMercator alias                 rejected
    conformal factor surface          rejected

The documentation/release metadata contract also passed:

    PASS: Ddoc generated 24 module files
    PASS: documentation/release metadata contract

The worktree remained clean after the run.

## G5C — external package / aggregate consumer — PASS

An external DUB consumer under `/tmp`, outside the geodesy-d repository,
successfully built, linked, and executed a Pseudo-Mercator forward/reverse
smoke program with:

    direct module import:
        DMD 2.111.0    PASS
        LDC 1.41.0     PASS

    package aggregate import geodesy:
        DMD 2.111.0    PASS
        LDC 1.41.0     PASS

The consumer resolved geodesy-d through the local DUB package path and used the
public production API only.

An earlier draft of the smoke program incorrectly attempted to call
`isValid` on Latitude/Longitude. That harness error was removed before the
acceptance run and is not a library failure.

## G5D — research-only leakage audit — PASS

The package manifest declares:

    targetType "library"
    sourcePaths "source"
    toolchainRequirements frontend=">=2.111.0"

No runtime dependency is declared in dub.sdl.

The package aggregate publicly imports:

    geodesy.projection.pseudo_mercator

The production Pseudo-Mercator module imports only Phobos and geodesy-d
production modules.

The accepted PM-F exclusions remain outside the public Pseudo-Mercator
surface:

    no WebMercator / EPSG3857 alias
    no latitude-of-natural-origin parameter/property
    no scale-factor-at-natural-origin parameter/property
    no conformal projection-factor API
    no one-shot free forward/reverse helpers
    no CRS / EPSG lookup abstraction
    no WebMercatorQuad / XYZ / TMS / zoom / tile policy
    no research differential observability field

The existing compile-negative API contracts independently reject the
WebMercator alias and conformal-factor surface.

No research driver, oracle, corpus-generation code, PROJ, GeographicLib,
imagery/raster, CRS database, or tile-policy dependency leaks into the
production package.

## G5E — platform evidence — PASS

Final local acceptance platform:

    OS:             Ubuntu 26.04.1 LTS (Resolute Raccoon)
    kernel:         Linux 6.17.0-22-generic
    architecture:   x86_64

Baseline compilers:

    DMD 2.111.0
    LDC 1.41.0
      DMD frontend 2.111.0
      LLVM 20.1.5
      target x86_64-unknown-linux-gnu

Measured scalar widths under both DMD and LDC:

    float.sizeof    4
    double.sizeof   8
    real.sizeof     16
    real.mant_dig   64

Thus the final acceptance host provides a platform `real` wider than
`double`, matching the scalar condition under which the qualified real path
was exercised.

This evidence is specifically for the tested x86_64 Linux platform. PM-G5 does
not extend support claims to untested operating-system/architecture
combinations.

## G5F — documentation consistency — PASS

The PM-A through PM-G5 evidence chain is internally consistent with the
accepted PM-F surface and production package boundary.

The final acceptance state is:

    PM-G5                  PASS
    Pseudo-Mercator        ACCEPTED

Research and roadmap status are updated with this result. Integration into
`main`, PR creation/merge, versioning, and release remain separate actions.

## Final result

All PM-G5 acceptance areas pass:

    G5A release builds                    PASS
    G5B repository regression             PASS
    G5C external consumer/package         PASS
    G5D research-only leakage audit       PASS
    G5E platform evidence                 PASS
    G5F documentation consistency         PASS

Pseudo-Mercator satisfies the bounded production/platform acceptance contract
defined for this research branch.

    RESULT PM-G5 PASS
    PSEUDO-MERCATOR ACCEPTED
