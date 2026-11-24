#version 330 compatibility

// ============================================================
// ETHERREALITY GENESIS™ :: COMPOSITE
//
// STABLE REALTIME WATER REFLECTION
//
// Water:
//
//     colortex7
//          ↓
//     water detection
//          ↓
//     depthtex0
//          ↓
//     water position
//          ↓
//     wave normal
//          ↓
//     VIEW-SPACE normal
//          ↓
//     SSR
//          ↓
//     actual colortex0 scene image
//          ↓
//     Fresnel-shaped reflection
//          ↓
//     refraction / absorption / fog
// ============================================================


// ============================================================
// SCENE DATA
// ============================================================

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex7;


// ============================================================
// CAMERA PROJECTION
// ============================================================

uniform mat4 gbufferProjection;


// ============================================================
// MODEL VIEW
// ============================================================
//
// Converts the water wave normal into VIEW SPACE.
// ============================================================

uniform mat4 gbufferModelView;


// ============================================================
// GAME STATE
// ============================================================

uniform int isEyeInWater;


// ============================================================
// SCREEN
// ============================================================

uniform int viewWidth;
uniform int viewHeight;


// ============================================================
// INPUT
// ============================================================

in vec2 texcoord;


// ============================================================
// CAMERA
// ============================================================

#include "/settings.glsl"
#include "/Common/Camera/cameraConfig.glsl"
#include "/Common/Camera/Vignette/vignette.glsl"


// ============================================================
// WATER UTILITIES
// ============================================================

uniform float sunAngle;

float gmDay() {
    return mix(0.06, 1.0, smoothstep(-0.10, 0.25, sin(6.2831853 * sunAngle)));
}

#include "/Common/Water/Utilities/DepthUtils.glsl"
#include "/Common/Water/Reflection/Reflection.glsl"
#include "/Common/Water/Refraction/WaterRefraction.glsl"
#include "/Common/Water/Absorption/Absorption.glsl"
#include "/Common/Water/Underwater/UnderwaterFog.glsl"


// ============================================================
// APPLY WATER
// ============================================================

vec3 applyWater(
    vec2 uv,
    vec3 worldNormal,
    float waterDepth,
    vec3 waterView
) {

    // ========================================================
    // VIEW → CAMERA
    // ========================================================

    vec3 viewDir =
        normalize(
            -waterView
        );


    // ========================================================
    // REFRACTION
    // ========================================================

    vec3 refracted =
        refractionColor(
            colortex0,
            uv,
            worldNormal,
            waterDepth
        );


    // ========================================================
    // SKY FALLBACK
    // ========================================================

    float skyBlend =
        clamp(
            worldNormal.y *
            0.5 +
            0.5,
            0.0,
            1.0
        );


    vec3 skyColor = gmDay() *
        mix(
            vec3(
                0.70,
                0.82,
                0.92
            ),
            vec3(
                0.94,
                0.97,
                1.0
            ),
            skyBlend
        );


    // ========================================================
    // FLAT WATER NORMAL
    // ========================================================
    //
    // Guaranteed correct VIEW-SPACE plane normal.
    //
    // This forms the stable base of the reflection.
    // ========================================================

    vec3 flatNormalView =
        normalize(
            mat3(
                gbufferModelView
            ) *
            vec3(
                0.0,
                1.0,
                0.0
            )
        );


    // ========================================================
    // WAVE NORMAL → VIEW SPACE
    // ========================================================

    vec3 waveNormalView =
        normalize(
            mat3(
                gbufferModelView
            ) *
            worldNormal
        );


    // ========================================================
    // CONTROLLED WAVE INFLUENCE
    // ========================================================
    //
    // Previously the complete wave normal could bend the SSR
    // ray too aggressively.
    //
    // Keep the reflection mostly planar while allowing the
    // water waves to distort it.
    // ========================================================

    vec3 reflectionNormal =
        normalize(
            mix(
                flatNormalView,
                waveNormalView,
                0.22
            )
        );


    // ========================================================
    // NORMAL ORIENTATION
    // ========================================================

    if (
        dot(
            reflectionNormal,
            -waterView
        ) < 0.0
    ) {

        reflectionNormal =
            -reflectionNormal;
    }


    // ========================================================
    // REALTIME SSR
    // ========================================================

    vec4 reflectionData =
        screenSpaceReflection(
            waterView,
            reflectionNormal,
            skyColor
        );


    vec3 reflected =
        reflectionData.rgb;


    float reflectionConfidence =
        reflectionData.a;


    // ========================================================
    // FRESNEL
    // ========================================================

    float rawFresnel =
        waterFresnel(
            viewDir,
            reflectionNormal,
            1.33
        );


    // ========================================================
    // WATER REFLECTION SHAPE
    // ========================================================
    //
    // A raw dielectric Fresnel value is very weak head-on.
    //
    // Give it a restrained minimum, while preserving stronger
    // grazing-angle reflection.
    // ========================================================

    float fresnelShape =
        pow(
            clamp(
                rawFresnel,
                0.0,
                1.0
            ),
            0.40
        );


    float reflectionFactor =
        mix(
            0.06,
            0.80,
            fresnelShape
        );


    // ========================================================
    // FINAL SSR STRENGTH
    // ========================================================

    float reflectionStrength =
        reflectionFactor *
        reflectionConfidence;


    reflectionStrength =
        clamp(
            reflectionStrength,
            0.0,
            1.0
        );


    // ========================================================
    // REFRACTION + REFLECTION
    // ========================================================

    vec3 waterSurface =
        mix(
            refracted,
            reflected,
            reflectionStrength
        );


    // ========================================================
    // ABSORPTION
    // ========================================================

    vec3 finalColor =
        applyAbsorption(
            waterSurface,
            waterDepth
        );


    // ========================================================
    // CLEAR WATER FOG
    // ========================================================

    float fogAmount =
        1.0 -
        exp(
            -waterDepth *
            0.009
        );


    finalColor =
        mix(
            finalColor,
            vec3(
                0.57,
                0.75,
                0.87
            ) * gmDay(),
            fogAmount *
            0.10
        );


    // ========================================================
    // UNDERWATER FOG
    // ========================================================

    if (
        isEyeInWater ==
        1
    ) {

        finalColor =
            underwaterFog(
                finalColor,
                waterDepth
            );
    }


    return finalColor;
}


// ============================================================
// OUTPUT
// ============================================================

/* RENDERTARGETS: 0 */

layout(location = 0) out vec4 color;


// ============================================================
// MAIN
// ============================================================

uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform vec3 cameraPosition;

#if defined(LAVA_STEAM) || defined(LAVA_HEAT_DISTORTION)
float stH(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
float stN(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(stH(i), stH(i + vec3(1,0,0)), f.x), mix(stH(i + vec3(0,1,0)), stH(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(stH(i + vec3(0,0,1)), stH(i + vec3(1,0,1)), f.x), mix(stH(i + vec3(0,1,1)), stH(i + vec3(1,1,1)), f.x), f.y), f.z);
}
#endif

void main()
{
    // ========================================================
    // CURRENT SCENE
    // ========================================================

    // ========================================================
    // LAVA HEAT DISTORTION: hot air above and around lava wobbles the picture
    // like a flame haze. Looks down the screen for lava, then bends the
    // image with upward-scrolling noise.
    // ========================================================
    vec2 sceneUV = texcoord;
#ifdef LAVA_HEAT_DISTORTION
    if (isEyeInWater == 0) {
        float hSum = 0.0;
        for (int k = 1; k < 7; k++) {
            vec2 hu = texcoord - vec2(0.0, 0.018 * float(k));
            if (hu.y < 0.0) break;
            float hL = 1.0 - step(0.5, abs(texture2D(colortex2, hu).r - 43.0));
            hSum += hL * (1.0 - float(k) / 8.0);
        }
        float heat = clamp(hSum * 0.35, 0.0, 1.0);
        if (heat > 0.01) {
            float hT = frameTimeCounter;
            float hAsp = float(viewWidth) / float(viewHeight);
            float nx = stN(vec3(texcoord.x * hAsp * 20.0, texcoord.y * 8.0 - hT * 1.6, 0.0)) - 0.5;
            float ny = stN(vec3(texcoord.x * hAsp * 13.0 + 9.0, texcoord.y * 6.0 - hT * 1.2, 3.0)) - 0.5;
            sceneUV += vec2(nx, ny * 0.6) * heat * 0.008 * LAVA_HEAT_STRENGTH;
            sceneUV = clamp(sceneUV, vec2(0.002), vec2(0.998));
        }
    }
#endif

    vec4 scene =
        texture2D(
            colortex0,
            sceneUV
        );


    // ========================================================
    // WATER MASK
    // ========================================================

    float waterMask =
        texture2D(
            colortex7,
            texcoord
        ).r;


    // ========================================================
    // WATER SURFACE DEPTH
    // ========================================================

    float depthIncl =
        texture2D(
            depthtex0,
            texcoord
        ).r;


    // ========================================================
    // TERRAIN DEPTH
    // ========================================================

    float depthExcl =
        texture2D(
            depthtex1,
            texcoord
        ).r;


    // ========================================================
    // WATER GATE
    // ========================================================

    bool isWaterPixel =
        waterMask >
        0.5;


    // ========================================================
    // WATER
    // ========================================================

    if (
        isWaterPixel
    ) {

        // ----------------------------------------------------
        // STORED WAVE NORMAL
        // ----------------------------------------------------

        vec3 worldNormal =
            normalize(
                texture2D(
                    colortex1,
                    texcoord
                ).rgb
                *
                2.0
                -
                1.0
            );


        // ----------------------------------------------------
        // WATER POSITION
        // ----------------------------------------------------

        vec3 waterView =
            getViewPos(
                texcoord,
                depthIncl
            );


        // ----------------------------------------------------
        // TERRAIN POSITION
        // ----------------------------------------------------

        vec3 terrainView =
            getViewPos(
                texcoord,
                depthExcl
            );


        // ----------------------------------------------------
        // WATER DEPTH
        // ----------------------------------------------------

        float waterDepth =
            length(
                terrainView -
                waterView
            );


        // ----------------------------------------------------
        // APPLY WATER
        // ----------------------------------------------------

        scene.rgb =
            applyWater(
                texcoord,
                worldNormal,
                waterDepth,
                waterView
            );
    }




    // ========================================================
    // LAVA SHADOWS (screen-space, realtime)
    // Lava is the main light, so surfaces lit by it are shadowed
    // wherever geometry blocks the way down toward the lava below.
    // ========================================================
#ifdef LAVA_SHADOWS
    if (isEyeInWater == 0 && depthIncl < 0.999999) {
        float lsTorch = smoothstep(0.15, 0.7, texture2D(colortex3, texcoord).x);
        if (lsTorch > 0.01) {
            vec3 lsP = getViewPos(texcoord, depthIncl);
            vec3 lsN = normalize(texture2D(colortex1, texcoord).rgb * 2.0 - 1.0);
            vec3 lsL = normalize(mat3(gbufferModelView) * vec3(0.0, -1.0, 0.0));   // toward the lava below
            float lsNdl = dot(lsN, lsL);
            if (lsNdl > 0.05) {
                float lsJ = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
                float lsOcc = 0.0;
                float lsT = 0.15;
                for (int i = 0; i < 10; i++) {
                    float st = 0.3 + 0.12 * float(i);
                    vec3 rp = lsP + lsN * 0.08 + lsL * (lsT + st * lsJ);
                    lsT += st;
                    vec4 rc = gbufferProjection * vec4(rp, 1.0);
                    if (rc.w <= 0.0) break;
                    vec2 ru = rc.xy / rc.w * 0.5 + 0.5;
                    if (ru.x < 0.0 || ru.x > 1.0 || ru.y < 0.0 || ru.y > 1.0) break;
                    float sd = texture2D(depthtex0, ru).r;
                    if (sd >= 0.999999) continue;
                    float sz = getViewPos(ru, sd).z;
                    float diff = rp.z - sz;            // > 0: scene surface is in front of the ray point
                    if (diff > 0.08 && diff < 1.2 + lsT * 0.15) { lsOcc = 1.0; break; }
                }
                scene.rgb *= 1.0 - lsOcc * lsTorch * clamp(lsNdl * 1.5, 0.0, 1.0) * LAVA_SHADOW_STRENGTH;
            }
        }
    }
#endif

    // ========================================================
    // LAVA STEAM: soft wisps rising off lava lakes
    // Lava is tagged id 43; look "down the screen" for lava of similar
    // depth, then shape the haze with rising world-space noise.
    // ========================================================
#ifdef LAVA_STEAM
    if (isEyeInWater == 0 && depthIncl < 0.999999) {
        vec3 stV = getViewPos(texcoord, depthIncl);
        float stDist = length(stV);
        if (stDist < 90.0) {
            float stAmt = 0.0;
            // World-anchored: walk straight down through WORLD space from this surface point (with a slow
            // sideways spiral) and check, on screen, whether lava lies there. This does not depend on which
            // way the camera is facing, so the steam stays put on the world.
            for (int k = 0; k < 8; k++) {
                float fk = float(k);
                vec3 off = vec3(cos(fk * 2.4) * 1.6, -fk * 0.8, sin(fk * 2.4) * 1.6) * step(0.5, fk);
                vec3 pk = stV + mat3(gbufferModelView) * off;
                vec4 pc = gbufferProjection * vec4(pk, 1.0);
                if (pc.w <= 0.0) continue;
                vec2 u2 = pc.xy / pc.w * 0.5 + 0.5;
                if (u2.x < 0.0 || u2.x > 1.0 || u2.y < 0.0 || u2.y > 1.0) continue;
                if (abs(texture2D(colortex2, u2).r - 43.0) < 0.5) {
                    vec3 p2 = getViewPos(u2, texture2D(depthtex0, u2).r);
                    float same = 1.0 - smoothstep(1.2, 2.6, length(p2 - pk));
                    stAmt += same * (1.0 - fk / 9.0);
                }
            }
            stAmt = clamp(stAmt * 0.45, 0.0, 1.0);
            if (stAmt > 0.01) {
                vec3 stW = (gbufferModelViewInverse * vec4(stV, 1.0)).xyz + cameraPosition;
                float stT = frameTimeCounter;
                vec3 sp = vec3(stW.x * 0.30, stW.y * 0.22 - stT * 0.30, stW.z * 0.30) + vec3(stT * 0.04, 0.0, stT * 0.03);
                float wisp = stN(sp) * 0.6 + stN(sp * 2.3 + 5.0) * 0.4;
                float steam = stAmt * smoothstep(0.30, 0.80, wisp) * (1.0 - smoothstep(50.0, 90.0, stDist)) * LAVA_STEAM_STRENGTH;
                vec3 stCol = mix(vec3(0.95, 0.42, 0.18), vec3(0.78, 0.62, 0.56), 0.45);
                scene.rgb = mix(scene.rgb, stCol * 0.55 + scene.rgb * 0.5, clamp(steam * 0.22, 0.0, 0.5));
                scene.rgb += stCol * steam * 0.12;
            }
        }
    }
#endif


    // ========================================================
    // VIGNETTE
    // ========================================================

    float vignette =
        calculateGrandVignette(
            texcoord
        );


    scene.rgb *=
        vignette;


    // ========================================================
    // OUTPUT
    // ========================================================

    color =
        scene;
}