/**
 * TOPO-E adversarial/failure contract probe.
 *
 * Research/release validation only.
 *
 * This probe intentionally exercises the public geodesy-d API. It complements
 * the production module unittests and the compile-time API contract tests.
 */
module topo_e_contract_probe;

import std.math :
    cos,
    fabs,
    sin,
    sqrt;
import std.stdio :
    writefln,
    writeln;

import geodesy.angle :
    Latitude,
    Longitude;
import geodesy.conversion :
    geocentricToGeodetic,
    geodeticToGeocentric;
import geodesy.ellipsoid :
    Ellipsoid,
    wgs84;
import geodesy.errors :
    GeodesyValueException;
import geodesy.geocentric :
    GeocentricCoordinate;
import geodesy.geodetic :
    GeodeticCoordinate;
import geodesy.topocentric :
    TopocentricCoordinate,
    TopocentricFrame;


private size_t checks;


private void require(
    const bool condition,
    const string label)
{
    ++checks;

    if (!condition)
        throw new Exception("TOPO-E FAIL: " ~ label);
}


private void expectValueException(
    void delegate() operation,
    const string label)
{
    bool thrown = false;

    try
    {
        operation();
    }
    catch (GeodesyValueException error)
    {
        cast(void) error;
        thrown = true;
    }

    require(thrown, label);
}


private bool near(
    const real actual,
    const real expected,
    const real tolerance)
{
    return fabs(actual - expected) <= tolerance;
}


private real scalarTolerance(T)()
{
    static if (is(T == float))
        return 2.0e-4L;
    else
        return 1.0e-11L;
}


private GeodeticCoordinate!T makeGeodetic(T)(
    const real latitudeDegrees,
    const real longitudeDegrees,
    const real height)
{
    return GeodeticCoordinate!T.fromComponents(
        Latitude!T.fromDegrees(
            cast(T) latitudeDegrees),
        Longitude!T.fromDegrees(
            cast(T) longitudeDegrees),
        cast(T) height);
}


private void testCoordinateContract(T)()
{
    const zero =
        TopocentricCoordinate!T.init;

    require(
        zero.east == cast(T) 0
            && zero.north == cast(T) 0
            && zero.up == cast(T) 0,
        T.stringof ~
            ": TopocentricCoordinate.init is exact zero");

    TopocentricCoordinate!T finite;

    require(
        TopocentricCoordinate!T.tryFromComponents(
            cast(T) 1.25,
            cast(T) -2.5,
            cast(T) 3.75,
            finite),
        T.stringof ~
            ": finite topocentric components accepted");

    const T[3] badValues =
    [
        T.nan,
        T.infinity,
        -T.infinity,
    ];

    foreach (component; 0 .. 3)
    {
        foreach (bad; badValues)
        {
            T east = cast(T) 1;
            T north = cast(T) 2;
            T up = cast(T) 3;

            final switch (component)
            {
                case 0:
                    east = bad;
                    break;

                case 1:
                    north = bad;
                    break;

                case 2:
                    up = bad;
                    break;
            }

            TopocentricCoordinate!T result;

            require(
                !TopocentricCoordinate!T.tryFromComponents(
                    east,
                    north,
                    up,
                    result),
                T.stringof ~
                    ": non-finite topocentric component rejected");

            expectValueException(
                {
                    const ignored =
                        TopocentricCoordinate!T.fromComponents(
                            east,
                            north,
                            up);

                    cast(void) ignored;
                },
                T.stringof ~
                    ": throwing coordinate factory rejects non-finite input");
        }
    }

    writeln(
        "PASS coordinate contract / ",
        T.stringof);
}


private void testFrameFailureContract(T)()
{
    const ellipsoid =
        wgs84!T();

    const geodetic =
        makeGeodetic!T(
            48.0L,
            16.0L,
            100.0L);

    const geocentric =
        geodeticToGeocentric(
            geodetic,
            ellipsoid);

    const local =
        TopocentricCoordinate!T.fromComponents(
            cast(T) 10,
            cast(T) -20,
            cast(T) 5);

    const invalidFrame =
        TopocentricFrame!T.init;

    require(
        !invalidFrame.isValid,
        T.stringof ~
            ": TopocentricFrame.init invalid");

    TopocentricCoordinate!T localResult;
    GeocentricCoordinate!T geocentricResult;
    GeodeticCoordinate!T geodeticResult;

    require(
        !invalidFrame.tryGeocentricToTopocentric(
            geocentric,
            localResult),
        T.stringof ~
            ": invalid frame rejects 9836 forward");

    require(
        !invalidFrame.tryTopocentricToGeocentric(
            local,
            geocentricResult),
        T.stringof ~
            ": invalid frame rejects 9836 reverse");

    require(
        !invalidFrame.tryGeodeticToTopocentric(
            geodetic,
            localResult),
        T.stringof ~
            ": invalid frame rejects 9837 forward");

    require(
        !invalidFrame.tryTopocentricToGeodetic(
            local,
            geodeticResult),
        T.stringof ~
            ": invalid frame rejects 9837 reverse");

    expectValueException(
        {
            const ignored =
                invalidFrame.geocentricToTopocentric(
                    geocentric);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid-frame 9836 forward throws");

    expectValueException(
        {
            const ignored =
                invalidFrame.topocentricToGeocentric(
                    local);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid-frame 9836 reverse throws");

    expectValueException(
        {
            const ignored =
                invalidFrame.geodeticToTopocentric(
                    geodetic);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid-frame 9837 forward throws");

    expectValueException(
        {
            const ignored =
                invalidFrame.topocentricToGeodetic(
                    local);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid-frame 9837 reverse throws");

    const invalidEllipsoid =
        Ellipsoid!T.init;

    TopocentricFrame!T candidate;

    require(
        !TopocentricFrame!T.tryFromGeodeticOrigin(
            invalidEllipsoid,
            geodetic,
            candidate),
        T.stringof ~
            ": invalid ellipsoid rejected for geodetic origin");

    require(
        !TopocentricFrame!T.tryFromGeocentricOrigin(
            invalidEllipsoid,
            geocentric,
            candidate),
        T.stringof ~
            ": invalid ellipsoid rejected for geocentric origin");

    expectValueException(
        {
            const ignored =
                TopocentricFrame!T.fromGeodeticOrigin(
                    invalidEllipsoid,
                    geodetic);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid ellipsoid geodetic factory throws");

    expectValueException(
        {
            const ignored =
                TopocentricFrame!T.fromGeocentricOrigin(
                    invalidEllipsoid,
                    geocentric);

            cast(void) ignored;
        },
        T.stringof ~
            ": invalid ellipsoid geocentric factory throws");

    /*
     * The exact geocentre is finite but has no unique EPSG 9602 inverse.
     */
    require(
        !TopocentricFrame!T.tryFromGeocentricOrigin(
            ellipsoid,
            GeocentricCoordinate!T.init,
            candidate),
        T.stringof ~
            ": exact geocentre rejected");

    expectValueException(
        {
            const ignored =
                TopocentricFrame!T.fromGeocentricOrigin(
                    ellipsoid,
                    GeocentricCoordinate!T.init);

            cast(void) ignored;
        },
        T.stringof ~
            ": exact geocentre throwing factory rejects");

    writeln(
        "PASS frame/failure contract / ",
        T.stringof);
}


private void testGeodeticOriginDomain(T)()
{
    const ellipsoid =
        wgs84!T();

    immutable real[9] latitudes =
    [
        -90.0L,
        -89.999999L,
        -80.0L,
        -45.0L,
        0.0L,
        45.0L,
        80.0L,
        89.999999L,
        90.0L,
    ];

    immutable real[9] longitudes =
    [
        -180.0L,
        -179.999999L,
        -90.0L,
        -1.0L,
        0.0L,
        1.0L,
        90.0L,
        179.999999L,
        180.0L,
    ];

    size_t combinations;

    foreach (latitudeDegrees; latitudes)
    {
        foreach (longitudeDegrees; longitudes)
        {
            const origin =
                makeGeodetic!T(
                    latitudeDegrees,
                    longitudeDegrees,
                    123.25L);

            TopocentricFrame!T frame;

            require(
                TopocentricFrame!T.tryFromGeodeticOrigin(
                    ellipsoid,
                    origin,
                    frame),
                T.stringof ~
                    ": legal geodetic origin accepted");

            require(
                frame.isValid,
                T.stringof ~
                    ": legal geodetic origin produces valid frame");

            const zero =
                frame.geodeticToTopocentric(
                    origin);

            require(
                zero.east == cast(T) 0
                    && zero.north == cast(T) 0
                    && zero.up == cast(T) 0,
                T.stringof ~
                    ": geodetic frame origin maps exactly to zero");

            ++combinations;
        }
    }

    require(
        combinations == 81,
        T.stringof ~
            ": complete 9x9 geodetic-origin matrix executed");

    writeln(
        "PASS geodetic origin matrix / ",
        T.stringof,
        " / 81 combinations");
}


private void testPoleOrientation()
{
    const earth =
        wgs84!double();

    const north0 =
        makeGeodetic!double(
            90.0L,
            0.0L,
            0.0L);

    const north90 =
        makeGeodetic!double(
            90.0L,
            90.0L,
            0.0L);

    const south0 =
        makeGeodetic!double(
            -90.0L,
            0.0L,
            0.0L);

    const north0Frame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            north0);

    const north90Frame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            north90);

    const south0Frame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            south0);

    const north0Ecef =
        geodeticToGeocentric(
            north0,
            earth);

    const north90Ecef =
        geodeticToGeocentric(
            north90,
            earth);

    const south0Ecef =
        geodeticToGeocentric(
            south0,
            earth);

    const north0Source =
        GeocentricCoordinate!double.fromComponents(
            north0Ecef.x + 1.0,
            north0Ecef.y,
            north0Ecef.z);

    const north90Source =
        GeocentricCoordinate!double.fromComponents(
            north90Ecef.x + 1.0,
            north90Ecef.y,
            north90Ecef.z);

    const south0Source =
        GeocentricCoordinate!double.fromComponents(
            south0Ecef.x + 1.0,
            south0Ecef.y,
            south0Ecef.z);

    const localNorth0 =
        north0Frame.geocentricToTopocentric(
            north0Source);

    const localNorth90 =
        north90Frame.geocentricToTopocentric(
            north90Source);

    const localSouth0 =
        south0Frame.geocentricToTopocentric(
            south0Source);

    require(
        near(
            localNorth0.east,
            0.0L,
            1.0e-12L)
        && near(
            localNorth0.north,
            -1.0L,
            1.0e-12L),
        "north pole longitude 0 defines expected East/North orientation");

    require(
        near(
            localNorth90.east,
            -1.0L,
            1.0e-12L)
        && near(
            localNorth90.north,
            0.0L,
            1.0e-12L),
        "north pole longitude 90 rotates East/North orientation");

    require(
        near(
            localSouth0.east,
            0.0L,
            1.0e-12L)
        && near(
            localSouth0.north,
            1.0L,
            1.0e-12L),
        "south pole longitude 0 defines expected East/North orientation");

    /*
     * +180 and -180 are distinct legal longitude representations but define
     * equivalent physical axes. Representation preservation itself is also
     * covered by the production module unittest, which inspects the prepared
     * sin(longitude) state directly.
     */
    const plus180 =
        makeGeodetic!double(
            90.0L,
            180.0L,
            0.0L);

    const minus180 =
        makeGeodetic!double(
            90.0L,
            -180.0L,
            0.0L);

    const plusFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            plus180);

    const minusFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            minus180);

    const plusEcef =
        geodeticToGeocentric(
            plus180,
            earth);

    const minusEcef =
        geodeticToGeocentric(
            minus180,
            earth);

    const plusSource =
        GeocentricCoordinate!double.fromComponents(
            plusEcef.x,
            plusEcef.y + 1.0,
            plusEcef.z);

    const minusSource =
        GeocentricCoordinate!double.fromComponents(
            minusEcef.x,
            minusEcef.y + 1.0,
            minusEcef.z);

    const plusLocal =
        plusFrame.geocentricToTopocentric(
            plusSource);

    const minusLocal =
        minusFrame.geocentricToTopocentric(
            minusSource);

    require(
        near(
            plusLocal.east,
            minusLocal.east,
            1.0e-12L)
        && near(
            plusLocal.north,
            minusLocal.north,
            1.0e-12L)
        && near(
            plusLocal.up,
            minusLocal.up,
            1.0e-12L),
        "+180/-180 polar frames have equivalent physical orientation");

    writeln("PASS exact-pole orientation");
}


private void testRotationAxis(T)()
{
    const earth =
        wgs84!T();

    const T tolerance =
        cast(T) scalarTolerance!T();

    const northOrigin =
        GeocentricCoordinate!T.fromComponents(
            cast(T) 0,
            cast(T) 0,
            earth.semiMinorAxis + cast(T) 100);

    const southOrigin =
        GeocentricCoordinate!T.fromComponents(
            cast(T) 0,
            cast(T) 0,
            -(earth.semiMinorAxis + cast(T) 100));

    const northFrame =
        TopocentricFrame!T.fromGeocentricOrigin(
            earth,
            northOrigin);

    const southFrame =
        TopocentricFrame!T.fromGeocentricOrigin(
            earth,
            southOrigin);

    const northSource =
        GeocentricCoordinate!T.fromComponents(
            cast(T) 1,
            cast(T) 0,
            northOrigin.z);

    const southSource =
        GeocentricCoordinate!T.fromComponents(
            cast(T) 1,
            cast(T) 0,
            southOrigin.z);

    const northLocal =
        northFrame.geocentricToTopocentric(
            northSource);

    const southLocal =
        southFrame.geocentricToTopocentric(
            southSource);

    require(
        near(
            cast(real) northLocal.east,
            0.0L,
            cast(real) tolerance)
        && near(
            cast(real) northLocal.north,
            -1.0L,
            cast(real) tolerance),
        T.stringof ~
            ": north rotation-axis canonical longitude is zero");

    require(
        near(
            cast(real) southLocal.east,
            0.0L,
            cast(real) tolerance)
        && near(
            cast(real) southLocal.north,
            1.0L,
            cast(real) tolerance),
        T.stringof ~
            ": south rotation-axis canonical longitude is zero");

    writeln(
        "PASS geocentric rotation axis / ",
        T.stringof);
}


private void testDeepInterior()
{
    const earth =
        wgs84!double();

    const origin =
        GeocentricCoordinate!double.fromComponents(
            1_000_000.0,
            2_000_000.0,
            3_000_000.0);

    const canonical =
        geocentricToGeodetic(
            origin,
            earth);

    const frame =
        TopocentricFrame!double.fromGeocentricOrigin(
            earth,
            origin);

    const source =
        GeocentricCoordinate!double.fromComponents(
            origin.x + 100.0,
            origin.y - 50.0,
            origin.z + 25.0);

    const local =
        frame.geocentricToTopocentric(
            source);

    const double phi =
        canonical.latitude.radians;

    const double lambda =
        canonical.longitude.radians;

    const double dx = 100.0;
    const double dy = -50.0;
    const double dz = 25.0;

    const double expectedEast =
        -dx * sin(lambda)
        + dy * cos(lambda);

    const double expectedNorth =
        -dx * sin(phi) * cos(lambda)
        - dy * sin(phi) * sin(lambda)
        + dz * cos(phi);

    const double expectedUp =
        dx * cos(phi) * cos(lambda)
        + dy * cos(phi) * sin(lambda)
        + dz * sin(phi);

    require(
        near(
            local.east,
            expectedEast,
            1.0e-9L)
        && near(
            local.north,
            expectedNorth,
            1.0e-9L)
        && near(
            local.up,
            expectedUp,
            1.0e-9L),
        "deep-interior frame inherits EPSG 9602 canonical orientation");

    const zero =
        frame.geocentricToTopocentric(
            origin);

    require(
        zero.east == 0.0
            && zero.north == 0.0
            && zero.up == 0.0,
        "deep-interior represented origin maps exactly to zero");

    writeln("PASS deep-interior geocentric origin");
}


private void testSphere()
{
    const sphere =
        Ellipsoid!double.sphere(
            6_371_000.0);

    const origin =
        makeGeodetic!double(
            20.0L,
            30.0L,
            50.0L);

    const source =
        makeGeodetic!double(
            20.01L,
            30.02L,
            70.0L);

    const originEcef =
        geodeticToGeocentric(
            origin,
            sphere);

    const sourceEcef =
        geodeticToGeocentric(
            source,
            sphere);

    const geodeticFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            sphere,
            origin);

    const geocentricFrame =
        TopocentricFrame!double.fromGeocentricOrigin(
            sphere,
            originEcef);

    const local9837 =
        geodeticFrame.geodeticToTopocentric(
            source);

    const local9836 =
        geocentricFrame.geocentricToTopocentric(
            sourceEcef);

    require(
        near(
            local9837.east,
            local9836.east,
            1.0e-8L)
        && near(
            local9837.north,
            local9836.north,
            1.0e-8L)
        && near(
            local9837.up,
            local9836.up,
            1.0e-8L),
        "sphere 9836 and 9837 forward agree");

    const ecefAgain =
        geocentricFrame.topocentricToGeocentric(
            local9836);

    require(
        near(
            ecefAgain.x,
            sourceEcef.x,
            1.0e-8L)
        && near(
            ecefAgain.y,
            sourceEcef.y,
            1.0e-8L)
        && near(
            ecefAgain.z,
            sourceEcef.z,
            1.0e-8L),
        "sphere 9836 reverse");

    const geodeticAgain =
        geodeticFrame.topocentricToGeodetic(
            local9837);

    require(
        near(
            geodeticAgain.latitude.radians,
            source.latitude.radians,
            1.0e-12L)
        && near(
            geodeticAgain.longitude.radians,
            source.longitude.radians,
            1.0e-12L)
        && near(
            geodeticAgain.ellipsoidalHeight,
            source.ellipsoidalHeight,
            1.0e-8L),
        "sphere 9837 reverse");

    foreach (pole; [-90.0L, 90.0L])
    {
        const poleOrigin =
            makeGeodetic!double(
                pole,
                73.0L,
                0.0L);

        const poleFrame =
            TopocentricFrame!double.fromGeodeticOrigin(
                sphere,
                poleOrigin);

        require(
            poleFrame.isValid,
            "sphere exact pole accepted");

        const zero =
            poleFrame.geodeticToTopocentric(
                poleOrigin);

        require(
            zero.east == 0.0
                && zero.north == 0.0
                && zero.up == 0.0,
            "sphere exact pole maps to zero");
    }

    writeln("PASS sphere");
}


private void testAntimeridian()
{
    const earth =
        wgs84!double();

    const plusOrigin =
        makeGeodetic!double(
            10.0L,
            180.0L,
            100.0L);

    const minusOrigin =
        makeGeodetic!double(
            10.0L,
            -180.0L,
            100.0L);

    const source =
        makeGeodetic!double(
            10.001L,
            179.999L,
            120.0L);

    const plusFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            plusOrigin);

    const minusFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            minusOrigin);

    const plusLocal =
        plusFrame.geodeticToTopocentric(
            source);

    const minusLocal =
        minusFrame.geodeticToTopocentric(
            source);

    require(
        near(
            plusLocal.east,
            minusLocal.east,
            1.0e-7L)
        && near(
            plusLocal.north,
            minusLocal.north,
            1.0e-7L)
        && near(
            plusLocal.up,
            minusLocal.up,
            1.0e-7L),
        "+180/-180 meridian representations give equivalent ENU geometry");

    const eastFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            makeGeodetic!double(
                10.0L,
                179.999L,
                100.0L));

    const westFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            earth,
            makeGeodetic!double(
                10.0L,
                -179.999L,
                100.0L));

    const acrossWest =
        eastFrame.geodeticToTopocentric(
            makeGeodetic!double(
                10.0L,
                -179.999L,
                100.0L));

    const acrossEast =
        westFrame.geodeticToTopocentric(
            makeGeodetic!double(
                10.0L,
                179.999L,
                100.0L));

    require(
        near(
            acrossWest.east,
            -acrossEast.east,
            1.0e-6L)
        && near(
            acrossWest.north,
            acrossEast.north,
            1.0e-6L)
        && near(
            acrossWest.up,
            acrossEast.up,
            1.0e-6L),
        "antimeridian crossing is continuous and symmetric");

    writeln("PASS antimeridian");
}


private void testFiniteArithmeticFailure(T)()
{
    const earth =
        wgs84!T();

    const origin =
        makeGeodetic!T(
            45.0L,
            45.0L,
            0.0L);

    const frame =
        TopocentricFrame!T.fromGeodeticOrigin(
            earth,
            origin);

    const hugeEcef =
        GeocentricCoordinate!T.fromComponents(
            T.max,
            T.max,
            T.max);

    TopocentricCoordinate!T localResult;

    require(
        !frame.tryGeocentricToTopocentric(
            hugeEcef,
            localResult),
        T.stringof ~
            ": non-finite 9836 forward arithmetic result rejected");

    expectValueException(
        {
            const ignored =
                frame.geocentricToTopocentric(
                    hugeEcef);

            cast(void) ignored;
        },
        T.stringof ~
            ": non-finite 9836 forward arithmetic throws");

    const hugeLocal =
        TopocentricCoordinate!T.fromComponents(
            T.max,
            T.max,
            T.max);

    GeocentricCoordinate!T ecefResult;

    require(
        !frame.tryTopocentricToGeocentric(
            hugeLocal,
            ecefResult),
        T.stringof ~
            ": non-finite 9836 reverse arithmetic result rejected");

    expectValueException(
        {
            const ignored =
                frame.topocentricToGeocentric(
                    hugeLocal);

            cast(void) ignored;
        },
        T.stringof ~
            ": non-finite 9836 reverse arithmetic throws");

    GeodeticCoordinate!T geodeticResult;

    require(
        !frame.tryTopocentricToGeodetic(
            hugeLocal,
            geodeticResult),
        T.stringof ~
            ": non-finite 9837 reverse arithmetic result rejected");

    expectValueException(
        {
            const ignored =
                frame.topocentricToGeodetic(
                    hugeLocal);

            cast(void) ignored;
        },
        T.stringof ~
            ": non-finite 9837 reverse arithmetic throws");

    writeln(
        "PASS finite-arithmetic failure / ",
        T.stringof);
}


private void testFloatReverseWorkingPrecision()
{
    const floatEllipsoid =
        wgs84!float();

    const floatOrigin =
        makeGeodetic!float(
            48.20849L,
            16.37208L,
            171.0L);

    const floatFrame =
        TopocentricFrame!float.fromGeodeticOrigin(
            floatEllipsoid,
            floatOrigin);

    const doubleEllipsoid =
        Ellipsoid!double.fromFlattening(
            cast(double) floatEllipsoid.semiMajorAxis,
            cast(double) floatEllipsoid.flattening);

    const doubleOrigin =
        GeodeticCoordinate!double.fromComponents(
            Latitude!double.fromRadians(
                cast(double) floatOrigin.latitude.radians),
            Longitude!double.fromRadians(
                cast(double) floatOrigin.longitude.radians),
            cast(double) floatOrigin.ellipsoidalHeight);

    const doubleFrame =
        TopocentricFrame!double.fromGeodeticOrigin(
            doubleEllipsoid,
            doubleOrigin);

    immutable float[3][4] localCases =
    [
        [1.25f, 2.5f, 0.75f],
        [12.34f, -56.78f, 9.1f],
        [0.01f, 0.02f, 0.03f],
        [100.0f, -200.0f, 50.0f],
    ];

    real maximumQuantizationDamage = 0.0L;

    foreach (values; localCases)
    {
        const floatLocal =
            TopocentricCoordinate!float.fromComponents(
                values[0],
                values[1],
                values[2]);

        const direct =
            floatFrame.topocentricToGeodetic(
                floatLocal);

        const reference =
            doubleFrame.topocentricToGeodetic(
                TopocentricCoordinate!double.fromComponents(
                    cast(double) values[0],
                    cast(double) values[1],
                    cast(double) values[2]));

        require(
            direct.latitude.radians
                == cast(float) reference.latitude.radians,
            "float reverse latitude is final narrowing of working path");

        require(
            direct.longitude.radians
                == cast(float) reference.longitude.radians,
            "float reverse longitude is final narrowing of working path");

        require(
            direct.ellipsoidalHeight
                == cast(float) reference.ellipsoidalHeight,
            "float reverse height is final narrowing of working path");

        /*
         * Deliberately emulate the forbidden composed reverse path:
         *
         *   ENU<float>
         *       -> ECEF<float>
         *       -> geodetic<float>
         *
         * The direct 9837 implementation must not materialize this
         * Earth-scale binary32 ECEF intermediate.
         */
        const referenceEcef =
            doubleFrame.topocentricToGeocentric(
                TopocentricCoordinate!double.fromComponents(
                    cast(double) values[0],
                    cast(double) values[1],
                    cast(double) values[2]));

        const quantizedEcef =
            floatFrame.topocentricToGeocentric(
                floatLocal);

        /*
         * Measure the forbidden narrowing at the point where information is
         * actually lost: Earth-scale ECEF. Comparing only the later public
         * GeodeticCoordinate<float> values can hide this loss behind the final
         * float rounding of latitude/longitude/height.
         */
        const real xDamage =
            fabs(
                cast(real) quantizedEcef.x
                - cast(real) referenceEcef.x);

        const real yDamage =
            fabs(
                cast(real) quantizedEcef.y
                - cast(real) referenceEcef.y);

        const real zDamage =
            fabs(
                cast(real) quantizedEcef.z
                - cast(real) referenceEcef.z);

        const real damage =
            xDamage > yDamage
            ? (xDamage > zDamage
                ? xDamage
                : zDamage)
            : (yDamage > zDamage
                ? yDamage
                : zDamage);

        if (damage > maximumQuantizationDamage)
            maximumQuantizationDamage = damage;
    }

    require(
        maximumQuantizationDamage > 0.0L,
        "forced reverse GeocentricCoordinate<float> intermediate changes working ECEF");

    writefln(
        "PASS float reverse working precision / "
        ~ "maximum forced-ECEF component quantization = %.9f m",
        maximumQuantizationDamage);
}


void main()
{
    writeln(
        "=== TOPO-E adversarial/failure contract probe ===");

    testCoordinateContract!float();
    testCoordinateContract!double();
    testCoordinateContract!real();

    testFrameFailureContract!float();
    testFrameFailureContract!double();
    testFrameFailureContract!real();

    testGeodeticOriginDomain!float();
    testGeodeticOriginDomain!double();
    testGeodeticOriginDomain!real();

    testPoleOrientation();

    testRotationAxis!float();
    testRotationAxis!double();
    testRotationAxis!real();

    testDeepInterior();
    testSphere();
    testAntimeridian();

    testFiniteArithmeticFailure!float();
    testFiniteArithmeticFailure!double();
    testFiniteArithmeticFailure!real();

    testFloatReverseWorkingPrecision();

    writeln();
    writeln("=== TOPO-E PROBE COMPLETE ===");
    writefln("PASS: %s contract checks", checks);
}
