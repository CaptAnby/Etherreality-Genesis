#ifndef GRAND_OVERLORD_FOG_LIGHTING_GLSL
#define GRAND_OVERLORD_FOG_LIGHTING_GLSL

#include "/Common/Fog/fogConfig.glsl"
#include "/Common/Fog/Atmospheric/fogAtmosphere.glsl"

// ============================================================
// ETHERREALITY GENESIS :: FOG LIGHTING
// ============================================================
// Broad forward-scattered sunlight.
// Soft ambient illumination.
// Existing V8 fog-lighting color configuration preserved.
// ============================================================

float grandFogHenyeyGreenstein(
    float cosTheta,
    float g
) {
    float g2 = g * g;

    float denominator = max(
        1.0 + g2 - 2.0 * g * cosTheta,
        0.001
    );

    // Equivalent to pow(denominator, 1.5).
    float denominatorPower = denominator * sqrt(denominator);

    return (1.0 - g2) / (
        12.5663706144 * denominatorPower
    );
}

vec3 grandFogLighting(
    vec3 rayDirection,
    vec3 lightDirection,
    float sunAngleValue
) {
    float sunHeight = grandFogSunHeight(sunAngleValue);

    float day = grandFogDayFactor(sunHeight);
    float night = grandFogNightFactor(sunHeight);
    float twilight = grandFogTwilightFactor(sunHeight);

    float directFactor = grandFogDirectSunFactor(sunHeight);

    // --------------------------------------------------------
    // AMBIENT COLOR
    // --------------------------------------------------------
    vec3 ambientColor = mix(
        GRAND_FOG_NIGHT_AMBIENT_COLOR,
        GRAND_FOG_DAY_AMBIENT_COLOR,
        day
    );

    ambientColor = mix(
        ambientColor,
        GRAND_FOG_TWILIGHT_AMBIENT_COLOR,
        twilight * (1.0 - day)
    );

    float ambientStrength = mix(
        GRAND_FOG_NIGHT_AMBIENT_STRENGTH,
        GRAND_FOG_AMBIENT_STRENGTH,
        day
    );

    ambientStrength = mix(
        ambientStrength,
        GRAND_FOG_AMBIENT_STRENGTH * 0.92,
        twilight * (1.0 - day)
    );

    vec3 sunColor = mix(
        GRAND_FOG_TWILIGHT_SUN_COLOR,
        GRAND_FOG_DAY_SUN_COLOR,
        day
    );

    // --------------------------------------------------------
    // ANGULAR SCATTERING
    // --------------------------------------------------------
    // Normalize once inside this function rather than normalizing
    // lightDirection separately in the raymarcher as well.

    float viewSun = clamp(
        dot(
            normalize(rayDirection),
            normalize(lightDirection)
        ),
        -1.0,
        1.0
    );

    float phaseRaw = grandFogHenyeyGreenstein(
        viewSun,
        GRAND_FOG_PHASE_G
    );

    float phase = clamp(
        phaseRaw * GRAND_FOG_PHASE_SCALE,
        GRAND_FOG_PHASE_MIN,
        GRAND_FOG_PHASE_MAX
    );

    // --------------------------------------------------------
    // FINAL ILLUMINATION
    // --------------------------------------------------------
    vec3 ambient = ambientColor * ambientStrength;

    vec3 direct =
        sunColor *
        directFactor *
        phase *
        GRAND_FOG_DIRECT_STRENGTH;

    float warmMix = clamp(
        day * 0.07 + twilight * 0.24,
        0.0,
        0.34
    );

    ambient *= mix(
        vec3(1.0),
        vec3(1.025, 1.012, 0.978),
        warmMix
    );

    vec3 result = ambient + direct;

    result *= mix(1.0, 0.92, night);

    return clamp(
        result,
        vec3(0.0),
        vec3(GRAND_FOG_MAX_LIGHT)
    );
}

#endif