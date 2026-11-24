#ifndef GRAND_OVERLORD_FOG_WEATHER_GLSL
#define GRAND_OVERLORD_FOG_WEATHER_GLSL

#include "/Common/Fog/fogConfig.glsl"

// Custom uniforms defined in shaders.properties (smoothed biome blend 0..1).
uniform float gmFogForest;
uniform float gmFogSea;

// rainStrength / thunderStrength are declared by cloudSystem.glsl, which
// deferred.fsh includes before the fog modules.

// 0..1 how "dense / enclosed" the area is (forest, jungle, swamp, sea).
float grandFogAreaDensity() {
#ifdef VOL_FOG_BIOME_DENSITY
    return clamp(max(gmFogForest, gmFogSea), 0.0, 1.0);
#else
    return 0.0;
#endif
}

// Density multiplier from area: dense forest = denser, sea = broad low banks.
float grandFogAreaMultiplier() {
#ifdef VOL_FOG_BIOME_DENSITY
    float k = (0.85 * gmFogForest + 0.70 * gmFogSea) * VOL_FOG_BIOME_STRENGTH;
    return 1.0 + k;
#else
    return 1.0;
#endif
}

// Morning mist is thickest, midday burns off, dusk is moderate, night is calm.
float grandFogTimeMultiplier(float sunAngleValue) {
#ifdef VOL_FOG_TIME_OF_DAY
    float sunH = sin(6.28318530718 * sunAngleValue);
    float morning = (1.0 - smoothstep(0.0, 0.14, sunAngleValue)) +
                    smoothstep(0.88, 0.99, sunAngleValue);
    float dusk = 1.0 - smoothstep(0.0, 0.09, abs(sunAngleValue - 0.5));
    float noon = smoothstep(0.35, 0.95, sunH);
    float night = smoothstep(0.05, 0.30, max(-sunH, 0.0));
    float m = 1.0 + 0.90 * clamp(morning, 0.0, 1.0) + 0.35 * dusk - 0.45 * noon + 0.15 * night;
    return max(m, 0.35);
#else
    return 1.0;
#endif
}

float grandFogWeatherMultiplier() {
#ifdef VOL_FOG_WEATHER
    // Moderate density bump here; deferred.fsh adds the grey/dark rain lighting.
    return GRAND_FOG_WEATHER_MULTIPLIER *
           (1.0 + 0.5 * clamp(rainStrength, 0.0, 1.0) + 0.4 * clamp(thunderStrength, 0.0, 1.0));
#else
    return GRAND_FOG_WEATHER_MULTIPLIER;
#endif
}

#endif
