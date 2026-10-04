#!/usr/bin/env python3

"""
PM-E0 — qualify local PROJ webmerc as an independent reference.

This deliberately validates PROJ itself before it is used as a
differential oracle for the D research kernel.

No production geodesy-d code is exercised here.
"""

from __future__ import annotations

import math
import shutil
import subprocess
import sys

import mpmath as mp


mp.mp.dps = 120

A = "6378137"
B_WGS84 = "6356752.3142451793"
B_SPHERE = A

METRE_TOL = mp.mpf("1e-6")
DEGREE_TOL = mp.mpf("1e-11")


def circumference(a=A):
    return (
        2
        * mp.pi
        * mp.mpf(str(a))
    )


def sheet_edge_equivalent(
    actual_x,
    expected_x,
    *,
    a=A,
):
    """
    Return True when two projected eastings differ by one complete
    principal-sheet width.

    PM-D canonicalizes an exact +pi longitude difference to -pi.
    Local PROJ keeps the positive edge for the tested exact +180-degree
    tie. Those are policy-distinct representatives of the same geographic
    antimeridian, not a webmerc formula disagreement.
    """
    difference = abs(
        abs(actual_x - expected_x)
        - circumference(a)
    )

    return difference <= METRE_TOL


def m(value) -> mp.mpf:
    return mp.mpf(str(value))


def radians(degrees: mp.mpf) -> mp.mpf:
    return degrees * mp.pi / 180


def degrees(radians_value: mp.mpf) -> mp.mpf:
    return radians_value * 180 / mp.pi


def wrap_pi(value: mp.mpf) -> mp.mpf:
    period = 2 * mp.pi

    result = mp.fmod(
        value + mp.pi,
        period,
    )

    if result < 0:
        result += period

    result -= mp.pi

    # Enforce the intended half-open representation.
    if result >= mp.pi:
        result -= period

    return result


def angular_error_degrees(
    actual: mp.mpf,
    expected: mp.mpf,
) -> mp.mpf:
    delta = radians(actual - expected)
    return abs(degrees(wrap_pi(delta)))


def oracle_forward(
    lon_deg,
    lat_deg,
    *,
    a,
    lon0_deg,
    x0,
    y0,
):
    lon = radians(m(lon_deg))
    lat = radians(m(lat_deg))
    lon0 = radians(m(lon0_deg))

    delta = wrap_pi(
        lon - lon0
    )

    # Independent high-precision form from the published equation.
    q = mp.log(
        mp.tan(
            mp.pi / 4
            + lat / 2
        )
    )

    x = m(x0) + m(a) * delta
    y = m(y0) + m(a) * q

    return x, y


def projection_args(
    *,
    a,
    b,
    lon0,
    x0,
    y0,
    over=False,
):
    args = [
        "+proj=webmerc",
        f"+a={a}",
        f"+b={b}",
        f"+lon_0={lon0}",
        f"+x_0={x0}",
        f"+y_0={y0}",
        "+units=m",
    ]

    if over:
        args.append("+over")

    return args


def run_proj_forward(
    lon,
    lat,
    *,
    a=A,
    b=B_WGS84,
    lon0="0",
    x0="0",
    y0="0",
    over=False,
):
    cmd = [
        "proj",
        "-f",
        "%.17g",
        *projection_args(
            a=a,
            b=b,
            lon0=lon0,
            x0=x0,
            y0=y0,
            over=over,
        ),
    ]

    completed = subprocess.run(
        cmd,
        input=f"{lon} {lat}\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    fields = completed.stdout.strip().split()

    if len(fields) < 2:
        raise RuntimeError(
            "unexpected PROJ forward output: "
            + completed.stdout
        )

    return (
        mp.mpf(fields[0]),
        mp.mpf(fields[1]),
    )


def run_proj_inverse(
    x,
    y,
    *,
    a=A,
    b=B_WGS84,
    lon0="0",
    x0="0",
    y0="0",
):
    cmd = [
        "proj",
        "-I",
        "-f",
        "%.17g",
        *projection_args(
            a=a,
            b=b,
            lon0=lon0,
            x0=x0,
            y0=y0,
        ),
    ]

    completed = subprocess.run(
        cmd,
        input=(
            f"{mp.nstr(x, 30)} "
            f"{mp.nstr(y, 30)}\n"
        ),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    fields = completed.stdout.strip().split()

    if len(fields) < 2:
        raise RuntimeError(
            "unexpected PROJ inverse output: "
            + completed.stdout
        )

    return (
        mp.mpf(fields[0]),
        mp.mpf(fields[1]),
    )


def fmt(value):
    return mp.nstr(value, 16)


def main():
    if shutil.which("proj") is None:
        raise SystemExit(
            "FAIL: proj executable not found"
        )

    profiles = [
        {
            "name": "wgs84_zero",
            "lon0": "0",
            "x0": "0",
            "y0": "0",
            "points": [
                (
                    "origin",
                    "0",
                    "0",
                ),
                (
                    "epsg_example",
                    "-100.333333333333333333333333333333",
                    "24.381786944444444444444444444444",
                ),
                (
                    "deg45",
                    "12.5",
                    "45",
                ),
                (
                    "webmercatorquad_north",
                    "0",
                    "85.0511287798066",
                ),
                (
                    "deg88_north",
                    "37",
                    "88",
                ),
                (
                    "deg88_south",
                    "-37",
                    "-88",
                ),
                (
                    "east180",
                    "180",
                    "0",
                ),
                (
                    "west180",
                    "-180",
                    "0",
                ),
            ],
        },
        {
            "name": "offset_lon170",
            "lon0": "170",
            "x0": "500000",
            "y0": "-2000000",
            "points": [
                (
                    "central_meridian",
                    "170",
                    "0",
                ),
                (
                    "cross_antimeridian",
                    "-179.75",
                    "45",
                ),
                (
                    "nominal_minus180_delta",
                    "-10",
                    "20",
                ),
                (
                    "deg88_offset",
                    "-175",
                    "88",
                ),
            ],
        },
        {
            "name": "offset_lon_minus170",
            "lon0": "-170",
            "x0": "-250000",
            "y0": "1250000",
            "points": [
                (
                    "central_meridian",
                    "-170",
                    "0",
                ),
                (
                    "cross_antimeridian",
                    "179.75",
                    "-45",
                ),
                (
                    "nominal_plus180_delta",
                    "10",
                    "-20",
                ),
                (
                    "deg88_offset",
                    "175",
                    "-88",
                ),
            ],
        },
    ]

    print(
        "=== PROJ WEBMERC VS HIGH-PRECISION ORACLE ==="
    )

    failures = 0
    tested = 0

    for profile in profiles:
        print()
        print(
            f"profile={profile['name']} "
            f"lon0={profile['lon0']} "
            f"x0={profile['x0']} "
            f"y0={profile['y0']}"
        )

        for (
            label,
            lon,
            lat,
        ) in profile["points"]:
            px, py = run_proj_forward(
                lon,
                lat,
                lon0=profile["lon0"],
                x0=profile["x0"],
                y0=profile["y0"],
            )

            ox, oy = oracle_forward(
                lon,
                lat,
                a=A,
                lon0_deg=profile["lon0"],
                x0=profile["x0"],
                y0=profile["y0"],
            )

            dx = abs(px - ox)
            dy = abs(py - oy)

            inv_lon, inv_lat = run_proj_inverse(
                px,
                py,
                lon0=profile["lon0"],
                x0=profile["x0"],
                y0=profile["y0"],
            )

            expected_lon = degrees(
                wrap_pi(
                    radians(m(lon))
                )
            )

            lon_error = angular_error_degrees(
                inv_lon,
                expected_lon,
            )

            lat_error = abs(
                inv_lat - m(lat)
            )

            direct_forward_ok = (
                dx <= METRE_TOL
                and dy <= METRE_TOL
            )

            tie_policy_equivalent = (
                dy <= METRE_TOL
                and sheet_edge_equivalent(
                    px,
                    ox,
                    a=A,
                )
            )

            forward_ok = (
                direct_forward_ok
                or tie_policy_equivalent
            )

            inverse_ok = (
                lon_error <= DEGREE_TOL
                and lat_error <= DEGREE_TOL
            )

            tested += 1

            if not (
                forward_ok
                and inverse_ok
            ):
                failures += 1

            if (
                tie_policy_equivalent
                and not direct_forward_ok
            ):
                disposition = (
                    "PASS_POLICY_DIFFERENCE"
                )
            elif (
                forward_ok
                and inverse_ok
            ):
                disposition = "PASS"
            else:
                disposition = "FAIL"

            print(
                f"  {label}:"
                f" dx={fmt(dx)}m"
                f" dy={fmt(dy)}m"
                f" inv_lon_err={fmt(lon_error)}deg"
                f" inv_lat_err={fmt(lat_error)}deg"
                f" {disposition}"
            )

    print()
    print("=== EPSG PUBLISHED EXAMPLE CONTROL ===")

    px, py = run_proj_forward(
        "-100.333333333333333333333333333333",
        "24.381786944444444444444444444444",
    )

    epsg_x = mp.mpf("-11169055.58")
    epsg_y = mp.mpf("2800000.00")

    print(
        "PROJ:",
        fmt(px),
        fmt(py),
    )

    print(
        "EPSG rounded example delta:",
        "dx=" + fmt(abs(px - epsg_x)),
        "dy=" + fmt(abs(py - epsg_y)),
    )

    if (
        abs(px - epsg_x)
        > mp.mpf("0.02")
        or abs(py - epsg_y)
        > mp.mpf("0.02")
    ):
        failures += 1
        print(
            "FAIL: outside tolerance of published EPSG example"
        )
    else:
        print(
            "PASS: consistent with EPSG rounded example"
        )

    print()
    print("=== SEMI-MAJOR-AXIS CONTROL ===")

    control_points = [
        ("0", "0"),
        ("12.5", "45"),
        ("37", "88"),
        ("-100.333333333333333", "24.381786944444444"),
    ]

    same_axis_failures = 0

    for lon, lat in control_points:
        ellipsoid_xy = run_proj_forward(
            lon,
            lat,
            a=A,
            b=B_WGS84,
        )

        sphere_xy = run_proj_forward(
            lon,
            lat,
            a=A,
            b=B_SPHERE,
        )

        equal = (
            ellipsoid_xy == sphere_xy
        )

        if not equal:
            same_axis_failures += 1
            failures += 1

        print(
            f"  lon={lon} lat={lat}: "
            f"{'IDENTICAL' if equal else 'DIFFERS'}"
        )

    if same_axis_failures == 0:
        print(
            "PASS: local webmerc result depends on a, "
            "not WGS84 flattening, for control corpus"
        )

    print()
    print("=== PROJ LONGITUDE-WRAP CONTROL ===")

    default_xy = run_proj_forward(
        "181",
        "0",
    )

    over_xy = run_proj_forward(
        "181",
        "0",
        over=True,
    )

    minus179_xy = run_proj_forward(
        "-179",
        "0",
    )

    print(
        "181 default:",
        fmt(default_xy[0]),
        fmt(default_xy[1]),
    )

    print(
        "-179 default:",
        fmt(minus179_xy[0]),
        fmt(minus179_xy[1]),
    )

    print(
        "181 +over:",
        fmt(over_xy[0]),
        fmt(over_xy[1]),
    )

    wrap_dx = abs(
        default_xy[0]
        - minus179_xy[0]
    )

    wrap_dy = abs(
        default_xy[1]
        - minus179_xy[1]
    )

    print(
        "181/-179 difference:",
        "dx=" + fmt(wrap_dx),
        "dy=" + fmt(wrap_dy),
    )

    if (
        wrap_dx <= METRE_TOL
        and wrap_dy <= METRE_TOL
    ):
        print(
            "PASS: default PROJ forward wrapping confirmed "
            "within numerical tolerance"
        )
    else:
        failures += 1
        print(
            "FAIL: default 181/-179 wrap differs beyond tolerance"
        )

    over_difference = abs(
        over_xy[0]
        - default_xy[0]
    )

    if over_difference <= METRE_TOL:
        failures += 1
        print(
            "FAIL: +over control did not materially change "
            "181-degree result"
        )
    else:
        print(
            "PASS: +over disables the default wrap for control point"
        )

    print()
    print("=== OUTSIDE-PM-D CONTROL ===")

    for latitude in (
        "88",
        "88.0001",
        "89",
    ):
        try:
            x, y = run_proj_forward(
                "0",
                latitude,
            )

            print(
                f"lat={latitude}: "
                f"PROJ returns finite="
                f"{math.isfinite(float(x)) and math.isfinite(float(y))} "
                f"x={fmt(x)} y={fmt(y)}"
            )

        except subprocess.CalledProcessError as exc:
            print(
                f"lat={latitude}: PROJ rejected: "
                f"{exc.stderr.strip()}"
            )

    print(
        "\nNOTE: PROJ acceptance above 88 degrees is only a "
        "reference-tool observation. PM-D still rejects poleward "
        "inputs by contract."
    )

    print()
    print("=== PM-E0 RESULT ===")
    print(
        f"tested differential cases={tested}"
    )
    print(
        f"failures={failures}"
    )

    if failures:
        raise SystemExit(1)

    print(
        "PASS: local PROJ webmerc qualified as PM-E numerical "
        "differential reference over the shared supported domain"
    )

    print(
        "NOTE: exact +pi principal-sheet tie policy is characterized "
        "separately and is not delegated to PROJ."
    )


if __name__ == "__main__":
    main()
