# geodesy-d-research

Research, experiments, validation evidence, benchmarks, and historical design
work for [geodesy-d](https://github.com/alex-1974/geodesy-d).

This repository is intentionally separate from the production `geodesy-d`
package. Normal DUB consumers should not need to download research and
benchmark artefacts.

Research is evidence, not production API. Results are promoted deliberately
into `geodesy-d` through accepted design decisions, implementation, tests,
validation, and documentation.

## Relationship to geodesy-d

The initial snapshot was imported from:

- source repository: `alex-1974/geodesy-d`;
- source commit: `1acd53709cbf014608c250fcb372d0b52b4e751a`;
- selected source paths:
  - `research/**`;
  - `benchmarks/**`.

The production repository retains source code, active regression and release
validation, CI/release machinery, user documentation, accepted ADRs, and small
maintainer tools. Historical Git commits in `geodesy-d` are not rewritten.

## Verified initial snapshot

The imported corpus contains:

~~~text
116 files
1,280,863 bytes
~~~

Full path, file-mode, byte-size, and Git blob SHA comparison against the pinned
source commit passed with zero missing files, zero extra selected files, and
zero mismatches.

See [PROVENANCE.md](PROVENANCE.md) and
[SNAPSHOT_MANIFEST.tsv](SNAPSHOT_MANIFEST.tsv). Repository CI independently
rechecks the pinned snapshot manifest on every change.
