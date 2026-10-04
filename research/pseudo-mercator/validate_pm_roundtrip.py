#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys

import mpmath as mp


mp.mp.dps = 160

EXPECTED_COLUMNS = 12


def parse_mp(value: str) -> mp.mpf:
    value = value.strip().lower()

    if value in ("nan", "-nan"):
        return mp.nan

    if value == "inf":
        return mp.inf

    if value == "-inf":
        return mp.ninf

    return mp.mpf(value)


def parse_bool(value: str) -> bool:
    if value == "true":
        return True

    if value == "false":
        return False

    raise ValueError(value)


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
        return mp.power(
            2,
            -(mant_dig - 1),
        )

    exponent = int(
        mp.floor(
            mp.log(value, 2)
        )
    )

    return mp.power(
        2,
        exponent - (mant_dig - 1),
    )


def load(path: Path):
    lines = path.read_text(
        encoding="utf-8"
    ).splitlines()

    if not lines:
        raise RuntimeError(
            f"{path}: empty"
        )

    header = lines[0].split("\t")

    if len(header) != EXPECTED_COLUMNS:
        raise RuntimeError(
            f"{path}: expected "
            f"{EXPECTED_COLUMNS} header columns, "
            f"found {len(header)}"
        )

    rows = []

    for line_number, line in enumerate(
        lines[1:],
        2,
    ):
        fields = line.split("\t")

        if len(fields) != EXPECTED_COLUMNS:
            raise RuntimeError(
                f"{path}:{line_number}: expected "
                f"{EXPECTED_COLUMNS} fields, "
                f"found {len(fields)}"
            )

        rows.append(
            {
                "path": fields[0],
                "scalar": fields[1],
                "mant_dig": int(fields[2]),
                "case": fields[3],
                "input": parse_mp(fields[4]),
                "intermediate": parse_mp(fields[5]),
                "returned": parse_mp(fields[6]),
                "abs_error": parse_mp(fields[7]),
                "exact_return": parse_bool(fields[8]),
                "intermediate_finite":
                    parse_bool(fields[9]),
                "returned_finite":
                    parse_bool(fields[10]),
                "intermediate_exact_pole":
                    parse_bool(fields[11]),
            }
        )

    return rows


def compare_compilers(dmd, ldc):
    print("=== COMPILER OUTPUT ===")

    if len(dmd) != len(ldc):
        raise RuntimeError(
            "DMD/LDC row-count mismatch"
        )

    differing = 0
    worst = mp.mpf(0)
    worst_key = None

    for left, right in zip(dmd, ldc):
        key_left = (
            left["path"],
            left["scalar"],
            left["case"],
            left["input"],
        )

        key_right = (
            right["path"],
            right["scalar"],
            right["case"],
            right["input"],
        )

        if key_left != key_right:
            raise RuntimeError(
                "DMD/LDC ordering mismatch"
            )

        for field in (
            "intermediate",
            "returned",
            "abs_error",
        ):
            a = left[field]
            b = right[field]

            if mp.isnan(a) and mp.isnan(b):
                continue

            if a == b:
                continue

            differing += 1

            if finite(a) and finite(b):
                difference = abs(a - b)

                if difference > worst:
                    worst = difference
                    worst_key = (
                        key_left,
                        field,
                        a,
                        b,
                    )
            else:
                worst = mp.inf
                worst_key = (
                    key_left,
                    field,
                    a,
                    b,
                )

    print(
        "differing numeric fields:",
        differing,
    )

    print(
        "max absolute difference:",
        fmt(worst),
    )

    if worst_key is not None:
        key, field, a, b = worst_key

        print(
            "worst:",
            key,
            field,
            "DMD=" + fmt(a),
            "LDC=" + fmt(b),
        )


def phi_range(
    row,
    maximum_degrees: mp.mpf | None,
):
    phi = abs(row["input"])

    if phi >= mp.pi / 2:
        return False

    if maximum_degrees is None:
        return True

    degrees = (
        phi * 180 / mp.pi
    )

    return degrees <= maximum_degrees


def summarize_phi_range(
    rows,
    scalar,
    label,
    maximum_degrees,
):
    subset = [
        row
        for row in rows
        if row["path"] == "PHI"
        and row["scalar"] == scalar
        and phi_range(
            row,
            maximum_degrees,
        )
    ]

    if not subset:
        return

    mant_dig = subset[0]["mant_dig"]

    exact = sum(
        row["exact_return"]
        for row in subset
    )

    finite_rows = [
        row
        for row in subset
        if row["returned_finite"]
    ]

    worst_abs = max(
        finite_rows,
        key=lambda row:
            row["abs_error"],
    )

    worst_ulp = max(
        finite_rows,
        key=lambda row:
            row["abs_error"]
            / ulp_at(
                row["input"],
                mant_dig,
            )
        if row["input"] != 0
        else row["abs_error"],
    )

    worst_ulp_value = (
        worst_ulp["abs_error"]
        / ulp_at(
            worst_ulp["input"],
            mant_dig,
        )
        if worst_ulp["input"] != 0
        else worst_ulp["abs_error"]
    )

    print(
        f"  PHI {label}: "
        f"rows={len(subset)} "
        f"exact={exact}"
    )

    print(
        "    worst abs:",
        fmt(worst_abs["abs_error"]),
        "@",
        worst_abs["case"],
    )

    print(
        "    worst input-ULP:",
        fmt(worst_ulp_value),
        "@",
        worst_ulp["case"],
    )


def q_for_degrees(degrees):
    with mp.workdps(200):
        phi = mp.radians(
            mp.mpf(str(degrees))
        )

        return +mp.asinh(
            mp.tan(phi)
        )


def summarize_q_range(
    rows,
    scalar,
    label,
    maximum_q,
):
    subset = [
        row
        for row in rows
        if row["path"] == "Q"
        and row["scalar"] == scalar
    ]

    if not subset:
        return

    mant_dig = subset[0]["mant_dig"]

    if maximum_q is not None:
        margin = (
            4
            * ulp_at(
                maximum_q,
                mant_dig,
            )
        )

        subset = [
            row
            for row in subset
            if abs(row["input"])
            <= maximum_q + margin
        ]

    saturated = [
        row
        for row in subset
        if row["intermediate_exact_pole"]
    ]

    invertible = [
        row
        for row in subset
        if not row["intermediate_exact_pole"]
        and row["returned_finite"]
    ]

    exact = sum(
        row["exact_return"]
        for row in invertible
    )

    print(
        f"  Q {label}: "
        f"rows={len(subset)} "
        f"invertible={len(invertible)} "
        f"saturated={len(saturated)} "
        f"exact={exact}"
    )

    if not invertible:
        return

    worst_abs = max(
        invertible,
        key=lambda row:
            row["abs_error"],
    )

    worst_ulp = max(
        invertible,
        key=lambda row:
            (
                row["abs_error"]
                / ulp_at(
                    row["input"],
                    mant_dig,
                )
            )
            if row["input"] != 0
            else row["abs_error"],
    )

    worst_ulp_value = (
        worst_ulp["abs_error"]
        / ulp_at(
            worst_ulp["input"],
            mant_dig,
        )
        if worst_ulp["input"] != 0
        else worst_ulp["abs_error"]
    )

    print(
        "    worst invertible abs:",
        fmt(worst_abs["abs_error"]),
        "@",
        worst_abs["case"],
    )

    print(
        "    worst invertible input-ULP:",
        fmt(worst_ulp_value),
        "@",
        worst_ulp["case"],
    )


def summarize_q(rows, scalar):
    q_web = mp.pi

    q_88 = q_for_degrees(
        88
    )

    q_89 = q_for_degrees(
        89
    )

    summarize_q_range(
        rows,
        scalar,
        "<=WebMercatorQuad",
        q_web,
    )

    summarize_q_range(
        rows,
        scalar,
        "<=88deg",
        q_88,
    )

    summarize_q_range(
        rows,
        scalar,
        "<=89deg",
        q_89,
    )

    summarize_q_range(
        rows,
        scalar,
        "full-before-saturation",
        None,
    )

    saturated = [
        row
        for row in rows
        if row["path"] == "Q"
        and row["scalar"] == scalar
        and row["intermediate_exact_pole"]
    ]

    print(
        "    post-saturation rows:",
        len(saturated),
        "(not valid Q->phi->Q error observations)",
    )

def summarize(rows):
    print()
    print("=== ROUND-TRIP SUMMARY ===")

    for scalar in (
        "float",
        "double",
        "real",
    ):
        print()
        print(f"{scalar}:")

        summarize_phi_range(
            rows,
            scalar,
            "<=WebMercatorQuad",
            mp.mpf(
                "85.0511287798066"
            ),
        )

        summarize_phi_range(
            rows,
            scalar,
            "<=88deg",
            mp.mpf("88"),
        )

        summarize_phi_range(
            rows,
            scalar,
            "<=89deg",
            mp.mpf("89"),
        )

        summarize_phi_range(
            rows,
            scalar,
            "full-open-pole",
            None,
        )

        summarize_q(
            rows,
            scalar,
        )


def main():
    dmd_path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "/tmp/pm-roundtrip-dmd.tsv"
    )

    ldc_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else "/tmp/pm-roundtrip-ldc.tsv"
    )

    dmd = load(dmd_path)
    ldc = load(ldc_path)

    print(
        "rows:",
        f"DMD={len(dmd)}",
        f"LDC={len(ldc)}",
    )

    compare_compilers(
        dmd,
        ldc,
    )

    summarize(dmd)


if __name__ == "__main__":
    main()
