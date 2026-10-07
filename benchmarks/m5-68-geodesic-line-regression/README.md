# M5 #68 — GeodesicLine hot-path regression benchmark

This benchmark compares the existing distance-only
`GeodesicLine!double.tryPosition(distance, result)` hot path before and after
the M5 #68 refactor.

It deliberately reuses the unchanged M2 benchmark source:

~~~text
benchmarks/geodesic-line/source/app.d
~~~

Thus baseline and candidate execute the same deterministic distance corpus,
fingerprint, warmups, sample count, compiler flags, CPU affinity, and process
structure. Only the linked geodesy-d source tree changes.

## Required checkouts

- baseline: geodesy-d `develop` at the pre-#68 commit;
- candidate: geodesy-d PR #100 head.

For the current qualification:

~~~text
baseline  0d4da128bae12220cf6ea27391fadb3305a532bb
candidate 87771bde34a1cefed66634d8b4019f30e85ba561
~~~

## Controlled XPS run

~~~bash
GEODESY_D_BASELINE_REPO=/path/to/geodesy-d-baseline \
GEODESY_D_CANDIDATE_REPO=/path/to/geodesy-d-candidate \
DC=ldc2 \
M5_68_CPU=2 \
M5_68_RUNS=12 \
bash benchmarks/m5-68-geodesic-line-regression/run.sh
~~~

The runner compiles both trees with:

~~~text
-release -O3 -enable-inlining -mcpu=native
~~~

and executes each binary in separate pinned processes. Each process retains the
M2 benchmark's 8 warmups, 24 timed traversals, and 65,536 positions per
traversal.

A default 3% noise budget is used only as an automated regression alarm. The
reported raw medians and percentage difference remain the evidence.


## One-command XPS qualification

With the normal sibling checkouts

~~~text
libs/geodesy-d
libs/geodesy-d-research
~~~

run from `geodesy-d-research`:

~~~bash
DC=ldc2 \
M5_68_CPU=2 \
M5_68_RUNS=12 \
bash benchmarks/m5-68-geodesic-line-regression/run-xps.sh
~~~

The wrapper fetches the production repository, creates detached temporary
worktrees at the exact baseline/candidate SHAs above, runs the controlled
comparison, and removes the worktrees afterwards.

Override the production checkout only when necessary:

~~~bash
GEODESY_D_REPO=/path/to/geodesy-d \
bash benchmarks/m5-68-geodesic-line-regression/run-xps.sh
~~~
