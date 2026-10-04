#!/usr/bin/env python3

from pathlib import Path
import re
import subprocess
import sys


EXPECTED_COMMIT = "475cbde5b8528a6294dfeb054bc177d90be9f7bb"

if len(sys.argv) != 3:
    raise SystemExit(
        "usage: generate_direct_series_module.py "
        "/path/to/geographiclib-r2.7 "
        "/path/to/output/geodesic_series.d"
    )

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])

SOURCE_PATH = "src/Geodesic.cpp"

commit = subprocess.check_output(
    ["git", "-C", str(root), "rev-parse", "HEAD"],
    encoding="utf-8",
).strip()

if commit != EXPECTED_COMMIT:
    raise SystemExit(
        "unexpected GeographicLib source commit:\n"
        f"  expected: {EXPECTED_COMMIT}\n"
        f"  actual:   {commit}"
    )

try:
    text = subprocess.check_output(
        [
            "git",
            "-C",
            str(root),
            "show",
            f"{EXPECTED_COMMIT}:{SOURCE_PATH}",
        ],
        encoding="utf-8",
    )
except subprocess.CalledProcessError as error:
    raise SystemExit(
        f"cannot read {SOURCE_PATH} from GeographicLib "
        f"commit {EXPECTED_COMMIT}"
    ) from error


def extract_function(name: str) -> str:
    marker = f"Geodesic::{name}"
    pos = text.find(marker)

    if pos < 0:
        raise RuntimeError(f"function not found: {marker}")

    start = text.rfind("\n", 0, pos) + 1
    brace = text.find("{", pos)

    if brace < 0:
        raise RuntimeError(f"opening brace not found: {marker}")

    depth = 0

    for i in range(brace, len(text)):
        ch = text[i]

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1

            if depth == 0:
                return text[start:i + 1]

    raise RuntimeError(f"unterminated function: {marker}")


def extract_order_branch(function: str, order: int) -> str:
    patterns = (
        rf"#(?:if|elif)\s+"
        rf"GEOGRAPHICLIB_GEODESIC_ORDER\s*==\s*{order}\b",

        rf"#(?:if|elif)\s+"
        rf"GEOGRAPHICLIB_GEODESIC_ORDER/2\s*==\s*{order // 2}\b",
    )

    starts = []

    for pattern in patterns:
        match = re.search(pattern, function)

        if match:
            starts.append(match)

    if not starts:
        raise RuntimeError(
            f"no order-{order} branch found"
        )

    match = min(starts, key=lambda item: item.start())
    tail = function[match.end():]

    end = re.search(
        r"(?m)^#(?:elif|else|endif)\b",
        tail,
    )

    if not end:
        raise RuntimeError(
            f"end of order-{order} branch not found"
        )

    return tail[:end.start()]


def extract_coefficients(name: str, order: int) -> list[int]:
    function = extract_function(name)
    branch = extract_order_branch(function, order)

    array = re.search(
        r"static\s+const\s+real\s+coeff\[\]\s*=\s*"
        r"\{(.*?)\};",
        branch,
        flags=re.S,
    )

    if not array:
        raise RuntimeError(
            f"coefficient array not found: {name}, order {order}"
        )

    body = re.sub(
        r"//[^\n]*",
        "",
        array.group(1),
    )

    values = [
        int(value)
        for value in re.findall(r"[-+]?\d+", body)
    ]

    if not values:
        raise RuntimeError(
            f"empty coefficient array: {name}, order {order}"
        )

    return values


FUNCTIONS = (
    "A1m1f",
    "C1f",
    "C1pf",
    "A2m1f",
    "C2f",
    "A3coeff",
    "C3coeff",
)

EXPECTED_COUNTS = {
    "A1m1f":  {6: 5,  7: 5,  8: 6},
    "C1f":    {6: 18, 7: 23, 8: 28},
    "C1pf":   {6: 18, 7: 23, 8: 28},
    "A2m1f":  {6: 5,  7: 5,  8: 6},
    "C2f":    {6: 18, 7: 23, 8: 28},
    "A3coeff": {6: 18, 7: 23, 8: 28},
    "C3coeff": {6: 45, 7: 69, 8: 98},
}

tables: dict[tuple[str, int], list[int]] = {}

for name in FUNCTIONS:
    for order in (6, 7, 8):
        values = extract_coefficients(
            name,
            order,
        )

        expected_count = EXPECTED_COUNTS[name][order]

        if len(values) != expected_count:
            raise RuntimeError(
                f"unexpected coefficient count for {name}, "
                f"order {order}: expected {expected_count}, "
                f"got {len(values)}"
            )

        tables[(name, order)] = values


def d_array(name: str, values: list[int]) -> str:
    lines = [
        f"private immutable long[{len(values)}] {name} = ["
    ]

    row = "    "

    for value in values:
        token = f"{value}, "

        if len(row) + len(token) > 92:
            lines.append(row.rstrip())
            row = "    "

        row += token

    if row.strip():
        lines.append(row.rstrip())

    lines.append("];")

    return "\n".join(lines)


generated_arrays = []

names = {
    "A1m1f": "a1",
    "C1f": "c1",
    "C1pf": "c1p",
    "A2m1f": "a2",
    "C2f": "c2",
    "A3coeff": "a3",
    "C3coeff": "c3",
}

for function in FUNCTIONS:
    stem = names[function]

    for order in (6, 7, 8):
        generated_arrays.append(
            d_array(
                f"{stem}Order{order}",
                tables[(function, order)],
            )
        )

arrays_text = "\n\n".join(generated_arrays)

module = f'''/**
 * Internal Karney geodesic series support.
 *
 * Generated from GeographicLib 2.7 (`r2.7`) source commit:
 *
 *     {EXPECTED_COMMIT}
 *
 * Coefficient provenance:
 *
 *     src/Geodesic.cpp
 *
 * GeographicLib is Copyright Charles Karney and distributed under the
 * MIT/X11 license.
 *
 * Do not edit the coefficient arrays manually. Regenerate them with:
 *
 *     research/geodesics/generate_direct_series_module.py
 */
module geodesy.internal.geodesic_series;

import geodesy.scalar : isGeodesyScalar;


package(geodesy):


template geodesicSeriesOrderFor(T)
if (isGeodesyScalar!T)
{{
    static if (is(T == float) || is(T == double))
        enum int geodesicSeriesOrderFor = 6;
    else static if (T.mant_dig <= 53)
        enum int geodesicSeriesOrderFor = 6;
    else static if (T.mant_dig <= 64)
        enum int geodesicSeriesOrderFor = 7;
    else
        enum int geodesicSeriesOrderFor = 8;
}}


{arrays_text}


private W polynomialFromIntegers(W, size_t N)(
    const ref long[N] coefficients,
    const size_t offset,
    const int degree,
    const W x)
    pure nothrow @safe @nogc
{{
    W result = cast(W) coefficients[offset];

    foreach (i; 1 .. degree + 1)
        result =
            result * x
            + cast(W) coefficients[offset + i];

    return result;
}}


private W rationalPolynomial(W, size_t N)(
    const ref long[N] coefficients,
    const size_t offset,
    const int degree,
    const W x)
    pure nothrow @safe @nogc
{{
    return polynomialFromIntegers!W(
            coefficients,
            offset,
            degree,
            x)
        / cast(W) coefficients[offset + degree + 1];
}}


private W polynomialFromScalars(W, size_t N)(
    const ref W[N] coefficients,
    const size_t offset,
    const int degree,
    const W x)
    pure nothrow @safe @nogc
{{
    W result = coefficients[offset];

    foreach (i; 1 .. degree + 1)
        result =
            result * x
            + coefficients[offset + i];

    return result;
}}


private W a1FromCoefficients(W, size_t N)(
    const W eps,
    const int order,
    const ref long[N] coefficients)
    pure nothrow @safe @nogc
{{
    const int degree = order / 2;
    const W eps2 = eps * eps;

    const W t = rationalPolynomial!W(
        coefficients,
        0,
        degree,
        eps2);

    return (t + eps) / (cast(W) 1 - eps);
}}


W geodesicA1m1(W, int order)(const W eps)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        return a1FromCoefficients!W(
            eps,
            order,
            a1Order6);
    else static if (order == 7)
        return a1FromCoefficients!W(
            eps,
            order,
            a1Order7);
    else
        return a1FromCoefficients!W(
            eps,
            order,
            a1Order8);
}}


private W a2FromCoefficients(W, size_t N)(
    const W eps,
    const int order,
    const ref long[N] coefficients)
    pure nothrow @safe @nogc
{{
    const int degree = order / 2;
    const W eps2 = eps * eps;

    const W t = rationalPolynomial!W(
        coefficients,
        0,
        degree,
        eps2);

    return (t - eps) / (cast(W) 1 + eps);
}}


W geodesicA2m1(W, int order)(const W eps)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        return a2FromCoefficients!W(
            eps,
            order,
            a2Order6);
    else static if (order == 7)
        return a2FromCoefficients!W(
            eps,
            order,
            a2Order7);
    else
        return a2FromCoefficients!W(
            eps,
            order,
            a2Order8);
}}


private void fillCSeriesLike(W, size_t N)(
    const W eps,
    const int order,
    const ref long[N] coefficients,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    result[] = cast(W) 0;

    const W eps2 = eps * eps;
    W multiplier = eps;
    size_t offset = 0;

    for (int l = 1; l <= order; ++l)
    {{
        const int degree = (order - l) / 2;

        result[l] =
            multiplier
            * rationalPolynomial!W(
                coefficients,
                offset,
                degree,
                eps2);

        offset += cast(size_t) degree + 2;
        multiplier *= eps;
    }}
}}


void fillGeodesicC1(W, int order)(
    const W eps,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        fillCSeriesLike!W(
            eps,
            order,
            c1Order6,
            result);
    else static if (order == 7)
        fillCSeriesLike!W(
            eps,
            order,
            c1Order7,
            result);
    else
        fillCSeriesLike!W(
            eps,
            order,
            c1Order8,
            result);
}}


void fillGeodesicC1p(W, int order)(
    const W eps,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        fillCSeriesLike!W(
            eps,
            order,
            c1pOrder6,
            result);
    else static if (order == 7)
        fillCSeriesLike!W(
            eps,
            order,
            c1pOrder7,
            result);
    else
        fillCSeriesLike!W(
            eps,
            order,
            c1pOrder8,
            result);
}}


void fillGeodesicC2(W, int order)(
    const W eps,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        fillCSeriesLike!W(
            eps,
            order,
            c2Order6,
            result);
    else static if (order == 7)
        fillCSeriesLike!W(
            eps,
            order,
            c2Order7,
            result);
    else
        fillCSeriesLike!W(
            eps,
            order,
            c2Order8,
            result);
}}


private void fillA3FromCoefficients(W, size_t N)(
    const W n,
    const int order,
    const ref long[N] coefficients,
    ref W[8] result)
    pure nothrow @safe @nogc
{{
    result[] = cast(W) 0;

    size_t offset = 0;
    size_t index = 0;

    for (int j = order - 1; j >= 0; --j)
    {{
        const int left = order - j - 1;
        const int degree = left < j ? left : j;

        result[index++] =
            rationalPolynomial!W(
                coefficients,
                offset,
                degree,
                n);

        offset += cast(size_t) degree + 2;
    }}
}}


void fillGeodesicA3x(W, int order)(
    const W n,
    ref W[8] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        fillA3FromCoefficients!W(
            n,
            order,
            a3Order6,
            result);
    else static if (order == 7)
        fillA3FromCoefficients!W(
            n,
            order,
            a3Order7,
            result);
    else
        fillA3FromCoefficients!W(
            n,
            order,
            a3Order8,
            result);
}}


private void fillC3xFromCoefficients(W, size_t N)(
    const W n,
    const int order,
    const ref long[N] coefficients,
    ref W[28] result)
    pure nothrow @safe @nogc
{{
    result[] = cast(W) 0;

    size_t offset = 0;
    size_t index = 0;

    for (int l = 1; l < order; ++l)
    {{
        for (int j = order - 1; j >= l; --j)
        {{
            const int left = order - j - 1;
            const int degree = left < j ? left : j;

            result[index++] =
                rationalPolynomial!W(
                    coefficients,
                    offset,
                    degree,
                    n);

            offset += cast(size_t) degree + 2;
        }}
    }}
}}


void fillGeodesicC3x(W, int order)(
    const W n,
    ref W[28] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    static if (order == 6)
        fillC3xFromCoefficients!W(
            n,
            order,
            c3Order6,
            result);
    else static if (order == 7)
        fillC3xFromCoefficients!W(
            n,
            order,
            c3Order7,
            result);
    else
        fillC3xFromCoefficients!W(
            n,
            order,
            c3Order8,
            result);
}}


W geodesicA3(W, int order)(
    const W eps,
    const ref W[8] a3x)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    return polynomialFromScalars!W(
        a3x,
        0,
        order - 1,
        eps);
}}


void fillGeodesicC3(W, int order)(
    const W eps,
    const ref W[28] c3x,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    static assert(order >= 6 && order <= 8);

    result[] = cast(W) 0;

    W multiplier = cast(W) 1;
    size_t offset = 0;

    for (int l = 1; l < order; ++l)
    {{
        const int degree = order - l - 1;

        multiplier *= eps;

        result[l] =
            multiplier
            * polynomialFromScalars!W(
                c3x,
                offset,
                degree,
                eps);

        offset += cast(size_t) degree + 1;
    }}
}}


W geodesicSinCosSeries(W)(
    const bool sineSeries,
    const W sinX,
    const W cosX,
    const ref W[9] coefficients,
    int terms)
    pure nothrow @safe @nogc
{{
    int index = terms + (sineSeries ? 1 : 0);

    const W recurrence =
        cast(W) 2
        * (cosX - sinX)
        * (cosX + sinX);

    W y0 =
        (terms & 1) != 0
            ? coefficients[--index]
            : cast(W) 0;

    W y1 = cast(W) 0;

    terms /= 2;

    while (terms-- > 0)
    {{
        y1 =
            recurrence * y0
            - y1
            + coefficients[--index];

        y0 =
            recurrence * y1
            - y0
            + coefficients[--index];
    }}

    return sineSeries
        ? cast(W) 2 * sinX * cosX * y0
        : cosX * (y0 - y1);
}}


unittest
{{
    assert(geodesicA2m1!(double, 6)(0.0) == 0.0);
    assert(geodesicA2m1!(double, 7)(0.0) == 0.0);
    assert(geodesicA2m1!(double, 8)(0.0) == 0.0);

    double[9] c2Order6Test;
    double[9] c2Order7Test;
    double[9] c2Order8Test;

    fillGeodesicC2!(double, 6)(
        0.0,
        c2Order6Test);

    fillGeodesicC2!(double, 7)(
        0.0,
        c2Order7Test);

    fillGeodesicC2!(double, 8)(
        0.0,
        c2Order8Test);

    foreach (value; c2Order6Test)
        assert(value == 0.0);

    foreach (value; c2Order7Test)
        assert(value == 0.0);

    foreach (value; c2Order8Test)
        assert(value == 0.0);
}}


unittest
{{
    static assert(geodesicSeriesOrderFor!float == 6);
    static assert(geodesicSeriesOrderFor!double == 6);

    static if (real.mant_dig <= 53)
        static assert(geodesicSeriesOrderFor!real == 6);
    else static if (real.mant_dig <= 64)
        static assert(geodesicSeriesOrderFor!real == 7);
    else
        static assert(geodesicSeriesOrderFor!real == 8);

    enum int order = 6;

    assert(geodesicA1m1!(double, order)(0.0) == 0.0);

    double[9] c1;
    double[9] c1p;

    fillGeodesicC1!(double, order)(0.0, c1);
    fillGeodesicC1p!(double, order)(0.0, c1p);

    foreach (value; c1)
        assert(value == 0.0);

    foreach (value; c1p)
        assert(value == 0.0);

    double[8] a3x;
    double[28] c3x;
    double[9] c3;

    fillGeodesicA3x!(double, order)(0.0, a3x);
    fillGeodesicC3x!(double, order)(0.0, c3x);

    assert(
        geodesicA3!(double, order)(
            0.0,
            a3x)
        == 1.0);

    fillGeodesicC3!(double, order)(
        0.0,
        c3x,
        c3);

    foreach (value; c3)
        assert(value == 0.0);

    double[9] c1Order7Test;
    double[9] c1pOrder7Test;
    double[8] a3xOrder7Test;
    double[28] c3xOrder7Test;
    double[9] c3Order7Test;

    assert(geodesicA1m1!(double, 7)(0.0) == 0.0);
    fillGeodesicC1!(double, 7)(0.0, c1Order7Test);
    fillGeodesicC1p!(double, 7)(0.0, c1pOrder7Test);
    fillGeodesicA3x!(double, 7)(0.0, a3xOrder7Test);
    fillGeodesicC3x!(double, 7)(0.0, c3xOrder7Test);
    assert(
        geodesicA3!(double, 7)(
            0.0,
            a3xOrder7Test)
        == 1.0);
    fillGeodesicC3!(double, 7)(
        0.0,
        c3xOrder7Test,
        c3Order7Test);

    double[9] c1Order8Test;
    double[9] c1pOrder8Test;
    double[8] a3xOrder8Test;
    double[28] c3xOrder8Test;
    double[9] c3Order8Test;

    assert(geodesicA1m1!(double, 8)(0.0) == 0.0);
    fillGeodesicC1!(double, 8)(0.0, c1Order8Test);
    fillGeodesicC1p!(double, 8)(0.0, c1pOrder8Test);
    fillGeodesicA3x!(double, 8)(0.0, a3xOrder8Test);
    fillGeodesicC3x!(double, 8)(0.0, c3xOrder8Test);
    assert(
        geodesicA3!(double, 8)(
            0.0,
            a3xOrder8Test)
        == 1.0);
    fillGeodesicC3!(double, 8)(
        0.0,
        c3xOrder8Test,
        c3Order8Test);

    double[9] simple;
    simple[1] = 2.0;

    assert(
        geodesicSinCosSeries(
            true,
            0.5,
            0.5,
            simple,
            1)
        == 1.0);
}}
'''

output.parent.mkdir(
    parents=True,
    exist_ok=True,
)

output.write_bytes(module.encode("utf-8"))

print(output)
print(f"source commit: {commit}")

for name in FUNCTIONS:
    for order in (6, 7, 8):
        values = tables[(name, order)]

        print(
            f"{name:8s} "
            f"order={order} "
            f"coefficients={len(values)}"
        )
