
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
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform int isEyeInWater;
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
uniform float sunAngle;

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

#include "/Common/Shadows/Filtering/pcf.glsl"
#include "/Common/Shadows/Directional/shadowDirection.glsl"
#include "/Common/Shadows/Utilities/shadowPosition.glsl"
#include "/Common/Shadows/Utilities/shadowDistortion.glsl"
#include "/Common/Shadows/Utilities/shadowBias.glsl"
#include "/Common/Shadows/SoftShadows/softShadow.glsl"

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

float nmHash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float nmNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(nmHash(i), nmHash(i + vec3(1,0,0)), f.x),
                   mix(nmHash(i + vec3(0,1,0)), nmHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(nmHash(i + vec3(0,0,1)), nmHash(i + vec3(1,0,1)), f.x),
                   mix(nmHash(i + vec3(0,1,1)), nmHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 nmFogCol(vec3 p) {
    vec3 col = vec3(0.24, 0.055, 0.008);                      // orange-ember haze
#ifndef NETHER_FOG_VARIATION
    return col;
#endif
    float a = nmNoise(vec3(p.x * 0.0035, 0.0, p.z * 0.0035));
    float b = nmNoise(vec3(p.x * 0.0035 + 40.0, 0.0, p.z * 0.0035 + 17.0));
    float c2 = nmNoise(vec3(p.x * 0.0035 - 25.0, 0.0, p.z * 0.0035 + 63.0));
    col = mix(col, vec3(0.20, 0.01, 0.01), smoothstep(0.5, 0.7, c2) * 0.5);   // deep red
    col = mix(col, vec3(0.04, 0.20, 0.28), smoothstep(0.58, 0.78, a) * 0.3);  // faint teal
    col = mix(col, vec3(0.24, 0.05, 0.30), smoothstep(0.58, 0.78, b) * 0.3);  // faint violet
    return col;
}

void main() {
    vec4 scene = texture(colortex0, texcoord);
    float depth = texture(depthtex0, texcoord).r;
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

        float shadowFactor =
            isHand ? 1.0 : sampleSoftShadow(shadowScreenPos);

        // Overcast: shadows melt into faint soft blobs.
        shadowFactor = mix(shadowFactor, 1.0, 0.82 * wx);

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
        if (!isHand && shadowFactor < 0.98 &&
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

        sunLight *= isHand ? 1.0 : cloudGroundShadow;

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
        ambientLight *= NETHER_BRIGHTNESS * 0.7;   // darker Nether

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
        float skyAmbient = hasLm ? mix(0.05, 1.0, pow(skyT, 1.5)) : 1.0;

        // Soft hemispheric fill (BSL-like): top faces get full sky light,
        // side faces slightly less, bottom faces a warm-ish bounce, so
        // unlit faces stay soft instead of going black.
        float upY = (gbufferModelViewInverse * vec4(normal, 0.0)).y;
        float hemi = mix(0.80, 1.0, smoothstep(-1.0, 1.0, upY));
        vec3 bounce = vec3(1.04, 1.0, 0.94);
        ambientLight *= hemi * mix(bounce, vec3(1.0), smoothstep(-0.6, 0.3, upY));

        vec3 lighting = ambientLight * skyAmbient;
        lighting += emissiveLight;
        lighting += sunLight;
        lighting += moonLight;

        scene.rgb = lighting;

        // Emissive pixels (torch tips, fire, lava, glowstone, fire on entities)
        float emMask = texture(colortex2, texcoord).g;
        scene.rgb += albedo * emMask * 1.8 * EMISSIVE_STRENGTH * (1.0 + 0.25 * flicker);
        // lava (material id 43) glows brighter
        if (abs(texture(colortex2, texcoord).r - 43.0) < 0.5) {
            scene.rgb += albedo * (1.0 + 0.3 * flicker) * 1.2 * LAVA_BRIGHTNESS;
        }
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
            float period = 5.0;
            float slot = floor(frameTimeCounter / period);
            float phase = fract(frameTimeCounter / period);

            // Two independent streaks per slot, each active ~0.5 s.
            for (int k = 0; k < 2; ++k) {
                float seed = slot * 7.13 + float(k) * 31.7;
                float h1 = fract(sin(seed * 12.9898) * 43758.5453);
                float h2 = fract(sin(seed * 78.233) * 43758.5453);
                float h3 = fract(sin(seed * 39.346) * 43758.5453);
                float h4 = fract(sin(seed * 11.135) * 43758.5453);

                // Only some slots spawn a star.
                if (h4 < 0.55) {
                    continue;
                }

                float startT = 0.1 + 0.6 * h3;
                float life = (phase - startT) / 0.10;
                if (life < 0.0 || life > 1.0) {
                    continue;
                }

                float az = h1 * 6.2831853;
                float el = 0.35 + 0.8 * h2;
                vec3 startDir = normalize(vec3(cos(az) * cos(el), sin(el), sin(az) * cos(el)));
                vec3 side = normalize(cross(startDir, vec3(0.0, 1.0, 0.0)));
                vec3 travel = normalize(side * (h2 - 0.5) * 2.0 + vec3(0.0, -0.8, 0.0));

                float len = 0.35;
                vec3 head = normalize(startDir + travel * (life * len));
                vec3 tailDir = normalize(startDir + travel * (max(life - 0.45, 0.0) * len));

                vec3 seg = head - tailDir;
                float segLen = max(length(seg), 0.0001);
                vec3 segN = seg / segLen;
                float along = clamp(dot(rayDirection - tailDir, segN), 0.0, segLen);
                float dist = length(rayDirection - (tailDir + segN * along));

                float u = along / segLen;
                float width = mix(0.0007, 0.0022, u);
                float streak = smoothstep(width, 0.0, dist) * u * u;
                float fade = sin(life * 3.14159265);

                scene.rgb += vec3(0.85, 0.92, 1.0) * streak * fade * 2.2 * starNight;
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

    // NETHER: smooth dense crimson fog (overworld-style soft distance fog)
#ifdef NETHER_FOG
    if (!isHand) {
        float nd = skyPixel ? 300.0 : min(cloudMaxDistance, 400.0);
        float nOp = clamp(1.0 - exp(-nd * 0.028 * NETHER_FOG_DENSITY), 0.0, 0.9);
        vec3 nFog = nmFogCol(rayOrigin + rayDirection * nd);
        // lava-ish pixels tint the fog orange
        float nLava = smoothstep(0.7, 1.0, scene.r) * smoothstep(0.3, 0.55, scene.g) * (1.0 - smoothstep(0.2, 0.4, scene.b));
        nFog = mix(nFog, vec3(0.95, 0.32, 0.06), nLava * 0.6);
        scene.rgb = mix(scene.rgb, nFog, nOp);
    }
#endif

    // NETHER: cheap 3D volumetric mist, thinner near lava, denser away from it
#ifdef NETHER_MIST
    if (!isHand) {
        float mLen = skyPixel ? 60.0 : min(cloudMaxDistance, 60.0);
        float lavaNear = 0.0;
        for (int k = 0; k < 4; k++) {
            float a = float(k) * 1.5708;
            vec2 o = vec2(cos(a), sin(a)) * 0.06;
            vec3 t = texture(colortex0, clamp(texcoord + o, vec2(0.001), vec2(0.999))).rgb;
            lavaNear += smoothstep(0.7, 1.0, t.r) * smoothstep(0.3, 0.55, t.g) * (1.0 - smoothstep(0.2, 0.4, t.b));
        }
        lavaNear = clamp(lavaNear * 0.5, 0.0, 1.0);
        float mT = 1.0;
        float mAcc = 0.0;
        for (int i = 0; i < 6; i++) {
            float f = (float(i) + dither) / 6.0;
            vec3 sp = rayOrigin + rayDirection * (f * mLen);
            float n = nmNoise(sp * 0.09 + vec3(0.0, float(frameCounter) * 0.0004, 0.0));
            float dens = smoothstep(0.35, 0.8, n);
            float away = smoothstep(26.0, 60.0, sp.y);   // lava sea ~ y31
            dens *= (0.25 + 0.75 * away) * (1.0 - 0.7 * lavaNear);
            float ex = exp(-dens * (mLen / 6.0) * 0.045);
            mAcc += mT * (1.0 - ex);
            mT *= ex;
        }
        vec3 mCol = mix(nmFogCol(rayOrigin + rayDirection * 30.0) * 1.25, vec3(0.9, 0.3, 0.07), lavaNear);
        scene.rgb = mix(scene.rgb, mCol, clamp(mAcc, 0.0, 0.7));
    }
#endif

    if (false) {
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
        float fogBoost = 1.0 + 0.8 * rainW + 0.7 * stormW;
        float newOpacity = min(fogOpacity * fogBoost, 0.97);
        vec3 fogRgb = fog.rgb * (newOpacity / max(fogOpacity, 0.0001));
        float fLum = dot(fogRgb, vec3(0.3333));
        fogRgb = mix(fogRgb, vec3(fLum) * vec3(1.02, 1.0, 0.96), clamp(0.6 * rainW + 0.3 * stormW, 0.0, 0.9));
        fogRgb *= mix(1.0, 0.92, rainW) * mix(1.0, 0.45, stormW);
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

    if (false) {
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

        if (cloudOpacity > 0.0001) {
            scene.rgb =
                scene.rgb * (1.0 - cloudOpacity) +
                clouds.rgb;
        }
    }

    color = vec4(scene.rgb, scene.a);
}
