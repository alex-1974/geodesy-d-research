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
    "|| ellipsoid.flattening > cast(T) 0.01)":
        "|| ellipsoid.flattening < cast(T) -0.01\n            || ellipsoid.flattening > cast(T) 0.01)",
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"geodesic marker missing: {old}")
    text = text.replace(old, new, 1)

geodesic.write_text(text)

print("R69.3 prepared temporary signed-flattening source")
