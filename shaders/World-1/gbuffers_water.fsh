#version 330 compatibility
#include "/settings.glsl"

// ============================================================
// ETHERREALITY GENESIS™ :: WATER FRAGMENT
//
// Full world-reactive water lighting.
//
// Base water:
//     RGB(10, 37, 59)
//
// The entire surface receives:
//     daylight
//     sunset warmth
//     sunrise warmth
//     moonlight
//     sky illumination
//
// Waves provide additional surface variation.
//
// GBUFFER OUTPUT:
//
//     colortex0 = water color
//     colortex1 = encoded wave normal
//     colortex7 = dedicated water mask
// ============================================================


// ============================================================
// INPUTS
// ============================================================

uniform sampler2D lightmap;

uniform float alphaTestRef = 0.1;

uniform vec3 cameraPosition;

in vec2 lmcoord;
in vec2 texcoord;

in vec4 glcolor;

in vec3 waveNormal;
in float isWaterFlag;
in float isGlassFlag;

uniform sampler2D gtexture;
uniform sampler2D noisetex;
uniform float frameTimeCounter;
uniform sampler2D depthtex1;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
in vec3 waterWorldPosition;


/* RENDERTARGETS: 0,1,7 */

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 waterMaskData;


// ============================================================
// DYNAMIC WATER LIGHTING
// ============================================================

#include "/Common/Water/Lighting/waterLighting.glsl"


float wHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float wNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(wHash(i), wHash(i + vec2(1.0, 0.0)), f.x),
               mix(wHash(i + vec2(0.0, 1.0)), wHash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main()
{
    // GLASS: proper glass look (opaque frame, tinted body, reflection sheen)
    if (isGlassFlag > 0.5)
    {
        vec4 tex = texture2D(gtexture, texcoord);
        vec3 tint = tex.rgb * glcolor.rgb;
        vec3 lm = texture2D(lightmap, lmcoord).rgb;

        vec3 gN = normalize(waveNormal);
        vec2 guv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        vec4 gp = gbufferProjectionInverse * vec4(guv * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
        vec3 gV = normalize(-(gp.xyz / gp.w));
        float gndv = clamp(abs(dot(gN, gV)), 0.0, 1.0);
        float gfres = (0.05 + 0.95 * pow(1.0 - gndv, 4.0)) * GLASS_REFLECTION;

        vec3 gSunW = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
        float gDay = smoothstep(-0.1, 0.25, gSunW.y);
        vec3 gRefl = mix(skyColor, vec3(0.78, 0.83, 0.88) * mix(0.05, 1.0, gDay), 0.6);

        // diagonal window glints, continuous across neighbouring panes
        float gd = fract((waterWorldPosition.x + waterWorldPosition.y + waterWorldPosition.z) * 0.45
                         - frameTimeCounter * 0.10 + gV.x * 0.7 + gV.y * 0.5);
        float streak = smoothstep(0.0, 0.04, gd) * (1.0 - smoothstep(0.04, 0.10, gd))
                     + 0.5 * smoothstep(0.20, 0.23, gd) * (1.0 - smoothstep(0.23, 0.27, gd));
        streak *= gDay * (1.0 - rainStrength * 0.7) * GLASS_GLINT_STRENGTH;

        float lum = dot(tint, vec3(0.333));
        float sat = max(max(tint.r, tint.g), tint.b) - min(min(tint.r, tint.g), tint.b);
        float isTinted = smoothstep(0.06, 0.18, sat);

        vec3 body = mix(vec3(lum), tint, 1.0 + 0.25 * isTinted) * mix(vec3(0.03), vec3(1.0), lm) * 1.1;
        float a = tex.a;
        // texture detail (frame, cracks, highlights) stays solid and visible
        a = mix(a, 1.0, smoothstep(0.45, 0.8, a));
        a = (tex.a > 0.04) ? max(a, 0.30) : a;
        // stained / tinted glass blocks more of what is behind it
        a = max(a, isTinted * step(0.3, tex.a) * 0.74);
        float shine = gfres * 0.40 + streak * 0.22;
        float outA = clamp(a + (1.0 - a) * shine, 0.0, 1.0);
        if (outA < 0.02) discard;

        vec3 rgb = mix(body, gRefl * lm.g, clamp(gfres * 0.25, 0.0, 1.0));
        rgb += vec3(1.0, 0.97, 0.90) * streak * 0.35;
        // clear parts: colour mostly the reflection, not the (white) texture
        rgb = mix(gRefl * lm.g + vec3(1.0) * streak * 0.3, rgb, step(0.02, a));
        color = vec4(rgb, outA);
        normalData = vec4(gN * 0.5 + 0.5, 1.0);
        waterMaskData = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // ICE / NON-WATER TRANSLUCENTS: use the real block texture
    if (isWaterFlag < 0.5)
    {
        vec4 tex = texture2D(gtexture, texcoord) * glcolor;
        vec3 lm = texture2D(lightmap, lmcoord).rgb;
        vec3 iceCol = tex.rgb * lm * 1.15;
        iceCol = mix(vec3(dot(iceCol, vec3(0.333))), iceCol, 1.15);
        color = vec4(iceCol, max(tex.a, 0.78));
        normalData = vec4(normalize(waveNormal) * 0.5 + 0.5, 1.0);
        waterMaskData = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec3 normal = normalize(waveNormal);

    // fine random ripples (procedural, rotated, no grid)
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    float t = frameTimeCounter;
    vec2 rp = waterWorldPosition.xz;
    vec2 a1 = rot * rp * 1.6 + vec2(t * 0.35, t * 0.21);
    vec2 a2 = rot * rot * rp * 3.8 - vec2(t * 0.55, -t * 0.4);
    vec2 a3 = rot * rp * 8.0 + vec2(-t * 0.8, t * 0.6);
    float e = 0.15;
    float h0 = wNoise(a1) * 0.6 + wNoise(a2) * 0.3 + wNoise(a3) * 0.1;
    float hx = wNoise(a1 + vec2(e, 0.0)) * 0.6 + wNoise(a2 + vec2(e, 0.0)) * 0.3 + wNoise(a3 + vec2(e, 0.0)) * 0.1;
    float hz = wNoise(a1 + vec2(0.0, e)) * 0.6 + wNoise(a2 + vec2(0.0, e)) * 0.3 + wNoise(a3 + vec2(0.0, e)) * 0.1;
    float ripple = h0 - 0.5;
    normal = normalize(normal + vec3(-(hx - h0), 0.0, -(hz - h0)) * 0.6);

    vec3 viewDirW = normalize(cameraPosition - waterWorldPosition);
    float ndv = clamp(dot(normal, viewDirW), 0.0, 1.0);
    float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

    // ---- LAYER 1: water column depth (water surface -> bottom) ----
    vec2 suv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float d1 = texture2D(depthtex1, suv).r;
    vec4 pBottom = gbufferProjectionInverse * vec4(suv * 2.0 - 1.0, d1 * 2.0 - 1.0, 1.0);
    vec4 pSurf   = gbufferProjectionInverse * vec4(suv * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
    float waterDepth = (d1 >= 0.9999) ? 40.0 : max((-pBottom.z / pBottom.w) - (-pSurf.z / pSurf.w), 0.0);
    waterDepth = min(waterDepth / max(ndv, 0.25), 60.0);

    // ---- LAYER 2: selective absorption (red dies first) ----
    // shallow = clear/turquoise-green, mid = blue, deep = navy
    float deepT = 1.0 - exp(-waterDepth * 0.045);
    vec3 shallowCol = vec3(0.14, 0.27, 0.31);
    vec3 midCol     = vec3(0.10, 0.22, 0.29);
    vec3 deepCol    = vec3(0.07, 0.15, 0.22);
    vec3 waterColor = mix(shallowCol, midCol, smoothstep(0.0, 0.45, deepT));
    waterColor = mix(waterColor, deepCol, smoothstep(0.35, 1.0, deepT));
    waterColor += vec3(0.01, 0.025, 0.03) * ripple * 1.5;

    // celestial cycle
    vec3 sunDirW = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmt = smoothstep(-0.1, 0.25, sunDirW.y);
    float nightAmt = 1.0 - dayAmt;

    vec3 dynamicLighting = getDynamicWaterLighting(normal, waterWorldPosition);
    float localLight = clamp(dot(texture2D(lightmap, lmcoord).rgb, vec3(0.3333)), 0.0, 1.0);
    vec3 lighting = vec3(0.50, 0.52, 0.55) * mix(0.10, 1.0, dayAmt) + dynamicLighting * 0.75;
    lighting *= mix(0.9, 1.15, localLight);
    waterColor *= lighting;

    // night glow: moonlit / starlit water
    waterColor += vec3(0.002, 0.004, 0.007) * nightAmt;

    // sky reflection
    vec3 refl = mix(skyColor, vec3(0.78, 0.83, 0.88) * mix(0.05, 1.0, dayAmt), 0.6) + vec3(0.004, 0.008, 0.016) * nightAmt;
    waterColor = mix(waterColor, refl, fres * 0.45);
    float foam = smoothstep(0.62, 0.85, ripple + 0.5);
    waterColor = mix(waterColor, vec3(0.92, 0.97, 1.0), foam * 0.08 * dayAmt);

    // sun / moon glint
    vec3 lightDirW = normalize(mat3(gbufferModelViewInverse) * normalize(sunAngle < 0.5 ? sunPosition : moonPosition));
    vec3 halfV = normalize(lightDirW + viewDirW);
    float spec = pow(clamp(dot(normal, halfV), 0.0, 1.0), 400.0);
    spec *= clamp(lightDirW.y * 4.0, 0.0, 1.0) * (1.0 - rainStrength * 0.8);
    vec3 glintCol = mix(vec3(0.25, 0.32, 0.45), vec3(1.0, 0.93, 0.8), dayAmt);
    waterColor += glintCol * spec * mix(1.4, 1.0, dayAmt);

    // ---- LAYER 3: transparency from depth, plus Fresnel surface reflection ----
    float bodyAlpha = clamp(0.30 + 0.45 * (1.0 - exp(-waterDepth * 0.12)), 0.30, 0.75);
    float alpha = clamp(max(bodyAlpha, fres * 0.6) + spec * 0.3, 0.0, 1.0);
    color = vec4(waterColor, alpha);
    normalData = vec4(normal * 0.5 + 0.5, 1.0);
    waterMaskData = vec4(1.0, 0.0, 0.0, 1.0);
}
