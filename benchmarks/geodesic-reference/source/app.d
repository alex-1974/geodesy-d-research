module app;

import geodesy;

import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.math : PI, fabs, fmod;
import std.stdio : stderr, writefln, writeln;

enum size_t sampleCount = 16_384;
enum size_t timedRounds = 21;

__gshared double benchmarkSink = 0.0;


extern(C)
{
    void* geodesic_reference_create(
        double a,
        double f);

    void geodesic_reference_destroy(
        void* handle);

    int geodesic_reference_direct(
        void* handle,
        double latitude1Degrees,
        double longitude1Degrees,
        double azimuth1Degrees,
        double distance,
        double* latitude2Radians,
        double* longitude2Radians,
        double* azimuth2Radians);

    int geodesic_reference_inverse(
        void* handle,
        double latitude1Degrees,
        double longitude1Degrees,
        double latitude2Degrees,
        double longitude2Degrees,
        double* distance,
        double* azimuth1Radians,
        double* azimuth2Radians);


    int geodesic_proj_direct(
        void* handle,
        double latitude1Radians,
        double longitude1Radians,
        double azimuth1Radians,
        double distance,
        double* latitude2Radians,
        double* longitude2Radians,
        double* azimuth2Radians);

    int geodesic_proj_inverse(
        void* handle,
        double latitude1Radians,
        double longitude1Radians,
        double latitude2Radians,
        double longitude2Radians,
        double* distance,
        double* azimuth1Degrees,
        double* azimuth2Degrees);
}


struct DirectCase
{
    GeographicCoordinate!double start;
    Angle!double azimuth;
    double distance;

    double latitudeDegrees;
    double longitudeDegrees;
    double azimuthDegrees;
}


struct InverseCase
{
    GeographicCoordinate!double start;
    GeographicCoordinate!double end;

    double latitude1Degrees;
    double longitude1Degrees;
    double latitude2Degrees;
    double longitude2Degrees;
}


double fraction(
    const size_t index,
    const size_t multiplier)
{
    const size_t value =
        (index * multiplier) % sampleCount;

    return
        cast(double) value
        / cast(double) (sampleCount - 1);
}


double canonicalDegrees(double value)
{
    while (value >= 180.0)
        value -= 360.0;

    while (value < -180.0)
        value += 360.0;

    return value;
}


double angularDifference(
    const double left,
    const double right)
{
    enum double twoPi =
        2.0 * cast(double) PI;

    double result =
        fmod(
            left - right,
            twoPi);

    if (result >= cast(double) PI)
        result -= twoPi;
    else if (result < -cast(double) PI)
        result += twoPi;

    return result;
}


void fillDirectOrdinary(
    DirectCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude =
            -75.0 + 150.0 * fraction(i, 1);

        const double longitude =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double azimuth =
            -180.0 + 360.0 * fraction(i, 7_919);

        const double distance =
            1_000.0
            + 19_000_000.0 * fraction(i, 3_571);

        item.latitudeDegrees = latitude;
        item.longitudeDegrees = longitude;
        item.azimuthDegrees = azimuth;
        item.distance = distance;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude),
                Longitude!double.fromDegrees(longitude));

        item.azimuth =
            Angle!double.fromDegrees(azimuth);
    }
}



void fillDirectShort(
    DirectCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude =
            -80.0 + 160.0 * fraction(i, 1);

        const double longitude =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double azimuth =
            -180.0 + 360.0 * fraction(i, 7_919);

        const double distance =
            0.01
            + 9_999.99 * fraction(i, 3_571);

        item.latitudeDegrees = latitude;
        item.longitudeDegrees = longitude;
        item.azimuthDegrees = azimuth;
        item.distance = distance;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude),
                Longitude!double.fromDegrees(longitude));

        item.azimuth =
            Angle!double.fromDegrees(azimuth);
    }
}


void fillDirectLong(
    DirectCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude =
            -70.0 + 140.0 * fraction(i, 1);

        const double longitude =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double azimuth =
            -180.0 + 360.0 * fraction(i, 7_919);

        const double distance =
            10_000_000.0
            + 9_500_000.0 * fraction(i, 3_571);

        item.latitudeDegrees = latitude;
        item.longitudeDegrees = longitude;
        item.azimuthDegrees = azimuth;
        item.distance = distance;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude),
                Longitude!double.fromDegrees(longitude));

        item.azimuth =
            Angle!double.fromDegrees(azimuth);
    }
}


void fillInverseOrdinary(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude1 =
            -75.0 + 150.0 * fraction(i, 1);

        const double longitude1 =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double latitude2 =
            -72.0 + 144.0 * fraction(i, 7_919);

        const double longitude2 =
            -180.0 + 360.0 * fraction(i, 3_571);

        item.latitude1Degrees = latitude1;
        item.longitude1Degrees = longitude1;
        item.latitude2Degrees = latitude2;
        item.longitude2Degrees = longitude2;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude1),
                Longitude!double.fromDegrees(longitude1));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude2),
                Longitude!double.fromDegrees(longitude2));
    }
}



void fillInverseShort(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude1 =
            -70.0 + 140.0 * fraction(i, 1);

        const double longitude1 =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double latitudeOffset =
            0.000001
            + 0.009999 * fraction(i, 7_919);

        const double longitudeOffset =
            0.000001
            + 0.009999 * fraction(i, 3_571);

        const double latitude2 =
            latitude1
            + ((i & 1) == 0
                ? latitudeOffset
                : -latitudeOffset);

        const double longitude2 =
            canonicalDegrees(
                longitude1
                + ((i & 2) == 0
                    ? longitudeOffset
                    : -longitudeOffset));

        item.latitude1Degrees = latitude1;
        item.longitude1Degrees = longitude1;
        item.latitude2Degrees = latitude2;
        item.longitude2Degrees = longitude2;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude1),
                Longitude!double.fromDegrees(longitude1));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude2),
                Longitude!double.fromDegrees(longitude2));
    }
}


void fillInverseMeridional(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude1 =
            -80.0 + 160.0 * fraction(i, 1);

        const double latitude2 =
            -79.0 + 158.0 * fraction(i, 7_919);

        const double longitude =
            -180.0 + 360.0 * fraction(i, 4_051);

        item.latitude1Degrees = latitude1;
        item.longitude1Degrees = longitude;
        item.latitude2Degrees = latitude2;
        item.longitude2Degrees = longitude;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude1),
                Longitude!double.fromDegrees(longitude));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude2),
                Longitude!double.fromDegrees(longitude));
    }
}


void fillInverseEquatorial(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double longitude1 =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double separation =
            0.01
            + 179.98 * fraction(i, 7_919);

        const double longitude2 =
            canonicalDegrees(
                longitude1 + separation);

        item.latitude1Degrees = 0.0;
        item.longitude1Degrees = longitude1;
        item.latitude2Degrees = 0.0;
        item.longitude2Degrees = longitude2;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(0.0),
                Longitude!double.fromDegrees(longitude1));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(0.0),
                Longitude!double.fromDegrees(longitude2));
    }
}


void fillInversePolar(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const bool north =
            (i & 1) == 0;

        const double poleLatitude =
            north ? 90.0 : -90.0;

        const double targetLatitudeMagnitude =
            70.0
            + 19.5 * fraction(i, 7_919);

        const double latitude2 =
            north
                ? targetLatitudeMagnitude
                : -targetLatitudeMagnitude;

        const double longitude1 =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double longitude2 =
            -180.0 + 360.0 * fraction(i, 3_571);

        item.latitude1Degrees = poleLatitude;
        item.longitude1Degrees = longitude1;
        item.latitude2Degrees = latitude2;
        item.longitude2Degrees = longitude2;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(poleLatitude),
                Longitude!double.fromDegrees(longitude1));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude2),
                Longitude!double.fromDegrees(longitude2));
    }
}


void fillInverseNearAntipodal(
    InverseCase[] cases)
{
    foreach (i, ref item; cases)
    {
        const double latitude1 =
            -60.0 + 120.0 * fraction(i, 1);

        const double longitude1 =
            -180.0 + 360.0 * fraction(i, 4_051);

        const double latitudeOffset =
            0.00001
            + 0.00099 * fraction(i, 7_919);

        const double longitudeOffset =
            0.00001
            + 0.00099 * fraction(i, 3_571);

        const double signedLatitudeOffset =
            (i & 1) == 0
                ? latitudeOffset
                : -latitudeOffset;

        const double latitude2 =
            -latitude1
            + signedLatitudeOffset;

        const double longitude2 =
            canonicalDegrees(
                longitude1
                + 180.0
                - longitudeOffset);

        item.latitude1Degrees = latitude1;
        item.longitude1Degrees = longitude1;
        item.latitude2Degrees = latitude2;
        item.longitude2Degrees = longitude2;

        item.start =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude1),
                Longitude!double.fromDegrees(longitude1));

        item.end =
            GeographicCoordinate!double.fromComponents(
                Latitude!double.fromDegrees(latitude2),
                Longitude!double.fromDegrees(longitude2));
    }
}


double fingerprint(
    const GeodesicDirectResult!double result)
{
    return
        result.position.latitude.radians
        + result.position.longitude.radians * 0.1
        + result.finalAzimuth.radians * 0.01;
}


double fingerprint(
    const GeodesicInverseResult!double result)
{
    return
        result.distance * 1.0e-7
        + result.initialAzimuth.radians
        + result.finalAzimuth.radians * 0.1;
}


void preflightDirect(
    const Geodesic!double solver,
    void* reference,
    const DirectCase[] cases)
{
    double maxLatitudeError = 0.0;
    double maxLongitudeError = 0.0;
    double maxAzimuthError = 0.0;

    foreach (const ref item; cases)
    {
        GeodesicDirectResult!double actual;

        if (!solver.tryDirect(
                item.start,
                item.azimuth,
                item.distance,
                actual))
            throw new Exception(
                "geodesy-d direct preflight failed");

        double referenceLatitude;
        double referenceLongitude;
        double referenceAzimuth;

        if (!geodesic_reference_direct(
                reference,
                item.latitudeDegrees,
                item.longitudeDegrees,
                item.azimuthDegrees,
                item.distance,
                &referenceLatitude,
                &referenceLongitude,
                &referenceAzimuth))
            throw new Exception(
                "GeographicLib direct preflight failed");

        maxLatitudeError =
            maxLatitudeError
                > fabs(
                    actual.position.latitude.radians
                    - referenceLatitude)
            ? maxLatitudeError
            : fabs(
                actual.position.latitude.radians
                - referenceLatitude);

        const double longitudeError =
            fabs(
                angularDifference(
                    actual.position.longitude.radians,
                    referenceLongitude));

        if (longitudeError > maxLongitudeError)
            maxLongitudeError = longitudeError;

        const double azimuthError =
            fabs(
                angularDifference(
                    actual.finalAzimuth.radians,
                    referenceAzimuth));

        if (azimuthError > maxAzimuthError)
            maxAzimuthError = azimuthError;
    }

    writefln(
        "direct preflight max errors: "
        ~ "lat=%.3e rad lon=%.3e rad azi=%.3e rad",
        maxLatitudeError,
        maxLongitudeError,
        maxAzimuthError);

    if (maxLatitudeError > 1.0e-9
        || maxLongitudeError > 1.0e-9
        || maxAzimuthError > 1.0e-9)
        throw new Exception(
            "direct reference envelope exceeded");
}


void preflightInverse(
    const char[] label,
    const Geodesic!double solver,
    void* reference,
    const InverseCase[] cases)
{
    double maxDistanceError = 0.0;
    double maxInitialAzimuthError = 0.0;
    double maxFinalAzimuthError = 0.0;

    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double actual;

        if (!solver.tryInverse(
                item.start,
                item.end,
                actual))
            throw new Exception(
                "geodesy-d inverse preflight failed");

        double referenceDistance;
        double referenceInitialAzimuth;
        double referenceFinalAzimuth;

        if (!geodesic_reference_inverse(
                reference,
                item.latitude1Degrees,
                item.longitude1Degrees,
                item.latitude2Degrees,
                item.longitude2Degrees,
                &referenceDistance,
                &referenceInitialAzimuth,
                &referenceFinalAzimuth))
            throw new Exception(
                "GeographicLib inverse preflight failed");

        const double distanceError =
            fabs(
                actual.distance
                - referenceDistance);

        if (distanceError > maxDistanceError)
            maxDistanceError = distanceError;

        const double initialError =
            fabs(
                angularDifference(
                    actual.initialAzimuth.radians,
                    referenceInitialAzimuth));

        if (initialError > maxInitialAzimuthError)
            maxInitialAzimuthError = initialError;

        const double finalError =
            fabs(
                angularDifference(
                    actual.finalAzimuth.radians,
                    referenceFinalAzimuth));

        if (finalError > maxFinalAzimuthError)
            maxFinalAzimuthError = finalError;
    }

    writefln(
        "%s preflight max errors: "
        ~ "distance=%.3e m azi1=%.3e rad azi2=%.3e rad",
        label,
        maxDistanceError,
        maxInitialAzimuthError,
        maxFinalAzimuthError);

    if (maxDistanceError > 1.0e-3
        || maxInitialAzimuthError > 1.0e-9
        || maxFinalAzimuthError > 1.0e-9)
        throw new Exception(
            "inverse reference envelope exceeded");
}



void preflightProjDirect(
    const Geodesic!double solver,
    void* reference,
    const DirectCase[] cases)
{
    double maxLatitudeError = 0.0;
    double maxLongitudeError = 0.0;
    double maxAzimuthError = 0.0;

    foreach (const ref item; cases)
    {
        GeodesicDirectResult!double actual;

        if (!solver.tryDirect(
                item.start,
                item.azimuth,
                item.distance,
                actual))
            throw new Exception(
                "geodesy-d direct PROJ preflight failed");

        double latitude;
        double longitude;
        double azimuth;

        if (!geodesic_proj_direct(
                reference,
                item.start.latitude.radians,
                item.start.longitude.radians,
                item.azimuth.radians,
                item.distance,
                &latitude,
                &longitude,
                &azimuth))
            throw new Exception(
                "PROJ direct preflight failed");

        const double latitudeError =
            fabs(
                actual.position.latitude.radians
                - latitude);

        const double longitudeError =
            fabs(
                angularDifference(
                    actual.position.longitude.radians,
                    longitude));

        const double azimuthError =
            fabs(
                angularDifference(
                    actual.finalAzimuth.radians,
                    azimuth));

        if (latitudeError > maxLatitudeError)
            maxLatitudeError = latitudeError;

        if (longitudeError > maxLongitudeError)
            maxLongitudeError = longitudeError;

        if (azimuthError > maxAzimuthError)
            maxAzimuthError = azimuthError;
    }

    writefln(
        "direct PROJ preflight max errors: "
        ~ "lat=%.3e rad lon=%.3e rad azi=%.3e rad",
        maxLatitudeError,
        maxLongitudeError,
        maxAzimuthError);

    if (maxLatitudeError > 1.0e-9
        || maxLongitudeError > 1.0e-9
        || maxAzimuthError > 1.0e-9)
        throw new Exception(
            "direct PROJ reference envelope exceeded");
}


void preflightProjInverse(
    const char[] label,
    const Geodesic!double solver,
    void* reference,
    const InverseCase[] cases)
{
    double maxDistanceError = 0.0;
    double maxInitialAzimuthError = 0.0;
    double maxFinalAzimuthError = 0.0;

    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double actual;

        if (!solver.tryInverse(
                item.start,
                item.end,
                actual))
            throw new Exception(
                "geodesy-d inverse PROJ preflight failed");

        double distance;
        double initialAzimuthDegrees;
        double finalAzimuthDegrees;

        if (!geodesic_proj_inverse(
                reference,
                item.start.latitude.radians,
                item.start.longitude.radians,
                item.end.latitude.radians,
                item.end.longitude.radians,
                &distance,
                &initialAzimuthDegrees,
                &finalAzimuthDegrees))
            throw new Exception(
                "PROJ inverse preflight failed");

        /*
         * PROJ 9.7.1 proj_geod() exposes geod_inverse() azimuth outputs
         * unchanged.  Those two values are degrees, despite the surrounding
         * proj_geod coordinate API using radians.
         *
         * geod_inverse() azi2 is the forward azimuth at point 2, matching
         * geodesy-d finalAzimuth semantics directly.
         */
        const double radiansPerDegree =
            cast(double) PI / 180.0;

        const double initialAzimuth =
            initialAzimuthDegrees
            * radiansPerDegree;

        const double finalAzimuth =
            finalAzimuthDegrees
            * radiansPerDegree;

        const double distanceError =
            fabs(actual.distance - distance);

        const double initialError =
            fabs(
                angularDifference(
                    actual.initialAzimuth.radians,
                    initialAzimuth));

        const double finalError =
            fabs(
                angularDifference(
                    actual.finalAzimuth.radians,
                    finalAzimuth));

        if (distanceError > maxDistanceError)
            maxDistanceError = distanceError;

        if (initialError > maxInitialAzimuthError)
            maxInitialAzimuthError = initialError;

        if (finalError > maxFinalAzimuthError)
            maxFinalAzimuthError = finalError;
    }

    writefln(
        "%s PROJ preflight max errors: "
        ~ "distance=%.3e m azi1=%.3e rad azi2=%.3e rad",
        label,
        maxDistanceError,
        maxInitialAzimuthError,
        maxFinalAzimuthError);

    if (maxDistanceError > 1.0e-3
        || maxInitialAzimuthError > 1.0e-9
        || maxFinalAzimuthError > 1.0e-9)
        throw new Exception(
            "inverse PROJ reference envelope exceeded");
}


double timeDirectGeodesy(
    const Geodesic!double solver,
    const DirectCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        GeodesicDirectResult!double result;

        if (solver.tryDirect(
                item.start,
                item.azimuth,
                item.distance,
                result))
            localSink += fingerprint(result);
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}


double timeDirectReference(
    void* reference,
    const DirectCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        double latitude;
        double longitude;
        double azimuth;

        if (geodesic_reference_direct(
                reference,
                item.latitudeDegrees,
                item.longitudeDegrees,
                item.azimuthDegrees,
                item.distance,
                &latitude,
                &longitude,
                &azimuth))
        {
            localSink +=
                latitude
                + longitude * 0.1
                + azimuth * 0.01;
        }
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}


double timeInverseGeodesy(
    const Geodesic!double solver,
    const InverseCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double result;

        if (solver.tryInverse(
                item.start,
                item.end,
                result))
            localSink += fingerprint(result);
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}


double timeInverseReference(
    void* reference,
    const InverseCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        double distance;
        double azimuth1;
        double azimuth2;

        if (geodesic_reference_inverse(
                reference,
                item.latitude1Degrees,
                item.longitude1Degrees,
                item.latitude2Degrees,
                item.longitude2Degrees,
                &distance,
                &azimuth1,
                &azimuth2))
        {
            localSink +=
                distance * 1.0e-7
                + azimuth1
                + azimuth2 * 0.1;
        }
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}



double timeDirectProj(
    void* reference,
    const DirectCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        double latitude;
        double longitude;
        double azimuth;

        if (geodesic_proj_direct(
                reference,
                item.start.latitude.radians,
                item.start.longitude.radians,
                item.azimuth.radians,
                item.distance,
                &latitude,
                &longitude,
                &azimuth))
        {
            localSink +=
                latitude
                + longitude * 0.1
                + azimuth * 0.01;
        }
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}


double timeInverseProj(
    void* reference,
    const InverseCase[] cases)
{
    double localSink = 0.0;
    StopWatch watch;

    watch.start();

    foreach (const ref item; cases)
    {
        double distance;
        double azimuth1Degrees;
        double azimuth2Degrees;

        if (geodesic_proj_inverse(
                reference,
                item.start.latitude.radians,
                item.start.longitude.radians,
                item.end.latitude.radians,
                item.end.longitude.radians,
                &distance,
                &azimuth1Degrees,
                &azimuth2Degrees))
        {
            /*
             * Keep native PROJ 9.7.1 degree outputs in the timed kernel.
             * Unit conversion belongs to numerical preflight, not timing.
             */
            localSink +=
                distance * 1.0e-7
                + azimuth1Degrees
                + azimuth2Degrees * 0.1;
        }
        else
            localSink += 1.0e100;
    }

    watch.stop();

    benchmarkSink += localSink;

    return
        cast(double) watch.peek.total!"nsecs"
        / cast(double) cases.length;
}


void report(
    const char[] name,
    const double[] values)
{
    auto ordered = values.dup;
    ordered.sort();

    const double p25 =
        ordered[(ordered.length - 1) / 4];

    const double median =
        ordered[ordered.length / 2];

    const double p75 =
        ordered[
            3 * (ordered.length - 1) / 4];

    writefln(
        "%-34s median=%10.3f ns/op  "
        ~ "p25=%10.3f  p75=%10.3f",
        name,
        median,
        p25,
        p75);
}


void benchmarkDirectThreeWay(
    const char[] label,
    const Geodesic!double solver,
    void* reference,
    const DirectCase[] cases)
{
    double[timedRounds] geodesyTimings;
    double[timedRounds] geographiclibTimings;
    double[timedRounds] projTimings;

    timeDirectGeodesy(solver, cases);
    timeDirectReference(reference, cases);
    timeDirectProj(reference, cases);

    foreach (round; 0 .. timedRounds)
    {
        final switch (round % 3)
        {
            case 0:
                geodesyTimings[round] =
                    timeDirectGeodesy(solver, cases);
                geographiclibTimings[round] =
                    timeDirectReference(reference, cases);
                projTimings[round] =
                    timeDirectProj(reference, cases);
                break;

            case 1:
                geographiclibTimings[round] =
                    timeDirectReference(reference, cases);
                projTimings[round] =
                    timeDirectProj(reference, cases);
                geodesyTimings[round] =
                    timeDirectGeodesy(solver, cases);
                break;

            case 2:
                projTimings[round] =
                    timeDirectProj(reference, cases);
                geodesyTimings[round] =
                    timeDirectGeodesy(solver, cases);
                geographiclibTimings[round] =
                    timeDirectReference(reference, cases);
                break;
        }
    }

    writeln();
    writeln(label);

    report("geodesy-d", geodesyTimings[]);
    report("GeographicLib 2.7", geographiclibTimings[]);
    report("PROJ", projTimings[]);
}



void profileInverseOrdinary(
    const Geodesic!double solver,
    const InverseCase[] cases)
{
    enum size_t profileRounds = 128;

    double localSink = 0.0;

    /*
     * One untimed warm-up traversal before the profiling workload.
     */
    foreach (const ref item; cases)
    {
        GeodesicInverseResult!double result;

        if (solver.tryInverse(
                item.start,
                item.end,
                result))
            localSink += fingerprint(result);
        else
            localSink += 1.0e100;
    }

    /*
     * Deliberately no StopWatch here.
     *
     * perf observes only the prepared geodesy-d inverse workload plus
     * the minimal loop/fingerprint machinery required to keep results live.
     */
    foreach (_; 0 .. profileRounds)
    {
        foreach (const ref item; cases)
        {
            GeodesicInverseResult!double result;

            if (solver.tryInverse(
                    item.start,
                    item.end,
                    result))
                localSink += fingerprint(result);
            else
                localSink += 1.0e100;
        }
    }

    benchmarkSink += localSink;

    writeln("=== geodesy-d profiling mode ===");

    writefln(
        "corpus:             INVERSE / ordinary-global");

    writefln(
        "samples per round:  %s",
        cases.length);

    writefln(
        "profile rounds:     %s",
        profileRounds);

    writefln(
        "profile operations: %s",
        profileRounds * cases.length);
}


void benchmarkInverseThreeWay(
    const char[] label,
    const Geodesic!double solver,
    void* reference,
    const InverseCase[] cases)
{
    double[timedRounds] geodesyTimings;
    double[timedRounds] geographiclibTimings;
    double[timedRounds] projTimings;

    timeInverseGeodesy(solver, cases);
    timeInverseReference(reference, cases);
    timeInverseProj(reference, cases);

    foreach (round; 0 .. timedRounds)
    {
        final switch (round % 3)
        {
            case 0:
                geodesyTimings[round] =
                    timeInverseGeodesy(solver, cases);
                geographiclibTimings[round] =
                    timeInverseReference(reference, cases);
                projTimings[round] =
                    timeInverseProj(reference, cases);
                break;

            case 1:
                geographiclibTimings[round] =
                    timeInverseReference(reference, cases);
                projTimings[round] =
                    timeInverseProj(reference, cases);
                geodesyTimings[round] =
                    timeInverseGeodesy(solver, cases);
                break;

            case 2:
                projTimings[round] =
                    timeInverseProj(reference, cases);
                geodesyTimings[round] =
                    timeInverseGeodesy(solver, cases);
                geographiclibTimings[round] =
                    timeInverseReference(reference, cases);
                break;
        }
    }

    writeln();
    writeln(label);

    report("geodesy-d", geodesyTimings[]);
    report("GeographicLib 2.7", geographiclibTimings[]);
    report("PROJ", projTimings[]);
}


void main(string[] args)
{
    if (args.length > 2
        || (args.length == 2
            && args[1] != "--profile-inverse-ordinary"))
        throw new Exception(
            "usage: geodesic-reference "
            ~ "[--profile-inverse-ordinary]");

    const bool profileInverseOrdinaryOnly =
        args.length == 2;

    const earth = wgs84!double();

    const solver =
        Geodesic!double.fromEllipsoid(
            earth);

    if (profileInverseOrdinaryOnly)
    {
        auto inverseOrdinary =
            new InverseCase[sampleCount];

        fillInverseOrdinary(
            inverseOrdinary);

        profileInverseOrdinary(
            solver,
            inverseOrdinary);

        writefln(
            "sink: %.17g",
            benchmarkSink);

        return;
    }

    void* reference =
        geodesic_reference_create(
            earth.semiMajorAxis,
            earth.flattening);

    if (reference is null)
        throw new Exception(
            "failed to create GeographicLib reference solver");

    scope(exit)
        geodesic_reference_destroy(
            reference);

    auto directOrdinary =
        new DirectCase[sampleCount];

    auto directShort =
        new DirectCase[sampleCount];

    auto directLong =
        new DirectCase[sampleCount];

    auto inverseOrdinary =
        new InverseCase[sampleCount];

    auto inverseShort =
        new InverseCase[sampleCount];

    auto inverseMeridional =
        new InverseCase[sampleCount];

    auto inverseEquatorial =
        new InverseCase[sampleCount];

    auto inversePolar =
        new InverseCase[sampleCount];

    auto inverseNearAntipodal =
        new InverseCase[sampleCount];

    fillDirectOrdinary(
        directOrdinary);

    fillDirectShort(
        directShort);

    fillDirectLong(
        directLong);

    fillInverseOrdinary(
        inverseOrdinary);

    fillInverseShort(
        inverseShort);

    fillInverseMeridional(
        inverseMeridional);

    fillInverseEquatorial(
        inverseEquatorial);

    fillInversePolar(
        inversePolar);

    fillInverseNearAntipodal(
        inverseNearAntipodal);

    writeln(
        "=== numerical preflight ===");

    preflightDirect(
        solver,
        reference,
        directOrdinary);

    preflightProjDirect(
        solver,
        reference,
        directOrdinary);

    preflightDirect(
        solver,
        reference,
        directShort);

    preflightProjDirect(
        solver,
        reference,
        directShort);

    preflightDirect(
        solver,
        reference,
        directLong);

    preflightProjDirect(
        solver,
        reference,
        directLong);

    preflightInverse(
        "inverse ordinary",
        solver,
        reference,
        inverseOrdinary);

    preflightProjInverse(
        "inverse ordinary",
        solver,
        reference,
        inverseOrdinary);

    preflightInverse(
        "inverse short",
        solver,
        reference,
        inverseShort);

    preflightProjInverse(
        "inverse short",
        solver,
        reference,
        inverseShort);

    preflightInverse(
        "inverse meridional",
        solver,
        reference,
        inverseMeridional);

    preflightProjInverse(
        "inverse meridional",
        solver,
        reference,
        inverseMeridional);

    preflightInverse(
        "inverse equatorial",
        solver,
        reference,
        inverseEquatorial);

    preflightProjInverse(
        "inverse equatorial",
        solver,
        reference,
        inverseEquatorial);

    preflightInverse(
        "inverse polar",
        solver,
        reference,
        inversePolar);

    preflightProjInverse(
        "inverse polar",
        solver,
        reference,
        inversePolar);

    preflightInverse(
        "inverse near-antipodal",
        solver,
        reference,
        inverseNearAntipodal);

    preflightProjInverse(
        "inverse near-antipodal",
        solver,
        reference,
        inverseNearAntipodal);

    writeln();
    writefln(
        "samples per corpus: %s",
        sampleCount);

    writefln(
        "timed rounds:       %s",
        timedRounds);

    benchmarkDirectThreeWay(
        "DIRECT / ordinary-global",
        solver,
        reference,
        directOrdinary);

    benchmarkDirectThreeWay(
        "DIRECT / short",
        solver,
        reference,
        directShort);

    benchmarkDirectThreeWay(
        "DIRECT / long",
        solver,
        reference,
        directLong);

    benchmarkInverseThreeWay(
        "INVERSE / ordinary-global",
        solver,
        reference,
        inverseOrdinary);

    benchmarkInverseThreeWay(
        "INVERSE / short",
        solver,
        reference,
        inverseShort);

    benchmarkInverseThreeWay(
        "INVERSE / meridional",
        solver,
        reference,
        inverseMeridional);

    benchmarkInverseThreeWay(
        "INVERSE / equatorial",
        solver,
        reference,
        inverseEquatorial);

    benchmarkInverseThreeWay(
        "INVERSE / polar",
        solver,
        reference,
        inversePolar);

    benchmarkInverseThreeWay(
        "INVERSE / near-antipodal",
        solver,
        reference,
        inverseNearAntipodal);

    writefln(
        "\nsink: %.17g",
        benchmarkSink);
}
