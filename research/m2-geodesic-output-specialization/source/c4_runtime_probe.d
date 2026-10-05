module geodesy.internal.c4_runtime_probe;

import geodesy.internal.geodesic_area_series :
    fillGeodesicC4,
    fillGeodesicC4x;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln, writeln;

enum size_t sampleCount = 16_384;
enum size_t timedRounds = 21;

__gshared double benchmarkSink = 0.0;

struct Case
{
    double n;
    double eps;
}

struct Prepared
{
    double eps;
    double[36] c4x;
}

double fraction(const size_t i, const size_t multiplier)
{
    return cast(double) ((i * multiplier) % sampleCount)
        / cast(double) (sampleCount - 1);
}

void fillCases(Case[] cases)
{
    foreach (i, ref item; cases)
    {
        /*
         * Cover the supported oblate range with values representative of
         * ordinary Earth-like flattenings and the f <= 0.01 support edge.
         */
        item.n =
            0.0005
            + 0.0046 * fraction(i, 4_051);

        item.eps =
            0.0001
            + 0.0050 * fraction(i, 7_919);
    }
}

void prepareCases(
    const Case[] cases,
    Prepared[] prepared)
{
    foreach (i, const ref item; cases)
    {
        prepared[i].eps =
            item.eps;

        fillGeodesicC4x!(
            double,
            6)(
                item.n,
                prepared[i].c4x);
    }
}

double timePrepare(const Case[] cases)
{
    double localSink = 0.0;

    StopWatch watch;
    watch.start();

    foreach (i, const ref item; cases)
    {
        double[36] c4x;

        fillGeodesicC4x!(
            double,
            6)(
                item.n,
                c4x);

        localSink +=
            c4x[i % 21];
    }

    watch.stop();
    benchmarkSink += localSink;

    return cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}

double timeEvaluate(const Prepared[] prepared)
{
    double localSink = 0.0;

    StopWatch watch;
    watch.start();

    foreach (i, const ref item; prepared)
    {
        double[9] c4;

        fillGeodesicC4!(
            double,
            6)(
                item.eps,
                item.c4x,
                c4);

        localSink +=
            c4[i % 6];
    }

    watch.stop();
    benchmarkSink += localSink;

    return cast(double) watch.peek.total!"nsecs"
        / cast(double) prepared.length;
}

double timePrepareAndEvaluate(const Case[] cases)
{
    double localSink = 0.0;

    StopWatch watch;
    watch.start();

    foreach (i, const ref item; cases)
    {
        double[36] c4x;
        double[9] c4;

        fillGeodesicC4x!(
            double,
            6)(
                item.n,
                c4x);

        fillGeodesicC4!(
            double,
            6)(
                item.eps,
                c4x,
                c4);

        localSink +=
            c4[i % 6];
    }

    watch.stop();
    benchmarkSink += localSink;

    return cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}

void report(
    const char[] name,
    double[timedRounds] values)
{
    values[].sort();

    writefln(
        "%-24s median=%9.3f ns/op  p25=%9.3f  p75=%9.3f",
        name,
        values[timedRounds / 2],
        values[(timedRounds - 1) / 4],
        values[3 * (timedRounds - 1) / 4]);
}

void main()
{
    auto cases =
        new Case[sampleCount];

    auto prepared =
        new Prepared[sampleCount];

    fillCases(cases);
    prepareCases(cases, prepared);

    double[timedRounds] prepTimings;
    double[timedRounds] evalTimings;
    double[timedRounds] combinedTimings;

    timePrepare(cases);
    timeEvaluate(prepared);
    timePrepareAndEvaluate(cases);

    foreach (round; 0 .. timedRounds)
    {
        final switch (round % 3)
        {
            case 0:
                prepTimings[round] =
                    timePrepare(cases);

                evalTimings[round] =
                    timeEvaluate(prepared);

                combinedTimings[round] =
                    timePrepareAndEvaluate(cases);
                break;

            case 1:
                evalTimings[round] =
                    timeEvaluate(prepared);

                combinedTimings[round] =
                    timePrepareAndEvaluate(cases);

                prepTimings[round] =
                    timePrepare(cases);
                break;

            case 2:
                combinedTimings[round] =
                    timePrepareAndEvaluate(cases);

                prepTimings[round] =
                    timePrepare(cases);

                evalTimings[round] =
                    timeEvaluate(prepared);
                break;
        }
    }

    writeln("=== geodesic C4 preparation/evaluation runtime ===");
    report("C4x prepare", prepTimings);
    report("C4 evaluate", evalTimings);
    report("prepare + evaluate", combinedTimings);
    writefln("sink=%0.17g", benchmarkSink);
}
