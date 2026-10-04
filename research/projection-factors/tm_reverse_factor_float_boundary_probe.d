module geodesy.projection.tm_reverse_factor_float_boundary_probe;

import std.format : format;
import std.math :
    PI,
    asinh,
    atan2,
    cos,
    fabs,
    hypot,
    sin,
    sinh,
    sqrt;
import std.stdio : writefln;

import geodesy.angle : Latitude, Longitude;
import geodesy.ellipsoid : Ellipsoid;
import geodesy.geographic : GeographicCoordinate;
import geodesy.projected : ProjectedCoordinate;
import geodesy.projection.transverse_mercator :
    TransverseMercator;


private enum double radius = 6_371_000.0;
private enum double lon0Degrees = 15.0;

private immutable double[] latitudeDegrees = [
    -89.9999,
    -89.99,
    -89.0,
    -80.0,
    -45.0,
    -1.0,
    0.0,
    1.0,
    45.0,
    80.0,
    89.0,
    89.99,
    89.9999,
];

private immutable double[] deltaMagnitudeDegrees = [
    60.0,
    60.000001,
    60.001,
    60.01,
    60.1,
    61.0,
    65.0,
];

private immutable float[] k0Values = [
    0.9f,
    1.0f,
    1.1f,
];


private struct Summary
{
    size_t cases;

    size_t reverseAccepted;
    size_t reverseRejected;

    size_t factorAccepted;
    size_t factorRejected;

    size_t acceptanceParityFailures;

    size_t acceptedRawExcursions;
    size_t rejectedRawExcursions;

    size_t clampedLongitudeFailures;

    size_t gammaClampSensitive;
    size_t gammaClampedCloser;
    size_t gammaRawCloser;
    size_t gammaTie;

    size_t scaleClampSensitive;
    size_t scaleClampedCloser;
    size_t scaleRawCloser;
    size_t scaleTie;

    double maxGammaErrorRadians = 0.0;
    string maxGammaErrorCase;

    double maxScaleRelativeError = 0.0;
    string maxScaleRelativeErrorCase;
}


private string caseLabel(
    const float k0,
    const double latitude,
    const double signedDelta)
{
    return format(
        "k0=%.9g lat=%+.7f dlon=%+.9f",
        cast(double) k0,
        latitude,
        signedDelta);
}


private ProjectedCoordinate!float sphericalOracleProjected(
    const Latitude!float latitude,
    const double deltaLongitudeDegrees,
    const float k0)
{
    /*
     * Independent exact spherical TM.
     *
     * The public latitude is promoted from its actual float representation.
     * E/N are rounded only at ProjectedCoordinate<float>.
     */
    const double phi =
        cast(double) latitude.radians;

    const double lambda =
        deltaLongitudeDegrees
        * cast(double) PI
        / 180.0;

    const double s = sin(phi);
    const double c = cos(phi);
    const double cl = cos(lambda);
    const double sl = sin(lambda);

    const double q =
        hypot(
            s,
            c * cl);

    const double xi =
        atan2(
            s,
            c * cl);

    const double eta =
        asinh(
            c * sl / q);

    const double representedRadius =
        cast(double) cast(float) radius;

    const double representedK0 =
        cast(double) k0;

    return ProjectedCoordinate!float.fromComponents(
        cast(float) (
            representedK0
            * representedRadius
            * eta),
        cast(float) (
            representedK0
            * representedRadius
            * xi));
}


private void sphericalOracleReverse(
    const ProjectedCoordinate!float projected,
    const float k0,
    out double latitude,
    out double deltaLongitude)
{
    /*
     * Exact inverse spherical TM, starting from the actual represented
     * binary32 E/N pair.
     */
    const double representedRadius =
        cast(double) cast(float) radius;

    const double representedK0 =
        cast(double) k0;

    const double naturalScale =
        representedRadius
        * representedK0;

    const double eta =
        cast(double) projected.easting
        / naturalScale;

    const double xi =
        cast(double) projected.northing
        / naturalScale;

    const double sinhEta =
        sinh(eta);

    const double cosXi =
        cos(xi);

    const double r =
        hypot(
            sinhEta,
            cosXi);

    deltaLongitude =
        atan2(
            sinhEta,
            cosXi);

    latitude =
        atan2(
            sin(xi),
            r);
}


private void sphericalOracleFactors(
    const double latitude,
    const double deltaLongitude,
    const float k0,
    out float gammaRadians,
    out float pointScale)
{
    const double sinPhi =
        sin(latitude);

    const double cosPhi =
        cos(latitude);

    const double sinLambda =
        sin(deltaLongitude);

    const double cosLambda =
        cos(deltaLongitude);

    const double gamma =
        atan2(
            sinLambda * sinPhi,
            cosLambda);

    const double q =
        cosPhi * sinLambda;

    const double scale =
        cast(double) k0
        / sqrt(
            1.0 - q * q);

    gammaRadians =
        cast(float) gamma;

    pointScale =
        cast(float) scale;
}


private void updateMaximum(
    ref double maximum,
    ref string maximumCase,
    const double candidate,
    const string label)
{
    if (maximumCase.length == 0 || candidate > maximum)
    {
        maximum = candidate;
        maximumCase = label;
    }
}


int main()
{
    Summary summary;

    const ellipsoid =
        Ellipsoid!float.fromFlattening(
            cast(float) radius,
            0.0f);

    const latitudeOfOrigin =
        Latitude!float.fromDegrees(
            0.0f);

    const longitudeOfOrigin =
        Longitude!float.fromDegrees(
            cast(float) lon0Degrees);

    const double maxDelta =
        cast(double) PI / 3.0;

    writefln(
        "=== FLOAT-R3 TM REVERSE FACTOR BOUNDARY PROBE ===");
    writefln(
        "model=sphere R=%.17g lon0-public-rad=%.17g",
        cast(double) cast(float) radius,
        cast(double) longitudeOfOrigin.radians);
    writefln(
        "public scalar=float; independent projected and reverse oracle");
    writefln(
        "boundary policy authority=tryReverse(); factor path=B");

    foreach (const k0; k0Values)
    {
        const projection =
            TransverseMercator!float.fromParameters(
                ellipsoid,
                latitudeOfOrigin,
                longitudeOfOrigin,
                k0,
                0.0f,
                0.0f);

        foreach (const nominalLatitude; latitudeDegrees)
        {
            const publicLatitude =
                Latitude!float.fromDegrees(
                    cast(float) nominalLatitude);

            /*
             * Keep actual public poles out of PF-B until the separate pole
             * convergence convention is selected.
             */
            if (fabs(
                    cast(double) publicLatitude.degrees)
                >= 90.0)
            {
                continue;
            }

            foreach (const longitudeSign; [-1.0, 1.0])
            {
                foreach (
                    const deltaMagnitude;
                    deltaMagnitudeDegrees)
                {
                    const double signedDelta =
                        longitudeSign
                        * deltaMagnitude;

                    const string label =
                        caseLabel(
                            k0,
                            nominalLatitude,
                            signedDelta);

                    const projected =
                        sphericalOracleProjected(
                            publicLatitude,
                            signedDelta,
                            k0);

                    ++summary.cases;

                    GeographicCoordinate!float recovered;

                    const bool reverseOk =
                        projection.tryReverse(
                            projected,
                            recovered);

                    float gammaB;
                    float scaleB;

                    const bool factorOk =
                        projection.researchTryReverseFactors(
                            projected,
                            gammaB,
                            scaleB);

                    if (reverseOk)
                        ++summary.reverseAccepted;
                    else
                        ++summary.reverseRejected;

                    if (factorOk)
                        ++summary.factorAccepted;
                    else
                        ++summary.factorRejected;

                    if (reverseOk != factorOk)
                    {
                        ++summary.acceptanceParityFailures;

                        writefln(
                            "PARITY FAIL: %s reverse=%s factors=%s "
                            ~ "E=%.17g N=%.17g",
                            label,
                            reverseOk,
                            factorOk,
                            cast(double) projected.easting,
                            cast(double) projected.northing);

                        continue;
                    }

                    double oracleLatitude;
                    double rawDelta;

                    sphericalOracleReverse(
                        projected,
                        k0,
                        oracleLatitude,
                        rawDelta);

                    const bool rawExcursion =
                        fabs(rawDelta) > maxDelta;

                    if (!reverseOk)
                    {
                        if (rawExcursion)
                            ++summary.rejectedRawExcursions;

                        continue;
                    }

                    if (rawExcursion)
                    {
                        ++summary.acceptedRawExcursions;

                        const double expectedLongitudeRadians =
                            cast(double)
                                longitudeOfOrigin.radians
                            + (
                                rawDelta < 0.0
                                    ? -maxDelta
                                    : maxDelta);

                        const float expectedPublicLongitude =
                            cast(float)
                                expectedLongitudeRadians;

                        if (
                            recovered.longitude.radians
                            != expectedPublicLongitude)
                        {
                            ++summary.clampedLongitudeFailures;

                            writefln(
                                "CLAMP LONGITUDE FAIL: %s "
                                ~ "rawDlonDeg=%+.12f "
                                ~ "actualLonRad=%.17g "
                                ~ "expectedLonRad=%.17g",
                                label,
                                rawDelta
                                    * 180.0
                                    / cast(double) PI,
                                cast(double)
                                    recovered.longitude.radians,
                                cast(double)
                                    expectedPublicLongitude);
                        }
                    }

                    const double factorDelta =
                        rawDelta < -maxDelta
                            ? -maxDelta
                            : rawDelta > maxDelta
                                ? maxDelta
                                : rawDelta;

                    float expectedGamma;
                    float expectedScale;

                    sphericalOracleFactors(
                        oracleLatitude,
                        factorDelta,
                        k0,
                        expectedGamma,
                        expectedScale);

                    const double gammaError =
                        fabs(
                            cast(double) gammaB
                            - cast(double) expectedGamma);

                    const double scaleRelativeError =
                        fabs(
                            cast(double) scaleB
                            - cast(double) expectedScale)
                        / cast(double) expectedScale;

                    updateMaximum(
                        summary.maxGammaErrorRadians,
                        summary.maxGammaErrorCase,
                        gammaError,
                        label);

                    updateMaximum(
                        summary.maxScaleRelativeError,
                        summary.maxScaleRelativeErrorCase,
                        scaleRelativeError,
                        label);

                    if (rawExcursion)
                    {
                        float rawGamma;
                        float rawScale;

                        sphericalOracleFactors(
                            oracleLatitude,
                            rawDelta,
                            k0,
                            rawGamma,
                            rawScale);

                        if (rawGamma != expectedGamma)
                        {
                            ++summary.gammaClampSensitive;

                            const double clampedError =
                                fabs(
                                    cast(double) gammaB
                                    - cast(double) expectedGamma);

                            const double rawError =
                                fabs(
                                    cast(double) gammaB
                                    - cast(double) rawGamma);

                            if (clampedError < rawError)
                                ++summary.gammaClampedCloser;
                            else if (rawError < clampedError)
                                ++summary.gammaRawCloser;
                            else
                                ++summary.gammaTie;
                        }

                        if (rawScale != expectedScale)
                        {
                            ++summary.scaleClampSensitive;

                            const double clampedError =
                                fabs(
                                    cast(double) scaleB
                                    - cast(double) expectedScale);

                            const double rawError =
                                fabs(
                                    cast(double) scaleB
                                    - cast(double) rawScale);

                            if (clampedError < rawError)
                                ++summary.scaleClampedCloser;
                            else if (rawError < clampedError)
                                ++summary.scaleRawCloser;
                            else
                                ++summary.scaleTie;
                        }
                    }
                }
            }
        }
    }

    writefln("");
    writefln("=== FLOAT-R3 SUMMARY ===");
    writefln("cases=%s", summary.cases);

    writefln(
        "reverse accepted/rejected=%s/%s",
        summary.reverseAccepted,
        summary.reverseRejected);

    writefln(
        "factors accepted/rejected=%s/%s",
        summary.factorAccepted,
        summary.factorRejected);

    writefln(
        "acceptance parity failures=%s",
        summary.acceptanceParityFailures);

    writefln(
        "accepted raw boundary excursions=%s",
        summary.acceptedRawExcursions);

    writefln(
        "rejected raw boundary excursions=%s",
        summary.rejectedRawExcursions);

    writefln(
        "clamped public longitude failures=%s",
        summary.clampedLongitudeFailures);

    writefln(
        "gamma clamp-sensitive "
        ~ "clamped-closer/raw-closer/tie=%s/%s/%s/%s",
        summary.gammaClampSensitive,
        summary.gammaClampedCloser,
        summary.gammaRawCloser,
        summary.gammaTie);

    writefln(
        "scale clamp-sensitive "
        ~ "clamped-closer/raw-closer/tie=%s/%s/%s/%s",
        summary.scaleClampSensitive,
        summary.scaleClampedCloser,
        summary.scaleRawCloser,
        summary.scaleTie);

    writefln(
        "max |gamma_B - analytic-clamped|=%.17g rad",
        summary.maxGammaErrorRadians);
    writefln(
        "  at: %s",
        summary.maxGammaErrorCase);

    writefln(
        "max relative |k_B - analytic-clamped|=%.17g",
        summary.maxScaleRelativeError);
    writefln(
        "  at: %s",
        summary.maxScaleRelativeErrorCase);

    /*
     * Research sanity bounds, deliberately looser than production tolerances.
     * R1/R2 observed factor errors well below these values.
     */
    enum double gammaSanityRadians = 2.0e-7;
    enum double scaleRelativeSanity = 2.0e-7;

    const bool pass =
        summary.acceptanceParityFailures == 0
        && summary.clampedLongitudeFailures == 0
        && summary.acceptedRawExcursions > 0
        && summary.maxGammaErrorRadians
            <= gammaSanityRadians
        && summary.maxScaleRelativeError
            <= scaleRelativeSanity;

    writefln("");

    if (!pass)
    {
        writefln(
            "FAIL: FLOAT-R3 reverse/factor boundary consistency");
        return 1;
    }

    writefln(
        "PASS: FLOAT-R3 reverse/factor boundary consistency");
    writefln(
        "NOTE: numerical bounds are characterization guards, "
        ~ "not production acceptance tolerances");

    return 0;
}
