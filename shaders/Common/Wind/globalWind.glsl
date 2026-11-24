#ifndef PHENYX_GLOBAL_WIND_GLSL
#define PHENYX_GLOBAL_WIND_GLSL
// ============================================================
// GlWS - Global Wind System  (+ SmGS - Smooth Gusts System)
// One shared wind state for clouds, vegetation, rain and wind streaks.
// Pure functions: callers pass time / weather, so any shader stage can include this.
// ============================================================

// shared wind direction (single source: CLOUD_WIND_ANGLE)
vec2 glwsDir() {
    float a = radians(CLOUD_WIND_ANGLE);
    return vec2(cos(a), sin(a));
}

// baseline strength: a bit stronger than before even in clear weather, rain stronger, thunder strongest
float glwsStrength(float rain, float thunder) {
    return mix(mix(1.20, 1.55, clamp(rain, 0.0, 1.0)), 2.40, clamp(thunder, 0.0, 1.0));
}

// SmGS: smooth irregular gust envelope 0..1 (sums of slow sines - no jumps); shared by every wind effect
float glwsGust(float t, float rain, float thunder) {
    float g = 0.50 + 0.26 * sin(t * 0.19) + 0.14 * sin(t * 0.071 + 1.3) * sin(t * 0.43 + 0.6)
            + 0.10 * sin(t * 0.61 + 2.1);
    g = clamp(g, 0.0, 1.0);
    g = mix(g, 0.80, clamp(rain, 0.0, 1.0) * 0.6);          // steadier in rain
    g = mix(g, clamp(g * 1.2, 0.0, 1.0), clamp(thunder, 0.0, 1.0));   // gustier in storms
    return g;
}
#endif
