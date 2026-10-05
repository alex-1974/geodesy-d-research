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
