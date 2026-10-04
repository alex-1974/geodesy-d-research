module app;

import geodesy;

import core.time : MonoTime;
import std.algorithm.sorting : sort;
import std.math : PI, cos, hypot, isFinite;
import std.stdio : writefln, writeln;

enum size_t sampleCount = 16_384;
enum size_t roundCount = 21;

enum double benchmarkA = 6_378_137.0;
enum double benchmarkF = 1.0 / 298.257223563;
enum double benchmarkK0 = 0.9996;
enum double benchmarkLon0Deg = 15.0;
enum double benchmarkFalseEasting = 500_000.0;
enum double benchmarkFalseNorthing = 0.0;

__gshared double benchmarkSink = 0.0;

extern(C):
void* tm_refs_create() nothrow @nogc;
void tm_refs_destroy(void* handle) nothrow @nogc;

int tm_refs_series_forward(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
int tm_refs_series_reverse(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
int tm_refs_exact_forward(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
int tm_refs_exact_reverse(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
int tm_refs_proj_forward(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
int tm_refs_proj_reverse(void*, size_t, const(double)*, const(double)*, double*, double*) nothrow @nogc;
extern(D):

enum CorpusKind { utmLike, ordinary, wide }
enum BenchDirection { forward, reverse }
enum ExternalImplementation { series, exact, proj }

string corpusName(CorpusKind kind)
{
    final switch (kind)
    {
        case CorpusKind.utmLike: return "UTM-like |dlon| <= 3 deg";
        case CorpusKind.ordinary: return "ordinary TM |dlon| <= 35 deg";
        case CorpusKind.wide: return "wide TM 35 <= |dlon| <= 60 deg";
    }
}

string scalarName(T)()
{
    static if (is(T == float)) return "float";
    else static if (is(T == double)) return "double";
    else static if (is(T == real)) return "real";
    else return T.stringof;
}

real latitudeFor(size_t i)
{
    const size_t j = (i * 7_919UL + 3_071UL) % sampleCount;
    const real u = (cast(real) j + 0.5L) / cast(real) sampleCount;
    return -88.5L + 177.0L * u;
}

real deltaLongitudeFor(CorpusKind kind, size_t i)
{
    const size_t j = (i * 4_051UL + 1_729UL) % sampleCount;
    const real u = (cast(real) j + 0.5L) / cast(real) sampleCount;

    final switch (kind)
    {
        case CorpusKind.utmLike:
            return -3.0L + 6.0L * u;
        case CorpusKind.ordinary:
            return -35.0L + 70.0L * u;
        case CorpusKind.wide:
        {
            const real magnitude = 35.0L + 25.0L * u;
            return (i & 1) == 0 ? -magnitude : magnitude;
        }
    }
}

TransverseMercator!T makeProjection(T)()
{
    return TransverseMercator!T.fromParameters(
        Ellipsoid!T.fromFlattening(cast(T) benchmarkA, cast(T) benchmarkF),
        Latitude!T.fromDegrees(cast(T) 0),
        Longitude!T.fromDegrees(cast(T) benchmarkLon0Deg),
        cast(T) benchmarkK0,
        cast(T) benchmarkFalseEasting,
        cast(T) benchmarkFalseNorthing);
}

double fingerprint(T)(const(ProjectedCoordinate!T) value)
{
    return cast(double) value.easting * 1.0e-7
         + cast(double) value.northing * 1.0e-8;
}

double fingerprint(T)(const(GeographicCoordinate!T) value)
{
    return cast(double) value.latitude.radians
         + cast(double) value.longitude.radians * 0.1;
}

double consumeProjected(T)(const ProjectedCoordinate!T[] values)
{
    double sum = 0;
    foreach (value; values) sum += fingerprint(value);
    return sum;
}

double consumeGeographic(T)(const GeographicCoordinate!T[] values)
{
    double sum = 0;
    foreach (value; values) sum += fingerprint(value);
    return sum;
}

double consumePairs(const double[] first, const double[] second)
{
    double sum = 0;
    foreach (i; 0 .. first.length)
        sum += first[i] * 1.0e-7 + second[i] * 1.0e-8;
    return sum;
}

struct TimingStats
{
    double median;
    double p25;
    double p75;
}

TimingStats summarize(const long[] elapsed, size_t operations)
{
    auto values = new double[elapsed.length];
    foreach (i, ns; elapsed)
        values[i] = cast(double) ns / cast(double) operations;
    sort(values);
    return TimingStats(
        values[values.length / 2],
        values[values.length / 4],
        values[(values.length * 3) / 4]);
}

void reportAbsolute(string label, TimingStats stats)
{
    writefln(
        "%-24s median %10.3f ns/op  p25 %10.3f  p75 %10.3f  %9.3f Mops/s",
        label, stats.median, stats.p25, stats.p75, 1_000.0 / stats.median);
}

void reportRelative(string label, TimingStats stats, double baseMedian)
{
    writefln(
        "%-24s median %10.3f ns/op  p25 %10.3f  p75 %10.3f  ratio %7.3fx",
        label, stats.median, stats.p25, stats.p75, stats.median / baseMedian);
}

struct NativeCorpus(T)
{
    string name;
    TransverseMercator!T projection;
    GeographicCoordinate!T[] geographicInput;
    ProjectedCoordinate!T[] projectedInput;
    ProjectedCoordinate!T[] projectedOutput;
    GeographicCoordinate!T[] geographicOutput;
}

NativeCorpus!T makeNativeCorpus(T)(CorpusKind kind)
{
    NativeCorpus!T corpus;
    corpus.name = corpusName(kind);
    corpus.projection = makeProjection!T();
    corpus.geographicInput = new GeographicCoordinate!T[sampleCount];
    corpus.projectedInput = new ProjectedCoordinate!T[sampleCount];
    corpus.projectedOutput = new ProjectedCoordinate!T[sampleCount];
    corpus.geographicOutput = new GeographicCoordinate!T[sampleCount];

    foreach (i; 0 .. sampleCount)
    {
        const real lat = latitudeFor(i);
        const real lon = benchmarkLon0Deg + deltaLongitudeFor(kind, i);
        corpus.geographicInput[i] = GeographicCoordinate!T.fromComponents(
            Latitude!T.fromDegrees(cast(T) lat),
            Longitude!T.fromDegrees(cast(T) lon));

        ProjectedCoordinate!T projected;
        if (!corpus.projection.tryForward(corpus.geographicInput[i], projected))
            throw new Exception("native corpus preparation failed");
        corpus.projectedInput[i] = projected;
    }
    return corpus;
}

long measureNativeForward(T)(ref NativeCorpus!T corpus)
{
    size_t failures;
    const start = MonoTime.currTime;
    foreach (i; 0 .. sampleCount)
    {
        ProjectedCoordinate!T result;
        if (!corpus.projection.tryForward(corpus.geographicInput[i], result))
            ++failures;
        corpus.projectedOutput[i] = result;
    }
    const ns = (MonoTime.currTime - start).total!"nsecs";
    if (failures) throw new Exception("native forward failed");
    benchmarkSink += consumeProjected(corpus.projectedOutput);
    return ns;
}

long measureNativeReverse(T)(ref NativeCorpus!T corpus)
{
    size_t failures;
    const start = MonoTime.currTime;
    foreach (i; 0 .. sampleCount)
    {
        GeographicCoordinate!T result;
        if (!corpus.projection.tryReverse(corpus.projectedInput[i], result))
            ++failures;
        corpus.geographicOutput[i] = result;
    }
    const ns = (MonoTime.currTime - start).total!"nsecs";
    if (failures) throw new Exception("native reverse failed");
    benchmarkSink += consumeGeographic(corpus.geographicOutput);
    return ns;
}

void runNativeGroup(T)(CorpusKind kind)
{
    auto corpus = makeNativeCorpus!T(kind);
    measureNativeForward(corpus);
    measureNativeReverse(corpus);

    auto forward = new long[roundCount];
    auto reverse = new long[roundCount];

    foreach (round; 0 .. roundCount)
    {
        if ((round & 1) == 0)
        {
            forward[round] = measureNativeForward(corpus);
            reverse[round] = measureNativeReverse(corpus);
        }
        else
        {
            reverse[round] = measureNativeReverse(corpus);
            forward[round] = measureNativeForward(corpus);
        }
    }

    writeln;
    writefln("native geodesy-d: scalar=%s  corpus=%s", scalarName!T(), corpus.name);
    reportAbsolute("forward", summarize(forward, sampleCount));
    reportAbsolute("reverse", summarize(reverse, sampleCount));
}

struct ReferenceCorpus
{
    string name;
    TransverseMercator!double projection;
    double[] latitudeDeg;
    double[] longitudeDeg;
    GeographicCoordinate!double[] geographicInput;
    ProjectedCoordinate!double[] projectedInput;
    ProjectedCoordinate!double[] geodesyProjectedOutput;
    GeographicCoordinate!double[] geodesyGeographicOutput;
    double[] exactEasting;
    double[] exactNorthing;
    double[] externalFirst;
    double[] externalSecond;
}

ReferenceCorpus makeReferenceCorpus(void* refs, CorpusKind kind)
{
    ReferenceCorpus corpus;
    corpus.name = corpusName(kind);
    corpus.projection = makeProjection!double();
    corpus.latitudeDeg = new double[sampleCount];
    corpus.longitudeDeg = new double[sampleCount];
    corpus.geographicInput = new GeographicCoordinate!double[sampleCount];
    corpus.projectedInput = new ProjectedCoordinate!double[sampleCount];
    corpus.geodesyProjectedOutput = new ProjectedCoordinate!double[sampleCount];
    corpus.geodesyGeographicOutput = new GeographicCoordinate!double[sampleCount];
    corpus.exactEasting = new double[sampleCount];
    corpus.exactNorthing = new double[sampleCount];
    corpus.externalFirst = new double[sampleCount];
    corpus.externalSecond = new double[sampleCount];

    foreach (i; 0 .. sampleCount)
    {
        const double lat = cast(double) latitudeFor(i);
        const double lon = benchmarkLon0Deg + cast(double) deltaLongitudeFor(kind, i);
        corpus.latitudeDeg[i] = lat;
        corpus.longitudeDeg[i] = lon;
        corpus.geographicInput[i] = GeographicCoordinate!double.fromComponents(
            Latitude!double.fromDegrees(lat), Longitude!double.fromDegrees(lon));
    }

    if (!tm_refs_exact_forward(refs, sampleCount,
            corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
            corpus.exactEasting.ptr, corpus.exactNorthing.ptr))
        throw new Exception("Exact forward failed while preparing reverse corpus");

    foreach (i; 0 .. sampleCount)
        corpus.projectedInput[i] = ProjectedCoordinate!double.fromComponents(
            corpus.exactEasting[i], corpus.exactNorthing[i]);

    return corpus;
}

long measureGeodesyForward(ref ReferenceCorpus corpus)
{
    size_t failures;
    const start = MonoTime.currTime;
    foreach (i; 0 .. sampleCount)
    {
        ProjectedCoordinate!double result;
        if (!corpus.projection.tryForward(corpus.geographicInput[i], result)) ++failures;
        corpus.geodesyProjectedOutput[i] = result;
    }
    const ns = (MonoTime.currTime - start).total!"nsecs";
    if (failures) throw new Exception("geodesy-d comparison forward failed");
    benchmarkSink += consumeProjected(corpus.geodesyProjectedOutput);
    return ns;
}

long measureGeodesyReverse(ref ReferenceCorpus corpus)
{
    size_t failures;
    const start = MonoTime.currTime;
    foreach (i; 0 .. sampleCount)
    {
        GeographicCoordinate!double result;
        if (!corpus.projection.tryReverse(corpus.projectedInput[i], result)) ++failures;
        corpus.geodesyGeographicOutput[i] = result;
    }
    const ns = (MonoTime.currTime - start).total!"nsecs";
    if (failures) throw new Exception("geodesy-d comparison reverse failed");
    benchmarkSink += consumeGeographic(corpus.geodesyGeographicOutput);
    return ns;
}

long measureExternal(void* refs, ref ReferenceCorpus corpus,
    ExternalImplementation impl, BenchDirection direction)
{
    int ok;
    const start = MonoTime.currTime;

    final switch (impl)
    {
        case ExternalImplementation.series:
            ok = direction == BenchDirection.forward
                ? tm_refs_series_forward(refs, sampleCount,
                    corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr)
                : tm_refs_series_reverse(refs, sampleCount,
                    corpus.exactEasting.ptr, corpus.exactNorthing.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr);
            break;
        case ExternalImplementation.exact:
            ok = direction == BenchDirection.forward
                ? tm_refs_exact_forward(refs, sampleCount,
                    corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr)
                : tm_refs_exact_reverse(refs, sampleCount,
                    corpus.exactEasting.ptr, corpus.exactNorthing.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr);
            break;
        case ExternalImplementation.proj:
            ok = direction == BenchDirection.forward
                ? tm_refs_proj_forward(refs, sampleCount,
                    corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr)
                : tm_refs_proj_reverse(refs, sampleCount,
                    corpus.exactEasting.ptr, corpus.exactNorthing.ptr,
                    corpus.externalFirst.ptr, corpus.externalSecond.ptr);
            break;
    }

    const ns = (MonoTime.currTime - start).total!"nsecs";
    if (!ok) throw new Exception("external TM operation failed");
    benchmarkSink += consumePairs(corpus.externalFirst, corpus.externalSecond);
    return ns;
}

double reverseGroundError(GeographicCoordinate!double got, double latDeg, double lonDeg)
{
    const double lat = latDeg * PI / 180.0;
    const double lon = lonDeg * PI / 180.0;
    return hypot(
        benchmarkA * (got.latitude.radians - lat),
        benchmarkA * cos(lat) * (got.longitude.radians - lon));
}

void validateReferenceCorpus(void* refs, ref ReferenceCorpus corpus)
{
    measureGeodesyForward(corpus);
    double geodesyForwardMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const error = hypot(
            corpus.geodesyProjectedOutput[i].easting - corpus.exactEasting[i],
            corpus.geodesyProjectedOutput[i].northing - corpus.exactNorthing[i]);
        if (error > geodesyForwardMax) geodesyForwardMax = error;
    }

    if (!tm_refs_series_forward(refs, sampleCount,
            corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
            corpus.externalFirst.ptr, corpus.externalSecond.ptr))
        throw new Exception("Series preflight forward failed");
    double seriesForwardMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const error = hypot(corpus.externalFirst[i] - corpus.exactEasting[i],
                            corpus.externalSecond[i] - corpus.exactNorthing[i]);
        if (error > seriesForwardMax) seriesForwardMax = error;
    }

    if (!tm_refs_proj_forward(refs, sampleCount,
            corpus.latitudeDeg.ptr, corpus.longitudeDeg.ptr,
            corpus.externalFirst.ptr, corpus.externalSecond.ptr))
        throw new Exception("PROJ preflight forward failed");
    double projForwardMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const error = hypot(corpus.externalFirst[i] - corpus.exactEasting[i],
                            corpus.externalSecond[i] - corpus.exactNorthing[i]);
        if (error > projForwardMax) projForwardMax = error;
    }

    measureGeodesyReverse(corpus);
    double geodesyReverseMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const error = reverseGroundError(
            corpus.geodesyGeographicOutput[i],
            corpus.latitudeDeg[i],
            corpus.longitudeDeg[i]);

        if (error > geodesyReverseMax)
            geodesyReverseMax = error;
    }

    double externalReverseGroundError(
        const size_t i)
    {
        const double latitudeRad =
            corpus.externalFirst[i] * PI / 180.0;

        const double longitudeRad =
            corpus.externalSecond[i] * PI / 180.0;

        const double expectedLatitudeRad =
            corpus.latitudeDeg[i] * PI / 180.0;

        const double expectedLongitudeRad =
            corpus.longitudeDeg[i] * PI / 180.0;

        return hypot(
            benchmarkA
                * (latitudeRad - expectedLatitudeRad),
            benchmarkA
                * cos(expectedLatitudeRad)
                * (longitudeRad - expectedLongitudeRad));
    }

    if (!tm_refs_series_reverse(
            refs,
            sampleCount,
            corpus.exactEasting.ptr,
            corpus.exactNorthing.ptr,
            corpus.externalFirst.ptr,
            corpus.externalSecond.ptr))
        throw new Exception(
            "Series preflight reverse failed");

    double seriesReverseMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const double error =
            externalReverseGroundError(i);

        if (error > seriesReverseMax)
            seriesReverseMax = error;
    }

    if (!tm_refs_exact_reverse(
            refs,
            sampleCount,
            corpus.exactEasting.ptr,
            corpus.exactNorthing.ptr,
            corpus.externalFirst.ptr,
            corpus.externalSecond.ptr))
        throw new Exception(
            "Exact preflight reverse failed");

    double exactReverseMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const double error =
            externalReverseGroundError(i);

        if (error > exactReverseMax)
            exactReverseMax = error;
    }

    if (!tm_refs_proj_reverse(
            refs,
            sampleCount,
            corpus.exactEasting.ptr,
            corpus.exactNorthing.ptr,
            corpus.externalFirst.ptr,
            corpus.externalSecond.ptr))
        throw new Exception(
            "PROJ preflight reverse failed");

    double projReverseMax = 0.0;
    foreach (i; 0 .. sampleCount)
    {
        const double error =
            externalReverseGroundError(i);

        if (error > projReverseMax)
            projReverseMax = error;
    }

    writeln;
    writefln(
        "reference preflight: %s",
        corpus.name);

    writefln(
        "  forward vs Exact: geodesy-d %.9g m  Series %.9g m  PROJ %.9g m",
        geodesyForwardMax,
        seriesForwardMax,
        projForwardMax);

    writefln(
        "  reverse ground:   geodesy-d %.9g m  Series %.9g m  Exact %.9g m  PROJ %.9g m",
        geodesyReverseMax,
        seriesReverseMax,
        exactReverseMax,
        projReverseMax);

    enum double sanityEnvelope = 1.0;

    if (!isFinite(geodesyForwardMax)
        || !isFinite(seriesForwardMax)
        || !isFinite(projForwardMax)
        || !isFinite(geodesyReverseMax)
        || !isFinite(seriesReverseMax)
        || !isFinite(exactReverseMax)
        || !isFinite(projReverseMax)
        || geodesyForwardMax > sanityEnvelope
        || seriesForwardMax > sanityEnvelope
        || projForwardMax > sanityEnvelope
        || geodesyReverseMax > sanityEnvelope
        || seriesReverseMax > sanityEnvelope
        || exactReverseMax > sanityEnvelope
        || projReverseMax > sanityEnvelope)
        throw new Exception(
            "TM reference preflight exceeded 1 m sanity envelope");
}

void runReferenceGroup(void* refs, CorpusKind kind)
{
    auto corpus = makeReferenceCorpus(refs, kind);
    validateReferenceCorpus(refs, corpus);

    measureGeodesyForward(corpus);
    measureGeodesyReverse(corpus);
    foreach (impl; [ExternalImplementation.series, ExternalImplementation.exact, ExternalImplementation.proj])
    {
        measureExternal(refs, corpus, impl, BenchDirection.forward);
        measureExternal(refs, corpus, impl, BenchDirection.reverse);
    }

    auto gf = new long[roundCount]; auto gr = new long[roundCount];
    auto sf = new long[roundCount]; auto sr = new long[roundCount];
    auto ef = new long[roundCount]; auto er = new long[roundCount];
    auto pf = new long[roundCount]; auto pr = new long[roundCount];

    foreach (round; 0 .. roundCount)
    {
        foreach (slot; 0 .. 8)
        {
            const size_t op = (round + slot) % 8;
            switch (op)
            {
                case 0: gf[round] = measureGeodesyForward(corpus); break;
                case 1: sf[round] = measureExternal(refs, corpus, ExternalImplementation.series, BenchDirection.forward); break;
                case 2: ef[round] = measureExternal(refs, corpus, ExternalImplementation.exact, BenchDirection.forward); break;
                case 3: pf[round] = measureExternal(refs, corpus, ExternalImplementation.proj, BenchDirection.forward); break;
                case 4: gr[round] = measureGeodesyReverse(corpus); break;
                case 5: sr[round] = measureExternal(refs, corpus, ExternalImplementation.series, BenchDirection.reverse); break;
                case 6: er[round] = measureExternal(refs, corpus, ExternalImplementation.exact, BenchDirection.reverse); break;
                case 7: pr[round] = measureExternal(refs, corpus, ExternalImplementation.proj, BenchDirection.reverse); break;
                default: assert(0);
            }
        }
    }

    const gfs = summarize(gf, sampleCount); const grs = summarize(gr, sampleCount);
    const sfs = summarize(sf, sampleCount); const srs = summarize(sr, sampleCount);
    const efs = summarize(ef, sampleCount); const ers = summarize(er, sampleCount);
    const pfs = summarize(pf, sampleCount); const prs = summarize(pr, sampleCount);

    writeln;
    writefln("same-process double comparison: %s", corpus.name);
    writeln("forward:");
    reportRelative("geodesy-d", gfs, gfs.median);
    reportRelative("GeographicLib Series", sfs, gfs.median);
    reportRelative("GeographicLib Exact", efs, gfs.median);
    reportRelative("PROJ poder_engsager", pfs, gfs.median);
    writeln("reverse:");
    reportRelative("geodesy-d", grs, grs.median);
    reportRelative("GeographicLib Series", srs, grs.median);
    reportRelative("GeographicLib Exact", ers, grs.median);
    reportRelative("PROJ poder_engsager", prs, grs.median);
}

void main()
{
    writeln("geodesy-d Transverse Mercator performance baseline");
    writefln("samples per corpus: %s", sampleCount);
    writefln("timed rounds:       %s", roundCount);
    writeln("projection:         WGS84 lat0=0 lon0=15 k0=0.9996 FE=500000 FN=0");

    foreach (kind; [CorpusKind.utmLike, CorpusKind.ordinary, CorpusKind.wide])
    {
        runNativeGroup!float(kind);
        runNativeGroup!double(kind);
        runNativeGroup!real(kind);
    }

    auto refs = tm_refs_create();
    if (refs is null)
        throw new Exception("failed to construct GeographicLib/PROJ references");
    scope(exit) tm_refs_destroy(refs);

    foreach (kind; [CorpusKind.utmLike, CorpusKind.ordinary, CorpusKind.wide])
        runReferenceGroup(refs, kind);

    writefln("\nbenchmark sink: %.17g", benchmarkSink);
}
