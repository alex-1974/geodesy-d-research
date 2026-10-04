#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys

import mpmath as mp


mp.mp.dps = 250


def parse_mp(value: str) -> mp.mpf:
    return mp.mpf(value)


def fmt(value: mp.mpf) -> str:
    return mp.nstr(value, 18)


def q_ulp(value: mp.mpf, mant_dig: int) -> mp.mpf:
    """
    Binary ULP size in the binade containing value.

    All q boundaries studied here are normal numbers.
    """
    exponent = int(
        mp.floor(
            mp.log(abs(value), 2)
        )
    )

    return mp.power(
        2,
        exponent - (mant_dig - 1),
    )


def forward_q(phi: mp.mpf) -> mp.mpf:
    """
    High-precision inverse of the inverse projection:

        q = asinh(tan(phi))

    Evaluated far above the precision of all scalar types under study.
    """
    with mp.workdps(400):
        return +mp.asinh(mp.tan(phi))


def load_representations(path: Path):
    lines = path.read_text(
        encoding="utf-8"
    ).splitlines()

    rows = {}

    for line in lines[1:]:
        if not line:
            continue

        fields = line.split("\t")

        if len(fields) != 6:
            raise RuntimeError(
                f"{path}: malformed row: {line}"
            )

        rows[fields[0]] = {
            "mant_dig": int(fields[1]),
            "positive_pole": parse_mp(fields[2]),
            "positive_interior": parse_mp(fields[3]),
            "negative_pole": parse_mp(fields[4]),
            "negative_interior": parse_mp(fields[5]),
        }

    return rows


def load_thresholds(path: Path):
    result = {}

    for line in path.read_text(
        encoding="utf-8"
    ).splitlines():
        if not line.startswith("THRESHOLD\t"):
            continue

        fields = line.split("\t")

        if len(fields) != 6:
            raise RuntimeError(
                f"{path}: malformed threshold row"
            )

        scalar = fields[1]
        candidate = fields[3]

        result[(scalar, candidate)] = {
            "positive": parse_mp(fields[4]),
            "negative": parse_mp(fields[5]),
        }

    return result


def classification(delta: mp.mpf) -> str:
    if delta == 0:
        return "exact"

    if delta < 0:
        return "EARLY"

    return "LATE"


def main():
    representations_path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "/tmp/pm-reverse-rounding-dmd.tsv"
    )

    thresholds_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else "/tmp/pm-reverse-dmd.tsv"
    )

    representations = load_representations(
        representations_path
    )

    thresholds = load_thresholds(
        thresholds_path
    )

    print(
        "=== THEORETICAL CORRECT-ROUNDING "
        "POLE BOUNDARIES ==="
    )

    boundaries = {}

    for scalar in ("float", "double", "real"):
        row = representations[scalar]

        positive_midpoint = (
            row["positive_pole"]
            + row["positive_interior"]
        ) / 2

        negative_midpoint = (
            row["negative_pole"]
            + row["negative_interior"]
        ) / 2

        positive_q = forward_q(
            positive_midpoint
        )

        negative_q = abs(
            forward_q(
                negative_midpoint
            )
        )

        boundaries[scalar] = {
            "positive": positive_q,
            "negative": negative_q,
        }

        print()
        print(
            f"{scalar}: mant_dig={row['mant_dig']}"
        )

        print(
            "  represented +pole:",
            fmt(row["positive_pole"]),
        )

        print(
            "  inner +neighbor:",
            fmt(row["positive_interior"]),
        )

        print(
            "  +midpoint:",
            fmt(positive_midpoint),
        )

        print(
            "  theoretical +q boundary:",
            fmt(positive_q),
        )

        print(
            "  theoretical -q boundary magnitude:",
            fmt(negative_q),
        )

        print(
            "  theoretical symmetry error:",
            fmt(
                abs(
                    positive_q
                    - negative_q
                )
            ),
        )

    print()
    print(
        "=== OBSERVED CANDIDATE THRESHOLD ERRORS ==="
    )

    for scalar in ("float", "double", "real"):
        mant_dig = representations[
            scalar
        ]["mant_dig"]

        print()
        print(f"{scalar}:")

        for candidate in (
            "R1",
            "R2",
            "R3",
            "R4",
        ):
            observed = thresholds[
                (scalar, candidate)
            ]

            target_pos = boundaries[
                scalar
            ]["positive"]

            target_neg = boundaries[
                scalar
            ]["negative"]

            delta_pos = (
                observed["positive"]
                - target_pos
            )

            delta_neg = (
                observed["negative"]
                - target_neg
            )

            pos_ulp = q_ulp(
                target_pos,
                mant_dig,
            )

            neg_ulp = q_ulp(
                target_neg,
                mant_dig,
            )

            symmetry = (
                observed["positive"]
                - observed["negative"]
            )

            print(
                f"  {candidate}:"
            )

            print(
                "    observed +:",
                fmt(observed["positive"]),
                classification(delta_pos),
            )

            print(
                "    delta +:",
                fmt(delta_pos),
                "q-ULP:",
                fmt(delta_pos / pos_ulp),
            )

            print(
                "    observed -:",
                fmt(observed["negative"]),
                classification(delta_neg),
            )

            print(
                "    delta -:",
                fmt(delta_neg),
                "q-ULP:",
                fmt(delta_neg / neg_ulp),
            )

            print(
                "    observed threshold asymmetry:",
                fmt(symmetry),
            )


if __name__ == "__main__":
    main()
