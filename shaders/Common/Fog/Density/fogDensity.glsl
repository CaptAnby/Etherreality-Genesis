#ifndef GRAND_OVERLORD_FOG_DENSITY_GLSL
#define GRAND_OVERLORD_FOG_DENSITY_GLSL

#include "/Common/Fog/fogConfig.glsl"
#include "/Common/Fog/Utilities/fogNoise.glsl"
#include "/Common/Fog/Wind/fogWind.glsl"
#include "/Common/Fog/Weather/fogWeather.glsl"

// ============================================================
// ETHERREALITY GENESIS :: FOG DENSITY :: PERFORMANCE UPDATE
// ============================================================
// Preserves broad, low-altitude world-space fog banks.
//
// Optimizations:
// 1. Reject vertically empty samples before calculating advection.
// 2. Reuse a weather multiplier supplied by the raymarcher.
// 3. Retain conditional detail noise sampling inside fog banks.
// ============================================================

float grandFogDensityAtWithWeather(
    vec3 worldPosition,
    float time,
    float weatherMultiplier
) {
    // --------------------------------------------------------
    // HEIGHT ENVELOPE
    // --------------------------------------------------------
    // Fog density is zero below the lower fade and becomes
    // negligible above the exponential upper fade.
    float lowerFade = smoothstep(
        GRAND_FOG_BASE_HEIGHT - GRAND_FOG_GROUND_SOFTNESS,
        GRAND_FOG_BASE_HEIGHT + 5.0,
        worldPosition.y
    );

    float heightAboveBase = max(
        worldPosition.y - GRAND_FOG_BASE_HEIGHT,
        0.0
    );

    float upperFade = exp(
        -heightAboveBase * GRAND_FOG_HEIGHT_FALLOFF
    );

    float heightEnvelope = lowerFade * upperFade;

    if (heightEnvelope <= 0.0001) {
        return 0.0;
    }

    // --------------------------------------------------------
    // WISPY WORLD-SPACE FOG BANKS
    // --------------------------------------------------------
    float wisp = VOL_FOG_WISPINESS;
    float area = grandFogAreaDensity();

    vec3 advected = grandFogAdvectPosition(
        worldPosition,
        time
    );

    // Cheap sine domain warp bends the banks into soft curling wisps.
    vec3 wp = advected * (GRAND_FOG_DETAIL_NOISE_SCALE * 0.5);
    vec3 warp = vec3(
        sin(wp.z * 1.7 + wp.y),
        sin(wp.x * 1.3 - wp.z) * 0.4,
        cos(wp.y * 1.1 + wp.x)
    ) * (26.0 * wisp);

    vec3 bankPosition = (advected + warp) * GRAND_FOG_BANK_NOISE_SCALE;
    bankPosition.y *= GRAND_FOG_BANK_VERTICAL_SCALE;

    float bankNoise = grandFogValueNoise3D(bankPosition);

    // Dense areas (forest / sea) fill in more of the gaps.
    float bankOccupancy = smoothstep(
        GRAND_FOG_BANK_THRESHOLD_LOW - 0.12 * area,
        GRAND_FOG_BANK_THRESHOLD_HIGH + 0.10 - 0.08 * area,
        bankNoise
    );

    float bankDensity = mix(
        GRAND_FOG_BANK_GAP_DENSITY * (1.0 + 2.0 * area),
        GRAND_FOG_BANK_PEAK_DENSITY,
        bankOccupancy
    );

    // --------------------------------------------------------
    // INTERIOR DETAIL / STREAKS (skipped in empty gaps)
    // --------------------------------------------------------
    float detailVariation = 1.0;

    if (bankOccupancy > 0.035) {
        vec3 detailPosition =
            (advected + warp * 0.6) * GRAND_FOG_DETAIL_NOISE_SCALE;

        detailPosition.y *= GRAND_FOG_DETAIL_VERTICAL_SCALE;

        float detailNoise =
            grandFogValueNoise3D(detailPosition);

        detailVariation = mix(
            GRAND_FOG_DETAIL_MIN,
            GRAND_FOG_DETAIL_MAX,
            detailNoise
        );

        // Wispiness: thin feathery streaks inside the bank.
        detailVariation *= mix(
            1.0,
            0.35 + 1.3 * detailNoise,
            clamp(0.5 * wisp, 0.0, 0.95)
        );
    }

    // --------------------------------------------------------
    // FINAL DENSITY
    // --------------------------------------------------------
    return max(
        GRAND_FOG_BASE_DENSITY *
        heightEnvelope *
        bankDensity *
        detailVariation *
        weatherMultiplier,
        0.0
    );
}

// ============================================================
// COMPATIBILITY WRAPPER
// ============================================================
// Preserve the existing function for any other shader include
// that calls grandFogDensityAt(worldPosition, time).

float grandFogDensityAt(
    vec3 worldPosition,
    float time
) {
    float weatherMultiplier = grandFogWeatherMultiplier();

    return grandFogDensityAtWithWeather(
        worldPosition,
        time,
        weatherMultiplier
    );
}

#endif