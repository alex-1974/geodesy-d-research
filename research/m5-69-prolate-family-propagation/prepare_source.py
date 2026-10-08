#!/usr/bin/env python3
from pathlib import Path
import shutil
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: prepare_source.py GEODESY_D OUT_SOURCE")

repo = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()

if out.exists():
    shutil.rmtree(out)
shutil.copytree(repo / "source", out)

ellipsoid = out / "geodesy" / "ellipsoid.d"
text = ellipsoid.read_text()

replacements = {
    "&& _flattening >= cast(T) 0\n            && _flattening < cast(T) 1;":
        "&& _flattening > cast(T) -1\n            && _flattening < cast(T) 1;",
    "flattening < 0 || flattening >= 1":
        "flattening <= -1 || flattening >= 1",
    "inverseFlattening <= 1":
        "(inverseFlattening > 0 && inverseFlattening <= 1) || inverseFlattening == 0",
    "semiMinorAxis <= 0 || semiMinorAxis > semiMajorAxis":
        "semiMinorAxis <= 0",
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"ellipsoid marker missing: {old}")
    text = text.replace(old, new, 1)

ellipsoid.write_text(text)

geodesic = out / "geodesy" / "geodesic.d"
text = geodesic.read_text()

replacements = {
    "&& _f >= cast(W) 0\n            && _f <= cast(W) 0.01":
        "&& _f >= cast(W) -0.01\n            && _f <= cast(W) 0.01",
    "&& _e2 >= cast(W) 0":
        "&& _e2 > cast(W) -1",
    "&& _ep2 >= cast(W) 0":
        "&& _ep2 > cast(W) -1",
    "&& _n >= cast(W) 0;":
        "&& _n > cast(W) -1;",
    "|| ellipsoid.flattening > cast(T) 0.01)":
        "|| ellipsoid.flattening < cast(T) -0.01\n            || ellipsoid.flattening > cast(T) 0.01)",
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"geodesic marker missing: {old}")
    text = text.replace(old, new, 1)

geodesic.write_text(text)

print("R69.4 prepared temporary signed-flattening source")


area = out / "geodesy" / "internal" / "geodesic_area.d"
text = area.read_text()

if "    atanh,\n    sqrt;" not in text:
    raise SystemExit("area import marker missing")
text = text.replace(
    "    atanh,\n    sqrt;",
    "    atan,\n    atanh,\n    sqrt;",
    1)

old = """    const W e =
        sqrt(e2);

    return (
        a * a
        + b * b
            * atanh(e)
            / e
    ) / cast(W) 2;"""

new = """    const W factor =
        e2 > cast(W) 0
            ? atanh(sqrt(e2)) / sqrt(e2)
            : atan(sqrt(-e2)) / sqrt(-e2);

    return (
        a * a
        + b * b * factor
    ) / cast(W) 2;"""

if old not in text:
    raise SystemExit("area formula marker missing")
text = text.replace(old, new, 1)
area.write_text(text)

print("R69.4 added temporary prolate authalic-area branch")
