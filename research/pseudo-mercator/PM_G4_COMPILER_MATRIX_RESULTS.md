# PM-G4 — Controlled compiler matrix results

Status: PASS

## Purpose

PM-G4 validates the accepted Pseudo-Mercator production implementation over the
controlled DMD/LDC compiler matrix after PM-G3 established production/research
equivalence.

The gate exercises, for every controlled compiler:

- public API contracts;
- PM-G2 API/runtime contracts;
- PM-G3 production/research equivalence;
- the full repository `dub test` suite.

The durable runner is:

    tools/validate-pseudo-mercator-compiler-matrix.sh

## Qualified compiler matrix

The completed run covered:

    DMD 2.111.0
    DMD 2.112.1
    DMD 2.113.0

    LDC 1.41.0
      frontend DMD 2.111
      LLVM 20.1.5

    LDC 1.42.0
      frontend DMD 2.112.1
      LLVM 21.1.8

    LDC 1.43.0
      frontend DMD 2.113
      LLVM 22.1.8

## Results

For every compiler in the matrix:

    public API contracts                    PASS
    PM-G2 API/runtime contract              PASS
    PM-G3 production/research equivalence   PASS
    full repository dub test                PASS

Every repository test run reported:

    22 modules passed unittests

The PM-G3 equivalence gate reported for every compiler:

    PASS: forward corpus/output/report byte-identical
    PASS: reverse corpus/output/report equivalent
    RESULT: PM-G3A PASS

The matrix summary was:

    controlled compilers: 6
    failed checks:        0
    RESULT: PM-G4 PASS

The runner exited successfully.

## Acceptance

PM-G4 is accepted.

The controlled compiler matrix found no compiler-dependent regression in the
accepted Pseudo-Mercator public API, runtime contract, qualified numerical
behaviour, production/research equivalence, or repository regression suite.

This result does not replace PM-G5. The remaining gate is platform / release /
regression acceptance, including release-facing packaging and documentation
consistency.

Next state:

    PM-G4 controlled compiler matrix              PASS
    PM-G5 platform / release / regression         ACTIVE
