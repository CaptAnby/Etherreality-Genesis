#ifndef GRAND_OVERLORD_FOG_WIND_GLSL
#define GRAND_OVERLORD_FOG_WIND_GLSL

#include "/Common/Fog/fogConfig.glsl"

// ============================================================
// ETHERREALITY GENESIS :: FOG WIND
// ============================================================
// Slowly advect world-space fog horizontally.
//
// time should already be scaled by the caller.
// Vertical coordinates are preserved exactly.
// ============================================================

vec3 grandFogAdvectPosition(
    vec3 worldPosition,
    float time
) {
    vec2 drift =
        GRAND_FOG_WIND_DIRECTION *
        (time * GRAND_FOG_WIND_SPEED);

    worldPosition.xz += drift;

    return worldPosition;
}

#endif