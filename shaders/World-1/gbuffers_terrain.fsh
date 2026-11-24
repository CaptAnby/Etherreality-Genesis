// ============================================================
// ETHERREALITY GENESIS :: TERRAIN GBUFFER
// ============================================================

#version 330 compatibility


// ============================================================
// TEXTURES
// ============================================================

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform mat4 gbufferProjectionInverse;
uniform float viewWidth;
uniform float viewHeight;


// ============================================================
// ALPHA
// ============================================================

uniform float alphaTestRef = 0.1;


// ============================================================
// INPUTS
// ============================================================

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
in float materialID;
in vec3 puddleWorldPos;
in float puddleUp;
in vec3 puddleRel;

uniform float puddleAmt;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform vec3 skyColor;

float pHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float pNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 fr = fract(p);
    fr = fr * fr * (3.0 - 2.0 * fr);
    return mix(mix(pHash(i), pHash(i + vec2(1,0)), fr.x),
               mix(pHash(i + vec2(0,1)), pHash(i + vec2(1,1)), fr.x), fr.y);
}



// ============================================================
// OUTPUTS
// ============================================================
//
// 0 = scene color
// 1 = normal
// 2 = material
// 3 = lightmap
// 4 = local-light source data
// ============================================================

/* RENDERTARGETS: 0,1,2,3,4 */

layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 lightmapData;
layout(location = 4) out vec4 localLightData;


// ============================================================
// MAIN
// ============================================================

void main() {

    // --------------------------------------------------------
    // Base terrain color
    // --------------------------------------------------------

    color =
        texture(
            gtexture,
            texcoord
        ) *
        glcolor;


    // --------------------------------------------------------
    // Existing Minecraft lightmap
    // --------------------------------------------------------

    // Lightmap is applied in deferred.fsh (clean albedo here).


    // --------------------------------------------------------
    // Alpha test
    // --------------------------------------------------------

    if (
        color.a <
        alphaTestRef
    ) {
        discard;
    }


    // --------------------------------------------------------
    // Puddles + wet ground (up-facing, open-sky surfaces only)
    // --------------------------------------------------------
    {
        float outdoor = smoothstep(0.8, 0.95, lmcoord.y);
        float flatUp = smoothstep(0.9, 0.98, puddleUp);
        float gate = outdoor * flatUp * smoothstep(0.02, 0.12, puddleAmt);
        if (gate > 0.0) {
            vec2 pp = puddleWorldPos.xz;
            float n = pNoise(pp * 0.45) * 0.65 + pNoise(pp * 1.3 + 17.0) * 0.35;
            float T = 0.80 - 0.34 * puddleAmt;
            float mask = smoothstep(T, T + 0.09, n) * gate;
            float wet = gate * puddleAmt;
            color.rgb *= 1.0 - 0.28 * wet;
            vec3 V = normalize(puddleRel);
            float fres = pow(1.0 - clamp(dot(vec3(0.0, 1.0, 0.0), -V), 0.0, 1.0), 3.0);
            vec3 refl = skyColor * 1.1 + 0.05;
            // raindrop ripples (only while it is actually raining)
            vec2 rg = pp * 2.0;
            vec2 rid = floor(rg);
            vec2 rf = fract(rg) - 0.5;
            float rh = pHash(rid);
            vec2 rc = (vec2(pHash(rid + 3.1), pHash(rid + 7.7)) - 0.5) * 0.4;
            float ph = fract(frameTimeCounter * (0.7 + rh * 0.5) + rh * 10.0);
            float ring = exp(-pow((length(rf - rc) - ph * 0.5) * 16.0, 2.0)) * (1.0 - ph);
            ring *= step(0.35, rh) * rainStrength * mask;
            float k = mask * (0.10 + 0.28 * fres) + ring * 0.35;
            color.rgb = mix(color.rgb * (1.0 - 0.38 * mask), refl, k);
        }
    }


    // ========================================================
    // NORMAL
    // ========================================================

    normalData =
        vec4(
            normalize(
                normal
            ) *
            0.5 +
            0.5,
            1.0
        );


    // ========================================================
    // MATERIAL
    // ========================================================

    // G = emissive mask: bright pixels of light-emitting blocks
    // (torch flame, lantern glass, glowstone, lava, fire...).
    float emLum = dot(color.rgb, vec3(0.3, 0.59, 0.11));
    bool emBlock = (materialID > 2.5 && materialID < 3.5) || abs(materialID - 41.0) < 0.5 || abs(materialID - 43.0) < 0.5;
    float emMask = emBlock ? smoothstep(0.50, 0.75, emLum) : 0.0;

    materialData =
        vec4(
            materialID,
            emMask,
            0.0,
            1.0
        );


    // ========================================================
    // LIGHTMAP
    // ========================================================

    vec2 lm = lmcoord;
    bool isEmitter = (materialID > 2.5 && materialID < 3.5) || abs(materialID - 41.0) < 0.5 || abs(materialID - 43.0) < 0.5;
    if (isEmitter) {
        lm.x = 1.0;
    }
    lightmapData = vec4(lm, 0.0, 1.0);


    // ========================================================
    // LOCAL LIGHT SOURCE DATA
    // ========================================================
    //
    // Current:
    //
    //   block.3 =
    //     torch
    //     lantern
    //     soul_torch
    //     soul_lantern
    //
    // R = reserved/source ID
    // G = depth
    // B = reserved
    // A = source flag
    // ========================================================

    // Surface gradient of block light (view space). Points toward the
    // brighter side, i.e. toward the nearest light source.
    vec3 N = normalize(normal);
    vec2 uvS = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 vp = gbufferProjectionInverse * vec4(vec3(uvS, gl_FragCoord.z) * 2.0 - 1.0, 1.0);
    vec3 P = vp.xyz / vp.w;
    vec3 dp1 = dFdx(P);
    vec3 dp2 = dFdy(P);
    float dl1 = dFdx(lm.x);
    float dl2 = dFdy(lm.x);
    vec3 c1 = cross(dp2, N);
    vec3 c2 = cross(N, dp1);
    float det = dot(dp1, c1);
    det = (abs(det) > 1e-7) ? det : 1e-7;
    vec3 g = (dl1 * c1 + dl2 * c2) / det;
    float gLen = length(g);
    float gMag = clamp(gLen * 16.0, 0.0, 1.0);
    vec3 gDir = gLen > 1e-6 ? g / gLen : N;
    localLightData = vec4(gDir * 0.5 + 0.5, gMag);
}
