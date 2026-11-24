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
uniform sampler2D colortex2;
uniform vec3 sunPosition;
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
#undef WIND_STREAKS
#undef SUNRAYS
#undef SUN_GLARE
#undef SUN_FLARE

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


vec3 gmPale(vec3 c) {
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 p = mix(vec3(l), vec3(0.85, 0.9, 0.95) * gmDay(), 0.35);
    return mix(c, p, REFLECTION_PALENESS * 0.8);
}

// Sun glint on reflective surfaces
vec3 gmSunGlint(vec3 viewPos, vec3 n) {
    vec3 r = reflect(normalize(viewPos), n);
    vec3 sd = normalize(sunPosition);
    float g = (pow(max(dot(r, sd), 0.0), 150.0) * 1.5 + pow(max(dot(r, sd), 0.0), 30.0) * 0.15) * SUN_GLINT_STRENGTH;
    return vec3(1.0, 0.92, 0.75) * g * gmDay();
}

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
                0.40
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
            0.08,
            0.85,
            fresnelShape
        ) * WATER_REFLECTION_STRENGTH;


    // ========================================================
    // FINAL SSR STRENGTH
    // ========================================================

    float reflectionStrength =
        reflectionFactor *
        max(reflectionConfidence, 0.0);
    // sky reflection on SSR miss
    vec3 skyRefl = skyColor + gmSunGlint(waterView, reflectionNormal);
    float missW = (1.0 - reflectionConfidence) * reflectionFactor;
    vec3 reflectedFull = reflected * reflectionConfidence + skyRefl * (1.0 - reflectionConfidence);
    reflected = gmPale(reflectedFull);
    reflectionStrength = clamp(reflectionFactor, 0.0, 1.0);


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

void main()
{
    // ========================================================
    // CURRENT SCENE
    // ========================================================

    vec4 scene =
        texture2D(
            colortex0,
            texcoord
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

#ifdef WATER_REFLECTIONS
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


#endif

    // ========================================================
    // PUDDLES (SSR on flagged terrain)
    // ========================================================
    if (!isWaterPixel && depthIncl < 0.999999 && isEyeInWater == 0) {
        float pm = smoothstep(0.4, 0.95, texture2D(colortex2, texcoord).b);
        if (pm > 0.05) {
            vec3 pv = getViewPos(texcoord, depthIncl);
            vec3 pn = normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
            float cosT = clamp(dot(normalize(-pv), pn), 0.0, 1.0);
            float f = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);
            f = mix(0.15, 0.6, pow(f, 0.4));
            vec3 sky = gmDay() * mix(vec3(0.70, 0.82, 0.92), vec3(0.94, 0.97, 1.0), 0.5);
            vec4 ssr = screenSpaceReflection(pv, pn, sky);
            vec3 rc = gmPale(ssr.rgb * ssr.a + (sky + gmSunGlint(pv, pn)) * (1.0 - ssr.a));
            scene.rgb = mix(scene.rgb * 0.92, rc, clamp(f * pm * PUDDLE_REFLECTION_STRENGTH, 0.0, 1.0));
        }
    }

    // ========================================================
    // VIGNETTE
    // ========================================================

    float vignette =
        calculateGrandVignette(
            texcoord
        );


    scene.rgb *= 1.0;
    // vignette handled in final.fsh


    // ========================================================
    // OUTPUT
    // ========================================================

    color =
        scene;
}