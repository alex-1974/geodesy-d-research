# GEO-G provenance — platform/compiler and D `real` width

## Status

**PASS**

GEO-G closes the final mandatory validation gate for the initial
`Geodesic!T` direct/inverse surface.

No production numerical source was changed to obtain this result.

## Accepted GitHub Actions run

- repository: `alex-1974/geodesy-d`
- source branch: `validation/geodesics-platform`
- source commit: `95f851cf0704386a34fc1cf84de4c8c5db5e5031`
- workflow: `Geodesic platform matrix`
- workflow path: `.github/workflows/geodesic-platform-matrix.yml`
- run id: `35442370160`
- run number: `2`
- event: `push`
- start: `2026-09-19T12:16:00Z`
- completion: `2026-09-19T12:17:46Z`
- conclusion: `success`

GitHub run URL:

```text
https://github.com/alex-1974/geodesy-d/actions/runs/35442370160
```

## Mandatory matrix

| Target | Job ID | Actual fingerprint | D `real` | Result |
|---|---:|---|---|---|
| Linux x86_64 / LDC 1.41.0 | 105895294943 | Linux / x86_64 / LDC | sizeof 16, mantissa 64 | PASS |
| Linux AArch64 / LDC 1.41.0 | 105895295082 | Linux / AArch64 / LDC | sizeof 16, mantissa 113 | PASS |
| Windows x86_64 / LDC 1.41.0 | 105895294997 | Windows / x86_64 / LDC | sizeof 8, mantissa 53 | PASS |
| macOS AArch64 / LDC 1.41.0 | 105895295002 | macOS / AArch64 / LDC | sizeof 8, mantissa 53 | PASS |
| macOS x86_64 / LDC 1.41.0 | 105895295034 | macOS / x86_64 / LDC | sizeof 16, mantissa 64 | PASS |
| Linux x86_64 / DMD 2.111.0 | 105895295003 | Linux / x86_64 / DMD | sizeof 16, mantissa 64 | PASS |

Every mandatory job passed:

- library unit tests;
- aggregate public API contract;
- GEO-A portable semantic gate;
- portable analytical/property gate;
- D `real` precision-preservation gate;
- GEO-F API/runtime gate.

## D `real` width evidence

The accepted matrix covers all widths required by the validation plan:

```text
mant_dig == 53
mant_dig == 64
mant_dig == 113
```

Targets with `real.mant_dig > double.mant_dig` additionally execute
`validation/geodesic_real_precision_validation.d`.

The 64-bit-mantissa and 113-bit-mantissa targets both passed the direct and
inverse witnesses in which distinct D `real` inputs collapse to the same
materialized binary64 representation while the public `real` geodesic result
retains the distinction.

The 53-bit-mantissa targets correctly report that `real` has no precision
beyond `double` on that ABI.

## Windows/AArch64 informational runner

The workflow also contains an informational:

```text
Windows AArch64 / LDC 1.41.0
runner: windows-11-arm
job id: 105895295025
```

The job succeeded, but the compiled D executable reported:

```text
os=Windows
architecture=x86_64
compiler=LDC
real.mant_dig=53
```

It therefore appears to have exercised the x86_64 target on the ARM runner and
is **not counted as native Windows/AArch64 evidence**.

This does not affect GEO-G acceptance because Windows/AArch64 is explicitly
informational in the validation contract.

## Accepted evidence file

- `research/geodesics/data/geog_acceptance_20260919T121600Z.log`
- SHA-256: `6c2a35b2fb1065a3f0d587e8b2ec7ba6432acb752cbe0e9901888496a1a16f4e`

## Validation-source hashes

```text
46d8217a3fbe9a7bc40679000f1605997fc8947bba6d4c48b0b3c9c53eba5eec  .github/workflows/geodesic-platform-matrix.yml
65247a7448e59368b4b72548889c8f9a0b6edbdfb49949bbddfa31d0ba127b55  validation/geodesic_portable_semantics.d
81dcb7f242ddc7581ec31adf82037780fbc2a8a441f5d6e8c6bb0a85873a2fd1  validation/geodesic_portable_properties.d
fe981d77a5bedb5f5c6f945fc476a0a2697c0efc07af3bad2188383e3a906f34  validation/geodesic_real_precision_validation.d
270c3c199138d8003e4183ed5ec3289bc57a19e7aeb5ece8535fe4dfe3b835eb  validation/geodesic_api_runtime_validation.d
b422a9a4e59d722da4a2ea2d37919fb7b942b4ef93b15b0feb56435d02d8fe97  validation/api/public_api_contract.d
6aa8d2ef01a524fe36351045d2b722ddc0b0d838c93731d718a07bfc7326ab77  validation/api/named_arguments_contract.d
```

## Acceptance conclusion

The required portable platform/compiler matrix is complete.

The accepted evidence establishes:

- DMD and LDC coverage;
- Linux, Windows and macOS mandatory coverage;
- x86_64 and AArch64 mandatory architecture coverage;
- D `real` mantissa widths 53, 64 and 113;
- retained wider-than-binary64 arithmetic on the 64- and 113-bit-mantissa
  targets;
- unchanged checked API/runtime semantics across all mandatory targets.

Therefore:

```text
GEO-G = PASS
```

With GEO-A through GEO-G now all PASS, the technical validation program required
by ADR-0008 is complete. Moving ADR-0008 from `Proposed` to `Accepted`
remains a separate explicit governance decision.
