#!/usr/bin/env python3

from pathlib import Path
import re
import subprocess
import sys

EXPECTED_COMMIT = "475cbde5b8528a6294dfeb054bc177d90be9f7bb"

if len(sys.argv) != 3:
    raise SystemExit(
        "usage: generate_area_series_module.py "
        "/path/to/geographiclib-r2.7 "
        "/path/to/output/geodesic_area_series.d"
    )

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
source_path = "src/Geodesic.cpp"

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

text = subprocess.check_output(
    ["git", "-C", str(root), "show", f"{commit}:{source_path}"],
    encoding="utf-8",
)

def extract_function(name: str) -> str:
    marker = f"Geodesic::{name}"
    pos = text.find(marker)
    if pos < 0:
        raise RuntimeError(f"function not found: {marker}")

    start = text.rfind("\n", 0, pos) + 1
    brace = text.find("{", pos)
    depth = 0

    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]

    raise RuntimeError(f"unterminated function: {marker}")

def extract_order_branch(function: str, order: int) -> str:
    match = re.search(
        rf"#(?:if|elif)\s+GEOGRAPHICLIB_GEODESIC_ORDER\s*==\s*{order}\b",
        function,
    )
    if not match:
        raise RuntimeError(f"no order-{order} branch found")

    tail = function[match.end():]
    end = re.search(r"(?m)^#(?:elif|else|endif)\b", tail)
    if not end:
        raise RuntimeError(f"end of order-{order} branch not found")
    return tail[:end.start()]

def extract_coefficients(order: int) -> list[int]:
    branch = extract_order_branch(extract_function("C4coeff"), order)
    array = re.search(
        r"static\s+const\s+real\s+coeff\[\]\s*=\s*\{(.*?)\};",
        branch,
        flags=re.S,
    )
    if not array:
        raise RuntimeError(f"C4 coefficient array not found for order {order}")

    body = re.sub(r"//[^\n]*", "", array.group(1))
    return [int(v) for v in re.findall(r"[-+]?\d+", body)]

def d_array(name: str, values: list[int]) -> str:
    lines = [f"private immutable long[{len(values)}] {name} = ["]
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

tables = {}
for order in (6, 7, 8):
    values = extract_coefficients(order)
    expected = order * (order + 1) * (order + 5) // 6
    if len(values) != expected:
        raise RuntimeError(
            f"unexpected C4 coefficient count for order {order}: "
            f"expected {expected}, got {len(values)}"
        )
    tables[order] = values

arrays = "\n\n".join(
    d_array(f"c4Order{order}", tables[order])
    for order in (6, 7, 8)
)

module = f'''/**
 * Internal Karney geodesic area-series support.
 *
 * Generated from GeographicLib 2.7 source commit:
 *
 *     {EXPECTED_COMMIT}
 *
 * Coefficient provenance:
 *
 *     src/Geodesic.cpp, Geodesic::C4coeff / Geodesic::C4f
 *
 * GeographicLib is Copyright Charles Karney and distributed under the
 * MIT/X11 license.
 *
 * Do not edit the coefficient arrays manually. Regenerate them with:
 *
 *     research/geodesics/generate_area_series_module.py
 */
module geodesy.internal.geodesic_area_series;


package(geodesy):


{arrays}


private W polynomialFromIntegers(W, size_t N)(
    const ref long[N] coefficients,
    const size_t offset,
    const int degree,
    const W x)
    pure nothrow @safe @nogc
{{
    W result = cast(W) coefficients[offset];

    foreach (i; 1 .. degree + 1)
        result = result * x + cast(W) coefficients[offset + i];

    return result;
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
        result = result * x + coefficients[offset + i];

    return result;
}}


private void fillC4xFromCoefficients(
    W,
    int order,
    size_t N)(
    const W n,
    const ref long[N] coefficients,
    ref W[36] result)
    pure nothrow @safe @nogc
{{
    result[] = cast(W) 0;

    size_t inputOffset = 0;
    size_t outputIndex = 0;

    foreach (l; 0 .. order)
    {{
        for (int j = order - 1; j >= l; --j)
        {{
            const int degree =
                order - j - 1;

            result[outputIndex++] =
                polynomialFromIntegers!W(
                    coefficients,
                    inputOffset,
                    degree,
                    n)
                / cast(W) coefficients[
                    inputOffset
                    + cast(size_t) degree
                    + 1];

            inputOffset +=
                cast(size_t) degree
                + 2;
        }}
    }}
}}


/** Prepare the ellipsoid-dependent C4 polynomial table. */
void fillGeodesicC4x(W, int order)(
    const W n,
    ref W[36] result)
    pure nothrow @safe @nogc
{{
    static assert(
        order >= 6 && order <= 8,
        "unsupported geodesic series order");

    static if (order == 6)
        fillC4xFromCoefficients!(W, order)(
            n,
            c4Order6,
            result);
    else static if (order == 7)
        fillC4xFromCoefficients!(W, order)(
            n,
            c4Order7,
            result);
    else
        fillC4xFromCoefficients!(W, order)(
            n,
            c4Order8,
            result);
}}


/** Evaluate the C4 area-series coefficients for one geodesic epsilon. */
void fillGeodesicC4(W, int order)(
    const W eps,
    const ref W[36] c4x,
    ref W[9] result)
    pure nothrow @safe @nogc
{{
    static assert(
        order >= 6 && order <= 8,
        "unsupported geodesic series order");

    result[] = cast(W) 0;

    W multiplier =
        cast(W) 1;

    size_t offset = 0;

    foreach (l; 0 .. order)
    {{
        const int degree =
            order - cast(int) l - 1;

        result[l] =
            multiplier
            * polynomialFromScalars!W(
                c4x,
                offset,
                degree,
                eps);

        offset +=
            cast(size_t) degree
            + 1;

        multiplier *=
            eps;
    }}
}}


unittest
{{
    double[36] c4x;
    double[9] c4;

    fillGeodesicC4x!(double, 6)(
        0.0,
        c4x);

    fillGeodesicC4!(double, 6)(
        0.0,
        c4x,
        c4);

    /*
     * C4[0] remains finite on a sphere; all higher C4 terms carry explicit
     * powers of eps and therefore vanish at eps == 0.
     */
    assert(c4[0] == c4[0]);

    foreach (value; c4[1 .. 6])
        assert(value == 0.0);

    double[36] order7;
    double[36] order8;

    fillGeodesicC4x!(double, 7)(0.001, order7);
    fillGeodesicC4x!(double, 8)(0.001, order8);

    foreach (value; order7)
        assert(value == value);

    foreach (value; order8)
        assert(value == value);
}}
'''

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(module, encoding="utf-8")

print(output)
print(f"source commit: {commit}")
for order in (6, 7, 8):
    print(f"C4coeff order={order} coefficients={len(tables[order])}")
