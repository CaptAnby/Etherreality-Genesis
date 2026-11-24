#ifndef GRAND_OVERLORD_FOG_DISTANCE_GLSL
#define GRAND_OVERLORD_FOG_DISTANCE_GLSL

#include "/Common/Fog/fogConfig.glsl"

// ============================================================
// ETHERREALITY GENESIS :: FOG DISTANCE
// ============================================================
// Opaque rays use reconstructed scene depth.
// Sky rays use their separate fog distance.
// Both are limited to the configured maximum.
// ============================================================

float grandFogResolveDistance(
    float sceneDistance,
    bool skyPixel
) {
    if (skyPixel) {
        return clamp(
            GRAND_FOG_SKY_DISTANCE,
            0.0,
            GRAND_FOG_MAX_DISTANCE
        );
    }

    return clamp(
        sceneDistance,
        0.0,
        GRAND_FOG_MAX_DISTANCE
    );
}

#endif