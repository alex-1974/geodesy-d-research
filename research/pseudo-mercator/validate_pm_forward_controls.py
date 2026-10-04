#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys

import mpmath as mp


mp.mp.dps = 160

EXPECTED_COLUMNS = 20
CANDIDATES = ("F2", "F3", "F4", "F5")


def parse_mp(value: str) -> mp.mpf:
    value = value.strip().lower()

    if value == "nan" or value == "-nan":
        return mp.nan
    if value == "inf":
        return mp.inf
    if value == "-inf":
        return mp.ninf

    return mp.mpf(value)


def finite(value: mp.mpf) -> bool:
    return bool(mp.isfinite(value))


def ulp_at(value: mp.mpf, mant_dig: int) -> mp.mpf:
    value = abs(value)

    if value == 0:
        return mp.power(2, -(mant_dig - 1))

    exponent = int(mp.floor(mp.log(value, 2)))

    return mp.power(
        2,
        exponent - (mant_dig - 1),
    )


def fmt(value: mp.mpf) -> str:
    if mp.isnan(value):
        return "nan"

    if mp.isinf(value):
        return "+inf" if value > 0 else "-inf"

    return mp.nstr(value, 13)


def reference(phi: mp.mpf) -> mp.mpf:
    """
    High-precision normalized Pseudo-Mercator northing.

    Evaluate two analytical identities with much more precision than any D
    scalar under test. asinh(tan(phi)) is returned only after the independent
    log/tan identity agrees.
    """
    with mp.workdps(300):
        r1 = mp.asinh(mp.tan(phi))
        r2 = mp.log(mp.tan(mp.pi / 4 + phi / 2))

        difference = abs(r1 - r2)

        if difference > mp.mpf("1e-220"):
            raise RuntimeError(
                "oracle identities disagree for phi="
                + mp.nstr(phi, 60)
                + " difference="
                + mp.nstr(difference, 30)
            )

        return +r1


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
    lines = path.read_text(encoding="utf-8").splitlines()

    if not lines:
        raise RuntimeError(f"{path}: empty")

    header = lines[0].split("\t")

    if len(header) != EXPECTED_COLUMNS:
        raise RuntimeError(
            f"{path}: expected {EXPECTED_COLUMNS} columns, "
            f"found {len(header)}"
        )

    rows = []

    for line_number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")

        if len(fields) != EXPECTED_COLUMNS:
            raise RuntimeError(
                f"{path}:{line_number}: expected "
                f"{EXPECTED_COLUMNS} fields, found {len(fields)}"
            )

        rows.append(
            {
                "scalar": fields[0],
                "mant_dig": int(fields[1]),
                "case": fields[2],
                "phi": parse_mp(fields[3]),

                "F2+": parse_mp(fields[4]),
                "F2-": parse_mp(fields[5]),

                "F3+": parse_mp(fields[6]),
                "F3-": parse_mp(fields[7]),

                "F4+": parse_mp(fields[8]),
                "F4-": parse_mp(fields[9]),

                "F5+": parse_mp(fields[10]),
                "F5-": parse_mp(fields[11]),
            }
        )

    return rows


def range_name(phi: mp.mpf) -> str:
    degrees = abs(phi) * 180 / mp.pi

    if degrees <= mp.mpf("85.0511287798066"):
        return "<=WebMercatorQuad"

    if degrees <= 88:
        return "<=88deg"

    if degrees <= 89:
        return "<=89deg"

    return "full-open-pole"


def summarize_range(rows, scalar, label, predicate):
    subset = [
        row
        for row in rows
        if row["scalar"] == scalar
        and abs(row["phi"]) < mp.pi / 2
        and predicate(abs(row["phi"]) * 180 / mp.pi)
    ]

    if not subset:
        return

    mant_dig = subset[0]["mant_dig"]

    observations = {
        candidate: []
        for candidate in CANDIDATES
    }

    winners = {
        candidate: 0
        for candidate in CANDIDATES
    }

    ties = 0

    for row in subset:
        ref_pos = reference(row["phi"])
        ref_neg = -ref_pos

        per_observation = []

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

        for sign in ("+", "-"):
            errors = {
                candidate:
                    metrics(
                        row[candidate + sign],
                        ref_pos if sign == "+" else ref_neg,
                        mant_dig,
                    )[0]
                for candidate in CANDIDATES
            }

            best = min(errors.values())

            best_candidates = [
                candidate
                for candidate, error in errors.items()
                if error == best
            ]

            if len(best_candidates) == 1:
                winners[best_candidates[0]] += 1
            else:
                ties += 1

    print(f"  range {label}: rows={len(subset)}")

    for candidate in CANDIDATES:
        data = observations[candidate]

        finite_data = [
            item
            for item in data
            if finite(item[1])
        ]

        nonfinite = len(data) - len(finite_data)

        print(f"    {candidate}:")

        if not finite_data:
            print("      finite: 0")
            print(f"      nonfinite: {nonfinite}")
            continue

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

        print(
            "      worst abs:",
            fmt(worst_abs[1]),
            "@",
            worst_abs[0],
        )

        print(
            "      worst rel:",
            fmt(worst_rel[2]),
            "@",
            worst_rel[0],
        )

        print(
            "      worst ulp:",
            fmt(worst_ulp[3]),
            "@",
            worst_ulp[0],
        )

        print(
            "      nonfinite:",
            nonfinite,
        )

    print(
        "    unique wins:",
        " ".join(
            f"{candidate}={winners[candidate]}"
            for candidate in CANDIDATES
        ),
        f"ties={ties}",
    )


def summarize_compiler(name: str, rows):
    print()
    print(f"=== {name} ===")

    scalars = []

    for row in rows:
        if row["scalar"] not in scalars:
            scalars.append(row["scalar"])

    for scalar in scalars:
        scalar_rows = [
            row
            for row in rows
            if row["scalar"] == scalar
        ]

        valid = [
            row
            for row in scalar_rows
            if abs(row["phi"]) < mp.pi / 2
        ]

        invalid = [
            row
            for row in scalar_rows
            if abs(row["phi"]) >= mp.pi / 2
        ]

        print()
        print(
            f"{scalar}: mant_dig={scalar_rows[0]['mant_dig']} "
            f"valid={len(valid)} invalid={len(invalid)}"
        )

        for row in invalid:
            print(
                "  outside domain:",
                row["case"],
                "phi=" + mp.nstr(row["phi"], 30),
            )

        summarize_range(
            rows,
            scalar,
            "<=WebMercatorQuad",
            lambda deg:
                deg <= mp.mpf("85.0511287798066"),
        )

        summarize_range(
            rows,
            scalar,
            "<=88deg",
            lambda deg:
                deg <= 88,
        )

        summarize_range(
            rows,
            scalar,
            "<=89deg",
            lambda deg:
                deg <= 89,
        )

        summarize_range(
            rows,
            scalar,
            "full-open-pole",
            lambda deg: True,
        )


def compare_compilers(dmd, ldc):
    print()
    print("=== DMD / LDC CANDIDATE DIFFERENCES ===")

    if len(dmd) != len(ldc):
        raise RuntimeError("row-count mismatch")

    for candidate in CANDIDATES:
        differing = 0
        max_difference = mp.mpf(0)
        worst = None

        for left, right in zip(dmd, ldc):
            key_left = (
                left["scalar"],
                left["case"],
                left["phi"],
            )

            key_right = (
                right["scalar"],
                right["case"],
                right["phi"],
            )

            if key_left != key_right:
                raise RuntimeError(
                    "DMD/LDC row ordering mismatch"
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
                    difference = abs(a - b)

                    if difference > max_difference:
                        max_difference = difference
                        worst = (
                            left["scalar"],
                            left["case"],
                            sign,
                            a,
                            b,
                        )
                else:
                    worst = (
                        left["scalar"],
                        left["case"],
                        sign,
                        a,
                        b,
                    )
                    max_difference = mp.inf

        print(
            f"{candidate}: differing observations={differing}",
            f"max abs difference={fmt(max_difference)}",
        )

        if worst is not None:
            scalar, case, sign, a, b = worst

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
        else "/tmp/pm-forward-controls-dmd.tsv"
    )

    ldc_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else "/tmp/pm-forward-controls-ldc.tsv"
    )

    dmd = load(dmd_path)
    ldc = load(ldc_path)

    print(
        "rows:",
        f"DMD={len(dmd)}",
        f"LDC={len(ldc)}",
    )

    summarize_compiler("DMD", dmd)
    summarize_compiler("LDC", ldc)
    compare_compilers(dmd, ldc)


if __name__ == "__main__":
    main()
