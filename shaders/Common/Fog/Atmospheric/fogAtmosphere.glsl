#ifndef GRAND_OVERLORD_FOG_ATMOSPHERE_GLSL
#define GRAND_OVERLORD_FOG_ATMOSPHERE_GLSL

#include "/Common/Fog/fogConfig.glsl"

float grandFogSunHeight(float angle) {
    return sin(6.28318530718 * angle);
}

float grandFogDayFactor(float sunHeight) {
    return smoothstep(
        GRAND_FOG_DAY_START,
        GRAND_FOG_DAY_FULL,
        sunHeight
    );
}

float grandFogNightFactor(float sunHeight) {
    return smoothstep(
        GRAND_FOG_NIGHT_START,
        GRAND_FOG_NIGHT_FULL,
        max(-sunHeight, 0.0)
    );
}

float grandFogTwilightFactor(float sunHeight) {
    return 1.0 - smoothstep(
        0.0,
        GRAND_FOG_TWILIGHT_WIDTH,
        abs(sunHeight)
    );
}

float grandFogDirectSunFactor(float sunHeight) {
    // Fade direct sunlight through the horizon; retain ambient fog at night.
    return smoothstep(-0.055, 0.085, sunHeight);
}

#endif
