#!/usr/bin/env python3

from __future__ import annotations

import math
from pathlib import Path
import sys

import mpmath as mp


mp.mp.dps = 120

EXPECTED_COLUMNS = 16


def parse_mp(value: str) -> mp.mpf:
    value = value.strip().lower()

    if value == "nan":
        return mp.nan
    if value == "inf":
        return mp.inf
    if value == "-inf":
        return mp.ninf

    return mp.mpf(value)


def is_finite(value: mp.mpf) -> bool:
    return bool(mp.isfinite(value))


def ulp_at(value: mp.mpf, mant_dig: int) -> mp.mpf:
    """
    Return the spacing of a normal binary floating-point format having
    mant_dig significant binary digits in the binade containing value.

    All PM-B oracle outputs are far from the subnormal range.
    """
    value = abs(value)

    if value == 0:
        return mp.power(2, -(mant_dig - 1))

    exponent = int(mp.floor(mp.log(value, 2)))

    return mp.power(
        2,
        exponent - (mant_dig - 1),
    )


def error_metrics(
    candidate: mp.mpf,
    reference: mp.mpf,
    mant_dig: int,
):
    if not is_finite(candidate):
        return mp.inf, mp.inf, mp.inf

    absolute = abs(candidate - reference)

    relative = (
        absolute / abs(reference)
        if reference != 0
        else absolute
    )

    ulp_scaled = absolute / ulp_at(reference, mant_dig)

    return absolute, relative, ulp_scaled


def fmt(value: mp.mpf) -> str:
    if mp.isnan(value):
        return "nan"
    if mp.isinf(value):
        return "+inf" if value > 0 else "-inf"

    return mp.nstr(value, 12)


def load(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()

    if not lines:
        raise RuntimeError(f"{path}: empty file")

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
                "f1_pos": parse_mp(fields[4]),
                "f1_neg": parse_mp(fields[5]),
                "f2_pos": parse_mp(fields[6]),
                "f2_neg": parse_mp(fields[7]),
                "f1_odd": parse_mp(fields[12]),
                "f2_odd": parse_mp(fields[13]),
            }
        )

    return rows


def validate_oracle_identity(phi: mp.mpf):
    """
    Independently evaluate both analytical identities with extra working
    precision.

    Near +/-pi/2 the log/tan identity loses decimal digits through the
    pi/4 + phi/2 addition even in arbitrary precision. That is exactly the
    numerical behaviour under study, so the oracle self-check must use
    substantially more precision than the candidate formats.

    The returned reference uses asinh(tan(phi)); the log/tan evaluation is
    retained only as an independent analytical-identity check.
    """
    with mp.workdps(250):
        by_asinh = mp.asinh(mp.tan(phi))
        by_log = mp.log(mp.tan(mp.pi / 4 + phi / 2))

        difference = abs(by_asinh - by_log)

        if difference > mp.mpf("1e-180"):
            raise RuntimeError(
                "high-precision oracle identities disagree for "
                f"phi={mp.nstr(phi, 50)}: "
                f"difference={mp.nstr(difference, 20)}"
            )

        return +by_asinh


def summarize(rows):
    scalars = []

    for row in rows:
        if row["scalar"] not in scalars:
            scalars.append(row["scalar"])

    total_valid = 0
    total_invalid = 0

    print("=== HIGH-PRECISION FORWARD ORACLE ===")

    for scalar in scalars:
        subset = [r for r in rows if r["scalar"] == scalar]
        mant_dig = subset[0]["mant_dig"]

        valid = []
        invalid = []

        for row in subset:
            if abs(row["phi"]) < mp.pi / 2:
                valid.append(row)
            else:
                invalid.append(row)

        total_valid += len(valid)
        total_invalid += len(invalid)

        print()
        print(
            f"{scalar}: mant_dig={mant_dig} "
            f"valid={len(valid)} invalid={len(invalid)}"
        )

        if invalid:
            print("  outside mathematical open-pole domain:")
            for row in invalid:
                relation = (
                    "above +pi/2"
                    if row["phi"] >= mp.pi / 2
                    else "below -pi/2"
                )

                print(
                    "   ",
                    row["case"],
                    relation,
                    "phi=" + mp.nstr(row["phi"], 30),
                )

        observations = {
            "F1": [],
            "F2": [],
        }

        closer = {
            "F1": 0,
            "F2": 0,
            "tie": 0,
        }

        for row in valid:
            reference_pos = validate_oracle_identity(row["phi"])
            reference_neg = -reference_pos

            f1_pos = error_metrics(
                row["f1_pos"],
                reference_pos,
                mant_dig,
            )
            f1_neg = error_metrics(
                row["f1_neg"],
                reference_neg,
                mant_dig,
            )
            f2_pos = error_metrics(
                row["f2_pos"],
                reference_pos,
                mant_dig,
            )
            f2_neg = error_metrics(
                row["f2_neg"],
                reference_neg,
                mant_dig,
            )

            observations["F1"].append(
                (row["case"] + " +",) + f1_pos
            )
            observations["F1"].append(
                (row["case"] + " -",) + f1_neg
            )
            observations["F2"].append(
                (row["case"] + " +",) + f2_pos
            )
            observations["F2"].append(
                (row["case"] + " -",) + f2_neg
            )

            for f1, f2 in (
                (f1_pos[0], f2_pos[0]),
                (f1_neg[0], f2_neg[0]),
            ):
                if f1 < f2:
                    closer["F1"] += 1
                elif f2 < f1:
                    closer["F2"] += 1
                else:
                    closer["tie"] += 1

        for candidate in ("F1", "F2"):
            data = observations[candidate]

            worst_abs = max(data, key=lambda item: item[1])
            worst_rel = max(data, key=lambda item: item[2])
            worst_ulp = max(data, key=lambda item: item[3])

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
                "    worst ulp-scale:",
                fmt(worst_ulp[3]),
                "@",
                worst_ulp[0],
            )

        worst_f1_odd = max(
            valid,
            key=lambda row: (
                row["f1_odd"]
                if is_finite(row["f1_odd"])
                else mp.inf
            ),
        )

        worst_f2_odd = max(
            valid,
            key=lambda row: (
                row["f2_odd"]
                if is_finite(row["f2_odd"])
                else mp.inf
            ),
        )

        print(
            "  closer observations:",
            f"F1={closer['F1']}",
            f"F2={closer['F2']}",
            f"tie={closer['tie']}",
        )

        print(
            "  max odd error F1:",
            fmt(worst_f1_odd["f1_odd"]),
            "@",
            worst_f1_odd["case"],
        )

        print(
            "  max odd error F2:",
            fmt(worst_f2_odd["f2_odd"]),
            "@",
            worst_f2_odd["case"],
        )

    print()
    print(
        "TOTAL:",
        f"valid rows={total_valid}",
        f"outside-domain rows={total_invalid}",
    )


def main():
    dmd_path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else "/tmp/pm-forward-dmd.tsv"
    )

    ldc_path = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else "/tmp/pm-forward-ldc.tsv"
    )

    dmd_bytes = dmd_path.read_bytes()
    ldc_bytes = ldc_path.read_bytes()

    print("=== COMPILER OUTPUT ===")

    if dmd_bytes == ldc_bytes:
        print("PASS: DMD and LDC TSV output is byte-identical")
    else:
        raise RuntimeError(
            "DMD and LDC PM-B outputs differ; "
            "inspect them before oracle analysis"
        )

    rows = load(dmd_path)

    print(f"rows: {len(rows)}")

    summarize(rows)


if __name__ == "__main__":
    main()
