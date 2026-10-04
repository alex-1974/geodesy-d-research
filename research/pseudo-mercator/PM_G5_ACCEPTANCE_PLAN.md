# PM-G5 — Platform / release / regression acceptance

Status: ACTIVE

## Purpose

PM-G5 is the final Pseudo-Mercator acceptance gate.

PM-G4 already established compiler-matrix correctness for the accepted
production implementation. PM-G5 therefore does not repeat the complete PM-G4
matrix without cause. It validates the remaining release-facing boundaries:
release-mode construction, package exposure, platform assumptions, repository
regression, documentation consistency, and absence of research-only leakage.

No production numerical change is admitted by this gate unless a PM-G5 check
exposes a concrete defect.

## Baseline

PM-G5 starts from:

    PM-A .. PM-F    PASS
    PM-G0 .. PM-G4 PASS

The accepted public implementation is:

    source/geodesy/projection/pseudo_mercator.d

and the package aggregate exports it through:

    source/geodesy/package.d

The package remains a dependency-light DUB library with:

    targetType "library"
    sourcePaths "source"
    frontend >= 2.111.0

## G5A — release builds

Validate release-mode construction with the normal supported compiler baseline:

    dub build --build=release --compiler=dmd-2.111.0 --force
    dub build --build=release --compiler=ldc-1.41.0 --force

Also validate the repository's ordinary current compiler aliases where
available:

    dub build --build=release --compiler=dmd --force
    dub build --build=release --compiler=ldc2 --force

A failure caused only by an unavailable local alias is an environment issue,
not a numerical failure; record the actual compiler identity used.

Exit criterion:

- release builds succeed;
- no Pseudo-Mercator-specific release-only compile failure exists.

## G5B — repository regression

Run the standard repository checks on the baseline compilers:

    dub test --compiler=dmd-2.111.0 --force
    dub test --compiler=ldc-1.41.0 --force

    DC=dmd-2.111.0 tools/validate-api.sh
    DC=ldc-1.41.0 tools/validate-api.sh

    tools/validate-docs.sh

PM-G4 already ran the full six-compiler correctness matrix. G5B is a
release-acceptance regression check, not a second six-compiler qualification.

Exit criterion:

- repository tests remain green;
- public API contracts remain green;
- documentation contracts remain green.

## G5C — package and aggregate exposure

Validate the release-facing DUB/package boundary:

- `import geodesy;` exposes `PseudoMercator!T`;
- direct import of `geodesy.projection.pseudo_mercator` remains valid;
- the public package does not require PROJ, GeographicLib, raster/image, CRS,
  tile, or other unintended runtime dependencies;
- no research directory is part of the source path;
- the minimum frontend remains 2.111.0 unless separately changed and justified.

Use an external consumer smoke project where practical so this check is not
satisfied only by in-repository imports.

Exit criterion:

- package-level and direct-module consumer builds succeed;
- no unintended dependency or package-surface growth is found.

## G5D — research-only leakage audit

The production/public surface must not expose research-only concepts or helper
state.

In particular, verify that the accepted exclusions remain excluded:

    WebMercator alias
    ConformalProjectionFactors surface
    latitude-of-natural-origin parameter
    scale-factor-at-natural-origin parameter
    one-shot free forward/reverse helpers
    CRS abstraction / EPSG lookup
    tile / zoom / XYZ / TMS policy
    research differential observability fields

Research drivers, oracle code, corpus-generation logic, and PM-E/PM-G
qualification machinery may remain in research/validation/tooling locations,
but must not become runtime dependencies of the production module.

Exit criterion:

- no research-only public symbol or runtime dependency leaks into the package.

## G5E — platform assumptions

Record the platform on which the final local acceptance run is executed,
including:

- OS and architecture;
- DMD/LDC identities used for release builds;
- whether `real` is wider than `double`;
- any platform-specific observation affecting the accepted scalar contract.

PM-G5 does not claim a platform that has not actually been tested. Existing
cross-platform evidence from earlier accepted gates remains valid evidence and
need not be recreated unless PM-G5 changes production code.

Exit criterion:

- the release-facing documentation makes no unsupported platform claim;
- no new platform-dependent defect is observed.

## G5F — documentation consistency

Audit at minimum:

    README.md
    ROADMAP.md
    research/pseudo-mercator/RESEARCH.md
    research/pseudo-mercator/PM_F_PUBLIC_API.md
    research/pseudo-mercator/PM_G0_ENDPOINT_RESULTS.md
    research/pseudo-mercator/PM_G1_PRODUCTION_EXTRACTION.md
    research/pseudo-mercator/PM_G2_API_RUNTIME_RESULTS.md
    research/pseudo-mercator/PM_G3_EQUIVALENCE_RESULTS.md
    research/pseudo-mercator/PM_G4_COMPILER_MATRIX_RESULTS.md

Before final acceptance, release-facing documentation must describe
Pseudo-Mercator as accepted rather than merely active, while preserving the
method/CRS/tile-policy ownership boundary.

Exit criterion:

- no contradictory gate status remains;
- public documentation matches the implemented API and package surface.

## Final acceptance rule

PM-G5 passes only when G5A through G5F are supported by recorded evidence.

On PASS:

    Pseudo-Mercator ACCEPTED
    PM-G5 PASS

Then update the research status and ROADMAP accordingly. Integration into
`main`, PR creation/merge, versioning, or release remain separate actions and
must not be inferred from PM-G5 acceptance.

If PM-G5 exposes a production-code defect, fix that defect and rerun every
PM-G5 check affected by the change. Rerun PM-G4 only if the change can affect
compiler-dependent semantics or the previously qualified production/research
equivalence.
