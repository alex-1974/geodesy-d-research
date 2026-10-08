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

print("R69.5 prepared temporary signed-flattening source")


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

print("R69.5 added temporary prolate authalic-area branch")


intersection = out / "geodesy" / "geodesic_intersection.d"
text = intersection.read_text()

if "    atan,\n" not in text:
    marker = "import std.math :\n"
    if marker not in text:
        raise SystemExit("intersection std.math import missing")
    text = text.replace(
        marker,
        marker + "    atan,\n",
        1)

old_authalic = """    if (!(e2 > cast(W) 0)
        || !(e2 < cast(W) 1))
        return false;

    const W e =
        sqrt(e2);

    const W radiusSquared =
        a * a
        * cast(W) 0.5
        * (
            cast(W) 1
            + (cast(W) 1 - e2) / e * atanh(e));"""

new_authalic = """    if (!(e2 > cast(W) -1)
        || !(e2 < cast(W) 1))
        return false;

    const W e =
        sqrt(abs(e2));

    const W factor =
        e2 > cast(W) 0
            ? atanh(e) / e
            : atan(e) / e;

    const W radiusSquared =
        a * a
        * cast(W) 0.5
        * (
            cast(W) 1
            + (cast(W) 1 - e2) * factor);"""

if old_authalic not in text:
    raise SystemExit("intersection authalic marker missing")
text = text.replace(old_authalic, new_authalic, 1)

old_spacing = """    t1 = cast(W) PI * a * (cast(W) 1 - f);
    delta = d * pow(W.epsilon, cast(W) 0.2);
    if (f == cast(W) 0)
    {
        d1 = cast(W) PI * a / cast(W) 2;
        return true;
    }"""

new_spacing = """    const W meridionalHalf =
        cast(W) PI * a * (cast(W) 1 - f);

    t1 = meridionalHalf;
    delta = d * pow(W.epsilon, cast(W) 0.2);

    if (f == cast(W) 0)
    {
        d1 = cast(W) PI * a / cast(W) 2;
        return true;
    }"""

if old_spacing not in text:
    raise SystemExit("closest spacing preamble marker missing")
text = text.replace(old_spacing, new_spacing, 1)

old_return = """    return tryIntersectionConjugateFromOrigin!T(
        line, tolerance, initial, true, d1);
}"""

new_return = """    W polarSemiConjugate;

    if (!tryIntersectionConjugateFromOrigin!T(
            line,
            tolerance,
            initial,
            true,
            polarSemiConjugate))
        return false;

    if (f < cast(W) 0)
    {
        t1 = cast(W) 2 * polarSemiConjugate;
        d1 = meridionalHalf / cast(W) 2;
        return isFiniteGeodesyScalar(t1)
            && isFiniteGeodesyScalar(d1)
            && t1 > cast(W) 0
            && d1 > cast(W) 0;
    }

    d1 = polarSemiConjugate;
    return true;
}"""

if old_return not in text:
    raise SystemExit("closest spacing return marker missing")
text = text.replace(old_return, new_return, 1)

intersection.write_text(text)

print("R69.5 added temporary prolate Closest spacing")

intersection = out / "geodesy" / "geodesic_intersection.d"
text = intersection.read_text()

old_next = """    W t3;

    if (f == cast(W) 0)
    {
        t3 = halfCircumference;
    }
    else
    {
        if (!tryIntersectionDistOblique!T(
                solver,
                authalicRadius,
                t3))
            return false;
    }

    d2 =
        cast(W) 2 * t3 / cast(W) 3;"""

new_next = """    W t3;

    if (f == cast(W) 0)
    {
        t3 = halfCircumference;
    }
    else if (f < cast(W) 0)
    {
        Latitude!T poleLatitude;
        Longitude!T zeroLongitude;
        Latitude!T zeroLatitude;

        if (!Latitude!T.tryFromRadians(
                cast(T) (cast(W) PI / cast(W) 2),
                poleLatitude)
            || !Latitude!T.tryFromRadians(
                cast(T) 0,
                zeroLatitude)
            || !Longitude!T.tryFromRadians(
                cast(T) 0,
                zeroLongitude))
            return false;

        const auto equator =
            GeographicCoordinate!T.fromComponents(
                zeroLatitude,
                zeroLongitude);

        const auto pole =
            GeographicCoordinate!T.fromComponents(
                poleLatitude,
                zeroLongitude);

        GeodesicInverseResult!T meridian;

        if (!solver.tryInverse(
                equator,
                pole,
                meridian))
            return false;

        t3 =
            cast(W) 2
            * cast(W) meridian.distance;

        Angle!T poleAzimuth;

        if (!Angle!T.tryFromRadians(
                cast(T) 0,
                poleAzimuth))
            return false;

        GeodesicLine!T polarLine;

        if (!GeodesicLine!T.tryFromGeodesic(
                solver,
                pole,
                poleAzimuth,
                polarLine))
            return false;

        const W tolerance =
            halfCircumference
            * pow(W.epsilon, cast(W) 0.75);

        const W initial =
            (cast(W) 1 + f / cast(W) 2)
            * a
            * cast(W) PI
            / cast(W) 2;

        W polarSemiConjugate;

        if (!tryIntersectionConjugateFromOrigin!T(
                polarLine,
                tolerance,
                initial,
                true,
                polarSemiConjugate))
            return false;

        t1 =
            cast(W) 2
            * polarSemiConjugate;
    }
    else
    {
        if (!tryIntersectionDistOblique!T(
                solver,
                authalicRadius,
                t3))
            return false;
    }

    d2 =
        cast(W) 2 * t3 / cast(W) 3;"""

if old_next not in text:
    raise SystemExit("next spacing marker missing")
text = text.replace(old_next, new_next, 1)
intersection.write_text(text)
print("R69.5 added temporary prolate Next spacing")

intersection = out / "geodesy" / "geodesic_intersection.d"
text = intersection.read_text()

marker = "struct GeodesicIntersectionSolver(T)\nif (isGeodesyScalar!T)\n{"
if marker not in text:
    raise SystemExit("intersection solver marker missing")

helper = r"""
/** R69.5 research-only GeographicLib-compatible distpolar helper. */
private bool tryIntersectionDistPolarResearch(T)(
    const Geodesic!T solver,
    const IntersectionWorkingScalar!T authalicRadius,
    const IntersectionWorkingScalar!T latitudeDegrees,
    out IntersectionWorkingScalar!T distance)
    pure nothrow @safe @nogc
if (isGeodesyScalar!T)
{
    alias W = IntersectionWorkingScalar!T;

    Latitude!T latitude;
    Longitude!T longitude;
    Angle!T azimuth;

    if (!Latitude!T.tryFromRadians(
            cast(T) (
                latitudeDegrees
                * cast(W) PI
                / cast(W) 180),
            latitude)
        || !Longitude!T.tryFromRadians(
            cast(T) 0,
            longitude)
        || !Angle!T.tryFromRadians(
            cast(T) 0,
            azimuth))
        return false;

    const auto origin =
        GeographicCoordinate!T.fromComponents(
            latitude,
            longitude);

    GeodesicLine!T line;

    if (!GeodesicLine!T.tryFromGeodesic(
            solver,
            origin,
            azimuth,
            line))
        return false;

    const W d =
        cast(W) PI
        * authalicRadius;

    const W tolerance =
        d
        * pow(
            W.epsilon,
            cast(W) 0.75);

    const W f =
        cast(W) solver.ellipsoid.flattening;

    const W a =
        cast(W) solver.ellipsoid.semiMajorAxis;

    const W initial =
        (cast(W) 1 + f / cast(W) 2)
        * a
        * cast(W) PI
        / cast(W) 2;

    return tryIntersectionConjugateFromOrigin!T(
        line,
        tolerance,
        initial,
        true,
        distance);
}


/** R69.5 research-only GeographicLib polarb analogue. */
private bool tryIntersectionPolarBoundResearch(T)(
    const Geodesic!T solver,
    const IntersectionWorkingScalar!T authalicRadius,
    out IntersectionWorkingScalar!T distance)
    pure nothrow @safe @nogc
if (isGeodesyScalar!T)
{
    alias W = IntersectionWorkingScalar!T;

    W lat0 = cast(W) 63;
    W lat1 = cast(W) 65;
    W lat2 = cast(W) 64;

    W s0;
    W s1;
    W s2;

    if (!tryIntersectionDistPolarResearch!T(
            solver,
            authalicRadius,
            lat0,
            s0)
        || !tryIntersectionDistPolarResearch!T(
            solver,
            authalicRadius,
            lat1,
            s1)
        || !tryIntersectionDistPolarResearch!T(
            solver,
            authalicRadius,
            lat2,
            s2))
        return false;

    W sx = s2;
    const W f =
        cast(W) solver.ellipsoid.flattening;

    foreach (_; 0 .. 10)
    {
        const W denominator =
            (lat1 - lat0) * s2
            + (lat0 - lat2) * s1
            + (lat2 - lat1) * s0;

        if (!(denominator < cast(W) 0
            || denominator > cast(W) 0))
            break;

        const W nextLatitude =
            (
                (lat1 - lat0) * (lat1 + lat0) * s2
                + (lat0 - lat2) * (lat0 + lat2) * s1
                + (lat2 - lat1) * (lat2 + lat1) * s0
            )
            / (
                cast(W) 2
                * denominator);

        lat0 = lat1;
        s0 = s1;
        lat1 = lat2;
        s1 = s2;
        lat2 = nextLatitude;

        if (!tryIntersectionDistPolarResearch!T(
                solver,
                authalicRadius,
                lat2,
                s2))
            return false;

        const bool better =
            f < cast(W) 0
                ? s2 < sx
                : s2 > sx;

        if (better)
            sx = s2;
    }

    distance =
        cast(W) 2
        * sx;

    return isFiniteGeodesyScalar(distance)
        && distance > cast(W) 0;
}


"""

text = text.replace(marker, helper + marker, 1)

old = """        const W flattening =
            cast(W) solver.ellipsoid.flattening;

        if (flattening < cast(W) 0)
            return false;

        result._allT1 = nextT1;
        result._allDelta = nextDelta;
        result._allD3 = nextT1 - nextDelta;"""

new = """        const W flattening =
            cast(W) solver.ellipsoid.flattening;

        W allT4 =
            nextT1;

        if (flattening < cast(W) 0
            && !tryIntersectionPolarBoundResearch!T(
                solver,
                authalicRadius,
                allT4))
            return false;

        result._allT1 = nextT1;
        result._allDelta = nextDelta;
        result._allD3 = allT4 - nextDelta;"""

if old not in text:
    raise SystemExit("all prepared-state marker missing")
text = text.replace(old, new, 1)

intersection.write_text(text)
print("R69.5 added temporary prolate All polarb spacing")
