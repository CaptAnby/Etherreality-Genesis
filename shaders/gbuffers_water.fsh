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

// Realistic ocean swell: sum of directional waves whose wave vectors are integer multiples of 2*pi/512,
// so the pattern tiles exactly with the 512-block coordinate wrap (no popping). Returns the surface slope.
vec2 oceanSlope(vec2 p, float t, float dist) {
    const vec2 K[7] = vec2[7](vec2(14.0, 5.0), vec2(-9.0, 19.0), vec2(31.0, -12.0), vec2(-22.0, -38.0),
                              vec2(47.0, 27.0), vec2(-61.0, 18.0), vec2(12.0, -83.0));
    const float S[7] = float[7](0.17, 0.15, 0.13, 0.11, 0.09, 0.07, 0.055);
    vec2 g = vec2(0.0);
    for (int i = 0; i < 7; i++) {
        vec2 k = K[i] * (6.2831853 / 512.0);
        float kl = length(k);
        float w = sqrt(9.8 * kl) * 0.7;
        float ph = dot(k, p) - w * t + 1.7 * float(i);
        ph += 0.55 * sin(ph);                                   // sharper crests, flatter troughs
        g += (k / kl) * S[i] * cos(ph) * exp(-dist * kl * 0.012);   // small waves fade with distance (no shimmer)
    }
    return g;
}

#include "/Common/Water/Photoreal/waterPhotoreal.glsl"

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

#ifndef REALISTIC_WATER
    {
        vec4 vt = texture2D(gtexture, texcoord) * glcolor;
        vec3 vlm = texture2D(lightmap, lmcoord).rgb;
        color = vec4(vt.rgb * vlm, vt.a);
        normalData = vec4(normalize(waveNormal) * 0.5 + 0.5, 1.0);
        waterMaskData = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
#endif
    // ================================================================
    // PHOTOREAL WATER SURFACE
    // ================================================================
    vec3 camToSurf = waterWorldPosition - cameraPosition;
    float wDist = length(camToSurf);
    vec2 wp = waterWorldPosition.xz - floor(cameraPosition.xz / 512.0) * 512.0;
    float wTime = frameTimeCounter * WAVE_SPEED;

    float wH;
    vec2 slope = pwSlope(wp / max(WAVE_SCALE, 0.05), wTime, wDist, wH) * WAVE_INTENSITY * 1.3;
    slope += pwCapillary(wp, wTime, wDist) * WAVE_DETAIL;
    vec3 vn = normalize(waveNormal);
    slope += (-vn.xz / max(vn.y, 0.2)) * 0.25;                     // keeps shading consistent with the mesh waves
    float slopeLen = length(slope);
    slope *= min(1.0, 1.4 / max(slopeLen, 0.001));
    vec3 normal = normalize(vec3(-slope.x, 1.0, -slope.y));
    float ripple = wH * 0.5;

    vec3 viewDirW = normalize(cameraPosition - waterWorldPosition);
    if (dot(normal, viewDirW) < 0.0) normal = -normal;
    float ndv = clamp(dot(normal, viewDirW), 0.0, 1.0);
    float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

    // ---- water column depth (surface -> bottom) ----
    vec2 suv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float d1 = texture2D(depthtex1, suv).r;
    vec4 pBottom = gbufferProjectionInverse * vec4(suv * 2.0 - 1.0, d1 * 2.0 - 1.0, 1.0);
    vec4 pSurf   = gbufferProjectionInverse * vec4(suv * 2.0 - 1.0, gl_FragCoord.z * 2.0 - 1.0, 1.0);
    float waterDepth = (d1 >= 0.9999) ? 40.0 : max((-pBottom.z / pBottom.w) - (-pSurf.z / pSurf.w), 0.0);
    waterDepth = min(waterDepth / max(ndv, 0.25), 60.0);

    // ---- Beer-Lambert absorption + in-scattering ----
    vec3 sigma = WATER_SIGMA * (WATER_ABSORPTION / WATER_CLARITY) * PW_DEPTH_FADE;
    vec3 Tr = exp(-sigma * waterDepth);
    float Tbar = pow(clamp(dot(Tr, vec3(0.30, 0.50, 0.20)), 0.0, 1.0), 1.0 / WATER_TRANSPARENCY);
    float deepK = pow(smoothstep(0.8, 14.0 / PW_DEPTH_FADE, waterDepth), 0.8);   // objects fade into the depth
    float tintFloor = clamp(0.55 * PW_WATER_TINT, 0.0, 0.9);   // the navy tint stays even when you stand in / look straight into shallow water
    float bodyA = clamp(max(deepK * 0.985, max(1.0 - Tbar, max(max(WATER_SHALLOW_OPACITY, tintFloor), 0.06) + 0.10 * WATER_TURBIDITY)), 0.0, 0.985);

    // celestial cycle
    vec3 sunDirW = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmt = smoothstep(-0.1, 0.25, sunDirW.y);
    float nightAmt = 1.0 - dayAmt;
    vec3 dynamicLighting = getDynamicWaterLighting(normal, waterWorldPosition);
    float localLight = clamp(dot(texture2D(lightmap, lmcoord).rgb, vec3(0.3333)), 0.0, 1.0);
    vec3 lighting = vec3(0.50, 0.52, 0.55) * mix(0.10, 1.0, dayAmt) + dynamicLighting * 0.75;
    float skyShade = clamp(texture2D(lightmap, lmcoord).g, 0.0, 1.0);
    float skyVis = smoothstep(0.12, 0.90, skyShade);
    float caveDark = mix(0.08 + 0.5 * clamp(texture2D(lightmap, lmcoord).r, 0.0, 1.0), 1.0, skyVis);   // only block light reaches cave water
    lighting *= mix(0.9, 1.15, localLight) * 1.25;
    lighting *= mix(1.0 - WATER_SHADOW_DARKEN * 0.75, 1.0, smoothstep(0.2, 0.95, skyShade));
    lighting = (vec3(1.0) - exp(-lighting * 0.9)) * 0.8;

    vec3 scatterCol = WATER_SCATTER * vec3(WATER_TINT_R, WATER_TINT_G, WATER_TINT_B) * WATER_BRIGHTNESS;
    scatterCol = mix(scatterCol, scatterCol * (0.6 + skyColor), 0.25);
    scatterCol = mix(scatterCol, vec3(dot(scatterCol, vec3(0.333))), WATER_PALENESS * 0.6) * (1.0 + 0.5 * WATER_PALENESS);
    vec3 bodyRGB = scatterCol * lighting * clamp((vec3(1.0) - Tr) / max(1.0 - Tbar, 0.05), 0.0, 1.6);
    // overall colour: dark navy, slightly light blue (everywhere, not only in the depths), deeper = darker navy
    vec3 navyLight = vec3(0.032, 0.100, 0.175) * (0.45 + 0.9 * dayAmt);
    bodyRGB = mix(bodyRGB, navyLight, clamp(0.70 * PW_WATER_TINT, 0.0, 1.0));
    bodyRGB = mix(bodyRGB, vec3(0.016, 0.055, 0.105) * (0.45 + 0.9 * dayAmt) + vec3(0.003, 0.008, 0.003) * dayAmt, deepK * 0.85);
    bodyRGB += vec3(0.002, 0.004, 0.007) * nightAmt;
    bodyRGB *= caveDark;

    // subsurface glow: thin wave crests lit from behind turn bright teal (stronger toward the sun)
    {
        float crest = clamp(wH * 0.9 + 0.35 + slopeLen * 0.9, 0.0, 1.0);
        float toSun = pow(clamp(dot(-viewDirW.xz, sunDirW.xz) * 0.5 + 0.5, 0.0, 1.0), 2.0);
        bodyRGB += vec3(0.020, 0.090, 0.075) * crest * crest * (0.4 + 0.6 * toSun)
                 * clamp(sunDirW.y * 2.0, 0.0, 1.0) * (1.0 - deepK * 0.4) * dayAmt * PW_SSS;
    }

    // ---- sky reflection: horizon -> zenith gradient sampled along the reflected ray, Fresnel weighted ----
    vec3 Rw = reflect(-viewDirW, normal);
    // desaturated sky tint so far/grazing water melts into the pale hazy horizon instead of showing vivid sky blue
    vec3 skyPale = mix(skyColor, vec3(dot(skyColor, vec3(0.3333)) * 1.1), 0.7);
    vec3 horizonCol = mix(skyPale, vec3(0.74, 0.79, 0.84), 0.6) * mix(0.05, 1.0, dayAmt);
    vec3 zenithCol = skyColor * mix(0.05, 1.05, dayAmt);
    vec3 refl = mix(horizonCol, zenithCol, pow(clamp(Rw.y, 0.0, 1.0), 0.55)) + vec3(0.004, 0.008, 0.016) * nightAmt;
    refl *= mix(0.04, 1.0, skyVis);
    float fR = clamp((0.05 * WATER_PALENESS + fres * 0.95 + 0.04) * PW_REFLECTION, 0.0, 1.0);
    float alphaTot = bodyA + (1.0 - bodyA) * fR;
    vec3 waterColor = (bodyRGB * bodyA + refl * (1.0 - bodyA) * fR) / max(alphaTot, 0.001);

    // ---- whitecaps / crest foam ----
    float capNoise = pwNoise(wp * 2.2 + vec2(wTime * 0.35, -wTime * 0.2)) * 0.6 + pwNoise(wp * 6.0 - vec2(wTime * 0.5)) * 0.4;
    float foam = smoothstep(0.42, 0.78, wH * 0.8 + slopeLen * 0.35) * smoothstep(0.35, 0.8, capNoise)
               * (1.0 - smoothstep(60.0, 260.0, wDist)) * 0.30 * dayAmt * WATER_FOAM * PW_WHITECAPS;
    waterColor = mix(waterColor, vec3(0.92, 0.97, 1.0), clamp(foam, 0.0, 0.6));
#ifdef FOAM_EDGES
    {
        float eT = frameTimeCounter * FOAM_EDGE_SPEED;
        vec2 ep = wp * FOAM_EDGE_SCALE;
        float en = wNoise(ep * 2.5 + vec2(eT * 0.15, -eT * 0.1)) * 0.6 + wNoise(ep * 6.0 - vec2(eT * 0.2, eT * 0.12)) * 0.4;
        float pulse = 0.75 + 0.25 * sin(eT * 0.9 + en * 6.0);
        float edgeW = 0.9 * FOAM_EDGE_WIDTH * pulse;
        float edge = 1.0 - smoothstep(0.0, edgeW, waterDepth * (0.6 + 0.8 * en));
        edge *= step(waterDepth, 30.0);
        edge = smoothstep(0.25, 0.9, edge) * (0.55 + 0.45 * smoothstep(0.3, 0.7, en));
        float eFoam = clamp(edge * FOAM_EDGE_STRENGTH, 0.0, 1.0) * mix(0.55, 1.0, dayAmt);
        waterColor = mix(waterColor, vec3(0.93, 0.97, 1.0) * mix(0.35, 1.0, dayAmt), eFoam * 0.9);
        alphaTot = mix(alphaTot, 1.0, eFoam * 0.85);
    }
#endif

    // ---- sun / moon: sharp glitter + broad sheen, sparkling with the ripples ----
    vec3 lightDirW = normalize(mat3(gbufferModelViewInverse) * normalize(sunAngle < 0.5 ? sunPosition : moonPosition));
    vec3 halfV = normalize(lightDirW + viewDirW);
    float nh = clamp(dot(normal, halfV), 0.0, 1.0);
    float lightUp = clamp(lightDirW.y * 4.0, 0.0, 1.0) * (1.0 - rainStrength * 0.8) * WATER_GLINT * PW_SUN_GLITTER * skyVis;
    float sparkle = 0.55 + 0.9 * pwNoise(wp * 7.0 + vec2(wTime * 1.3, -wTime));
    float spec = pow(nh, 700.0) * 3.0 * sparkle * lightUp;
    float sheen = pow(nh, 55.0) * 0.22 * clamp(lightDirW.y * 3.0, 0.0, 1.0) * (1.0 - rainStrength * 0.8) * WATER_GLINT * PW_SUN_GLITTER * skyVis;
    vec3 glintCol = mix(vec3(0.25, 0.32, 0.45), vec3(1.0, 0.93, 0.8), dayAmt);
    waterColor += glintCol * (spec * mix(1.4, 1.0, dayAmt) + sheen);

    // ---- distance: lighting, haze and fog wash the water paler toward the horizon ----
    {
        float pale = smoothstep(25.0, 420.0, wDist);
        pale = (pale * pale * (3.0 - 2.0 * pale) * 0.85 + pale * 0.1) * PW_DISTANCE_HAZE;
        vec3 hazeW = mix(skyPale, vec3(0.70, 0.76, 0.82), 0.6) * mix(0.08, 1.0, dayAmt) * (1.0 - 0.25 * rainStrength);
        float graze = pow(1.0 - clamp(abs(viewDirW.y), 0.0, 1.0), 6.0) * smoothstep(60.0, 300.0, wDist);
        pale = max(pale, graze * 0.9);
        waterColor = mix(waterColor, hazeW, clamp(pale, 0.0, 0.95));
        alphaTot = mix(alphaTot, 1.0, clamp(pale * 0.7, 0.0, 1.0));
    }

    // ---- cinematic grade: teal shadows, slightly warm highlights, a touch more contrast ----
    {
        float lum = dot(waterColor, vec3(0.3333));
        waterColor *= mix(vec3(1.0), vec3(0.92, 1.03, 1.05), (1.0 - smoothstep(0.1, 0.5, lum)) * PW_CINEMATIC * 0.6);
        waterColor = mix(waterColor, waterColor * vec3(1.06, 1.0, 0.94), smoothstep(0.35, 0.9, lum) * PW_CINEMATIC * 0.5);
        waterColor = mix(waterColor, waterColor * waterColor * 1.5, 0.12 * PW_CINEMATIC);
    }

    float alpha = clamp(alphaTot + spec * 0.3 + sheen * 0.3 + foam * 0.5, 0.0, 1.0);
    color = vec4(waterColor, alpha);
    normalData = vec4(normal * 0.5 + 0.5, 1.0);
    waterMaskData = vec4(1.0, 0.0, 0.0, 1.0);
}
