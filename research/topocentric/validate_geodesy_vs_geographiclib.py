#!/usr/bin/env python3

from __future__ import annotations

import os
import random
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from validate_geodesy_vs_proj import (
    ELLIPSOIDS,
    ORIGINS,
    FORWARD_CASES_PER_PROFILE,
    REVERSE_CASES_PER_PROFILE,
    FORWARD_SEED,
    REVERSE_SEED,
    Geodetic,
    Vec3,
    Ellipsoid,
    angular_difference_rad,
    compile_probe,
    compiler_version,
    deg_to_rad,
    ecef_to_enu,
    enu_to_ecef,
    forward_sources,
    geodetic_to_ecef,
    independent_reverse_enu,
    max_component_error,
    run_probe,
    witness,
)


REPO = Path(__file__).resolve().parents[2]

GEOGRAPHICLIB_PROBE_SOURCE = (
    REPO
    / "research"
    / "topocentric"
    / "geographiclib_localcartesian_probe.cpp"
)

# TOPO-D validation limits.
#
# These are research/release validation gates, not public
# accuracy guarantees.
#
# The observed forward and direct GeographicLib differences
# are at nanometre / ~1e-14 rad scale. The 1e-6 m and
# 1e-12 rad gates deliberately leave substantial numerical
# margin while still detecting meaningful regressions.
TOPO_D_LINEAR_TOL_M = 1.0e-6
TOPO_D_ANGULAR_TOL_RAD = 1.0e-12
TOPO_D_HEIGHT_TOL_M = 1.0e-6
TOPO_D_ECEF_TOL_M = 1.0e-6


@dataclass
class Maximum:
    value: float = 0.0
    witness: str = ""

    def observe(
        self,
        value: float,
        witness_text: str,
    ) -> None:
        if value > self.value:
            self.value = value
            self.witness = witness_text


def first_version_line(
    command: Sequence[str],
) -> str:
    proc = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=True,
    )

    output = (
        proc.stdout
        or proc.stderr
    ).strip()

    if not output:
        return "unknown"

    return output.splitlines()[0]


def geographiclib_version() -> str:
    proc = subprocess.run(
        [
            "dpkg-query",
            "-W",
            "-f=${Version}",
            "libgeographiclib-dev",
        ],
        text=True,
        capture_output=True,
        check=True,
    )

    return proc.stdout.strip()


def compile_geographiclib_probe(
    executable: Path,
) -> None:
    command = [
        "g++",
        "-std=c++17",
        "-O2",
        str(GEOGRAPHICLIB_PROBE_SOURCE),
        "-lGeographicLib",
        "-o",
        str(executable),
    ]

    proc = subprocess.run(
        command,
        cwd=REPO,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "GeographicLib probe compilation failed:\n"
            + " ".join(command)
            + "\n--- stdout ---\n"
            + proc.stdout
            + "\n--- stderr ---\n"
            + proc.stderr
        )


def run_geographiclib_probe(
    executable: Path,
    operation: str,
    ellipsoid: Ellipsoid,
    origin: Geodetic,
    rows: Sequence[Geodetic]
        | Sequence[Vec3],
) -> list[Geodetic] | list[Vec3]:
    command = [
        str(executable),
        operation,
        f"{ellipsoid.a:.17g}",
        f"{ellipsoid.f:.17g}",
        f"{origin.lat_deg:.17g}",
        f"{origin.lon_deg:.17g}",
        f"{origin.h:.17g}",
    ]

    if operation == "forward":
        payload = "".join(
            f"{row.lat_deg:.17g} "
            f"{row.lon_deg:.17g} "
            f"{row.h:.17g}\n"
            for row in rows
        )
    elif operation == "reverse":
        payload = "".join(
            f"{row.x:.17g} "
            f"{row.y:.17g} "
            f"{row.z:.17g}\n"
            for row in rows
        )
    else:
        raise ValueError(
            f"unknown operation: {operation}"
        )

    proc = subprocess.run(
        command,
        cwd=REPO,
        input=payload,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "GeographicLib probe failed:\n"
            + " ".join(command)
            + "\n--- stderr ---\n"
            + proc.stderr
        )

    if operation == "reverse":
        result_geo: list[Geodetic] = []

        for raw in proc.stdout.splitlines():
            line = raw.strip()

            if not line:
                continue

            fields = line.split()

            if len(fields) != 3:
                raise RuntimeError(
                    "unexpected GeographicLib "
                    f"output: {raw!r}"
                )

            lat, lon, h = map(
                float,
                fields,
            )

            result_geo.append(
                Geodetic(
                    lat_deg=lat,
                    lon_deg=lon,
                    h=h,
                )
            )

        if len(result_geo) != len(rows):
            raise RuntimeError(
                "GeographicLib row count mismatch: "
                f"expected {len(rows)}, "
                f"got {len(result_geo)}"
            )

        return result_geo

    result_vec: list[Vec3] = []

    for raw in proc.stdout.splitlines():
        line = raw.strip()

        if not line:
            continue

        fields = line.split()

        if len(fields) != 3:
            raise RuntimeError(
                "unexpected GeographicLib "
                f"output: {raw!r}"
            )

        east, north, up = map(
            float,
            fields,
        )

        result_vec.append(
            Vec3(
                east,
                north,
                up,
            )
        )

    if len(result_vec) != len(rows):
        raise RuntimeError(
            "GeographicLib row count mismatch: "
            f"expected {len(rows)}, "
            f"got {len(result_vec)}"
        )

    return result_vec


def main() -> None:
    compiler = os.environ.get(
        "DC",
        "dmd",
    )

    forward_rng = random.Random(
        FORWARD_SEED
    )

    reverse_rng = random.Random(
        REVERSE_SEED
    )

    metrics = {
        "forward D-GeographicLib [m]":
            Maximum(),

        "forward D-reference [m]":
            Maximum(),

        "forward GeographicLib-reference [m]":
            Maximum(),

        "reverse D-GeographicLib latitude [rad]":
            Maximum(),

        "reverse D-GeographicLib longitude [rad]":
            Maximum(),

        "reverse D-GeographicLib height [m]":
            Maximum(),

        "reverse D ECEF residual [m]":
            Maximum(),

        "reverse GeographicLib ECEF residual [m]":
            Maximum(),
    }

    forward_cases = 0
    reverse_cases = 0

    print(
        "=== geodesy-d vs GeographicLib "
        "LocalCartesian differential ==="
    )

    print(
        "GeographicLib package: "
        + geographiclib_version()
    )

    print(
        "C++ compiler: "
        + first_version_line(
            ["g++", "--version"]
        )
    )

    print(
        "D compiler: "
        + compiler_version(
            compiler
        )
    )

    print(
        "forward seed: "
        f"0x{FORWARD_SEED:016X}"
    )

    print(
        "reverse seed: "
        f"0x{REVERSE_SEED:016X}"
    )

    print(
        "forward cases/profile: "
        f"{FORWARD_CASES_PER_PROFILE}"
    )

    print(
        "reverse cases/profile: "
        f"{REVERSE_CASES_PER_PROFILE}"
    )

    print(
        "mode: TOPO-D PASS/FAIL"
    )

    print(
        "linear tolerance: "
        f"{TOPO_D_LINEAR_TOL_M:.3e} m"
    )

    print(
        "angular tolerance: "
        f"{TOPO_D_ANGULAR_TOL_RAD:.3e} rad"
    )

    print(
        "height tolerance: "
        f"{TOPO_D_HEIGHT_TOL_M:.3e} m"
    )

    print(
        "ECEF residual tolerance: "
        f"{TOPO_D_ECEF_TOL_M:.3e} m"
    )

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)

        d_probe = (
            tmp_path
            / "geodesy_topocentric_probe"
        )

        geographiclib_probe = (
            tmp_path
            / "geographiclib_localcartesian_probe"
        )

        compile_probe(
            compiler,
            d_probe,
        )

        compile_geographiclib_probe(
            geographiclib_probe,
        )

        for ellipsoid in ELLIPSOIDS:
            for origin in ORIGINS:
                origin_ecef = (
                    geodetic_to_ecef(
                        origin,
                        ellipsoid,
                    )
                )

                forward = forward_sources(
                    forward_rng,
                    origin,
                )

                forward_ecef = [
                    geodetic_to_ecef(
                        source,
                        ellipsoid,
                    )
                    for source in forward
                ]

                forward_reference = [
                    ecef_to_enu(
                        source,
                        origin_ecef,
                        origin.lat_deg,
                        origin.lon_deg,
                    )
                    for source
                    in forward_ecef
                ]

                reverse_enu = (
                    independent_reverse_enu(
                        reverse_rng
                    )
                )

                reverse_reference_ecef = [
                    enu_to_ecef(
                        source,
                        origin_ecef,
                        origin.lat_deg,
                        origin.lon_deg,
                    )
                    for source
                    in reverse_enu
                ]

                # ---------------------------------
                # Forward
                # ---------------------------------

                d_forward = run_probe(
                    d_probe,
                    "9837f",
                    ellipsoid,
                    (
                        origin.lat_deg,
                        origin.lon_deg,
                        origin.h,
                    ),
                    forward,
                )

                g_forward = (
                    run_geographiclib_probe(
                        geographiclib_probe,
                        "forward",
                        ellipsoid,
                        origin,
                        forward,
                    )
                )

                for index, (
                    d_value,
                    g_value,
                    reference,
                    source,
                ) in enumerate(zip(
                    d_forward,
                    g_forward,
                    forward_reference,
                    forward,
                )):
                    w = witness(
                        ellipsoid,
                        origin,
                        index,
                        source,
                    )

                    metrics[
                        "forward D-GeographicLib [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            g_value,
                        ),
                        w,
                    )

                    metrics[
                        "forward D-reference [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            reference,
                        ),
                        w,
                    )

                    metrics[
                        "forward GeographicLib-reference [m]"
                    ].observe(
                        max_component_error(
                            g_value,
                            reference,
                        ),
                        w,
                    )

                forward_cases += len(
                    forward
                )

                # ---------------------------------
                # Reverse, independent ENU
                # ---------------------------------

                d_reverse = run_probe(
                    d_probe,
                    "9837r",
                    ellipsoid,
                    (
                        origin.lat_deg,
                        origin.lon_deg,
                        origin.h,
                    ),
                    reverse_enu,
                )

                g_reverse = (
                    run_geographiclib_probe(
                        geographiclib_probe,
                        "reverse",
                        ellipsoid,
                        origin,
                        reverse_enu,
                    )
                )

                for index, (
                    d_value,
                    g_value,
                    reference_ecef,
                    source,
                ) in enumerate(zip(
                    d_reverse,
                    g_reverse,
                    reverse_reference_ecef,
                    reverse_enu,
                )):
                    w = witness(
                        ellipsoid,
                        origin,
                        index,
                        source,
                    )

                    lat_delta = abs(
                        deg_to_rad(
                            d_value.lat_deg
                            - g_value.lat_deg
                        )
                    )

                    lon_delta = abs(
                        angular_difference_rad(
                            deg_to_rad(
                                d_value.lon_deg
                            ),
                            deg_to_rad(
                                g_value.lon_deg
                            ),
                        )
                    )

                    height_delta = abs(
                        d_value.h
                        - g_value.h
                    )

                    metrics[
                        "reverse D-GeographicLib latitude [rad]"
                    ].observe(
                        lat_delta,
                        w,
                    )

                    metrics[
                        "reverse D-GeographicLib longitude [rad]"
                    ].observe(
                        lon_delta,
                        w,
                    )

                    metrics[
                        "reverse D-GeographicLib height [m]"
                    ].observe(
                        height_delta,
                        w,
                    )

                    d_ecef = geodetic_to_ecef(
                        d_value,
                        ellipsoid,
                    )

                    g_ecef = geodetic_to_ecef(
                        g_value,
                        ellipsoid,
                    )

                    metrics[
                        "reverse D ECEF residual [m]"
                    ].observe(
                        max_component_error(
                            d_ecef,
                            reference_ecef,
                        ),
                        w,
                    )

                    metrics[
                        "reverse GeographicLib ECEF residual [m]"
                    ].observe(
                        max_component_error(
                            g_ecef,
                            reference_ecef,
                        ),
                        w,
                    )

                reverse_cases += len(
                    reverse_enu
                )

                print(
                    "profile complete: "
                    f"{ellipsoid.name} / "
                    f"({origin.lat_deg:.6g}, "
                    f"{origin.lon_deg:.6g}, "
                    f"{origin.h:.6g})"
                )

    print()
    print("=== CASE COUNTS ===")

    print(
        f"forward: {forward_cases}"
    )

    print(
        f"reverse: {reverse_cases}"
    )

    expected_forward = (
        len(ELLIPSOIDS)
        * len(ORIGINS)
        * FORWARD_CASES_PER_PROFILE
    )

    expected_reverse = (
        len(ELLIPSOIDS)
        * len(ORIGINS)
        * REVERSE_CASES_PER_PROFILE
    )

    if forward_cases != expected_forward:
        raise RuntimeError(
            "unexpected forward case count"
        )

    if reverse_cases != expected_reverse:
        raise RuntimeError(
            "unexpected reverse case count"
        )

    print()
    print("=== MAXIMA ===")

    for name, maximum in metrics.items():
        print(
            f"{name}: "
            f"{maximum.value:.12e}"
        )

        print(
            "  witness: "
            f"{maximum.witness}"
        )

    print()
    print("=== TOPO-D ACCEPTANCE ===")

    checks = [
        (
            "forward D-GeographicLib [m]",
            TOPO_D_LINEAR_TOL_M,
        ),
        (
            "forward D-reference [m]",
            TOPO_D_LINEAR_TOL_M,
        ),
        (
            "forward GeographicLib-reference [m]",
            TOPO_D_LINEAR_TOL_M,
        ),
        (
            "reverse D-GeographicLib latitude [rad]",
            TOPO_D_ANGULAR_TOL_RAD,
        ),
        (
            "reverse D-GeographicLib longitude [rad]",
            TOPO_D_ANGULAR_TOL_RAD,
        ),
        (
            "reverse D-GeographicLib height [m]",
            TOPO_D_HEIGHT_TOL_M,
        ),
        (
            "reverse D ECEF residual [m]",
            TOPO_D_ECEF_TOL_M,
        ),
        (
            "reverse GeographicLib ECEF residual [m]",
            TOPO_D_ECEF_TOL_M,
        ),
    ]

    failures = []

    for name, limit in checks:
        value = metrics[name].value
        passed = value <= limit

        print(
            f"{'PASS' if passed else 'FAIL'}: "
            f"{name} = {value:.12e}; "
            f"limit = {limit:.12e}"
        )

        if not passed:
            failures.append(
                (
                    name,
                    value,
                    limit,
                    metrics[name].witness,
                )
            )

    if failures:
        print()
        print("=== FAILING WITNESSES ===")

        for (
            name,
            value,
            limit,
            failure_witness,
        ) in failures:
            print(
                f"{name}: "
                f"{value:.12e} > "
                f"{limit:.12e}"
            )
            print(
                f"  witness: "
                f"{failure_witness}"
            )

        raise SystemExit(
            "FAIL: TOPO-D GeographicLib "
            "LocalCartesian differential gate"
        )

    print()
    print(
        "PASS: TOPO-D GeographicLib "
        "LocalCartesian differential gate"
    )

    print(
        "100000 forward and 100000 independent "
        "reverse cases completed successfully."
    )


if __name__ == "__main__":
    main()
