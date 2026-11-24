
#version 330 compatibility
#include "/settings.glsl"

// ============================================================
// ETHERREALITY GENESIS :: DEFERRED
// OPTIMIZED CLOUD-GROUND SHADOWS RESTORED
// ============================================================

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform mat4 gbufferProjection;
uniform sampler2D lightmap;
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;

uniform vec3 sunPosition;
uniform vec3 moonPosition;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform int frameCounter;
uniform int isEyeInWater;
uniform float sunAngle;

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

#include "/Common/Shadows/Filtering/pcf.glsl"
#include "/Common/Shadows/Directional/shadowDirection.glsl"
#include "/Common/Shadows/Utilities/shadowPosition.glsl"
#include "/Common/Shadows/Utilities/shadowDistortion.glsl"
#include "/Common/Shadows/Utilities/shadowBias.glsl"
#include "/Common/Shadows/SoftShadows/softShadow.glsl"
#include "/Common/End/endShadow.glsl"

#include "/Common/Lighting/Environment/timeLighting.glsl"
#include "/Common/Lighting/Direct/sunLighting.glsl"
#include "/Common/Lighting/Direct/moonLighting.glsl"
#include "/Common/Lighting/Ambient/ambientLighting.glsl"
#include "/Common/Lighting/Emissive/emissiveLighting.glsl"

#include "/Common/Cloud/cloudSystem.glsl"
#include "/Common/Fog/Volumetric/fogRaymarch.glsl"

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// ============================================================
// PROJECTION HELPER
// ============================================================

vec3 grandCloudProjectAndDivide(
    mat4 inverseProjection,
    vec3 ndcPosition
) {
    vec4 projected =
        inverseProjection * vec4(ndcPosition, 1.0);

    float safeW = abs(projected.w) < 0.000001
        ? (projected.w < 0.0 ? -0.000001 : 0.000001)
        : projected.w;

    return projected.xyz / safeW;
}

// ============================================================
// BLOCK LIGHT: warm/vibrant + cheap screen-space local shadows
// ============================================================
#define GRAND_BLOCKLIGHT_COLOR     vec3(1.00, 0.50, 0.14)
#define GRAND_BLOCKLIGHT_STRENGTH  (2.4 * BLOCKLIGHT_STRENGTH)
#define GRAND_BLOCKLIGHT_SHADOW    0.55

// Marches a short ray from the surface toward the (estimated) light
// direction and checks the depth buffer. Returns 0 (lit) .. 1 (blocked).
float grandBlockLightOcclusion(
    vec3 viewPos,
    vec3 N,
    vec3 gDir,
    float gMag,
    float dither
) {
    // Gradient is unreliable on weak/noisy light gradients -> fade out
    // smoothly instead of switching on, which caused random patches.
    float gate = smoothstep(0.20, 0.55, gMag);
    if (gate <= 0.0) {
        return 0.0;
    }

    vec3 L = normalize(gDir * 0.85 + N * 0.45);
    float occ = 0.0;
    float wSum = 0.0;

    for (int i = 1; i <= 4; i++) {
        float stepLen = 0.30 * (float(i) - 1.0 + dither) + 0.15;
        vec3 p = viewPos + L * stepLen;
        vec4 c = gbufferProjection * vec4(p, 1.0);

        if (c.w <= 0.0) {
            break;
        }

        vec2 uv = c.xy / c.w * 0.5 + 0.5;

        // Fade near screen edges rather than cutting off.
        vec2 edge = smoothstep(0.0, 0.06, uv) * (1.0 - smoothstep(0.94, 1.0, uv));
        float edgeFade = edge.x * edge.y;

        float w = 1.0 / (1.0 + float(i) * 0.5);
        wSum += w;

        if (edgeFade <= 0.0) {
            continue;
        }

        float d = texture(depthtex0, uv).r;

        if (d >= 0.999999) {
            continue;
        }

        float sceneZ = grandCloudProjectAndDivide(
            gbufferProjectionInverse,
            vec3(uv, d) * 2.0 - 1.0
        ).z;

        float diff = sceneZ - p.z;

        // Thickness-aware, smooth hit: ignores the surface itself and
        // far-away geometry, and fades in/out instead of hard on/off.
        float minD = 0.08 + 0.01 * abs(p.z);
        float hit = smoothstep(minD, minD + 0.15, diff) *
                    (1.0 - smoothstep(0.9, 1.6, diff));

        occ += hit * edgeFade * w;
    }

    occ = occ / max(wSum, 0.0001);

    return clamp(occ * gate, 0.0, 1.0);
}

// ============================================================
// HELD LIGHT: light-emitting items/blocks in hand glow (weaker
// than a placed one) with cheap screen-space local shadows
// ============================================================
#define GRAND_HELD_LIGHT_COLOR     vec3(1.00, 0.55, 0.18)
#define GRAND_HELD_LIGHT_STRENGTH  (1.5 * HELD_LIGHT_STRENGTH)
#define GRAND_HELD_LIGHT_RADIUS    0.55
#define GRAND_HELD_LIGHT_SHADOW    0.85

float grandHeldLightOcclusion(
    vec3 viewPos,
    vec3 lightPos,
    float dither
) {
    float occ = 0.0;

    for (int i = 1; i <= 6; i++) {
        float t = (float(i) - 1.0 + dither) / 6.0;
        t = 0.04 + 0.92 * t;
        vec3 p = mix(viewPos, lightPos, t);
        vec4 c = gbufferProjection * vec4(p, 1.0);

        if (c.w <= 0.0) {
            continue;
        }

        vec2 uv = c.xy / c.w * 0.5 + 0.5;

        if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
            continue;
        }

        float d = texture(depthtex0, uv).r;

        if (d >= 0.999999) {
            continue;
        }

        float sceneZ = grandCloudProjectAndDivide(
            gbufferProjectionInverse,
            vec3(uv, d) * 2.0 - 1.0
        ).z;

        float diff = sceneZ - p.z;
        float minD = 0.10 + 0.01 * abs(p.z);
        float hit = smoothstep(minD, minD + 0.15, diff) *
                    (1.0 - smoothstep(1.0, 2.0, diff));

        occ = max(occ, hit);
    }

    return occ;
}

// ============================================================
// CLOUD DITHER
// ============================================================

float grandCloudDither(vec2 coordinate) {
    return fract(
        52.9829189 * fract(
            dot(
                coordinate,
                vec2(0.06711056, 0.00583715)
            )
        )
    );
}

// ============================================================
// MAIN
// ============================================================

#ifdef FUNNEL
#define GM_FN_BOT 0.0
float gmFnHash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float gmFnNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(gmFnHash(i), gmFnHash(i + vec3(1,0,0)), f.x),
                   mix(gmFnHash(i + vec3(0,1,0)), gmFnHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(gmFnHash(i + vec3(0,0,1)), gmFnHash(i + vec3(1,0,1)), f.x),
                   mix(gmFnHash(i + vec3(0,1,1)), gmFnHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float gmFnFbm(vec3 p) {
    return 0.55 * gmFnNoise(p) + 0.30 * gmFnNoise(p * 2.1 + 5.0) + 0.15 * gmFnNoise(p * 4.3 + 9.0);
}
float gmFnMap(vec3 p, vec2 fc, float ft) {
    float hh = clamp((165.0 - p.y) / (165.0 - GM_FN_BOT), 0.0, 1.0);
    float hb = hh * hh;
    vec2 ax = fc + vec2(sin(ft * 0.30 + hh * 3.2), cos(ft * 0.23 + hh * 2.4)) * 32.0 * hb;
    vec2 rel = p.xz - ax;
    float rad = mix(95.0, 10.0, pow(hh, 0.7)) * FUNNEL_SIZE;
#ifdef FUNNEL_DEBRIS
    rad *= 1.0 + 0.8 * (1.0 - smoothstep(63.0, 105.0, p.y));
#endif
    float rot = atan(rel.y, rel.x) + hh * 4.0 - ft * 1.4;
    float n = gmFnFbm(vec3(cos(rot) * 2.2, sin(rot) * 2.2, hh * 5.0 + ft * 0.2));
    float d = length(rel) - rad * (0.75 + 0.5 * n);
    d = max(d, max(p.y - 165.0, GM_FN_BOT - p.y));
    return d * 0.6;
}
#endif

#include "/Common/End/endSky.glsl"

void main() {
    vec4 scene = texture(colortex0, texcoord);
    float depth = texture(depthtex0, texcoord).r;
    // THE END: paint the cosmic sky only on empty-sky pixels; terrain keeps normal lighting
    if (depth >= 0.999999) {
#ifdef DISTANT_HORIZONS
        if (texture(dhDepthTex0, texcoord).r < 0.999999) { color = scene; return; }
#endif
        vec4 evp = gbufferProjectionInverse * vec4(vec3(texcoord, 1.0) * 2.0 - 1.0, 1.0);
        vec3 ewd = normalize(mat3(gbufferModelViewInverse) * normalize(evp.xyz / evp.w));
        vec3 scam = vec3(cameraPositionInt) + cameraPositionFract;
        float sdith = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
        vec3 skyC = endSky(ewd, frameTimeCounter, scam, 0);
        vec3 pulsarC = endSky(ewd, frameTimeCounter, scam, 1);
        vec4 skyCl = endCosmicClouds(ewd, scam, frameTimeCounter, 700.0, sdith);
        vec4 skyFg = endNebulaFog(ewd, scam, frameTimeCounter, 220.0, sdith);
        vec3 pillarBeams = endPillarBeams(ewd, scam, frameTimeCounter, 4000.0);
        vec3 skyOut = (skyC * skyFg.a + skyFg.rgb) * skyCl.a + skyCl.rgb + pulsarC + pillarBeams;   // fog first, then clouds/pulsar/beams on top
        skyOut = skyOut / (1.0 + 0.22 * skyOut);
        color = vec4(mix(vec3(dot(skyOut, vec3(0.333))), skyOut, 1.08) + vec3(0.004, 0.003, 0.010), 1.0);
        return;
    }

    // THE END terrain lighting: soft blue-white ambient + pale directional light from CPS001 (south, above)
    {
        vec3 eN = normalize(texture(colortex1, texcoord).rgb * 2.0 - 1.0);
        vec2 eLm = texture(colortex3, texcoord).rg;
        float eEmit = texture(colortex2, texcoord).g;
        vec3 eL = normalize(transpose(mat3(gbufferModelViewInverse)) * normalize(vec3(0.0, 0.20, 0.98)));
        float eNdl = max(dot(eN, eL), 0.0);
        vec3 ePP = (gbufferModelViewInverse * vec4(vec3(0.0), 1.0)).xyz;
        vec4 ep0 = gbufferProjectionInverse * vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
        ePP = (gbufferModelViewInverse * vec4(ep0.xyz / ep0.w, 1.0)).xyz;
        vec3 eNW0 = normalize(mat3(gbufferModelViewInverse) * eN);
        float eShadow = 1.0;
#ifdef REALTIME_SHADOWS
        vec4 eSC = applyShadowBias(vec4(endShadowClip(ePP), 1.0), eNW0, END_LIGHT_DIR);
        eSC.xyz = distortShadowClipPos(eSC.xyz);
        eShadow = abs(texture(colortex2, texcoord).r - 4.0) < 0.1 ? 1.0 : sampleSoftShadow(eSC.xyz * 0.5 + 0.5);
#endif
        vec3 eLight = vec3(0.17, 0.14, 0.27) + vec3(0.60, 0.50, 0.86) * eNdl * 0.55 * eShadow;
        eLight += vec3(1.0, 0.72, 0.42) * pow(clamp(eLm.x, 0.0, 1.0), 2.0) * 1.1;
        // CPS001 beams: pass through the map (glow in front of terrain) and light the surfaces they touch
        vec3 ecam = vec3(cameraPositionInt) + cameraPositionFract;
        vec4 ep4 = gbufferProjectionInverse * vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
        vec3 epv = ep4.xyz / ep4.w;
        vec3 eRel = mat3(gbufferModelViewInverse) * epv;
        float eDist = length(eRel);
        vec3 eDirW = eRel / max(eDist, 1e-4);
        vec3 eNw = normalize(mat3(gbufferModelViewInverse) * eN);
        vec3 eBeamLit = endBeamLight(ecam + eRel, eNw, frameTimeCounter, ecam);
        vec3 eGlow = endBeamGlow(eDirW, ecam, frameTimeCounter, eDist);
        float edith = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
        vec4 eCl = endCosmicClouds(eDirW, ecam, frameTimeCounter, eDist, edith);
        vec3 eLit = scene.rgb * (eLight + eBeamLit) * (1.0 + eEmit * 1.5);
        vec4 eFg = endNebulaFog(eDirW, ecam, frameTimeCounter, eDist, edith);
        // aerial perspective: distant terrain melts into a soft violet cosmic haze
        eLit = mix(eLit, vec3(0.16, 0.12, 0.34), (1.0 - exp(-eDist * 0.0035)) * 0.55);
        eLit = eLit * eFg.a + eFg.rgb;
        vec3 eOut = eLit * eCl.a + eCl.rgb + eGlow * 0.6 + endPillarBeams(eDirW, ecam, frameTimeCounter, eDist);   // beams/clouds on top of fog
        eOut = eOut / (1.0 + 0.22 * eOut);                         // soft filmic shoulder
        eOut = mix(vec3(dot(eOut, vec3(0.333))), eOut, 1.08) + vec3(0.004, 0.003, 0.010);   // cinematic tint, lifted violet blacks
        color = vec4(eOut, scene.a);
        return;
    }
#ifdef DISTANT_HORIZONS
    // Distant Horizons terrain beyond vanilla range: keep it, don't paint sky/clouds over it
    if (depth >= 0.999999 && texture(dhDepthTex0, texcoord).r < 0.999999) {
        color = scene;
        return;
    }
#endif
    bool skyPixel = depth >= 0.999999;
    bool isHand = !skyPixel && abs(texture(colortex2, texcoord).r - 4.0) < 0.1;

    // --------------------------------------------------------
    // VIEW POSITION
    // --------------------------------------------------------

    vec3 ndcPosition = vec3(
        texcoord,
        skyPixel ? 1.0 : depth
    ) * 2.0 - 1.0;

    vec3 viewPosition = grandCloudProjectAndDivide(
        gbufferProjectionInverse,
        ndcPosition
    );

    // --------------------------------------------------------
    // WORLD LIGHTING
    // --------------------------------------------------------

    WorldLighting worldLighting = getWorldLighting();

    // Weather: rain = soft gray cozy light, thunder = dark and intense.
    float rainW  = clamp(rainStrength, 0.0, 1.0);
    float stormW = clamp(thunderStrength, 0.0, 1.0);
    float wx     = max(rainW, stormW);

    // --------------------------------------------------------
    // TERRAIN LIGHTING
    // --------------------------------------------------------

    if (!skyPixel) {
        vec3 albedo = scene.rgb;

        vec3 normal = texture(
            colortex1,
            texcoord
        ).rgb;

        normal = normalize(normal * 2.0 - 1.0);

        vec3 lightDir = getShadowLightDirection();

        vec3 playerPos = (
            gbufferModelViewInverse *
            vec4(viewPosition, 1.0)
        ).xyz;

        vec3 absoluteWorldPosition =
            vec3(cameraPositionInt) +
            cameraPositionFract +
            playerPos;

        // Normal terrain shadow map.
        vec3 shadowViewPos = (
            shadowModelView *
            vec4(playerPos, 1.0)
        ).xyz;

        vec4 shadowClipPos =
            shadowProjection *
            vec4(shadowViewPos, 1.0);

        shadowClipPos = applyShadowBias(
            shadowClipPos,
            normal,
            lightDir
        );

        shadowClipPos.xyz =
            distortShadowClipPos(shadowClipPos.xyz);

        vec3 shadowNDCPos =
            shadowClipPos.xyz / shadowClipPos.w;

        vec3 shadowScreenPos =
            shadowNDCPos * 0.5 + 0.5;

        #ifdef REALTIME_SHADOWS
        float shadowFactor =
            isHand ? 1.0 : sampleSoftShadow(shadowScreenPos);
#else
        float shadowFactor = 1.0;
#endif

#ifdef RAYTRACE
        // Screen-space ray-traced sun shadows (cheap, depth-buffer march).
        if (!isHand && shadowFactor > 0.02 && isEyeInWater == 0) {
            float rtLen = length(viewPosition);
            if (rtLen < RT_RANGE) {
                vec3 rtL = normalize(lightDir);
                if (dot(normal, lightDir) > 0.02) {
                    vec2 rtTx = 1.0 / vec2(textureSize(depthtex0, 0));
                    float rtZ0 = abs(gbufferProjection[3][2] / (depth * 2.0 - 1.0 + gbufferProjection[2][2]));
                    float rtEdge = 0.0;
                    for (int k = 0; k < 4; ++k) {
                        vec2 rto = (k == 0) ? vec2(1.0, 0.0) : (k == 1) ? vec2(-1.0, 0.0) : (k == 2) ? vec2(0.0, 1.0) : vec2(0.0, -1.0);
                        float rtDn = texture(depthtex0, texcoord + rto * rtTx * 1.5).r;
                        float rtZn = abs(gbufferProjection[3][2] / (rtDn * 2.0 - 1.0 + gbufferProjection[2][2]));
                        rtEdge = max(rtEdge, abs(rtZn - rtZ0) / (rtZ0 * 0.04 + 0.05));
                    }
                    float rtEdgeMask = 1.0 - smoothstep(0.6, 1.5, rtEdge);
                    ivec2 rtP = ivec2(gl_FragCoord.xy) & 3;
                    float rtJit = (float((rtP.x * 4 + rtP.y * 7 + (rtP.x ^ rtP.y) * 5) & 15) + 0.5) / 16.0;
                    rtJit = (rtJit - 0.5) * RT_NOISE + 0.5;
                                        float rtOcc = 0.0;
                    for (int i = 0; i < RT_STEPS; ++i) {
                        float rtF = (float(i) + rtJit) / float(RT_STEPS);
                        float rtT = RT_DISTANCE * rtF * rtF + 0.08 + 0.003 * rtLen;
                        vec3 rp = viewPosition + rtL * rtT;
                        vec4 rc = gbufferProjection * vec4(rp, 1.0);
                        if (rc.w <= 0.0) break;
                        vec2 ruv = rc.xy / rc.w * 0.5 + 0.5;
                        if (ruv.x < 0.03 || ruv.x > 0.97 || ruv.y < 0.03 || ruv.y > 0.97) break;
                        float rd = texture(depthtex0, ruv).r;
                        if (rd >= 0.999999) continue;
                        float rz = grandCloudProjectAndDivide(gbufferProjectionInverse, vec3(ruv, rd) * 2.0 - 1.0).z;
                        float diff = rz - rp.z;
                        if (diff > 0.08 + 0.03 * rtT && diff < RT_THICKNESS * (0.6 + 0.4 * rtT)) { rtOcc = 1.0 - sqrt(clamp(rtT / RT_DISTANCE, 0.0, 1.0)); break; }
                    }
                    float rtFade = 1.0 - smoothstep(RT_RANGE * 0.6, RT_RANGE, rtLen);
                    shadowFactor *= 1.0 - rtOcc * RT_STRENGTH * rtFade * rtEdgeMask;
                }
            }
        }
#endif

#ifdef REALISTIC_WATER
        // Underwater: no shadow-map shadows, just soft, slowly drifting shade blobs
        if (isEyeInWater == 1) {
            vec3 ub = absoluteWorldPosition * 0.22;
            float ut = frameTimeCounter * 0.15;
            float blob = 0.5 + 0.5 * sin(ub.x + sin(ub.z * 1.3 + ut) * 1.5)
                                   * sin(ub.z * 0.9 - ut + sin(ub.x * 0.8) * 1.7);
            blob = 0.5 * blob + 0.25 * (0.5 + 0.5 * sin(ub.y * 1.2 + ub.x * 0.7 + ut));
            shadowFactor = mix(0.55, 1.0, smoothstep(0.1, 0.9, blob));
        }
#endif
        // Overcast: shadows melt into faint soft blobs.
        shadowFactor = mix(shadowFactor, 1.0, SHADOW_WEATHER_FADE * wx);

        // Direct sunlight with normal terrain shadows.
        vec3 sunLight = calculateGrandSunLight(
            albedo,
            normal,
            lightDir,
            shadowFactor,
            worldLighting
        );

        // Optimized cloud-cast shadows on terrain.
        // Only the direct sun-light contribution is attenuated.
        float cloudGroundShadow =
            grandCloudGroundShadowFactor(
                absoluteWorldPosition,
                frameTimeCounter * 0.05
            );

        // Colored shadows: light passing through stained/tinted glass
        // (blocked in shadowtex0, but not in the opaque-only shadowtex1).
#ifdef COLORED_GLASS_SHADOWS
        if (!isHand && shadowFactor < 0.98 && isEyeInWater == 0 &&
            shadowScreenPos.x > 0.0 && shadowScreenPos.x < 1.0 &&
            shadowScreenPos.y > 0.0 && shadowScreenPos.y < 1.0) {
            float zRef = shadowScreenPos.z - 0.0008;
            float dAll = texture(shadowtex0, shadowScreenPos.xy).r;
            float dOpq = texture(shadowtex1, shadowScreenPos.xy).r;
            if (dAll < zRef && dOpq >= zRef) {
                vec4 sc = texture(shadowcolor0, shadowScreenPos.xy);
                vec3 glassTint = mix(vec3(1.0), sc.rgb, clamp(sc.a * 1.5, 0.0, 1.0));
                glassTint = mix(vec3(dot(glassTint, vec3(0.333))), glassTint, 1.35);
                vec3 litSun = calculateGrandSunLight(
                    albedo, normal, lightDir, 1.0, worldLighting
                );
                sunLight = litSun * clamp(glassTint, 0.0, 1.0) * 0.85;
            }
        }

#endif

        #ifdef CLOUD_SHADOWS
        sunLight *= (isHand || isEyeInWater == 1) ? 1.0 : mix(1.0, cloudGroundShadow, CLOUD_SHADOW_STRENGTH);
#endif

        // Direct light is mostly blocked by the overcast sky.
        float directKeep = (1.0 - 0.75 * rainW) * (1.0 - 0.55 * stormW);
        sunLight *= directKeep;

        // Remaining lighting components stay unchanged.
        vec3 moonLight = calculateGrandMoonLightV2(
            albedo,
            normal,
            shadowFactor,
            worldLighting
        );

        moonLight *= (1.0 - 0.70 * rainW) * (1.0 - 0.5 * stormW);

        vec4 lmData = texture(colortex3, texcoord);
        bool hasLm = lmData.a > 0.5;
        float torchT = hasLm ? clamp((lmData.x - 0.03) / 0.92, 0.0, 1.0) : 0.0;
        float skyT = hasLm ? clamp((lmData.y - 0.03) / 0.92, 0.0, 1.0) : 1.0;

        // Caves/indoors: no direct sun or moon where there is no sky light
        // (stops shadow-map leaks lighting up cave walls).
        if (!isHand) {
            float skyGate = smoothstep(0.0, 0.45, skyT);
            sunLight *= skyGate;
            moonLight *= skyGate;
        }

        vec3 ambientLight =
            calculateGrandAmbientLight(
                albedo,
                worldLighting
            );

        // Pale warm-gray ambient in rain, darker gray in thunderstorms.
        float aLum = dot(ambientLight, vec3(0.3333));
        vec3 grayWarm = vec3(aLum) * vec3(1.04, 1.00, 0.93);
        ambientLight = mix(ambientLight, grayWarm, clamp(0.65 * rainW + 0.25 * stormW, 0.0, 0.9));
        ambientLight *= mix(1.0, 1.04, rainW) * mix(1.0, 0.55, stormW);

        // Block light: steep warm falloff, subtle flicker.
        float torchAmt = pow(torchT, mix(2.2, 1.8, wx));
        // Gentle, slow, calm flame breathing. Phase varies smoothly
        // with position (no cells/squares).
        float fph = dot(absoluteWorldPosition, vec3(0.31, 0.23, 0.27));
        float flicker = 1.0
            + 0.075 * sin(frameTimeCounter * 2.2 + fph)
            + 0.045 * sin(frameTimeCounter * 3.7 + fph * 1.9)
            + 0.030 * sin(frameTimeCounter * 1.1 + fph * 0.7);
        flicker = mix(1.0, flicker, smoothstep(0.1, 0.5, torchT));

        if (torchAmt > 0.01 && !isHand) {
            vec4 gd = texture(colortex4, texcoord);
            float occ = grandBlockLightOcclusion(
                viewPosition,
                normal,
                normalize(gd.rgb * 2.0 - 1.0),
                gd.a,
                grandCloudDither(gl_FragCoord.xy)
            );
            torchAmt *= 1.0 - GRAND_BLOCKLIGHT_SHADOW * occ;
        }

        vec3 emissiveLight =
            albedo * GRAND_BLOCKLIGHT_COLOR *
            torchAmt * GRAND_BLOCKLIGHT_STRENGTH * flicker *
            (1.0 + 0.30 * rainW + 0.55 * stormW);

        // Held light (torch etc. in either hand), centered near the hand.
        float heldLevel = float(max(heldBlockLightValue, heldBlockLightValue2));

#ifdef HELD_LIGHT
        if (heldLevel > 0.5) {
            vec3 heldPos = vec3(0.25, -0.30, -0.35);
            vec3 toL = heldPos - viewPosition;
            float dL = length(toL);
            float radius = heldLevel * GRAND_HELD_LIGHT_RADIUS;

            if (dL < radius) {
                vec3 Ldir = toL / max(dL, 0.0001);
                float ndl = isHand ? 0.6 : max(dot(normal, Ldir), 0.0);
                float att = 1.0 - dL / radius;
                att *= att;

                float occH = isHand ? 0.0 : grandHeldLightOcclusion(
                    viewPosition,
                    heldPos,
                    grandCloudDither(gl_FragCoord.xy + 17.0)
                );

                float fl = 1.0
                    + 0.06 * sin(frameTimeCounter * 7.0)
                    + 0.04 * sin(frameTimeCounter * 11.3);

                emissiveLight += albedo * GRAND_HELD_LIGHT_COLOR *
                    att * ndl * (heldLevel / 15.0) *
                    GRAND_HELD_LIGHT_STRENGTH * fl *
                    (1.0 - GRAND_HELD_LIGHT_SHADOW * occH);
            }
        }

#endif

        // Caves/indoors lose skylight ambient (the old premultiplied
        // lightmap used to do this implicitly).
        float skyAmbient = hasLm ? mix(0.02, 1.0, pow(skyT, 1.5)) : 1.0;

        // Soft hemispheric fill (BSL-like): top faces get full sky light,
        // side faces slightly less, bottom faces a warm-ish bounce, so
        // unlit faces stay soft instead of going black.
        float upY = (gbufferModelViewInverse * vec4(normal, 0.0)).y;
        float hemi = mix(0.80, 1.0, smoothstep(-1.0, 1.0, upY));
        vec3 bounce = vec3(1.04, 1.0, 0.94);
        ambientLight *= hemi * mix(bounce, vec3(1.0), smoothstep(-0.6, 0.3, upY));

        vec3 lighting = ambientLight * skyAmbient;

        // Ambient glow: unlit faces keep a soft sky-tinted fill.
        {
            float glowDay = 0.25 + 0.75 * smoothstep(-0.1, 0.3, sin(6.2831853 * sunAngle));
            vec3 glowCol = mix(worldLighting.skyColor, worldLighting.ambientColor, 0.5);
            lighting += albedo * glowCol * (0.10 * AMBIENT_GLOW * glowDay * mix(0.25, 1.0, skyAmbient) * hemi);
        }
        lighting += emissiveLight;
        lighting += sunLight;
        lighting += moonLight;

        scene.rgb = lighting;

        // Emissive pixels (torch tips, fire, lava, glowstone, fire on entities)
        float emMask = texture(colortex2, texcoord).g;
        scene.rgb += albedo * emMask * 1.8 * EMISSIVE_STRENGTH * (1.0 + 0.25 * flicker);

#ifdef RAYLEIGH
        // Cheap Rayleigh aerial perspective: distant terrain fades to sky blue.
        {
            float rDist = length(viewPosition);
            vec3 rBeta = vec3(5.8, 13.5, 33.1) * 0.0003 * RAYLEIGH_DENSITY;
            vec3 rExt = exp(-rBeta * rDist);
            float rDay = smoothstep(-0.05, 0.25, sin(6.2831853 * sunAngle));
            float rCos = dot(normalize(viewPosition), normalize(sunPosition));
            float rPhase = 0.6 + 0.4 * rCos * rCos;
            float rLow = 1.0 - smoothstep(0.1, 0.5, sin(6.2831853 * sunAngle));
            vec3 rCol = mix(worldLighting.skyColor, vec3(0.40, 0.60, 1.0), 0.5) * RAYLEIGH_BLUE;
            rCol *= mix(vec3(1.0), vec3(1.30, 0.85, 0.55), rLow * clamp(0.5 * RAYLEIGH_SUNSET, 0.0, 1.0));
            float rGate = rDay * mix(0.3, 1.0, skyAmbient) * (1.0 - 0.6 * wx);
            scene.rgb = scene.rgb * rExt + rCol * rPhase * (1.0 - rExt) * RAYLEIGH_STRENGTH * rGate;
        }
#endif
    }

    // --------------------------------------------------------
    // CAMERA RAY
    // --------------------------------------------------------

    vec3 viewDirection = normalize(viewPosition);

    vec3 rayDirection = normalize(
        mat3(gbufferModelViewInverse) *
        viewDirection
    );

    vec3 rayOrigin =
        vec3(cameraPositionInt) +
        cameraPositionFract;

    vec3 cloudLightDirection =
        normalize(getShadowLightDirection());

    // --------------------------------------------------------
    // SCENE DISTANCE
    // --------------------------------------------------------

    float cloudMaxDistance;

    if (skyPixel) {
        cloudMaxDistance = CLOUD_VIEW_DISTANCE;
    } else {
        cloudMaxDistance = max(
            length(viewPosition) - 0.25,
            0.0
        );
    }

    float dither = grandCloudDither(gl_FragCoord.xy);

    // --------------------------------------------------------
    // SHOOTING STARS (night only, sky pixels)
    // --------------------------------------------------------

#ifdef SHOOTING_STARS
    if (skyPixel && !isHand) {
        float starNight = smoothstep(0.05, 0.30, -sin(6.2831853 * sunAngle));
        starNight *= 1.0 - clamp(max(rainStrength, thunderStrength), 0.0, 1.0);

        if (starNight > 0.001 && rayDirection.y > 0.05) {
            float period = 3.0;
            float slot = floor(frameTimeCounter / period);
            float phase = fract(frameTimeCounter / period);

            // Two independent streaks per slot, each active ~0.5 s.
            for (int k = 0; k < 3; ++k) {
                float seed = slot * 7.13 + float(k) * 31.7;
                float h1 = fract(sin(seed * 12.9898) * 43758.5453);
                float h2 = fract(sin(seed * 78.233) * 43758.5453);
                float h3 = fract(sin(seed * 39.346) * 43758.5453);
                float h4 = fract(sin(seed * 11.135) * 43758.5453);

                // Only some slots spawn a star.
                if (h4 < 0.30) {
                    continue;
                }

                float startT = 0.05 + 0.6 * h3;
                float life = (phase - startT) / 0.16;
                if (life < 0.0 || life > 1.0) {
                    continue;
                }

                float az = h1 * 6.2831853;
                float el = 0.35 + 0.8 * h2;
                vec3 startDir = normalize(vec3(cos(az) * cos(el), sin(el), sin(az) * cos(el)));
                vec3 side = normalize(cross(startDir, vec3(0.0, 1.0, 0.0)));
                vec3 travel = normalize(side * (h2 - 0.5) * 2.0 + vec3(0.0, -0.8, 0.0));

                float len = 0.55;
                vec3 head = normalize(startDir + travel * (life * len));
                vec3 tailDir = normalize(startDir + travel * (max(life - 0.85, 0.0) * len));

                vec3 seg = head - tailDir;
                float segLen = max(length(seg), 0.0001);
                vec3 segN = seg / segLen;
                float along = clamp(dot(rayDirection - tailDir, segN), 0.0, segLen);
                float dist = length(rayDirection - (tailDir + segN * along));

                float u = along / segLen;
                float width = mix(0.0006, 0.0035, u);
                float streak = smoothstep(width, 0.0, dist) * pow(u, 1.6)
                             + 0.35 * exp(-dist * dist / (width * width * 9.0)) * u * u;
                float fade = sin(life * 3.14159265);

                scene.rgb += vec3(0.85, 0.92, 1.0) * streak * fade * 2.2 * starNight;

                // glowing tip
                float hd = length(rayDirection - head);
                float tip = exp(-hd * hd / 0.000030) * 2.0 + 0.6 * exp(-hd * hd / 0.00060) + 0.15 * exp(-hd * hd / 0.004);
                scene.rgb += vec3(1.0, 0.93, 0.80) * tip * fade * 4.0 * starNight;
            }
        }
    }

#endif


    // --------------------------------------------------------
    // FUNNEL CLOUD (thunderstorm only, purely visual, volumetric)
    // --------------------------------------------------------
#ifdef FUNNEL
    if (!isHand) {
        float fAct = clamp(stormW * 10.0, 0.0, 1.0);
        if (fAct > 0.001) {
            float ft = frameTimeCounter * FUNNEL_SPEED;
            vec2 cell = floor(rayOrigin.xz / 400.0);
            vec2 fc = (cell + 0.5) * 400.0
                    + (vec2(gmFnHash(vec3(cell, 1.0)), gmFnHash(vec3(cell, 2.0))) - 0.5) * 120.0
                    + vec2(sin(ft * 0.03), cos(ft * 0.025)) * 40.0;
            float sceneDist = skyPixel ? 1.0e5 : length(viewPosition);
            vec2 o2 = rayOrigin.xz - fc;
            vec2 d2 = rayDirection.xz;
            float qa = dot(d2, d2);
            float qb = dot(o2, d2);
            float qc = dot(o2, o2) - (190.0 * FUNNEL_SIZE) * (190.0 * FUNNEL_SIZE);
            float disc = qb * qb - qa * qc;
            if (qa > 1.0e-6 && disc > 0.0 && abs(rayDirection.y) > 1.0e-4) {
                float sq = sqrt(disc);
                float t0 = max((-qb - sq) / qa, 0.0);
                float t1 = (-qb + sq) / qa;
                float ya = (GM_FN_BOT - rayOrigin.y) / rayDirection.y;
                float yb = (165.0 - rayOrigin.y) / rayDirection.y;
                t0 = max(t0, min(ya, yb));
                t1 = min(min(t1, max(ya, yb)), sceneDist);
                if (t1 > t0) {
                    float tt = t0 + dither * 0.5;
                    bool hit = false;
                    for (int i = 0; i < 64; ++i) {
                        float dd = gmFnMap(rayOrigin + rayDirection * tt, fc, ft);
                        if (dd < 0.4) { hit = true; break; }
                        tt += max(dd, 0.3);
                        if (tt > t1) break;
                    }
                    if (hit) {
                        vec3 p = rayOrigin + rayDirection * tt;
                        vec2 e = vec2(1.0, 0.0);
                        vec3 nrm = normalize(vec3(
                            gmFnMap(p + e.xyy, fc, ft) - gmFnMap(p - e.xyy, fc, ft),
                            gmFnMap(p + e.yxy, fc, ft) - gmFnMap(p - e.yxy, fc, ft),
                            gmFnMap(p + e.yyx, fc, ft) - gmFnMap(p - e.yyx, fc, ft)) + 1.0e-5);
                        float hh = clamp((165.0 - p.y) / (165.0 - GM_FN_BOT), 0.0, 1.0);
                        float tex = gmFnFbm(p * 0.09 + vec3(0.0, -ft * 0.8, 0.0));
                        float dayF = smoothstep(-0.1, 0.3, sin(6.2831853 * sunAngle));
                        float diff = 0.5 + 0.5 * dot(nrm, normalize(cloudLightDirection));
                        float rim = pow(1.0 - clamp(dot(nrm, -rayDirection), 0.0, 1.0), 2.0);
                        vec3 col = vec3(0.13, 0.13, 0.15) * (0.30 + 0.70 * dayF)
                                 * (0.35 + 0.9 * diff) * (0.55 + 0.9 * tex)
                                 * (1.0 - 0.3 * hh) + vec3(0.05, 0.05, 0.06) * rim * dayF;
                        col *= FUNNEL_BRIGHTNESS;
#ifdef FUNNEL_DEBRIS
                        float dust = (1.0 - smoothstep(63.0, 125.0, p.y)) * (0.4 + 0.6 * tex);
                        col = mix(col, vec3(0.30, 0.24, 0.17) * (0.3 + 0.7 * dayF), clamp(dust * 0.8, 0.0, 0.85));
#endif
                        scene.rgb = mix(scene.rgb, col, fAct);
                    }
#ifdef FUNNEL_DUST
                    {
                        float tEnd = hit ? tt : t1;
                        float dl = (tEnd - t0) / 20.0;
                        float td = t0 + dl * dither;
                        float dT = 1.0;
                        vec3 dA = vec3(0.0);
                        float dayD = smoothstep(-0.1, 0.3, sin(6.2831853 * sunAngle));
                        for (int j = 0; j < 20; ++j) {
                            vec3 q = rayOrigin + rayDirection * td;
                            float h2 = clamp((165.0 - q.y) / (165.0 - GM_FN_BOT), 0.0, 1.0);
                            vec2 ax2 = fc + vec2(sin(ft * 0.30 + h2 * 3.2), cos(ft * 0.23 + h2 * 2.4)) * 32.0 * h2 * h2;
                            vec2 rl = q.xz - ax2;
                            float r = length(rl);
                            float rd = mix(95.0, 10.0, pow(h2, 0.7)) * FUNNEL_SIZE;
                            float an = ft * 1.6 + h2 * 2.5;
                            vec2 rr = vec2(cos(an) * rl.x - sin(an) * rl.y, sin(an) * rl.x + cos(an) * rl.y);
                            float nz = gmFnNoise(vec3(rr * 0.30, q.y * 0.22 - ft * 1.5));
                            float sp = smoothstep(0.66, 0.82, nz);
                            float x = (r - rd * 1.5) / (rd * 0.9 + 8.0);
                            float dens = sp * exp(-x * x) * (1.0 - 0.8 * smoothstep(63.0, 165.0, q.y)) * FUNNEL_DUST_AMOUNT * fAct;
                            float da = 1.0 - exp(-dens * dl * 0.35);
                            dA += vec3(0.34, 0.27, 0.19) * (0.3 + 0.7 * dayD) * da * dT;
                            dT *= 1.0 - da;
                            td += dl;
                        }
                        scene.rgb = scene.rgb * dT + dA;
                    }
#endif
                }
            }
        }
    }
#endif

    // --------------------------------------------------------
    // VOLUMETRIC FOG
    // --------------------------------------------------------

    float fogMaxDistance = grandFogResolveDistance(
        cloudMaxDistance,
        skyPixel
    );

    if (fogMaxDistance > 0.5 && !isHand) {
        vec4 fog = renderGrandVolumetricFog(
            rayOrigin,
            rayDirection,
            fogMaxDistance,
            dither,
            cloudLightDirection,
            float(frameCounter) * GRAND_FOG_TIME_SCALE,
            sunAngle
        );

        float fogOpacity = clamp(
            fog.a,
            0.0,
            1.0
        );

        // Weather fog: denser, grayer; dark gray in thunderstorms.
        float fogBoost = 1.0 + (0.8 * rainW + 0.7 * stormW) * RAIN_FOG_STRENGTH;
        float newOpacity = min(fogOpacity * fogBoost, 0.97);
        vec3 fogRgb = fog.rgb * (newOpacity / max(fogOpacity, 0.0001));
        float fLum = dot(fogRgb, vec3(0.3333));
        fogRgb = mix(fogRgb, vec3(fLum) * vec3(1.02, 1.0, 0.96), clamp(0.6 * rainW + 0.3 * stormW, 0.0, 0.9));
        fogRgb *= mix(1.0, 0.92, rainW) * mix(1.0, 1.0 - 0.55 * STORM_DARKNESS, stormW);
        fogOpacity = newOpacity;
        fog.rgb = fogRgb;

        if (fogOpacity > 0.0001) {
            scene.rgb =
                scene.rgb * (1.0 - fogOpacity) +
                fog.rgb;
        }
    }

    // --------------------------------------------------------
    // VOLUMETRIC CLOUDS
    // --------------------------------------------------------

#ifdef VOLUMETRIC_CLOUDS
    if (cloudMaxDistance > 0.0 && !isHand) {
        vec4 clouds = renderVolumetricClouds(
            rayOrigin,
            rayDirection,
            cloudLightDirection,
            dither,
            cloudMaxDistance
        );

        float cloudOpacity = clamp(
            clouds.a,
            0.0,
            1.0
        );

        // Soft horizon blend: distant, flat rays accumulate near-opaque cloud
        // in a few long segments, which made a hard line against the sky.
        float horizonBlend = smoothstep(0.0, CLOUD_HORIZON_SOFTNESS, abs(rayDirection.y));
        horizonBlend *= horizonBlend;
        {
            float camY = rayOrigin.y;
            float outside = max(max(cloudOverallMinY() - camY, camY - cloudOverallMaxY()), 0.0);
            horizonBlend = mix(horizonBlend, 1.0, 1.0 - smoothstep(0.0, 80.0, outside));
        }
        cloudOpacity *= horizonBlend;
        clouds.rgb *= horizonBlend;
        cloudOpacity *= CLOUD_OPACITY;
        clouds.rgb *= CLOUD_OPACITY * CLOUD_BRIGHTNESS;

        if (cloudOpacity > 0.0001) {
            scene.rgb =
                scene.rgb * (1.0 - cloudOpacity) +
                clouds.rgb;
        }
    }
#endif

    color = vec4(scene.rgb, scene.a);
}
