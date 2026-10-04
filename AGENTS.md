# Research Repository Rules

This repository is the research/evidence companion to
`alex-1974/geodesy-d`.

- Do not place production API code here.
- Preserve experiment inputs, outputs, provenance, raw evidence, and negative
  results.
- Record compiler, platform, library, and toolchain versions for reproducible
  experiments.
- Preserve exact source/probe hashes where they matter.
- Do not silently rewrite historical evidence.
- Production source, active regression/release gates, accepted ADRs, and user
  documentation belong in `geodesy-d`.
- A research result becomes production only through explicit promotion with
  implementation, tests, validation, and documentation.
- Benchmark fixtures and historical measurements may live here; small active
  benchmark driver tools may remain in the production repository and consume
  this checkout explicitly.
