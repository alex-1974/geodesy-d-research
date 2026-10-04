#!/usr/bin/env python3

"""
Controlled PM-E1C1B reverse-performance matrix.

Research-only benchmark.  It compares the selected extended-real reverse
latitude path against the same R6 path with only the quotient-residual
correction disabled.

The benchmark corpus and timed kernel live in pm_e1_kernel_probe.d under
PseudoMercatorReverseBenchmark.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import statistics
import subprocess
from pathlib import Path


ROOT = (
    Path(__file__)
    .resolve()
    .parents[2]
)

KERNEL = (
    ROOT
    / "research"
    / "pseudo-mercator"
    / "pm_e1_kernel_probe.d"
)

ERRORS = (
    ROOT
    / "source"
    / "geodesy"
    / "errors.d"
)


COMPILERS = (
    (
        "dmd",
        "dmd_2_111_0",
        "dmd-2.111.0",
    ),
    (
        "dmd",
        "dmd_2_112_1",
        "dmd-2.112.1",
    ),
    (
        "dmd",
        "dmd_2_113_0",
        "dmd-2.113.0",
    ),
    (
        "ldc",
        "ldc_1_41_0",
        "ldc-1.41.0",
    ),
    (
        "ldc",
        "ldc_1_42_0",
        "ldc-1.42.0",
    ),
    (
        "ldc",
        "ldc_1_43_0",
        "ldc-1.43.0",
    ),
)


def run_text(
    command: list[str],
) -> tuple[int, str]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    return (
        result.returncode,
        result.stdout
        + result.stderr,
    )


def percentile(
    values: list[float],
    fraction: float,
) -> float:
    ordered = sorted(
        values
    )

    position = (
        len(ordered) - 1
    ) * fraction

    low = int(
        position
    )

    high = min(
        low + 1,
        len(ordered) - 1,
    )

    part = (
        position - low
    )

    return (
        ordered[low]
        * (1.0 - part)
        + ordered[high]
        * part
    )


def compiler_identity(
    compiler: str,
) -> str:
    status, text = run_text(
        [
            compiler,
            "--version",
        ]
    )

    if status != 0:
        return (
            f"ERROR: --version returned "
            f"{status}\n{text}"
        )

    return "\n".join(
        text.strip()
        .splitlines()[:10]
    )


def build(
    family: str,
    label: str,
    compiler: str,
    output_dir: Path,
) -> tuple[Path, int]:
    binary = (
        output_dir
        / label
    )

    try:
        binary.unlink()
    except FileNotFoundError:
        pass

    if family == "dmd":
        command = [
            compiler,
            "-preview=in",
            "-wi",
            "-O",
            "-release",
            "-version=PseudoMercatorReverseBenchmark",
            "-Isource",
            str(KERNEL),
            str(ERRORS),
            f"-of={binary}",
        ]
    else:
        command = [
            compiler,
            "-preview=in",
            "-wi",
            "-O3",
            "-release",
            "--d-version=PseudoMercatorReverseBenchmark",
            "-Isource",
            str(KERNEL),
            str(ERRORS),
            f"-of={binary}",
        ]

    status, text = run_text(
        command
    )

    if text:
        print(
            text,
            end=""
            if text.endswith("\n")
            else "\n",
        )

    print(
        f"build status: {status}"
    )

    return (
        binary,
        status,
    )


def execute(
    binary: Path,
    cpu: int,
    output: Path,
) -> int:
    result = subprocess.run(
        [
            "taskset",
            "-c",
            str(cpu),
            str(binary),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    output.write_text(
        result.stdout,
        encoding="utf-8",
    )

    if result.stderr:
        print(
            result.stderr,
            end=""
            if result.stderr.endswith("\n")
            else "\n",
        )

    return (
        result.returncode
    )


def parse_output(
    path: Path,
):
    operations: dict[
        str,
        int,
    ] = {}

    rows = []
    failures = []

    for line in path.read_text(
        encoding="utf-8"
    ).splitlines():
        fields = line.split(
            "\t"
        )

        if not fields:
            continue

        values = {}

        for field in fields[1:]:
            if "=" not in field:
                continue

            key, value = (
                field.split(
                    "=",
                    1,
                )
            )

            values[key] = value

        if fields[0] == "META":
            operations[
                values["profile"]
            ] = int(
                values[
                    "operations"
                ]
            )

        elif fields[0] == "RESULT":
            rows.append(
                values
            )

        elif fields[0] == "FAIL":
            failures.append(
                line
            )

    return (
        operations,
        rows,
        failures,
    )


def summarize(
    path: Path,
):
    (
        operations,
        rows,
        failures,
    ) = parse_output(
        path
    )

    summaries = []

    for profile in sorted(
        operations
    ):
        subset = [
            row
            for row in rows
            if row[
                "profile"
            ] == profile
        ]

        expected_operations = (
            operations[
                profile
            ]
        )

        if len(subset) != 21:
            failures.append(
                f"profile={profile}: "
                f"RESULT rows={len(subset)} "
                "expected=21"
            )

            continue

        baseline = [
            int(
                row[
                    "baseline_ns"
                ]
            )
            / expected_operations
            for row in subset
        ]

        selected = [
            int(
                row[
                    "selected_ns"
                ]
            )
            / expected_operations
            for row in subset
        ]

        overhead = [
            (
                int(
                    row[
                        "selected_ns"
                    ]
                )
                / int(
                    row[
                        "baseline_ns"
                    ]
                )
                - 1.0
            )
            * 100.0
            for row in subset
        ]

        order_medians = {}

        for order in (
            "BS",
            "SB",
        ):
            order_values = [
                (
                    int(
                        row[
                            "selected_ns"
                        ]
                    )
                    / int(
                        row[
                            "baseline_ns"
                        ]
                    )
                    - 1.0
                )
                * 100.0
                for row in subset
                if row[
                    "order"
                ] == order
            ]

            if not order_values:
                failures.append(
                    f"profile={profile}: "
                    f"missing order={order}"
                )

                order_medians[
                    order
                ] = float(
                    "nan"
                )
            else:
                order_medians[
                    order
                ] = (
                    statistics.median(
                        order_values
                    )
                )

        successes_ok = all(
            int(
                row[
                    "baseline_success"
                ]
            )
            == expected_operations
            and int(
                row[
                    "selected_success"
                ]
            )
            == expected_operations
            for row in subset
        )

        if not successes_ok:
            failures.append(
                f"profile={profile}: "
                "unexpected rejection"
            )

        summaries.append(
            (
                profile,
                statistics.median(
                    baseline
                ),
                statistics.median(
                    selected
                ),
                statistics.median(
                    overhead
                ),
                percentile(
                    overhead,
                    0.10,
                ),
                percentile(
                    overhead,
                    0.90,
                ),
                order_medians[
                    "BS"
                ],
                order_medians[
                    "SB"
                ],
            )
        )

    return (
        summaries,
        failures,
    )


def main() -> int:
    parser = (
        argparse.ArgumentParser()
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "/tmp/"
            "geodesy-pm-e1c1-"
            "reverse-benchmark"
        ),
    )

    parser.add_argument(
        "--cpu",
        type=int,
    )

    args = (
        parser.parse_args()
    )

    output_dir = (
        args.output_dir
        .expanduser()
        .resolve()
    )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    if args.cpu is None:
        cpu = min(
            os.sched_getaffinity(
                0
            )
        )
    else:
        cpu = args.cpu

    print(
        "=== PM-E1C1B REVERSE "
        "PERFORMANCE MATRIX ==="
    )

    print(
        "repo:",
        ROOT,
    )

    print(
        "git HEAD:",
        subprocess.run(
            [
                "git",
                "rev-parse",
                "--short",
                "HEAD",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        ).stdout.strip(),
    )

    print(
        "host:",
        platform.platform(),
    )

    print(
        "logical CPU:",
        cpu,
    )

    print(
        "output:",
        output_dir,
    )

    print()
    print(
        "=== HOST CPU ==="
    )

    cpu_status, cpu_text = (
        run_text(
            [
                "lscpu",
            ]
        )
    )

    if cpu_status == 0:
        wanted = (
            "Architecture:",
            "CPU(s):",
            "Thread(s) per core:",
            "Core(s) per socket:",
            "Socket(s):",
            "Model name:",
            "CPU min MHz:",
            "CPU max MHz:",
        )

        for line in (
            cpu_text.splitlines()
        ):
            if line.startswith(
                wanted
            ):
                print(
                    line
                )

    failures = 0
    completed = {}

    print()
    print(
        "=== TOOLCHAIN MATRIX ==="
    )

    for (
        family,
        label,
        compiler,
    ) in COMPILERS:
        print()
        print(
            "========================================"
        )

        print(
            compiler
        )

        print(
            "========================================"
        )

        resolved = (
            shutil.which(
                compiler
            )
        )

        if resolved is None:
            print(
                "FAIL: compiler missing"
            )

            failures += 1
            continue

        print(
            compiler_identity(
                compiler
            )
        )

        binary, status = build(
            family,
            label,
            compiler,
            output_dir,
        )

        if status != 0:
            failures += 1
            continue

        output = (
            output_dir
            / f"{label}.out"
        )

        status = execute(
            binary,
            cpu,
            output,
        )

        print(
            f"run status: {status}"
        )

        if status != 0:
            failures += 1
            continue

        completed[
            label
        ] = output

    print()
    print(
        "=== PERFORMANCE MATRIX ANALYSIS ==="
    )

    print(
        "compiler\tprofile"
        "\tbaseline_ns_op"
        "\tselected_ns_op"
        "\toverhead_pct"
        "\tp10_pct"
        "\tp90_pct"
        "\tBS_pct"
        "\tSB_pct"
    )

    for label in sorted(
        completed
    ):
        (
            summaries,
            local_failures,
        ) = summarize(
            completed[
                label
            ]
        )

        for failure in (
            local_failures
        ):
            print(
                "FAIL:",
                label,
                failure,
            )

        failures += len(
            local_failures
        )

        for (
            profile,
            baseline,
            selected,
            overhead,
            p10,
            p90,
            bs,
            sb,
        ) in summaries:
            print(
                label,
                profile,
                f"{baseline:.3f}",
                f"{selected:.3f}",
                f"{overhead:+.3f}",
                f"{p10:+.3f}",
                f"{p90:+.3f}",
                f"{bs:+.3f}",
                f"{sb:+.3f}",
                sep="\t",
            )

    print()
    print(
        "=== MATRIX COMPLETENESS ==="
    )

    print(
        "expected compilers:",
        len(COMPILERS),
    )

    print(
        "completed compilers:",
        len(completed),
    )

    if (
        len(completed)
        != len(COMPILERS)
    ):
        failures += (
            len(COMPILERS)
            - len(completed)
        )

    print()
    print(
        "=== RESULT ==="
    )

    if failures == 0:
        print(
            "PASS: controlled "
            "PM-E1C1B performance "
            "matrix completed"
        )
    else:
        print(
            "FAIL: total failures=",
            failures,
            sep="",
        )

    return (
        failures
    )


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
