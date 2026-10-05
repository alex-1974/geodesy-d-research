module geodesic_output_specialization_runtime_probe;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.math : cos, sin, sqrt;
import std.stdio : writefln, writeln;

enum size_t sampleCount = 16_384;
enum size_t timedRounds = 21;

__gshared double benchmarkSink = 0.0;

extern(C)
{
    double probe_geodesic_length_distance(
        double, double, double, double, double, double,
        double, double, double, double, double);

    double probe_geodesic_length_reduced(
        double, double, double, double, double, double,
        double, double, double, double, double);

    double probe_geodesic_length_scales(
        double, double, double, double, double, double,
        double, double, double, double, double);

    double probe_geodesic_length_full(
        double, double, double, double, double, double,
        double, double, double, double, double);
}

struct Case
{
    double eps;
    double ep2;
    double sigma12;
    double sinSigma1;
    double cosSigma1;
    double dn1;
    double cosBeta1;
    double sinSigma2;
    double cosSigma2;
    double dn2;
    double cosBeta2;
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
        const double u = fraction(i, 1);
        const double v = fraction(i, 4_051);
        const double w = fraction(i, 7_919);

        const double sigma1 = -1.2 + 2.4 * u;
        const double sigma12 = 0.001 + 2.8 * v;
        const double sigma2 = sigma1 + sigma12;

        const double beta1 = -1.3 + 2.6 * v;
        const double beta2 = -1.3 + 2.6 * w;

        const double ep2 = 0.006 + 0.008 * w;

        item.eps = 0.0002 + 0.0015 * u;
        item.ep2 = ep2;
        item.sigma12 = sigma12;
        item.sinSigma1 = sin(sigma1);
        item.cosSigma1 = cos(sigma1);
        item.cosBeta1 = cos(beta1);
        item.dn1 = sqrt(1.0 + ep2 * sin(beta1) * sin(beta1));
        item.sinSigma2 = sin(sigma2);
        item.cosSigma2 = cos(sigma2);
        item.cosBeta2 = cos(beta2);
        item.dn2 = sqrt(1.0 + ep2 * sin(beta2) * sin(beta2));
    }
}

extern(C) alias Kernel = double function(
    double, double, double, double, double, double,
    double, double, double, double, double);

double timeKernel(Kernel kernel, const Case[] cases)
{
    double localSink = 0.0;

    StopWatch watch;
    watch.start();

    foreach (const ref item; cases)
    {
        localSink += kernel(
            item.eps,
            item.ep2,
            item.sigma12,
            item.sinSigma1,
            item.cosSigma1,
            item.dn1,
            item.cosBeta1,
            item.sinSigma2,
            item.cosSigma2,
            item.dn2,
            item.cosBeta2);
    }

    watch.stop();
    benchmarkSink += localSink;

    return cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}

void report(const char[] name, double[timedRounds] values)
{
    values[].sort();

    const double p25 = values[(timedRounds - 1) / 4];
    const double median = values[timedRounds / 2];
    const double p75 = values[3 * (timedRounds - 1) / 4];

    writefln(
        "%-18s median=%9.3f ns/op  p25=%9.3f  p75=%9.3f",
        name,
        median,
        p25,
        p75);
}

void main()
{
    auto cases = new Case[sampleCount];
    fillCases(cases);

    double[timedRounds] distance;
    double[timedRounds] reduced;
    double[timedRounds] scales;
    double[timedRounds] full;

    timeKernel(&probe_geodesic_length_distance, cases);
    timeKernel(&probe_geodesic_length_reduced, cases);
    timeKernel(&probe_geodesic_length_scales, cases);
    timeKernel(&probe_geodesic_length_full, cases);

    foreach (round; 0 .. timedRounds)
    {
        final switch (round % 4)
        {
            case 0:
                distance[round] = timeKernel(&probe_geodesic_length_distance, cases);
                reduced[round] = timeKernel(&probe_geodesic_length_reduced, cases);
                scales[round] = timeKernel(&probe_geodesic_length_scales, cases);
                full[round] = timeKernel(&probe_geodesic_length_full, cases);
                break;
            case 1:
                reduced[round] = timeKernel(&probe_geodesic_length_reduced, cases);
                scales[round] = timeKernel(&probe_geodesic_length_scales, cases);
                full[round] = timeKernel(&probe_geodesic_length_full, cases);
                distance[round] = timeKernel(&probe_geodesic_length_distance, cases);
                break;
            case 2:
                scales[round] = timeKernel(&probe_geodesic_length_scales, cases);
                full[round] = timeKernel(&probe_geodesic_length_full, cases);
                distance[round] = timeKernel(&probe_geodesic_length_distance, cases);
                reduced[round] = timeKernel(&probe_geodesic_length_reduced, cases);
                break;
            case 3:
                full[round] = timeKernel(&probe_geodesic_length_full, cases);
                distance[round] = timeKernel(&probe_geodesic_length_distance, cases);
                reduced[round] = timeKernel(&probe_geodesic_length_reduced, cases);
                scales[round] = timeKernel(&probe_geodesic_length_scales, cases);
                break;
        }
    }

    writeln("=== geodesic length output specialization runtime ===");
    report("distance", distance);
    report("reduced", reduced);
    report("scales", scales);
    report("full", full);
    writefln("sink=%0.17g", benchmarkSink);
}
