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
uniform sampler2D colortex3;
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
uniform vec3 cameraPosition;
uniform float rainStrength;


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

// raindrop ripples on standing water: returns the surface slope of a field of expanding, damped rings
vec2 rpRipple(vec2 p, float t, float rain) {
    vec2 g = vec2(0.0);
    for (int L = 0; L < 2; L++) {
        vec2 q = p * (1.7 + 1.2 * float(L)) + 17.3 * float(L);
        vec2 id = floor(q);
        vec2 f = fract(q) - 0.5;
        float h = fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
        vec2 ctr = (vec2(fract(h * 13.1), fract(h * 7.7)) - 0.5) * 0.5;
        float ph = fract(t * (0.8 + 0.5 * h) + h * 7.0);
        vec2 d = f - ctr;
        float r = length(d);
        float x = (r - ph * 0.5) * 14.0;
        float dH = (-3.0 * sin(3.0 * x) - 2.0 * x * cos(3.0 * x)) * exp(-x * x) * (1.0 - ph) * step(mix(0.80, 0.30, clamp(rain, 0.0, 1.0)), h);
        g += d / max(r, 0.001) * dH * 0.16;
    }
    return g;
}

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
        float pr = texture2D(colortex2, texcoord).b;     // >0.55 standing water, below = wet glossy material
        if (pr > 0.03) {
            vec3 pv = getViewPos(texcoord, depthIncl);
            vec3 vN = normalize(texture2D(colortex1, texcoord).rgb * 2.0 - 1.0);   // terrain normals are stored in view space
            vec3 wN = normalize(mat3(gbufferModelViewInverse) * vN);
            vec3 wPos = (gbufferModelViewInverse * vec4(pv, 1.0)).xyz + cameraPosition;
            float core = smoothstep(0.55, 0.90, pr);
            // raindrops distort the reflection in puddles (more drops in heavier rain)
            vec2 rs = rpRipple(wPos.xz, frameTimeCounter, rainStrength) * rainStrength * core;
            // a real water surface is never perfectly flat: very faint, slow undulation (stronger in rain / wind)
            float wob = 0.006 + 0.010 * rainStrength;
            vec2 wq = wPos.xz * 0.9 + vec2(frameTimeCounter * 0.07, -frameTimeCounter * 0.05);
            vec2 und = vec2(sin(wq.x * 3.1 + sin(wq.y * 2.3)), sin(wq.y * 2.7 + sin(wq.x * 1.9))) * wob * core;
            wN = normalize(wN + vec3(rs.x + und.x, 0.0, rs.y + und.y));
            vec3 pn = normalize(mat3(gbufferModelView) * wN);
            float cosT = clamp(dot(normalize(-pv), pn), 0.0, 1.0);
            float f = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);                  // Schlick Fresnel for water
            f = mix(mix(0.06, 0.30, pow(f, 0.5)), mix(0.15, 0.65, pow(f, 0.4)), core);   // wet stone: grazing sheen, puddle: mirror
            vec3 sky = gmDay() * mix(vec3(0.70, 0.82, 0.92), vec3(0.94, 0.97, 1.0), 0.5);
            vec4 ssr = (core > 0.3 && dot(pv, pv) < 3600.0) ? screenSpaceReflection(pv, pn, sky) : vec4(sky, 0.0);   // cheap: SSR only on nearby standing water
            vec3 rc = gmPale(ssr.rgb * ssr.a + (sky + gmSunGlint(pv, pn)) * (1.0 - ssr.a));
            rc *= mix(1.0, 0.70, core);   // reflection strength unchanged (the puddle surface itself is what got darker)
            // slight cinematic grade on the reflection: cool teal cast, a touch more contrast, and bright lights
            // (lamps, sun, lightning) bloom a little into the water
            rc = mix(rc, rc * vec3(0.84, 0.97, 1.08), core * 0.55);
            rc = mix(rc, pow(max(rc, vec3(0.0)), vec3(1.10)) * 1.05, core * 0.6);
            float rLum = dot(rc, vec3(0.3333));
            rc += rc * smoothstep(0.75, 1.5, rLum) * 0.22 * core;
            scene.rgb = mix(scene.rgb, rc, clamp(f * pr * 1.6 * PUDDLE_REFLECTION_STRENGTH, 0.0, 0.92));
        }
    }

#if defined(BLOCK_REFLECTIONS) && defined(PBR_MATERIALS)
    // ========================================================
    // BLOCK REFLECTIONS (SSR driven by per-block material)
    // ========================================================
    if (!isWaterPixel && depthIncl < 0.999999 && isEyeInWater == 0) {
        vec4 bkM = texture2D(colortex3, texcoord);
        float bkP = bkM.b;
        bool bkHand = abs(texture2D(colortex2, texcoord).r - 4.0) < 0.1;
        if (bkP > 0.0 && !bkHand) {
            bool bkMetal = bkP >= 0.5;
            float bkR = clamp((bkP - (bkMetal ? 0.5 : 0.0)) / 0.49, 0.02, 1.0);
            // only smooth-ish materials show a readable mirror image; rough ones fade out
            float bkK = (1.0 - smoothstep(0.22, 0.70, bkR)) * 0.6;
            if (bkK > 0.01) {
                vec3 bkV = getViewPos(texcoord, depthIncl);
                vec3 bkN = normalize(texture2D(colortex1, texcoord).rgb * 2.0 - 1.0);
                float bkCos = clamp(dot(normalize(-bkV), bkN), 0.0, 1.0);
                vec3 bkHue = scene.rgb / max(max(scene.r, max(scene.g, scene.b)), 0.001);
                vec3 bkF0 = bkMetal ? mix(vec3(0.78), bkHue, 0.6) : vec3(0.04);
                vec3 bkF = bkF0 + (1.0 - bkF0) * pow(1.0 - bkCos, 5.0);
                float skyOcc = smoothstep(0.10, 0.90, bkM.g);
                vec3 bkSky = gmDay() * mix(vec3(0.70, 0.82, 0.92), vec3(0.94, 0.97, 1.0), 0.5) * skyOcc;
                vec4 bkS = screenSpaceReflection(bkV, bkN, bkSky);
                vec3 bkRc = bkS.rgb * bkS.a + (bkSky + gmSunGlint(bkV, bkN) * skyOcc) * (1.0 - bkS.a);
                // softness: rougher material -> reflection melts toward a blurred average of the environment
                float bkSoft = 0.60 + 0.35 * smoothstep(0.10, 0.60, bkR);
                bkSoft = clamp(bkSoft * BLOCK_REFLECTION_SOFTNESS, 0.0, 1.0);
                bkRc = mix(bkRc, vec3(dot(bkRc, vec3(0.3333))) * mix(vec3(1.0), bkHue, bkMetal ? 0.5 : 0.0), bkSoft);
                // strength: smoother = stronger mirror; metals reflect strongly, dielectrics mostly at grazing angles
                vec3 bkAmt = clamp(bkF * bkK * (bkMetal ? 0.75 : 1.0), 0.0, bkMetal ? 0.42 : 0.20);
                // SSR misses indoors must not paint the sky onto surfaces
                bkAmt *= mix(skyOcc, 1.0, bkS.a);
                bkAmt = clamp(bkAmt * BLOCK_REFLECTION_STRENGTH, 0.0, 0.9);
                scene.rgb = mix(scene.rgb, bkRc * (bkMetal ? bkHue * 0.5 + 0.5 : vec3(1.0)), bkAmt);
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


    scene.rgb *= 1.0;
    // vignette handled in final.fsh


    // ========================================================
    // OUTPUT
    // ========================================================

    color =
        scene;
}