# TM output specialization research

This experiment compares geodesy-d `develop` with the compile-time forward
output specialization in PR #61.

The candidate introduces an internal output family:

- position only;
- factors only;
- position + factors (available to the internal kernel family).

The public API is unchanged. The primary goal is to remove duplicate
trigonometric and conformal-state preparation from `tryForwardFactors` while
preserving a lean position-only path.

## LDC 1.41.0 CI evidence

The same benchmark source was compiled separately against:

- baseline: `faa587d6d7469c4e1e94edc42575a0c7dc164b99` (`develop`);
- candidate: `08d047ae41ae8707c8d8308f0e12b0851aecd610`.

Median of three process medians:

| corpus | baseline forward | candidate forward | change | baseline factors | candidate factors | change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| UTM-like | 332.410 ns | 281.635 ns | -15.27% | 727.124 ns | 330.365 ns | -54.57% |
| ordinary | 335.364 ns | 284.656 ns | -15.12% | 733.234 ns | 333.594 ns | -54.50% |
| wide | 339.703 ns | 288.934 ns | -14.95% | 747.882 ns | 338.647 ns | -54.72% |

The factor result is the architectural signal: factor evaluation is about
2.20x faster because it no longer performs a complete forward projection and
then recomputes latitude/longitude trigonometry, conformal tau, denominator,
and xi'/eta'.

The forward-only improvement was not an explicit design target. It is
consistent across all three corpora and may be caused by the smaller,
compile-time-specialized working path being easier for LDC to inline and
optimize. It must be reproduced on the controlled XPS benchmark machine before
being treated as a release performance claim.

## Acceptance direction

Keep the candidate only if:

1. all existing TM/API/PROJ/platform gates remain green;
2. XPS measurements reproduce a material factor-speed improvement;
3. forward-only performance does not regress;
4. code size remains reasonable;
5. no public runtime output-mask API is introduced.

The intended architecture remains: public semantic operations, internal
compile-time output specialization.


## XPS candidate run

Candidate commit:

`08d047ae41ae8707c8d8308f0e12b0851aecd610`

Seven independent process runs on the project XPS with LDC 1.41.0 produced
these medians of the process medians:

| corpus | forward ns/op | factors ns/op |
| --- | ---: | ---: |
| UTM-like | 258.972 | 345.380 |
| ordinary | 272.662 | 357.697 |
| wide | 283.813 | 370.166 |

Observed process-median ranges:

| corpus | forward range | factors range |
| --- | --- | --- |
| UTM-like | 251.398 .. 274.994 | 333.685 .. 365.472 |
| ordinary | 255.078 .. 285.883 | 338.269 .. 374.939 |
| wide | 275.287 .. 295.801 | 362.189 .. 388.409 |

This candidate-only run is not sufficient for an XPS speedup claim. A second
run of the identical harness against the exact develop baseline is required so
both sides share the same machine, compiler, affinity, governor, turbo state,
and benchmark source.


## XPS baseline comparison

The same harness was then run seven times against the exact develop baseline
`faa587d6d7469c4e1e94edc42575a0c7dc164b99` on the same XPS.

Median of seven process medians:

| corpus | baseline forward | candidate forward | forward change | baseline factors | candidate factors | factors change | factors speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| UTM-like | 265.393 ns | 258.972 ns | -2.42% | 610.260 ns | 345.380 ns | -43.40% | 1.767x |
| ordinary | 278.479 ns | 272.662 ns | -2.09% | 631.073 ns | 357.697 ns | -43.32% | 1.764x |
| wide | 289.526 ns | 283.813 ns | -1.97% | 662.238 ns | 370.166 ns | -44.10% | 1.789x |

The final wide-baseline process showed an obvious transient slowdown
(353.735 ns forward / 753.333 ns factors), but the median-of-seven comparison
is insensitive to that outlier.

The XPS result confirms the intended architectural benefit:

- factor evaluation is consistently about 43--44% faster, or about 1.77x;
- forward-only does not regress and is about 2% faster in this environment;
- the gain reproduces independently of the GitHub-hosted runner, although the
  absolute CI speedup was larger.

This is sufficient performance evidence to keep the internal compile-time
forward-output specialization, subject to the normal merge gates and code-size
review.
