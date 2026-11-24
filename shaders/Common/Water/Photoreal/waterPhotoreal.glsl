#ifndef GM_PHOTOREAL_WATER_GLSL
#define GM_PHOTOREAL_WATER_GLSL

// ============================================================
// PHOTOREAL WATER :: surface wave model
//
// - 8 directional swell waves with trochoidal (Gerstner-like) crest sharpening. All wave vectors are
//   integer multiples of 2*pi/512, so the field tiles exactly with the 512-block coordinate wrap.
// - Wind direction biases which swells are strong (changing it never pops).
// - Small waves fade with distance (no shimmer), capillary ripples only near the camera.
// Needs settings.glsl (PW_* and WAVE_* options).
// ============================================================

float pwHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float pwNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(pwHash(i), pwHash(i + vec2(1.0, 0.0)), f.x),
               mix(pwHash(i + vec2(0.0, 1.0)), pwHash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 pwWindDir() {
    float a = radians(PW_WIND_ANGLE);
    return vec2(cos(a), sin(a));
}

// surface slope (d height / d xz); h = wave height in roughly [-1, 1] * PW_WAVE_HEIGHT
vec2 pwSlope(vec2 p, float t, float dist, out float h) {
    // short, interconnected waves (4-15 blocks) travelling in many different directions
    const vec2 K[10] = vec2[10](vec2(29.0, 17.0), vec2(-34.0, 26.0), vec2(52.0, -21.0), vec2(-47.0, -44.0), vec2(71.0, 30.0),
                                vec2(-63.0, 58.0), vec2(24.0, -96.0), vec2(95.0, -47.0), vec2(-88.0, -71.0), vec2(41.0, 118.0));
    const float S[10] = float[10](0.09, 0.085, 0.08, 0.075, 0.07, 0.065, 0.06, 0.05, 0.045, 0.04);
    vec2 wind = pwWindDir();
    float warpK = 6.2831853 * 4.0 / 512.0;
    // two-level domain warp: waves bend and merge instead of forming straight rows
    p += 4.0 * vec2(sin(p.y * warpK + t * 0.21), cos(p.x * warpK - t * 0.17));
    p += 2.0 * vec2(sin(p.y * warpK * 1.75 - t * 0.13 + 1.3), cos(p.x * warpK * 1.75 + t * 0.11));
    float chop = 0.6 * PW_CHOPPINESS;
    vec2 g = vec2(0.0);
    h = 0.0;
    for (int i = 0; i < 10; i++) {
        vec2 k = K[i] * (6.2831853 / 512.0);
        float kl = length(k);
        vec2 dir = k / kl;
        float wgt = 0.35 + 0.65 * pow(clamp(0.5 + 0.5 * dot(dir, wind), 0.0, 1.0), 1.5);
        float w = sqrt(9.8 * kl) * 0.7;
        float ph = dot(k, p) - w * t + 1.7 * float(i);
        float u = ph + chop * sin(ph);                                  // sharper crests, flatter troughs
        float patchK = 0.55 + 0.45 * sin(dot(p, vec2(5.0, 3.0) * (6.2831853 / 512.0)) + float(i) * 2.1 + t * 0.15);   // irregular strength patches
        float s = S[i] * PW_WAVE_HEIGHT * wgt * patchK * exp(-dist * kl * 0.006);
        g += dir * s * cos(u) * (1.0 + chop * cos(ph));
        h += s * sin(u) * 2.0;
    }
    return g;
}

// tiny wind ripples, only close to the camera
vec2 pwCapillary(vec2 p, float t, float dist) {
    float fade = (1.0 - smoothstep(8.0, 80.0, dist)) * PW_CAPILLARY;
    if (fade <= 0.001) return vec2(0.0);
    vec2 wind = pwWindDir();
    vec2 q1 = p * 1.7 + wind * t * 0.9;
    vec2 q2 = p * 3.9 + vec2(-wind.y, wind.x) * t * 0.7;
    float e = 0.12;
    float h0 = pwNoise(q1) * 0.6 + pwNoise(q2) * 0.4;
    float hx = pwNoise(q1 + vec2(e, 0.0)) * 0.6 + pwNoise(q2 + vec2(e, 0.0)) * 0.4;
    float hz = pwNoise(q1 + vec2(0.0, e)) * 0.6 + pwNoise(q2 + vec2(0.0, e)) * 0.4;
    return vec2(hx - h0, hz - h0) / e * 0.035 * fade;
}

#endif
