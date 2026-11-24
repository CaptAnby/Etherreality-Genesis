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

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// 6-key ramp over sun elevation: -0.30, -0.12, -0.02, 0.08, 0.30, 1.0
vec3 ramp6(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f) {
    vec3 r = mix(a, b, smoothstep(-0.30, -0.12, s));
    r = mix(r, c, smoothstep(-0.12, -0.02, s));
    r = mix(r, d, smoothstep(-0.02, 0.08, s));
    r = mix(r, e, smoothstep(0.08, 0.30, s));
    r = mix(r, f, smoothstep(0.30, 1.0, s));
    return r;
}

void main() {
    float rainW  = clamp(rainStrength, 0.0, 1.0);
    float stormW = clamp(thunderStrength, 0.0, 1.0);

    vec3 sunDir  = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);
    vec3 up      = normalize(upPosition);

    float sh    = dot(sunDir, up);
    float day   = smoothstep(-0.12, 0.30, sh);
    float tw    = exp(-pow((sh + 0.02) * 4.0, 2.0));
    float night = 1.0 - smoothstep(-0.20, 0.02, sh);

    // ---------------- STARS ----------------
    if (renderStage == MC_RENDER_STAGE_STARS) {
        float vis = night * (1.0 - rainW) * (1.0 - 0.5 * tw);
        float tw2 = 0.88 + 0.12 * sin(frameTimeCounter * 1.7 + gl_FragCoord.x * 0.37 + gl_FragCoord.y * 0.53);
        color = vec4(vec3(0.82, 0.90, 1.0) * 1.6 * tw2, clamp(vis, 0.0, 1.0));
        return;
    }

    // ---------------- VIEW RAY ----------------
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec3 dir = normalize(p.xyz / p.w);

    float h  = dot(dir, up);
    float hp = max(h, 0.0);
    float t  = pow(clamp(hp, 0.0, 1.0), 0.55);   // soft gradient

    // ---------------- TIME-DEPENDENT PALETTE ----------------
    //                         night                   deep twi                civil twi               low sun                 morning/late            noon
    vec3 zen = ramp6(sh, vec3(0.006,0.011,0.036), vec3(0.030,0.060,0.170), vec3(0.110,0.190,0.430),
                         vec3(0.200,0.360,0.680), vec3(0.200,0.410,0.760), vec3(0.150,0.350,0.720));
    vec3 hor = ramp6(sh, vec3(0.030,0.050,0.105), vec3(0.130,0.150,0.290), vec3(0.560,0.560,0.720),
                         vec3(0.800,0.780,0.820), vec3(0.740,0.850,0.960), vec3(0.790,0.890,0.980));

    vec3 sky = mix(hor, zen, t);
    // Rayleigh-style whitening toward the horizon
    sky = mix(sky, hor * 1.05, exp(-hp * 7.0) * 0.35);

    // ---------------- SUN-SIDE / OPPOSITE ----------------
    vec3 dirH = dir - up * h;
    vec3 sunH = sunDir - up * sh;
    dirH = dirH / max(length(dirH), 0.0001);
    sunH = sunH / max(length(sunH), 0.0001);
    float facing = dot(dirH, sunH);

    float band = exp(-hp * 4.0);
    float high = exp(-hp * 1.8);

    // soft golden hour tint on the sun side (afternoon / morning)
    float golden = 1.0 - smoothstep(0.05, 0.45, sh);
    golden *= smoothstep(-0.10, 0.05, sh);
    float side = pow(max(facing, 0.0), 1.5);
    vec3 glowCol = mix(vec3(1.0, 0.36, 0.14), vec3(1.0, 0.72, 0.40), exp(-hp * 9.0));
    sky += glowCol * side * (band * 2.0 + high * 0.55) * max(tw, golden * 0.4);
    sky += vec3(0.95, 0.30, 0.50) * side * high * tw * 0.22;   // pink/magenta upper glow

    // layered sunrise/sunset: red at the horizon -> orange -> rose -> violet,
    // strongest toward the sun, wrapping softly around the whole horizon
    {
        vec3 ss = mix(vec3(1.0, 0.22, 0.04), vec3(1.0, 0.52, 0.18), smoothstep(0.0, 0.07, hp));
        ss = mix(ss, vec3(0.95, 0.36, 0.44), smoothstep(0.05, 0.22, hp));
        ss = mix(ss, vec3(0.42, 0.30, 0.66), smoothstep(0.18, 0.55, hp));
        float sw = (0.22 + 0.78 * side) * exp(-hp * 2.6) * tw;
        sky = mix(sky, ss * 1.05, clamp(sw * 0.6 * SUNSET_STRENGTH, 0.0, 0.9));
        // earth shadow: dusky blue-violet band opposite the sun
        float oppS = pow(max(-facing, 0.0), 1.2);
        sky = mix(sky, vec3(0.20, 0.24, 0.45), oppS * exp(-hp * 6.0) * tw * 0.35);
    }

    // opposite side: cold, soft blue (belt of Venus)
    float opp = pow(max(-facing, 0.0), 1.4);
    sky = mix(sky, vec3(0.50, 0.60, 0.88), opp * band * tw * 0.6);

    // soft Mie forward-scatter around the sun, tiny halo at the moon
    float sd = max(dot(dir, sunDir), 0.0);
    vec3 haloCol = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.58, 0.28), max(tw, golden));
    sky += haloCol * (pow(sd, 5.0) * 0.10 + pow(sd, 70.0) * 0.40)
         * smoothstep(-0.10, 0.05, sh) * (1.0 - 0.9 * rainW);

    float md = max(dot(dir, moonDir), 0.0);
    sky += vec3(0.30, 0.45, 0.90) * (pow(md, 40.0) * 0.20 + pow(md, 6.0) * 0.03) * night * (1.0 - rainW);

    sky *= mix(1.0, 0.85, smoothstep(0.0, -0.30, h));

    // ---------------- WEATHER ----------------
    float dk = mix(0.10, 1.0, day);
    vec3 rainSky = mix(vec3(0.68, 0.71, 0.75), vec3(0.53, 0.56, 0.61), t) * dk
                 + vec3(0.008, 0.012, 0.026) * (1.0 - day);
    vec3 stormSky = mix(vec3(0.25, 0.26, 0.30), vec3(0.085, 0.09, 0.115), t)
                  * mix(0.22, 1.0, day);
    rainSky += glowCol * side * band * tw * 0.08;

    sky = mix(sky, rainSky, rainW);
    sky = mix(sky, stormSky, stormW);

    float n = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    sky += (n - 0.5) / 255.0;

    color = vec4(max(sky, vec3(0.0)), 1.0);
}
