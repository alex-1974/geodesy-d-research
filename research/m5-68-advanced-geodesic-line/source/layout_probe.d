module layout_probe;

import core.stdc.stdio : printf;
import geodesy : GeodesicLine;

/*
 * This is a storage model only. It deliberately does not pretend to be the
 * final production implementation.
 *
 * The additions correspond to line-specific state expected for repeated
 * m12/M12/M21/S12 evaluation without retaining the complete ellipsoid C4x
 * table in every prepared line.
 */
struct AdvancedAdditions(W)
{
    W eps;
    W ep2;
    W a;
    W e2;
    W authalicRadiusSquared;

    W dn1;
    W cosBeta1;
    W sinAlpha1;
    W cosAlpha1;

    W a2m1;
    W b21;
    W b41;

    W[9] c2;
    W[9] c4;
}

/* Alternative A: every ordinary line carries advanced state. */
struct UnifiedLineModel(T, W)
{
    GeodesicLine!T base;
    AdvancedAdditions!W advanced;
}

/* Alternative B/C public footprint: advanced callers explicitly opt in. */
struct AdvancedLineModel(T, W)
{
    GeodesicLine!T base;
    AdvancedAdditions!W advanced;
}

private void report(T, W)(const char* publicName, const char* workingName)
{
    alias Base = GeodesicLine!T;
    alias Advanced = AdvancedLineModel!(T, W);
    alias Unified = UnifiedLineModel!(T, W);

    printf(
        "%s/%s base=%zu advanced_additions=%zu advanced=%zu unified=%zu "
        ~ "growth=%zu growth_pct=%.2f\n",
        publicName,
        workingName,
        Base.sizeof,
        AdvancedAdditions!W.sizeof,
        Advanced.sizeof,
        Unified.sizeof,
        Unified.sizeof - Base.sizeof,
        Base.sizeof
            ? 100.0 * cast(double)(Unified.sizeof - Base.sizeof)
                / cast(double)Base.sizeof
            : 0.0);
}

void main()
{
    /*
     * Production WorkingScalar policy:
     * float -> double, double -> double, real -> real.
     */
    report!(float, double)("float", "double");
    report!(double, double)("double", "double");
    report!(real, real)("real", "real");
}
