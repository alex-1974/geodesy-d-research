module tm_output_specialization_probe;

import core.time : MonoTime;
import std.algorithm.sorting : sort;
import std.math : PI;
import std.stdio : writefln, writeln;

import geodesy;

enum size_t sampleCount = 16_384;
enum size_t roundCount = 21;

__gshared double sink = 0.0;

enum CorpusKind
{
    utmLike,
    ordinary,
    wide
}

string corpusName(CorpusKind kind)
{
    final switch (kind)
    {
        case CorpusKind.utmLike:
            return "utm-like";
        case CorpusKind.ordinary:
            return "ordinary";
        case CorpusKind.wide:
            return "wide";
    }
}

double deltaLongitudeDegrees(
    CorpusKind kind,
    size_t i)
{
    const size_t j =
        (i * 4_051UL + 1_729UL)
        % sampleCount;

    const double u =
        (cast(double) j + 0.5)
        / cast(double) sampleCount;

    final switch (kind)
    {
        case CorpusKind.utmLike:
            return -3.0 + 6.0 * u;

        case CorpusKind.ordinary:
            return -35.0 + 70.0 * u;

        case CorpusKind.wide:
        {
            const double magnitude =
                35.0 + 25.0 * u;

            return (i & 1) == 0
                ? -magnitude
                : magnitude;
        }
    }
}

double latitudeDegrees(size_t i)
{
    const size_t j =
        (i * 7_919UL + 3_071UL)
        % sampleCount;

    const double u =
        (cast(double) j + 0.5)
        / cast(double) sampleCount;

    return -88.0 + 176.0 * u;
}

struct Corpus
{
    TransverseMercator!double projection;
    GeographicCoordinate!double[] input;
}

Corpus makeCorpus(CorpusKind kind)
{
    Corpus result;

    result.projection =
        TransverseMercator!double.fromParameters(
            wgs84!double(),
            Latitude!double.fromDegrees(0.0),
            Longitude!double.fromDegrees(15.0),
            0.9996,
            500_000.0,
            0.0);

    result.input =
        new GeographicCoordinate!double[sampleCount];

    foreach (i; 0 .. sampleCount)
    {
        result.input[i] =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(
                    latitudeDegrees(i)),
                Longitude!double.fromDegrees(
                    15.0
                    + deltaLongitudeDegrees(kind, i)));
    }

    return result;
}

long measureForward(ref Corpus corpus)
{
    size_t failures;
    double local = 0.0;

    const start =
        MonoTime.currTime;

    foreach (source; corpus.input)
    {
        ProjectedCoordinate!double projected;

        if (!corpus.projection.tryForward(
                source,
                projected))
        {
            ++failures;
            continue;
        }

        local +=
            projected.easting * 1.0e-7
            + projected.northing * 1.0e-8;
    }

    const elapsed =
        (MonoTime.currTime - start)
            .total!"nsecs";

    if (failures != 0)
        throw new Exception(
            "forward benchmark encountered failures");

    sink += local;
    return elapsed;
}

long measureFactors(ref Corpus corpus)
{
    size_t failures;
    double local = 0.0;

    const start =
        MonoTime.currTime;

    foreach (source; corpus.input)
    {
        ConformalProjectionFactors!double factors;

        if (!corpus.projection.tryForwardFactors(
                source,
                factors))
        {
            ++failures;
            continue;
        }

        local +=
            factors.meridianConvergence.radians
            + factors.pointScale;
    }

    const elapsed =
        (MonoTime.currTime - start)
            .total!"nsecs";

    if (failures != 0)
        throw new Exception(
            "factor benchmark encountered failures");

    sink += local;
    return elapsed;
}

double medianPerOperation(long[] elapsed)
{
    elapsed.sort();

    return cast(double) elapsed[elapsed.length / 2]
        / cast(double) sampleCount;
}

void run(CorpusKind kind)
{
    auto corpus =
        makeCorpus(kind);

    measureForward(corpus);
    measureFactors(corpus);

    auto forward =
        new long[roundCount];

    auto factors =
        new long[roundCount];

    foreach (round; 0 .. roundCount)
    {
        if ((round & 1) == 0)
        {
            forward[round] =
                measureForward(corpus);

            factors[round] =
                measureFactors(corpus);
        }
        else
        {
            factors[round] =
                measureFactors(corpus);

            forward[round] =
                measureForward(corpus);
        }
    }

    writefln(
        "%-10s forward=%9.3f ns/op factors=%9.3f ns/op",
        corpusName(kind),
        medianPerOperation(forward),
        medianPerOperation(factors));
}

void main()
{
    writeln("=== TM output specialization probe ===");

    run(CorpusKind.utmLike);
    run(CorpusKind.ordinary);
    run(CorpusKind.wide);

    writefln("sink=%0.17g", sink);
}
