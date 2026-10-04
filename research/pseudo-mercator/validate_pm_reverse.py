#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import math
import sys

import mpmath as mp


mp.mp.dps = 220

EXPECTED_COLUMNS = 24
CANDIDATES = ("R1", "R2", "R3", "R4")


def parse_mp(value: str) -> mp.mpf:
    value = value.strip().lower()

    if value in ("nan", "-nan"):
        return mp.nan
    if value == "inf":
        return mp.inf
    if value == "-inf":
        return mp.ninf

    return mp.mpf(value)


def finite(value: mp.mpf) -> bool:
    return bool(mp.isfinite(value))


def fmt(value: mp.mpf) -> str:
    if mp.isnan(value):
        return "nan"
    if mp.isinf(value):
        return "+inf" if value > 0 else "-inf"

    return mp.nstr(value, 14)


def ulp_at(value: mp.mpf, mant_dig: int) -> mp.mpf:
    value = abs(value)

    if value == 0:
        return mp.power(2, -(mant_dig - 1))

    exponent = int(mp.floor(mp.log(value, 2)))

    return mp.power(
        2,
        exponent - (mant_dig - 1),
    )


def reference(q: mp.mpf) -> mp.mpf:
    """
    Stable high-precision Gudermannian inverse.

    Avoid exp(+large) and sinh(+large):

      q >= 0:
          phi = pi/2 - 2 atan(exp(-q))

      q < 0:
          phi = -pi/2 + 2 atan(exp(q))
    """
    with mp.workdps(350):
        if q == 0:
            return mp.mpf(0)

        if q > 0:
            return +(
                mp.pi / 2
                - 2 * mp.atan(mp.exp(-q))
            )

        return +(
            -mp.pi / 2
            + 2 * mp.atan(mp.exp(q))
        )


def metrics(value: mp.mpf, ref: mp.mpf, mant_dig: int):
    if not finite(value):
        return mp.inf, mp.inf, mp.inf

    absolute = abs(value - ref)

    relative = (
        absolute / abs(ref)
        if ref != 0
        else absolute
    )

    ulp = absolute / ulp_at(ref, mant_dig)

    return absolute, relative, ulp


def load(path: Path):
    rows = []
    thresholds = []

    lines = path.read_text(
        encoding="utf-8"
    ).splitlines()

    header_seen = False

    for line_number, line in enumerate(lines, 1):
        if not line:
            continue

        fields = line.split("\t")

        if fields[0] == "THRESHOLD":
            if len(fields) != 6:
                raise RuntimeError(
                    f"{path}:{line_number}: malformed threshold"
                )

            thresholds.append(
                {
                    "scalar": fields[1],
                    "mant_dig": int(fields[2]),
                    "candidate": fields[3],
                    "positive": parse_mp(fields[4]),
                    "negative": parse_mp(fields[5]),
                }
            )

            continue

        if not header_seen:
            if len(fields) != EXPECTED_COLUMNS:
                raise RuntimeError(
                    f"{path}:{line_number}: expected "
                    f"{EXPECTED_COLUMNS} header columns, "
                    f"found {len(fields)}"
                )

            header_seen = True
            continue

        if len(fields) != EXPECTED_COLUMNS:
            raise RuntimeError(
                f"{path}:{line_number}: expected "
                f"{EXPECTED_COLUMNS} fields, "
                f"found {len(fields)}"
            )

        rows.append(
            {
                "scalar": fields[0],
                "mant_dig": int(fields[1]),
                "case": fields[2],
                "q": parse_mp(fields[3]),

                "R1+": parse_mp(fields[4]),
                "R1-": parse_mp(fields[5]),

                "R2+": parse_mp(fields[6]),
                "R2-": parse_mp(fields[7]),

                "R3+": parse_mp(fields[8]),
                "R3-": parse_mp(fields[9]),

                "R4+": parse_mp(fields[10]),
                "R4-": parse_mp(fields[11]),
            }
        )

    return rows, thresholds


def summarize_scalar(rows, scalar):
    subset = [
        row
        for row in rows
        if row["scalar"] == scalar
    ]

    mant_dig = subset[0]["mant_dig"]

    print()
    print(
        f"{scalar}: mant_dig={mant_dig} "
        f"rows={len(subset)}"
    )

    observations = {
        candidate: []
        for candidate in CANDIDATES
    }

    wins = {
        candidate: 0
        for candidate in CANDIDATES
    }

    ties = 0

    for row in subset:
        q = row["q"]

        ref_pos = reference(q)
        ref_neg = reference(-q)

        errors = {}

        for candidate in CANDIDATES:
            pos = metrics(
                row[candidate + "+"],
                ref_pos,
                mant_dig,
            )

            neg = metrics(
                row[candidate + "-"],
                ref_neg,
                mant_dig,
            )

            observations[candidate].append(
                (row["case"] + " +",) + pos
            )

            observations[candidate].append(
                (row["case"] + " -",) + neg
            )

            errors[candidate + "+"] = pos[0]
            errors[candidate + "-"] = neg[0]

        for sign in ("+", "-"):
            candidates = {
                candidate:
                    errors[candidate + sign]
                for candidate in CANDIDATES
            }

            best = min(candidates.values())

            best_names = [
                name
                for name, error in candidates.items()
                if error == best
            ]

            if len(best_names) == 1:
                wins[best_names[0]] += 1
            else:
                ties += 1

    for candidate in CANDIDATES:
        data = observations[candidate]

        finite_data = [
            item
            for item in data
            if finite(item[1])
        ]

        nonfinite = (
            len(data) - len(finite_data)
        )

        worst_abs = max(
            finite_data,
            key=lambda item: item[1],
        )

        worst_rel = max(
            finite_data,
            key=lambda item: item[2],
        )

        worst_ulp = max(
            finite_data,
            key=lambda item: item[3],
        )

        print(f"  {candidate}:")
        print(
            "    worst abs:",
            fmt(worst_abs[1]),
            "@",
            worst_abs[0],
        )
        print(
            "    worst rel:",
            fmt(worst_rel[2]),
            "@",
            worst_rel[0],
        )
        print(
            "    worst ulp:",
            fmt(worst_ulp[3]),
            "@",
            worst_ulp[0],
        )
        print(
            "    nonfinite:",
            nonfinite,
        )

    print(
        "  unique wins:",
        " ".join(
            f"{candidate}={wins[candidate]}"
            for candidate in CANDIDATES
        ),
        f"ties={ties}",
    )


def summarize_thresholds(thresholds):
    print()
    print("=== OBSERVED EXACT-POLE THRESHOLDS ===")

    for item in thresholds:
        print(
            item["scalar"],
            item["candidate"],
            "positive=" + fmt(item["positive"]),
            "negative=" + fmt(item["negative"]),
        )


def compare_compilers(dmd_rows, ldc_rows):
    print()
    print("=== DMD / LDC DIFFERENCES ===")

    if len(dmd_rows) != len(ldc_rows):
        raise RuntimeError(
            "DMD/LDC row-count mismatch"
        )

    for candidate in CANDIDATES:
        differing = 0
        worst = mp.mpf(0)
        worst_key = None

        for left, right in zip(
            dmd_rows,
            ldc_rows,
        ):
            key_left = (
                left["scalar"],
                left["case"],
                left["q"],
            )

            key_right = (
                right["scalar"],
                right["case"],
                right["q"],
            )

            if key_left != key_right:
                raise RuntimeError(
                    "DMD/LDC ordering mismatch"
                )

            for sign in ("+", "-"):
                a = left[candidate + sign]
                b = right[candidate + sign]

                if mp.isnan(a) and mp.isnan(b):
                    continue

                if a == b:
                    continue

                differing += 1

                if finite(a) and finite(b):
                    diff = abs(a - b)

                    if diff > worst:
                        worst = diff
                        worst_key = (
                            left["scalar"],
                            left["case"],
                            sign,
                            a,
                            b,
                        )
                else:
                    worst = mp.inf
                    worst_key = (
                        left["scalar"],
                        left["case"],
                        sign,
                        a,
                        b,
                    )

        print(
            f"{candidate}: differing={differing} "
            f"max_abs={fmt(worst)}"
        )

        if worst_key is not None:
            scalar, case, sign, a, b = worst_key

            print(
                "  worst:",
                scalar,
                case,
                sign,
                "DMD=" + fmt(a),
                "LDC=" + fmt(b),
            )


def main():
    dmd_path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "/tmp/pm-reverse-dmd.tsv"
    )

    ldc_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else "/tmp/pm-reverse-ldc.tsv"
    )

    dmd_rows, dmd_thresholds = load(
        dmd_path
    )

    ldc_rows, ldc_thresholds = load(
        ldc_path
    )

    print(
        "rows:",
        f"DMD={len(dmd_rows)}",
        f"LDC={len(ldc_rows)}",
    )

    for scalar in ("float", "double", "real"):
        summarize_scalar(
            dmd_rows,
            scalar,
        )

    summarize_thresholds(
        dmd_thresholds
    )

    compare_compilers(
        dmd_rows,
        ldc_rows,
    )


if __name__ == "__main__":
    main()
