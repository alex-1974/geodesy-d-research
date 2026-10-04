#!/usr/bin/env python3

"""
PM-E1C1B reverse differential characterization.

This harness deliberately separates:

1. reverse-domain / represented-boundary policy;
2. independent numerical inverse accuracy;
3. public longitude canonicalization;
4. forward/reverse round-trip concerns.

The primary inverse latitude oracle uses the EPSG literal form:

    D   = (FN - N) / a
    phi = pi/2 - 2 * atan(exp(D))

rather than the D research-kernel form:

    q   = (N - FN) / a
    phi = atan(sinh(q))

The existing PM-E1C1A binary-rounding utility is reused only for public
floating-point representation. Projection mathematics is evaluated
independently here.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import mpmath as mp


mp.mp.dps = 120


PRECISION = {
    "float": 24,
    "double": 53,
    "real": 64,
}


WORKING_PRECISION = {
    "float": 53,
    "double": 53,
    "real": 64,
}


@dataclass(frozen=True)
class Profile:
    name: str
    a: str
    lon0_deg: str
    fe: str
    fn: str


@dataclass
class ReverseCase:
    identifier: str
    scalar: str
    profile: Profile
    tag: str
    expect_accept: bool
    latitude_anchor: str | None
    easting_policy: str | None
    numerical: bool


PROFILES = (
    Profile(
        "unit_zero",
        "1",
        "0",
        "0",
        "0",
    ),
    Profile(
        "wgs84_zero",
        "6378137",
        "0",
        "0",
        "0",
    ),
    Profile(
        "offset_p170",
        "6378137",
        "170",
        "500000",
        "-2000000",
    ),
    Profile(
        "offset_m170",
        "6378137",
        "-170",
        "-250000",
        "1250000",
    ),
    Profile(
        "offset_p179_75",
        "6378137",
        "179.75",
        "500000",
        "-2000000",
    ),
    Profile(
        "offset_m179_75",
        "6378137",
        "-179.75",
        "-250000",
        "1250000",
    ),
)


def load_forward_rounding():
    path = Path(__file__).with_name(
        "validate_pm_e1c1_forward.py"
    )

    spec = importlib.util.spec_from_file_location(
        "pm_e1c1_forward_rounding",
        path,
    )

    if spec is None or spec.loader is None:
        raise RuntimeError(
            "cannot import forward validator rounding utilities"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    sys.modules[
        spec.name
    ] = module

    spec.loader.exec_module(
        module
    )

    return module.round_binary


round_binary = load_forward_rounding()


def run_driver(
    driver: Path,
    request_text: str,
) -> str:
    result = subprocess.run(
        [str(driver)],
        input=request_text,
        text=True,
        capture_output=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "driver failed with status "
            f"{result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    return result.stdout


def parse_output(text: str):
    rows = {}

    for line in text.splitlines():
        if not line:
            continue

        fields = line.split(
            "\t"
        )

        kind = fields[0]

        if kind in {
            "BOK",
            "FOK",
            "ROK",
        }:
            identifier = fields[1]
            scalar = fields[2]

            values = dict(
                item.split(
                    "=",
                    1,
                )
                for item in fields[3:]
            )

            rows[
                identifier
            ] = {
                "kind": kind,
                "scalar": scalar,
                "values": values,
                "raw": line,
            }

        elif kind == "REJECT":
            identifier = fields[1]

            rows[
                identifier
            ] = {
                "kind": kind,
                "operation": (
                    fields[2]
                    if len(fields) > 2
                    else "?"
                ),
                "scalar": (
                    fields[3]
                    if len(fields) > 3
                    else "?"
                ),
                "reason": (
                    fields[4]
                    if len(fields) > 4
                    else "?"
                ),
                "raw": line,
            }

        elif kind == "ERROR":
            identifier = (
                fields[1]
                if len(fields) > 1
                else "?"
            )

            rows[
                identifier
            ] = {
                "kind": kind,
                "raw": line,
            }

        else:
            raise RuntimeError(
                "unexpected driver row: "
                + line
            )

    return rows


def mpv(value: str) -> mp.mpf:
    return mp.mpf(
        value
    )


def public_value(
    value: str,
    scalar: str,
) -> mp.mpf:
    """
    Reconstruct the exact public binary scalar represented by a driver
    decimal echo.

    Driver %.40g output is an interchange representation, not the value
    on which neighbour or ULP operations should be performed directly.
    """
    return round_binary(
        mpv(value),
        PRECISION[scalar],
    )


def working_value(
    value: str,
    scalar: str,
) -> mp.mpf:
    """
    Reconstruct a WorkingScalar value echoed by the driver.

    float works in binary64; double works in binary64; real uses the
    observed 64-bit-significand D real on the current research host.
    """
    return round_binary(
        mpv(value),
        WORKING_PRECISION[scalar],
    )


def decimal_input(
    value: mp.mpf,
) -> str:
    return mp.nstr(
        value,
        80,
        strip_zeros=False,
    )


def hex_input(
    value: mp.mpf,
    precision: int,
) -> str:
    """
    Serialize an already represented binary scalar exactly as a C/D
    hexadecimal floating-point literal.

    Decimal transport is not reliable for x87 D real on the current
    toolchain: std.conv.to!real can round long decimal spellings to an
    adjacent representable value.  Hex-float parsing was independently
    verified to round-trip float, double and 64-significand-bit real
    exactly under both DMD and LDC.
    """
    value = round_binary(
        value,
        precision,
    )

    if value == 0:
        return "0x0p+0"

    sign = ""

    if value < 0:
        sign = "-"
        value = -value

    mantissa, exponent = mp.frexp(
        value
    )

    #
    # frexp:
    #
    #     value = mantissa * 2**exponent
    #     0.5 <= mantissa < 1
    #
    # Convert to:
    #
    #     1.fraction * 2**binary_exponent
    #
    normalized = (
        mantissa
        * 2
    )

    binary_exponent = (
        int(exponent)
        - 1
    )

    significand = int(
        mp.nint(
            normalized
            * mp.power(
                2,
                precision - 1,
            )
        )
    )

    leading = (
        1
        << (precision - 1)
    )

    if significand < leading             or significand >= (leading << 1):
        raise RuntimeError(
            "invalid normalized significand "
            f"for precision={precision}: "
            f"{significand}"
        )

    fraction = (
        significand
        - leading
    )

    fraction_bits = (
        precision
        - 1
    )

    hex_digits = (
        fraction_bits
        + 3
    ) // 4

    padding_bits = (
        hex_digits * 4
        - fraction_bits
    )

    encoded_fraction = (
        fraction
        << padding_bits
    )

    fraction_hex = format(
        encoded_fraction,
        f"0{hex_digits}x",
    )

    return (
        f"{sign}0x1."
        f"{fraction_hex}"
        f"p{binary_exponent:+d}"
    )


def is_power_of_two(
    value: mp.mpf,
) -> bool:
    if value <= 0:
        return False

    exponent = int(
        mp.floor(
            mp.log(
                value,
                2,
            )
        )
    )

    return value == mp.power(
        2,
        exponent,
    )


def positive_step(
    value: mp.mpf,
    precision: int,
) -> mp.mpf:
    if value <= 0:
        raise ValueError(
            "positive_step requires positive value"
        )

    exponent = int(
        mp.floor(
            mp.log(
                value,
                2,
            )
        )
    )

    return mp.power(
        2,
        exponent - precision + 1,
    )


def next_up_binary(
    value: mp.mpf,
    precision: int,
) -> mp.mpf:
    if value == 0:
        raise ValueError(
            "zero nextUp is not needed by this corpus"
        )

    if value < 0:
        return -next_down_binary(
            -value,
            precision,
        )

    return value + positive_step(
        value,
        precision,
    )


def next_down_binary(
    value: mp.mpf,
    precision: int,
) -> mp.mpf:
    if value == 0:
        raise ValueError(
            "zero nextDown is not needed by this corpus"
        )

    if value < 0:
        return -next_up_binary(
            -value,
            precision,
        )

    step = positive_step(
        value,
        precision,
    )

    if is_power_of_two(
        value
    ):
        step /= 2

    return value - step


def canonical_math(
    radians: mp.mpf,
) -> mp.mpf:
    result = mp.mpf(
        radians
    )

    two_pi = 2 * mp.pi

    while result >= mp.pi:
        result -= two_pi

    while result < -mp.pi:
        result += two_pi

    return result


def canonical_public(
    radians: mp.mpf,
    precision: int,
) -> mp.mpf:
    public_pi = round_binary(
        mp.pi,
        precision,
    )

    two_public_pi = (
        2
        * public_pi
    )

    result = mp.mpf(
        radians
    )

    if result >= public_pi:
        result -= two_public_pi
    elif result < -public_pi:
        result += two_public_pi

    if result >= public_pi:
        result -= two_public_pi
    elif result < -public_pi:
        result += two_public_pi

    return result


def angular_difference(
    actual: mp.mpf,
    expected: mp.mpf,
) -> mp.mpf:
    difference = (
        actual
        - expected
    )

    two_pi = 2 * mp.pi

    while difference >= mp.pi:
        difference -= two_pi

    while difference < -mp.pi:
        difference += two_pi

    return difference


def ulp_delta(
    actual: mp.mpf,
    expected: mp.mpf,
    precision: int,
) -> mp.mpf:
    if actual == expected:
        return mp.mpf(
            "0"
        )

    if actual > expected:
        neighbour = next_up_binary(
            expected,
            precision,
        )

        spacing = (
            neighbour
            - expected
        )
    else:
        neighbour = next_down_binary(
            expected,
            precision,
        )

        spacing = (
            expected
            - neighbour
        )

    return (
        abs(
            actual
            - expected
        )
        / spacing
    )


def scientific(
    value: mp.mpf,
) -> str:
    if value == 0:
        return "0"

    return mp.nstr(
        value,
        18,
        min_fixed=-4,
        max_fixed=6,
    )


def bootstrap_requests():
    lines = []

    for scalar in (
        "float",
        "double",
        "real",
    ):
        for profile in PROFILES:
            suffix = (
                f"{scalar}__"
                f"{profile.name}"
            )

            lines.append(
                " ".join(
                    (
                        "B",
                        f"b__{suffix}",
                        scalar,
                        profile.a,
                        profile.lon0_deg,
                        profile.fe,
                        profile.fn,
                    )
                )
            )

            lines.append(
                " ".join(
                    (
                        "F",
                        f"f_north__{suffix}",
                        scalar,
                        profile.a,
                        profile.lon0_deg,
                        profile.fe,
                        profile.fn,
                        "88",
                        profile.lon0_deg,
                    )
                )
            )

            lines.append(
                " ".join(
                    (
                        "F",
                        f"f_south__{suffix}",
                        scalar,
                        profile.a,
                        profile.lon0_deg,
                        profile.fe,
                        profile.fn,
                        "-88",
                        profile.lon0_deg,
                    )
                )
            )

    return lines


def make_reverse_corpus(
    bootstrap_rows,
):
    lines = []
    cases = {}

    def add(
        *,
        scalar,
        profile,
        tag,
        easting,
        northing,
        expect_accept=True,
        latitude_anchor=None,
        easting_policy=None,
        numerical=True,
    ):
        identifier = (
            f"r__{scalar}__"
            f"{profile.name}__"
            f"{tag}"
        )

        lines.append(
            " ".join(
                (
                    "R",
                    identifier,
                    scalar,
                    profile.a,
                    profile.lon0_deg,
                    profile.fe,
                    profile.fn,
                    hex_input(
                        round_binary(
                            easting,
                            PRECISION[scalar],
                        ),
                        PRECISION[scalar],
                    ),
                    hex_input(
                        round_binary(
                            northing,
                            PRECISION[scalar],
                        ),
                        PRECISION[scalar],
                    ),
                )
            )
        )

        cases[
            identifier
        ] = ReverseCase(
            identifier=identifier,
            scalar=scalar,
            profile=profile,
            tag=tag,
            expect_accept=expect_accept,
            latitude_anchor=latitude_anchor,
            easting_policy=easting_policy,
            numerical=numerical,
        )

    for scalar in (
        "float",
        "double",
        "real",
    ):
        precision = PRECISION[
            scalar
        ]

        for profile in PROFILES:
            suffix = (
                f"{scalar}__"
                f"{profile.name}"
            )

            boundary = bootstrap_rows[
                f"b__{suffix}"
            ]

            values = boundary[
                "values"
            ]

            a = public_value(
                values["a"],
                scalar,
            )

            fe = public_value(
                values["fe"],
                scalar,
            )

            fn = public_value(
                values["fn"],
                scalar,
            )

            south_n = public_value(
                values["southN"],
                scalar,
            )

            north_n = public_value(
                values["northN"],
                scalar,
            )

            west_e = public_value(
                values["westE"],
                scalar,
            )

            east_e = public_value(
                values["eastE"],
                scalar,
            )

            #
            # Ordinary independent projected coordinates.
            #
            add(
                scalar=scalar,
                profile=profile,
                tag="origin",
                easting=fe,
                northing=fn,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="east_half",
                easting=fe + mp.mpf("0.5") * a,
                northing=fn,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="west_1_25",
                easting=fe - mp.mpf("1.25") * a,
                northing=fn,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="mixed_ne",
                easting=fe + mp.mpf("2.5") * a,
                northing=fn + mp.mpf("1.2") * a,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="mixed_sw",
                easting=fe - mp.mpf("2.5") * a,
                northing=fn - mp.mpf("1.2") * a,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="north_mid",
                easting=fe + mp.mpf("0.25") * a,
                northing=(
                    fn + north_n
                ) / 2,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="south_mid",
                easting=fe - mp.mpf("0.25") * a,
                northing=(
                    fn + south_n
                ) / 2,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="north_inside",
                easting=fe,
                northing=next_down_binary(
                    north_n,
                    precision,
                ),
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="south_inside",
                easting=fe,
                northing=next_up_binary(
                    south_n,
                    precision,
                ),
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="west_inside",
                easting=next_up_binary(
                    west_e,
                    precision,
                ),
                northing=fn,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="east_inside",
                easting=next_down_binary(
                    east_e,
                    precision,
                ),
                northing=fn,
            )

            #
            # Explicit represented policy anchors.
            #
            add(
                scalar=scalar,
                profile=profile,
                tag="west_anchor",
                easting=west_e,
                northing=fn,
                easting_policy="west",
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="east_anchor",
                easting=east_e,
                northing=fn,
                easting_policy="east",
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="north_anchor",
                easting=fe,
                northing=north_n,
                latitude_anchor="north",
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="south_anchor",
                easting=fe,
                northing=south_n,
                latitude_anchor="south",
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="north_west_corner",
                easting=west_e,
                northing=north_n,
                latitude_anchor="north",
                easting_policy="west",
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="south_east_corner",
                easting=east_e,
                northing=south_n,
                latitude_anchor="south",
                easting_policy="east",
                numerical=False,
            )

            #
            # Exact next-representable public values outside the accepted
            # PM-D represented domain.
            #
            add(
                scalar=scalar,
                profile=profile,
                tag="reject_north_outside",
                easting=fe,
                northing=next_up_binary(
                    north_n,
                    precision,
                ),
                expect_accept=False,
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="reject_south_outside",
                easting=fe,
                northing=next_down_binary(
                    south_n,
                    precision,
                ),
                expect_accept=False,
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="reject_west_outside",
                easting=next_down_binary(
                    west_e,
                    precision,
                ),
                northing=fn,
                expect_accept=False,
                numerical=False,
            )

            add(
                scalar=scalar,
                profile=profile,
                tag="reject_east_outside",
                easting=next_up_binary(
                    east_e,
                    precision,
                ),
                northing=fn,
                expect_accept=False,
                numerical=False,
            )

    return lines, cases


def expected_reverse(
    case: ReverseCase,
    row,
    bootstrap_rows,
):
    scalar = case.scalar

    precision = PRECISION[
        scalar
    ]

    working_precision = (
        WORKING_PRECISION[
            scalar
        ]
    )

    values = row[
        "values"
    ]

    suffix = (
        f"{scalar}__"
        f"{case.profile.name}"
    )

    boundary_values = (
        bootstrap_rows[
            f"b__{suffix}"
        ]["values"]
    )

    a = public_value(
        values["a"],
        scalar,
    )

    lon0 = public_value(
        values["lon0_rad"],
        scalar,
    )

    fe = public_value(
        values["fe"],
        scalar,
    )

    fn = public_value(
        values["fn"],
        scalar,
    )

    easting = public_value(
        values["e"],
        scalar,
    )

    northing = public_value(
        values["n"],
        scalar,
    )

    #
    # Latitude oracle.
    #
    if case.latitude_anchor == "north":
        expected_latitude = public_value(
            bootstrap_rows[
                f"f_north__{suffix}"
            ]["values"]["lat_rad"],
            scalar,
        )

        exact_latitude = (
            expected_latitude
        )

    elif case.latitude_anchor == "south":
        expected_latitude = public_value(
            bootstrap_rows[
                f"f_south__{suffix}"
            ]["values"]["lat_rad"],
            scalar,
        )

        exact_latitude = (
            expected_latitude
        )

    else:
        D = (
            fn
            - northing
        ) / a

        exact_latitude = (
            mp.pi / 2
            - 2
            * mp.atan(
                mp.exp(
                    D
                )
            )
        )

        expected_latitude = (
            round_binary(
                exact_latitude,
                precision,
            )
        )

    #
    # Longitude oracle.
    #
    if case.easting_policy == "east":
        #
        # PM-G0 represented-domain policy:
        # the prepared public longitude is the authoritative inverse
        # identity for the exact represented east endpoint.
        #
        expected_longitude = public_value(
            boundary_values[
                "eastLon"
            ],
            scalar,
        )

        exact_longitude = (
            expected_longitude
        )

    else:
        if case.easting_policy == "west":
            delta = -round_binary(
                mp.pi,
                working_precision,
            )

        else:
            delta = (
                easting
                - fe
            ) / a

        exact_longitude = canonical_math(
            lon0
            + delta
        )

        expected_longitude = round_binary(
            exact_longitude,
            precision,
        )

        expected_longitude = (
            canonical_public(
                expected_longitude,
                precision,
            )
        )

    return {
        "exact_lat":
            exact_latitude,
        "rounded_lat":
            expected_latitude,
        "exact_lon":
            exact_longitude,
        "rounded_lon":
            expected_longitude,
    }


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--driver",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--write-input",
        type=Path,
    )

    parser.add_argument(
        "--write-output",
        type=Path,
    )

    args = parser.parse_args()

    bootstrap_lines = (
        bootstrap_requests()
    )

    bootstrap_text = (
        "\n".join(
            bootstrap_lines
        )
        + "\n"
    )

    bootstrap_output = run_driver(
        args.driver,
        bootstrap_text,
    )

    bootstrap_rows = parse_output(
        bootstrap_output
    )

    expected_bootstrap = (
        len(PROFILES)
        * 3
        * 3
    )

    if len(
        bootstrap_rows
    ) != expected_bootstrap:
        raise RuntimeError(
            "bootstrap row count "
            f"{len(bootstrap_rows)} != "
            f"{expected_bootstrap}"
        )

    reverse_lines, cases = (
        make_reverse_corpus(
            bootstrap_rows
        )
    )

    full_lines = (
        bootstrap_lines
        + reverse_lines
    )

    full_text = (
        "\n".join(
            full_lines
        )
        + "\n"
    )

    if args.write_input:
        args.write_input.write_text(
            full_text,
            encoding="utf-8",
        )

    full_output = run_driver(
        args.driver,
        full_text,
    )

    if args.write_output:
        args.write_output.write_text(
            full_output,
            encoding="utf-8",
        )

    rows = parse_output(
        full_output
    )

    accepted_expected = sum(
        1
        for case in cases.values()
        if case.expect_accept
    )

    rejected_expected = sum(
        1
        for case in cases.values()
        if not case.expect_accept
    )

    rok_count = sum(
        1
        for row in rows.values()
        if row["kind"] == "ROK"
    )

    reject_count = sum(
        1
        for row in rows.values()
        if row["kind"] == "REJECT"
    )

    error_count = sum(
        1
        for row in rows.values()
        if row["kind"] == "ERROR"
    )

    print(
        "=== PM-E1C1B REVERSE DIFFERENTIAL ==="
    )

    print(
        "profiles:",
        len(PROFILES) * 3,
    )

    print(
        "reverse requests:",
        len(cases),
    )

    print(
        "expected accepted:",
        accepted_expected,
    )

    print(
        "expected rejected:",
        rejected_expected,
    )

    print(
        "ROK:",
        rok_count,
    )

    print(
        "REJECT:",
        reject_count,
    )

    print(
        "ERROR:",
        error_count,
    )

    protocol_failures = []

    for identifier, case in cases.items():
        row = rows.get(
            identifier
        )

        if row is None:
            protocol_failures.append(
                (
                    identifier,
                    "missing",
                )
            )

            continue

        if case.expect_accept:
            if row["kind"] != "ROK":
                protocol_failures.append(
                    (
                        identifier,
                        row["kind"],
                        row.get(
                            "reason",
                            "?",
                        ),
                    )
                )

        else:
            if row["kind"] != "REJECT":
                protocol_failures.append(
                    (
                        identifier,
                        "expected-reject",
                        row["kind"],
                    )
                )

            elif row.get(
                "reason"
            ) != "domain":
                protocol_failures.append(
                    (
                        identifier,
                        "wrong-reject-reason",
                        row.get(
                            "reason"
                        ),
                    )
                )

    print()
    print(
        "=== DOMAIN / PROTOCOL CHECK ==="
    )

    print(
        "failures:",
        len(protocol_failures),
    )

    for failure in (
        protocol_failures[:40]
    ):
        print(
            "FAIL",
            failure,
        )

    stats = {
        scalar: {
            "cases": 0,
            "lat_matches": 0,
            "lon_matches": 0,
            "max_lat_round_ulp":
                mp.mpf("0"),
            "max_lon_round_ulp":
                mp.mpf("0"),
            "max_lat_abs":
                mp.mpf("0"),
            "max_lon_abs":
                mp.mpf("0"),
            "worst_lat_round":
                None,
            "worst_lon_round":
                None,
            "worst_lat_abs":
                None,
            "worst_lon_abs":
                None,
            "numerical_cases": 0,
            "east_policy_cases": 0,
            "east_policy_matches": 0,
            "non_east_lon_cases": 0,
            "non_east_lon_matches": 0,
        }
        for scalar in (
            "float",
            "double",
            "real",
        )
    }

    mismatches = []

    for identifier, case in cases.items():
        if not case.expect_accept:
            continue

        row = rows.get(
            identifier
        )

        if row is None \
            or row["kind"] != "ROK":
            continue

        scalar = case.scalar
        precision = PRECISION[
            scalar
        ]

        oracle = expected_reverse(
            case,
            row,
            bootstrap_rows,
        )

        actual_lat = public_value(
            row["values"][
                "lat_rad"
            ],
            scalar,
        )

        actual_lon = public_value(
            row["values"][
                "lon_rad"
            ],
            scalar,
        )

        expected_lat = (
            oracle[
                "rounded_lat"
            ]
        )

        expected_lon = (
            oracle[
                "rounded_lon"
            ]
        )

        lat_round_ulp = (
            ulp_delta(
                actual_lat,
                expected_lat,
                precision,
            )
        )

        lon_round_difference = (
            angular_difference(
                actual_lon,
                expected_lon,
            )
        )

        if lon_round_difference == 0:
            lon_round_ulp = (
                mp.mpf("0")
            )
        else:
            shifted_actual = (
                expected_lon
                + lon_round_difference
            )

            lon_round_ulp = (
                ulp_delta(
                    shifted_actual,
                    expected_lon,
                    precision,
                )
            )

        stat = stats[
            scalar
        ]

        stat["cases"] += 1

        if case.easting_policy == "east":
            stat[
                "east_policy_cases"
            ] += 1
        else:
            stat[
                "non_east_lon_cases"
            ] += 1

        if lat_round_ulp == 0:
            stat[
                "lat_matches"
            ] += 1
        else:
            mismatches.append(
                (
                    identifier,
                    "LAT",
                    scalar,
                    lat_round_ulp,
                    abs(
                        actual_lat
                        - expected_lat
                    ),
                )
            )

        if lon_round_ulp == 0:
            stat[
                "lon_matches"
            ] += 1

            if case.easting_policy == "east":
                stat[
                    "east_policy_matches"
                ] += 1
            else:
                stat[
                    "non_east_lon_matches"
                ] += 1
        else:
            mismatches.append(
                (
                    identifier,
                    "LON",
                    scalar,
                    lon_round_ulp,
                    abs(
                        lon_round_difference
                    ),
                )
            )

        if lat_round_ulp \
                > stat[
                    "max_lat_round_ulp"
                ]:
            stat[
                "max_lat_round_ulp"
            ] = lat_round_ulp

            stat[
                "worst_lat_round"
            ] = identifier

        if lon_round_ulp \
                > stat[
                    "max_lon_round_ulp"
                ]:
            stat[
                "max_lon_round_ulp"
            ] = lon_round_ulp

            stat[
                "worst_lon_round"
            ] = identifier

        if case.numerical:
            stat[
                "numerical_cases"
            ] += 1

            lat_abs = abs(
                actual_lat
                - oracle[
                    "exact_lat"
                ]
            )

            lon_abs = abs(
                angular_difference(
                    actual_lon,
                    oracle[
                        "exact_lon"
                    ],
                )
            )

            if lat_abs \
                    > stat[
                        "max_lat_abs"
                    ]:
                stat[
                    "max_lat_abs"
                ] = lat_abs

                stat[
                    "worst_lat_abs"
                ] = identifier

            if lon_abs \
                    > stat[
                        "max_lon_abs"
                    ]:
                stat[
                    "max_lon_abs"
                ] = lon_abs

                stat[
                    "worst_lon_abs"
                ] = identifier

    print()
    print(
        "=== HIGH-PRECISION ORACLE ==="
    )

    for scalar in (
        "float",
        "double",
        "real",
    ):
        stat = stats[
            scalar
        ]

        print()
        print(
            f"{scalar}:"
        )

        print(
            "  accepted cases:",
            stat["cases"],
        )

        print(
            "  numerical interior cases:",
            stat[
                "numerical_cases"
            ],
        )

        print(
            "  correctly-rounded latitude:",
            f'{stat["lat_matches"]}/'
            f'{stat["cases"]}',
        )

        print(
            "  longitude contract matches:",
            f'{stat["lon_matches"]}/'
            f'{stat["cases"]}',
        )

        print(
            "  east endpoint policy matches:",
            f'{stat["east_policy_matches"]}/'
            f'{stat["east_policy_cases"]}',
        )

        print(
            "  non-east longitude oracle matches:",
            f'{stat["non_east_lon_matches"]}/'
            f'{stat["non_east_lon_cases"]}',
        )

        print(
            "  max latitude delta from "
            "correctly-rounded output [ulp]:",
            scientific(
                stat[
                    "max_lat_round_ulp"
                ]
            ),
            "worst=",
            stat[
                "worst_lat_round"
            ],
        )

        print(
            "  max longitude delta from "
            "correctly-rounded output [ulp]:",
            scientific(
                stat[
                    "max_lon_round_ulp"
                ]
            ),
            "worst=",
            stat[
                "worst_lon_round"
            ],
        )

        print(
            "  max numerical latitude "
            "abs oracle error [rad]:",
            scientific(
                stat[
                    "max_lat_abs"
                ]
            ),
            "worst=",
            stat[
                "worst_lat_abs"
            ],
        )

        print(
            "  max numerical longitude "
            "abs oracle error [rad]:",
            scientific(
                stat[
                    "max_lon_abs"
                ]
            ),
            "worst=",
            stat[
                "worst_lon_abs"
            ],
        )

    print()
    print(
        "=== CORRECT-ROUNDING MISMATCHES ==="
    )

    print(
        "count:",
        len(mismatches),
    )

    mismatches.sort(
        key=lambda item: (
            item[2],
            item[0],
            item[1],
        )
    )

    for (
        identifier,
        axis,
        scalar,
        rounded_delta,
        absolute_delta,
    ) in mismatches[:80]:
        print(
            " ",
            identifier,
            f"axis={axis}",
            f"scalar={scalar}",
            "rounded_delta_ulp="
            + scientific(
                rounded_delta
            ),
            "abs_delta="
            + scientific(
                absolute_delta
            ),
        )

    print()
    print(
        "=== PM-E1C1B RESULT ==="
    )

    if protocol_failures:
        print(
            "DOMAIN / PROTOCOL FAILURE"
        )

        return 1

    print(
        "CHARACTERIZATION COMPLETE"
    )

    print(
        "No final reverse accuracy budget "
        "is selected by this run."
    )

    print(
        "Use the observed mismatch set to "
        "select the next explicit reverse gate."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
