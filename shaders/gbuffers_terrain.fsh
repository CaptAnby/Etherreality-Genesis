// ============================================================
// ETHERREALITY GENESIS :: TERRAIN GBUFFER
// ============================================================

#version 330 compatibility
#include "/settings.glsl"


// ============================================================
// TEXTURES
// ============================================================

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform sampler2D specular;
uniform sampler2D normals;
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
    float puddleMask = 0.0;
    {
        float outdoor = smoothstep(0.8, 0.95, lmcoord.y);
        float flatUp = smoothstep(0.9, 0.98, puddleUp);
#ifdef PUDDLES
        float wetG = outdoor * smoothstep(0.02, 0.12, puddleAmt);   // rain wetness reaching this surface
#else
        float wetG = 0.0;
#endif
        if (wetG > 0.0) {
            // how glossy this material gets when wet (stone, metal and concrete shine; wood less; earth stays dark and dull)
            float gl = 0.22;
            if (abs(materialID - 60.0) < 0.5) gl = 0.55;
            else if (abs(materialID - 61.0) < 0.5) gl = 0.95;
            else if (abs(materialID - 62.0) < 0.5) gl = 0.80;
            else if (abs(materialID - 63.0) < 0.5) gl = 0.40;
            else if (abs(materialID - 64.0) < 0.5) gl = 0.12;
            else if (abs(materialID - 2.0) < 0.5) gl = 0.50;
            else if (abs(materialID - 1.0) < 0.5) gl = 0.10;
            else if (abs(materialID - 40.0) < 0.5 || abs(materialID - 42.0) < 0.5) gl = 0.15;

            vec2 pp = puddleWorldPos.xz;
            // organic puddle outline: domain-warped noise with fine edge detail (no round blobs)
            vec2 wq = pp + vec2(pNoise(pp * 0.21) * 3.0);
            float n = pNoise(wq * 0.45) * 0.70 + pNoise(wq * 1.6 + 17.0) * 0.30;
            float T = 0.80 - 0.34 * puddleAmt;
            float core = smoothstep(T, T + 0.05, n) * flatUp * wetG;           // standing water
            float rim = smoothstep(T - 0.17, T + 0.02, n) * flatUp * wetG;     // soaked ground around it
            // water depth: thin film at the edge, deepest toward the middle (deeper water absorbs more light and reflects cleaner)
            float depthK = smoothstep(T + 0.02, T + 0.30, n);
            float wetAmt = wetG * puddleAmt * mix(0.4, 1.0, flatUp);
            // wet look: porous materials darken a lot, hard ones less (and they get glossy instead)
            color.rgb *= 1.0 - 0.40 * (1.0 - 0.55 * gl) * wetAmt;
            color.rgb *= 1.0 - 0.28 * rim * puddleAmt;                                   // damp ring around the puddle
            // standing water: much darker (water film over a dark, soaked surface) with a cool, slightly teal cinematic cast.
            // Darker with depth; only the reflection stays as bright as before (see composite.fsh).
            vec3 waterAlb = color.rgb * vec3(0.30, 0.35, 0.44);
            color.rgb = mix(color.rgb, waterAlb, core * mix(0.62, 0.92, depthK));
            // raindrop rings on the water (the reflection ripples too: see composite.fsh).
            // Drops per area follow the rain strength: sparse in a drizzle, dense in a downpour.
            vec2 rg = pp * 2.0;
            vec2 rid = floor(rg);
            vec2 rf = fract(rg) - 0.5;
            float rh = pHash(rid);
            vec2 rc = (vec2(pHash(rid + 3.1), pHash(rid + 7.7)) - 0.5) * 0.4;
            float ph = fract(frameTimeCounter * (0.7 + rh * 0.5) + rh * 10.0);
            float ring = exp(-pow((length(rf - rc) - ph * 0.5) * 16.0, 2.0)) * (1.0 - ph);
            ring *= step(mix(0.80, 0.30, clamp(rainStrength, 0.0, 1.0)), rh) * rainStrength * core;
#ifndef PUDDLE_RIPPLES
            ring = 0.0;
#endif
            color.rgb += ring * 0.05;
            // G-buffer: >0.55 = standing water, below = wet glossy material (reflectivity)
            puddleMask = max(core * mix(0.68, 1.0, depthK), wetAmt * gl * 0.5 + rim * 0.06);   // thin edges reflect less, deep water reflects fully
        }
    }


    // ========================================================
    // NORMAL
    // ========================================================

    vec3 nrm = normalize(normal);
#ifdef PBR_MATERIALS
    {
        // labPBR normal map: RG = normal xy, B = ambient occlusion. Black/missing texture = skip.
        vec4 nt = texture(normals, texcoord);
        bool hasNT = (nt.r + nt.g > 0.01);
        vec3 tn = vec3(0.0, 0.0, 1.0);
        if (hasNT) {
            vec2 nxy = nt.rg * 2.0 - 1.0;
            tn = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
        }
        if (hasNT) {
            vec2 pUv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
            vec4 pv = gbufferProjectionInverse * vec4(vec3(pUv, gl_FragCoord.z) * 2.0 - 1.0, 1.0);
            vec3 pp = pv.xyz / pv.w;
            vec3 dp1 = dFdx(pp);
            vec3 dp2 = dFdy(pp);
            vec2 du1 = dFdx(texcoord);
            vec2 du2 = dFdy(texcoord);
            vec3 d2p = cross(dp2, nrm);
            vec3 d1p = cross(nrm, dp1);
            vec3 Tt = d2p * du1.x + d1p * du2.x;
            vec3 Bt = -(d2p * du1.y + d1p * du2.y);
            float im = max(dot(Tt, Tt), dot(Bt, Bt));
            if (im > 1e-12) {
                im = inversesqrt(im);
                vec3 pn = normalize(Tt * im * tn.x + Bt * im * tn.y + nrm * tn.z);
                nrm = normalize(mix(nrm, pn, PBR_NORMAL_STRENGTH));
            }
            // baked AO from the texture, applied gently to albedo
            if (hasNT) color.rgb *= mix(1.0, clamp(nt.b, 0.0, 1.0), PBR_AO_STRENGTH);
        }
    }
#endif
    normalData = vec4(nrm * 0.5 + 0.5, 1.0);


    // ========================================================
    // MATERIAL
    // ========================================================

    // G = emissive mask: bright pixels of light-emitting blocks
    // (torch flame, lantern glass, glowstone, lava, fire...).
    float emLum = dot(color.rgb, vec3(0.3, 0.59, 0.11));
    bool emBlock = (materialID > 2.5 && materialID < 3.5) || abs(materialID - 41.0) < 0.5 || abs(materialID - 43.0) < 0.5;
    float emMask = emBlock ? smoothstep(0.50, 0.75, emLum) : 0.0;

#ifdef ORE_GLOW
    // Glowing ores: only the ore veins glow (gems/metal flecks), the stone
    // around them does not, and no block light is emitted.
    {
        bool overOre = abs(materialID - 50.0) < 0.5;
        bool netherOre = abs(materialID - 51.0) < 0.5;
        if (overOre || netherOre) {
            float oSat = max(max(color.r, color.g), color.b) - min(min(color.r, color.g), color.b);
            float oLum = emLum;
            float veins = netherOre
                ? smoothstep(0.52, 0.75, oLum)
                : max(smoothstep(0.17, 0.34, oSat), smoothstep(0.62, 0.82, oLum));
            emMask = max(emMask, clamp(veins * 0.6 * ORE_GLOW_STRENGTH, 0.0, 1.0));
        }
    }
#endif

#ifdef PBR_MATERIALS
    {
        // labPBR emission: specular alpha (255 = none)
        vec4 se = texture(specular, texcoord);
        if (se.r + se.g > 0.01 && se.a < 0.999) {
            emMask = max(emMask, clamp(se.a * 255.0 / 254.0, 0.0, 1.0));
        }
    }
#endif
    materialData =
        vec4(
            materialID,
            emMask,
            puddleMask,
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
    float pbrPack = 0.0;
#ifdef PBR_MATERIALS
    {
        // labPBR: R = perceptual smoothness, G = F0 (>=230 means metal). Black/missing texture = not PBR.
        vec4 sp = texture(specular, texcoord);
        // texture filtering: widen roughness where the normal changes quickly (specular anti-aliasing)
        vec3 gdx = dFdx(nrm);
        vec3 gdy = dFdy(nrm);
        float kern = min(0.5 * (dot(gdx, gdx) + dot(gdy, gdy)), 0.18);
        if (sp.r + sp.g > 0.01) {
            float pRough = 1.0 - clamp(sp.r, 0.0, 1.0);
            pRough = sqrt(clamp(pRough * pRough + kern, 0.0, 1.0));
            bool pMetal = sp.g * 255.0 >= 229.5;
            pbrPack = (pMetal ? 0.5 : 0.0) + clamp(pRough, 0.01, 1.0) * 0.49;
        } else {
            // no PBR texture: sensible default material per block group
            float dr = -1.0;
            bool dm = false;
            float pcMx = max(color.r, max(color.g, color.b));
            float pcSat = pcMx - min(color.r, min(color.g, color.b));
            float pcLum = dot(color.rgb, vec3(0.3, 0.59, 0.11));
            if (abs(materialID - 61.0) < 0.5) {
                // metals are grey or warm (iron, gold, copper); saturated cool/green/red blocks are polished gems
                bool warm = color.r > color.g * 1.02 && color.g > color.b * 1.05;
                bool grey = pcSat < 0.16;
                if (grey || warm) { dr = 0.32; dm = true; }
                else              { dr = 0.16; }
            }
            else if (abs(materialID - 62.0) < 0.5) { dr = 0.45; }
            else if (abs(materialID - 50.0) < 0.5 || abs(materialID - 51.0) < 0.5) { dr = 0.70; }   // ores              // quartz, prismarine, concrete
            else if (abs(materialID - 60.0) < 0.5) { dr = 0.80; }              // stone, bricks
            else if (abs(materialID - 2.0) < 0.5)  { dr = 0.85; }              // stone
            else if (abs(materialID - 63.0) < 0.5) { dr = 0.68; }              // wood
            else if (abs(materialID - 64.0) < 0.5) { dr = 0.95; }              // dirt, sand, gravel
            if (dr > 0.0) {
                dr = sqrt(clamp(dr * dr + kern, 0.0, 1.0));
                pbrPack = (dm ? 0.5 : 0.0) + clamp(dr, 0.01, 1.0) * 0.49;
            }
        }
    }
#endif
    lightmapData = vec4(lm, pbrPack, 1.0);


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
