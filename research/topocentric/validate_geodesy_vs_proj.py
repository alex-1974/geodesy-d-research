#!/usr/bin/env python3

from __future__ import annotations

import os
import random
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from validate_proj_oracle import (
    ELLIPSOIDS,
    ORIGINS,
    SEED,
    Ellipsoid,
    Geodetic,
    Vec3,
    angular_difference_rad,
    cct_version,
    deg_to_rad,
    ecef_to_enu,
    enu_to_ecef,
    geodetic_to_ecef,
    local_sources,
    max_component_error,
    random_sources,
    run_cct,
    run_cct_geodetic,
    run_cct_geodetic_inverse,
    structured_sources,
)


REPO = Path(__file__).resolve().parents[2]

PROBE_SOURCE = (
    REPO
    / "research"
    / "topocentric"
    / "geodesy_topocentric_probe.d"
)

FORWARD_CASES_PER_PROFILE = 5_000
REVERSE_CASES_PER_PROFILE = 5_000
LOCAL_FORWARD_CASES = 1_000

PROBE_SCALAR = os.environ.get(
    "GEODESY_TOPO_SCALAR",
    "double",
).strip().lower()

if PROBE_SCALAR not in ("double", "real"):
    raise RuntimeError(
        "GEODESY_TOPO_SCALAR must be 'double' or 'real'"
    )

# TOPO-C validation limits.
#
# These are research/release validation gates, not public accuracy promises.
# The linear limit intentionally leaves substantial margin over the observed
# nanometre-scale forward/9836 results and the sub-micrometre 9837 reverse
# reconstructed-ECEF residual.
TOPO_LINEAR_TOL_M = 1.0e-6
TOPO_REVERSE_ECEF_TOL_M = 1.0e-6

# Reuse the already qualified PROJ pipeline-attribution limits. These verify
# that any larger geographic reverse difference is attributable to PROJ's
# cart inverse rather than its topocentric stage.
PROJ_PIPELINE_LAT_TOL_RAD = 1.0e-13
PROJ_PIPELINE_LON_TOL_RAD = 1.0e-12
PROJ_PIPELINE_HEIGHT_TOL_M = 1.0e-6

FORWARD_SEED = (
    SEED ^ 0x4657445F44494646
)

REVERSE_SEED = (
    SEED ^ 0x5245565F44494646
)


@dataclass
class Maximum:
    value: float = 0.0
    witness: str = ""

    def observe(
        self,
        value: float,
        witness: str,
    ) -> None:
        if value > self.value:
            self.value = value
            self.witness = witness


def compiler_version(
    compiler: str,
) -> str:
    proc = subprocess.run(
        [compiler, "--version"],
        text=True,
        capture_output=True,
        check=True,
    )

    output = (
        proc.stdout
        or proc.stderr
    ).strip()

    if not output:
        return compiler

    return output.splitlines()[0]


def compile_probe(
    compiler: str,
    executable: Path,
) -> None:
    command = [
        compiler,
        "-Isource",
        "-i",
        str(PROBE_SOURCE),
        f"-of={executable}",
    ]

    if PROBE_SCALAR == "real":
        compiler_name = Path(compiler).name.lower()

        version_flag = (
            "-d-version=TopocentricRealProbe"
            if "ldc" in compiler_name
            else "-version=TopocentricRealProbe"
        )

        command.insert(
            3,
            version_flag,
        )

    proc = subprocess.run(
        command,
        cwd=REPO,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "probe compilation failed:\n"
            + " ".join(command)
            + "\n--- stdout ---\n"
            + proc.stdout
            + "\n--- stderr ---\n"
            + proc.stderr
        )


def run_probe(
    executable: Path,
    operation: str,
    ellipsoid: Ellipsoid,
    origin: Sequence[float],
    rows: Sequence[Vec3]
        | Sequence[Geodetic],
) -> list[Vec3] | list[Geodetic]:
    command = [
        str(executable),
        operation,
        f"{ellipsoid.a:.17g}",
        f"{ellipsoid.f:.17g}",
        *(
            f"{value:.17g}"
            for value in origin
        ),
    ]

    if operation == "9837f":
        payload = "".join(
            f"{row.lat_deg:.17g} "
            f"{row.lon_deg:.17g} "
            f"{row.h:.17g}\n"
            for row in rows
        )
    else:
        payload = "".join(
            f"{row.x:.17g} "
            f"{row.y:.17g} "
            f"{row.z:.17g}\n"
            for row in rows
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
            "geodesy-d probe failed:\n"
            + " ".join(command)
            + "\n--- stderr ---\n"
            + proc.stderr
        )

    if operation == "9837r":
        result_geo: list[Geodetic] = []

        for raw in proc.stdout.splitlines():
            line = raw.strip()

            if not line:
                continue

            fields = line.split()

            if len(fields) != 3:
                raise RuntimeError(
                    "unexpected probe output: "
                    f"{raw!r}"
                )

            a, b, c = map(
                float,
                fields,
            )

            result_geo.append(
                Geodetic(
                    lat_deg=a,
                    lon_deg=b,
                    h=c,
                )
            )

        if len(result_geo) != len(rows):
            raise RuntimeError(
                "probe row count mismatch: "
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
                "unexpected probe output: "
                f"{raw!r}"
            )

        a, b, c = map(
            float,
            fields,
        )

        result_vec.append(
            Vec3(
                a,
                b,
                c,
            )
        )

    if len(result_vec) != len(rows):
        raise RuntimeError(
            "probe row count mismatch: "
            f"expected {len(rows)}, "
            f"got {len(result_vec)}"
        )

    return result_vec


def forward_sources(
    rng: random.Random,
    origin: Geodetic,
) -> list[Geodetic]:
    structured = structured_sources()

    random_count = (
        FORWARD_CASES_PER_PROFILE
        - len(structured)
        - LOCAL_FORWARD_CASES
    )

    if random_count < 0:
        raise RuntimeError(
            "forward corpus configuration "
            "is invalid"
        )

    result = [
        *structured,
        *random_sources(
            rng,
            random_count,
        ),
        *local_sources(
            rng,
            origin,
            LOCAL_FORWARD_CASES,
        ),
    ]

    if (
        len(result)
        != FORWARD_CASES_PER_PROFILE
    ):
        raise RuntimeError(
            "unexpected forward corpus size"
        )

    return result


def independent_reverse_enu(
    rng: random.Random,
) -> list[Vec3]:
    """
    Generate the reverse corpus directly in ENU space.

    No value in this corpus is obtained through a
    forward topocentric transformation.
    """

    scales = [
        1.0e-3,
        1.0e-2,
        1.0e-1,
        1.0,
        10.0,
        100.0,
        1_000.0,
        10_000.0,
        100_000.0,
        500_000.0,
    ]

    result = [
        Vec3(
            0.0,
            0.0,
            0.0,
        ),
    ]

    for scale in scales:
        result.extend([
            Vec3(+scale, 0.0, 0.0),
            Vec3(-scale, 0.0, 0.0),

            Vec3(0.0, +scale, 0.0),
            Vec3(0.0, -scale, 0.0),

            Vec3(0.0, 0.0, +scale),
            Vec3(0.0, 0.0, -scale),

            Vec3(
                +scale,
                +scale,
                +scale,
            ),
            Vec3(
                +scale,
                -scale,
                +scale,
            ),
            Vec3(
                -scale,
                +scale,
                -scale,
            ),
            Vec3(
                -scale,
                -scale,
                -scale,
            ),
        ])

    while (
        len(result)
        < REVERSE_CASES_PER_PROFILE
    ):
        scale = scales[
            rng.randrange(
                len(scales)
            )
        ]

        result.append(
            Vec3(
                rng.uniform(
                    -scale,
                    scale,
                ),
                rng.uniform(
                    -scale,
                    scale,
                ),
                rng.uniform(
                    -scale,
                    scale,
                ),
            )
        )

    return result[
        :REVERSE_CASES_PER_PROFILE
    ]


def witness(
    ellipsoid: Ellipsoid,
    origin: Geodetic,
    index: int,
    value: object,
) -> str:
    return (
        f"ellipsoid={ellipsoid.name}; "
        f"origin="
        f"({origin.lat_deg:.15g},"
        f"{origin.lon_deg:.15g},"
        f"{origin.h:.15g}); "
        f"index={index}; "
        f"input={value}"
    )


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
        "9836 forward D-PROJ [m]":
            Maximum(),
        "9836 forward D-reference [m]":
            Maximum(),
        "9836 forward PROJ-reference [m]":
            Maximum(),

        "9836 reverse D-PROJ [m]":
            Maximum(),
        "9836 reverse D-reference [m]":
            Maximum(),
        "9836 reverse PROJ-reference [m]":
            Maximum(),

        "9837 forward D-PROJ [m]":
            Maximum(),
        "9837 forward D-reference [m]":
            Maximum(),
        "9837 forward PROJ-reference [m]":
            Maximum(),

        "9837 reverse D-PROJ latitude [rad]":
            Maximum(),
        "9837 reverse D-PROJ longitude [rad]":
            Maximum(),
        "9837 reverse D-PROJ height [m]":
            Maximum(),

        "9837 reverse D ECEF residual [m]":
            Maximum(),
        "9837 reverse PROJ ECEF residual [m]":
            Maximum(),
        "9837 reverse cart ECEF residual [m]":
            Maximum(),

        "9837 reverse PROJ-vs-cart latitude [rad]":
            Maximum(),
        "9837 reverse PROJ-vs-cart longitude [rad]":
            Maximum(),
        "9837 reverse PROJ-vs-cart height [m]":
            Maximum(),
    }

    cases_9836_forward = 0
    cases_9836_reverse = 0
    cases_9837_forward = 0
    cases_9837_reverse = 0

    print(
        "=== geodesy-d vs PROJ "
        "topocentric differential ==="
    )

    print(cct_version())

    print(
        "compiler: "
        + compiler_version(
            compiler
        )
    )

    print(
        "probe scalar: "
        + PROBE_SCALAR
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
        "mode: "
        + (
            "TOPO-G wide-real differential"
            if PROBE_SCALAR == "real"
            else "TOPO-C PASS/FAIL"
        )
    )

    print(
        "linear tolerance: "
        f"{TOPO_LINEAR_TOL_M:.3e} m"
    )

    print(
        "reverse ECEF tolerance: "
        f"{TOPO_REVERSE_ECEF_TOL_M:.3e} m"
    )

    with tempfile.TemporaryDirectory() as tmp:
        executable = (
            Path(tmp)
            / "geodesy_topocentric_probe"
        )

        compile_probe(
            compiler,
            executable,
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

                forward_reference_enu = [
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

                ellipsoid_args = (
                    ellipsoid.proj_args()
                )

                op_cart = [
                    "+proj=cart",
                    *ellipsoid_args,
                ]

                op9836 = [
                    "+proj=topocentric",
                    *ellipsoid_args,
                    (
                        "+X_0="
                        f"{origin_ecef.x:.17g}"
                    ),
                    (
                        "+Y_0="
                        f"{origin_ecef.y:.17g}"
                    ),
                    (
                        "+Z_0="
                        f"{origin_ecef.z:.17g}"
                    ),
                ]

                op9837 = [
                    "+proj=pipeline",
                    "+step",
                    "+proj=cart",
                    *ellipsoid_args,
                    "+step",
                    "+proj=topocentric",
                    *ellipsoid_args,
                    (
                        "+lon_0="
                        f"{origin.lon_deg:.17g}"
                    ),
                    (
                        "+lat_0="
                        f"{origin.lat_deg:.17g}"
                    ),
                    (
                        "+h_0="
                        f"{origin.h:.17g}"
                    ),
                ]

                # ---------------------------------
                # EPSG 9836 forward
                # ---------------------------------

                d_9836_forward = run_probe(
                    executable,
                    "9836f",
                    ellipsoid,
                    (
                        origin_ecef.x,
                        origin_ecef.y,
                        origin_ecef.z,
                    ),
                    forward_ecef,
                )

                p_9836_forward = run_cct(
                    op9836,
                    forward_ecef,
                )

                for index, (
                    d_value,
                    p_value,
                    reference,
                    source,
                ) in enumerate(zip(
                    d_9836_forward,
                    p_9836_forward,
                    forward_reference_enu,
                    forward,
                )):
                    w = witness(
                        ellipsoid,
                        origin,
                        index,
                        source,
                    )

                    metrics[
                        "9836 forward D-PROJ [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            p_value,
                        ),
                        w,
                    )

                    metrics[
                        "9836 forward D-reference [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            reference,
                        ),
                        w,
                    )

                    metrics[
                        "9836 forward PROJ-reference [m]"
                    ].observe(
                        max_component_error(
                            p_value,
                            reference,
                        ),
                        w,
                    )

                cases_9836_forward += len(
                    forward
                )

                # ---------------------------------
                # EPSG 9836 reverse
                # Independent ENU input.
                # ---------------------------------

                d_9836_reverse = run_probe(
                    executable,
                    "9836r",
                    ellipsoid,
                    (
                        origin_ecef.x,
                        origin_ecef.y,
                        origin_ecef.z,
                    ),
                    reverse_enu,
                )

                p_9836_reverse = run_cct(
                    op9836,
                    reverse_enu,
                    inverse=True,
                )

                for index, (
                    d_value,
                    p_value,
                    reference,
                    source,
                ) in enumerate(zip(
                    d_9836_reverse,
                    p_9836_reverse,
                    reverse_reference_ecef,
                    reverse_enu,
                )):
                    w = witness(
                        ellipsoid,
                        origin,
                        index,
                        source,
                    )

                    metrics[
                        "9836 reverse D-PROJ [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            p_value,
                        ),
                        w,
                    )

                    metrics[
                        "9836 reverse D-reference [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            reference,
                        ),
                        w,
                    )

                    metrics[
                        "9836 reverse PROJ-reference [m]"
                    ].observe(
                        max_component_error(
                            p_value,
                            reference,
                        ),
                        w,
                    )

                cases_9836_reverse += len(
                    reverse_enu
                )

                # ---------------------------------
                # EPSG 9837 forward
                # ---------------------------------

                d_9837_forward = run_probe(
                    executable,
                    "9837f",
                    ellipsoid,
                    (
                        origin.lat_deg,
                        origin.lon_deg,
                        origin.h,
                    ),
                    forward,
                )

                p_9837_forward = (
                    run_cct_geodetic(
                        op9837,
                        forward,
                    )
                )

                for index, (
                    d_value,
                    p_value,
                    reference,
                    source,
                ) in enumerate(zip(
                    d_9837_forward,
                    p_9837_forward,
                    forward_reference_enu,
                    forward,
                )):
                    w = witness(
                        ellipsoid,
                        origin,
                        index,
                        source,
                    )

                    metrics[
                        "9837 forward D-PROJ [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            p_value,
                        ),
                        w,
                    )

                    metrics[
                        "9837 forward D-reference [m]"
                    ].observe(
                        max_component_error(
                            d_value,
                            reference,
                        ),
                        w,
                    )

                    metrics[
                        "9837 forward PROJ-reference [m]"
                    ].observe(
                        max_component_error(
                            p_value,
                            reference,
                        ),
                        w,
                    )

                cases_9837_forward += len(
                    forward
                )

                # ---------------------------------
                # EPSG 9837 reverse
                # Independent ENU input.
                # ---------------------------------

                d_9837_reverse = run_probe(
                    executable,
                    "9837r",
                    ellipsoid,
                    (
                        origin.lat_deg,
                        origin.lon_deg,
                        origin.h,
                    ),
                    reverse_enu,
                )

                p_9837_reverse = (
                    run_cct_geodetic_inverse(
                        op9837,
                        reverse_enu,
                    )
                )

                p_cart_reverse = (
                    run_cct_geodetic_inverse(
                        op_cart,
                        reverse_reference_ecef,
                    )
                )

                for index, (
                    d_value,
                    p_value,
                    cart_value,
                    reference_ecef,
                    source,
                ) in enumerate(zip(
                    d_9837_reverse,
                    p_9837_reverse,
                    p_cart_reverse,
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
                            - p_value.lat_deg
                        )
                    )

                    lon_delta = abs(
                        angular_difference_rad(
                            deg_to_rad(
                                d_value.lon_deg
                            ),
                            deg_to_rad(
                                p_value.lon_deg
                            ),
                        )
                    )

                    height_delta = abs(
                        d_value.h
                        - p_value.h
                    )

                    metrics[
                        "9837 reverse D-PROJ latitude [rad]"
                    ].observe(
                        lat_delta,
                        w,
                    )

                    metrics[
                        "9837 reverse D-PROJ longitude [rad]"
                    ].observe(
                        lon_delta,
                        w,
                    )

                    metrics[
                        "9837 reverse D-PROJ height [m]"
                    ].observe(
                        height_delta,
                        w,
                    )

                    pipeline_cart_lat_delta = abs(
                        deg_to_rad(
                            p_value.lat_deg
                            - cart_value.lat_deg
                        )
                    )

                    pipeline_cart_lon_delta = abs(
                        angular_difference_rad(
                            deg_to_rad(
                                p_value.lon_deg
                            ),
                            deg_to_rad(
                                cart_value.lon_deg
                            ),
                        )
                    )

                    pipeline_cart_height_delta = abs(
                        p_value.h
                        - cart_value.h
                    )

                    metrics[
                        "9837 reverse PROJ-vs-cart latitude [rad]"
                    ].observe(
                        pipeline_cart_lat_delta,
                        w,
                    )

                    metrics[
                        "9837 reverse PROJ-vs-cart longitude [rad]"
                    ].observe(
                        pipeline_cart_lon_delta,
                        w,
                    )

                    metrics[
                        "9837 reverse PROJ-vs-cart height [m]"
                    ].observe(
                        pipeline_cart_height_delta,
                        w,
                    )

                    d_ecef = geodetic_to_ecef(
                        d_value,
                        ellipsoid,
                    )

                    p_ecef = geodetic_to_ecef(
                        p_value,
                        ellipsoid,
                    )

                    cart_ecef = geodetic_to_ecef(
                        cart_value,
                        ellipsoid,
                    )

                    metrics[
                        "9837 reverse D ECEF residual [m]"
                    ].observe(
                        max_component_error(
                            d_ecef,
                            reference_ecef,
                        ),
                        w,
                    )

                    metrics[
                        "9837 reverse PROJ ECEF residual [m]"
                    ].observe(
                        max_component_error(
                            p_ecef,
                            reference_ecef,
                        ),
                        w,
                    )

                    metrics[
                        "9837 reverse cart ECEF residual [m]"
                    ].observe(
                        max_component_error(
                            cart_ecef,
                            reference_ecef,
                        ),
                        w,
                    )

                cases_9837_reverse += len(
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
        "9836 forward: "
        f"{cases_9836_forward}"
    )

    print(
        "9836 reverse: "
        f"{cases_9836_reverse}"
    )

    print(
        "9837 forward: "
        f"{cases_9837_forward}"
    )

    print(
        "9837 reverse: "
        f"{cases_9837_reverse}"
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

    if (
        cases_9836_forward
        != expected_forward
    ):
        raise RuntimeError(
            "unexpected 9836 forward "
            "case count"
        )

    if (
        cases_9837_forward
        != expected_forward
    ):
        raise RuntimeError(
            "unexpected 9837 forward "
            "case count"
        )

    if (
        cases_9836_reverse
        != expected_reverse
    ):
        raise RuntimeError(
            "unexpected 9836 reverse "
            "case count"
        )

    if (
        cases_9837_reverse
        != expected_reverse
    ):
        raise RuntimeError(
            "unexpected 9837 reverse "
            "case count"
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

    gate_label = (
        "TOPO-G wide-real topocentric differential gate"
        if PROBE_SCALAR == "real"
        else "TOPO-C geodesy-d topocentric differential gate"
    )

    acceptance_heading = (
        "=== TOPO-G REAL ACCEPTANCE ==="
        if PROBE_SCALAR == "real"
        else "=== TOPO-C ACCEPTANCE ==="
    )

    print(acceptance_heading)

    checks = [
        (
            "9836 forward D-PROJ [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9836 forward D-reference [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9836 reverse D-PROJ [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9836 reverse D-reference [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9837 forward D-PROJ [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9837 forward D-reference [m]",
            TOPO_LINEAR_TOL_M,
        ),
        (
            "9837 reverse D ECEF residual [m]",
            TOPO_REVERSE_ECEF_TOL_M,
        ),
        (
            "9837 reverse PROJ-vs-cart latitude [rad]",
            PROJ_PIPELINE_LAT_TOL_RAD,
        ),
        (
            "9837 reverse PROJ-vs-cart longitude [rad]",
            PROJ_PIPELINE_LON_TOL_RAD,
        ),
        (
            "9837 reverse PROJ-vs-cart height [m]",
            PROJ_PIPELINE_HEIGHT_TOL_M,
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

        for name, value, limit, failure_witness in failures:
            print(
                f"{name}: "
                f"{value:.12e} > "
                f"{limit:.12e}"
            )
            print(
                f"  witness: {failure_witness}"
            )

        raise SystemExit(
            "FAIL: " + gate_label
        )

    print()
    print(
        "PASS: " + gate_label
    )

    print(
        "100000 cases per public path "
        "completed successfully."
    )

    print(
        "Direct EPSG 9837 reverse D-PROJ "
        "geodetic deltas are diagnostic only; "
        "PROJ cart-inverse attribution is "
        "validated separately above."
    )


if __name__ == "__main__":
    main()
