#version 330 compatibility
#include "/settings.glsl"

// ============================================================
// ETHERREALITY GENESIS :: REAL-LIFE SKY (soft, Rayleigh-style)
// Zenith AND horizon colors both change with sun elevation.
// ============================================================

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;
uniform int renderStage;
uniform mat4 gbufferModelViewInverse;

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// 7-key ramp over sun elevation (sin of angle). Keys follow real twilight stages:
// night(<-18deg) | astronomical(-12) | nautical/civil end(-6) | sunset(0) | low sun | morning | noon
vec3 ramp7(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f, vec3 g) {
    vec3 r = mix(a, b, smoothstep(-0.31, -0.21, s));
    r = mix(r, c, smoothstep(-0.21, -0.105, s));
    r = mix(r, d, smoothstep(-0.105, -0.02, s));
    r = mix(r, e, smoothstep(-0.02, 0.08, s));
    r = mix(r, f, smoothstep(0.08, 0.30, s));
    r = mix(r, g, smoothstep(0.30, 1.0, s));
    return r;
}

#ifdef NEBULA_SKY
float nHash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float nNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(nHash(i), nHash(i + vec3(1,0,0)), f.x),
                   mix(nHash(i + vec3(0,1,0)), nHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(nHash(i + vec3(0,0,1)), nHash(i + vec3(1,0,1)), f.x),
                   mix(nHash(i + vec3(0,1,1)), nHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float nFbm(vec3 p) {
    float a = 0.5, r = 0.0;
    for (int i = 0; i < 4; i++) { r += a * nNoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
    return r;
}
#endif

void main() {
	discard;
}
