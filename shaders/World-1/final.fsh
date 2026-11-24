#version 330 compatibility
#include "/settings.glsl"

uniform sampler2D colortex0;
uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float lensWet;
uniform sampler2D depthtex0;
uniform float centerDepthSmooth;
uniform float near;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float far;
uniform float netherAdapt;

#ifdef UNDER_LAVA_FX
#include "/Common/Lava/underLava.glsl"
#endif

// ---- FXAA (compact) ----
float fxLuma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 fxaa(vec2 uv) {
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    vec3 rgbM  = texture(colortex0, uv).rgb;
    vec3 rgbNW = texture(colortex0, uv + vec2(-1.0, -1.0) * px).rgb;
    vec3 rgbNE = texture(colortex0, uv + vec2( 1.0, -1.0) * px).rgb;
    vec3 rgbSW = texture(colortex0, uv + vec2(-1.0,  1.0) * px).rgb;
    vec3 rgbSE = texture(colortex0, uv + vec2( 1.0,  1.0) * px).rgb;
    float lM = fxLuma(rgbM), lNW = fxLuma(rgbNW), lNE = fxLuma(rgbNE);
    float lSW = fxLuma(rgbSW), lSE = fxLuma(rgbSE);
    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
    if (lMax - lMin < max(0.02, lMax * 0.08)) return rgbM;

    vec2 dir;
    dir.x = -((lNW + lNE) - (lSW + lSE));
    dir.y =  ((lNW + lSW) - (lNE + lSE));
    float dirReduce = max((lNW + lNE + lSW + lSE) * 0.03125, 1.0 / 128.0);
    float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcp, vec2(-6.0), vec2(6.0)) * px;

    vec3 a = 0.5 * (texture(colortex0, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
                    texture(colortex0, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 b = a * 0.5 + 0.25 * (texture(colortex0, uv + dir * -0.5).rgb +
                               texture(colortex0, uv + dir * 0.5).rgb);
    float lB = fxLuma(b);
    vec3 fx = (lB < lMin || lB > lMax) ? a : b;
    // gentle extra softening on edge pixels only
    vec3 soft = 0.25 * (texture(colortex0, uv + vec2( 0.5,  0.5) * px).rgb +
                        texture(colortex0, uv + vec2(-0.5,  0.5) * px).rgb +
                        texture(colortex0, uv + vec2( 0.5, -0.5) * px).rgb +
                        texture(colortex0, uv + vec2(-0.5, -0.5) * px).rgb);
    return mix(rgbM, mix(fx, soft, AA_SOFTNESS), FXAA_STRENGTH);
}

// ---- Depth of field ----
float dofLinear(float d) {
    return 2.0 * near * far / (far + near - (2.0 * d - 1.0) * (far - near));
}

vec3 dofApply(vec2 uv, vec3 base) {
    float z = dofLinear(texture(depthtex0, uv).r);
    if (z < 1.2) return base;                         // keep held items sharp
    float focus = min(dofLinear(centerDepthSmooth), 48.0);
    float raw = abs(1.0 / focus - 1.0 / z) * 2.0;
    float coc = smoothstep(0.08, 0.90, raw);
    if (coc < 0.02) return base;

    float r = coc * 2.2 * DOF_STRENGTH * (viewHeight / 1080.0);
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    vec3 acc = base;
    float w = 1.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i) + 0.5;
        float ang = fi * 2.399963;
        float rad = sqrt(fi / 8.0) * r;
        vec2 o = vec2(cos(ang), sin(ang)) * rad * px;
        vec2 suv = clamp(uv + o, vec2(0.001), vec2(0.999));
        // don't smear near (in-focus-front) pixels onto far ones
        float sz = dofLinear(texture(depthtex0, suv).r);
        float sw = (sz < z - 2.0 && sz < focus) ? 0.0 : 1.0;
        acc += texture(colortex0, suv).rgb * sw;
        w += sw;
    }
    return mix(base, acc / w, clamp(coc * 0.8 * DOF_STRENGTH, 0.0, 1.0));
}

float dH(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// cheap lens droplets that slide down; returns UV offset
vec2 lensDrops(vec2 uv, float wet, float t) {
    float aspect = viewWidth / viewHeight;
    vec2 off = vec2(0.0);
    for (int i = 0; i < 2; i++) {
        float sc = (i == 0) ? 7.0 : 13.0;
        vec2 g = vec2(uv.x * aspect, uv.y) * sc;
        vec2 id = floor(g);
        vec2 f = fract(g);
        float h = dH(id + float(i) * 17.0);
        if (h > wet) continue;                       // drops dry out over time
        float spd = 0.05 + 0.10 * dH(id + 3.1);
        float py = 1.0 - fract(t * spd + h * 7.0);   // slides downward
        vec2 d = f - vec2(0.2 + 0.6 * dH(id + 9.7), py);
        float r = 0.14 * (0.6 + 0.4 * wet);
        float drop = smoothstep(r, 0.0, length(d * vec2(1.0, 0.8)));
        float trail = smoothstep(0.035, 0.0, abs(d.x)) * step(0.0, d.y) * smoothstep(0.55, 0.0, d.y) * 0.35;
        off += (-d) * drop * 0.05 + vec2(0.0, 0.0006) * trail;
    }
    return off;
}

float lavaMask(vec2 p) {
    vec3 s = texture(colortex0, clamp(p, vec2(0.001), vec2(0.999))).rgb;
    return smoothstep(0.85, 1.0, s.r) * smoothstep(0.35, 0.55, s.g) * (1.0 - smoothstep(0.2, 0.4, s.b));
}

in vec2 texcoord;
out vec4 color;

float nfHash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
// one layer of drifting specks: returns brightness 0..1
float nfSpecks(vec2 uv, float scale, float speed, float t, float radius) {
    vec2 q = uv * scale;
    q.y += t * speed;
    q.x += sin(t * 0.5 + floor(q.y) * 1.7) * 0.3;
    vec2 id = floor(q);
    vec2 f = fract(q);
    float h = nfHash(id);
    vec2 pos = vec2(0.2 + 0.6 * nfHash(id + 7.1), 0.2 + 0.6 * nfHash(id + 3.3));
    float on = step(0.55, h);
    return on * smoothstep(radius, 0.0, length(f - pos));
}

// world-anchored particle: continuous (no shell popping) because visibility
// uses the true ray-to-particle distance and a soft slab weight.
float nfParticle(vec3 o, vec3 vdir, float d, float cell, float rad, float prob, float seed) {
    vec3 pt = (o + vdir * d) / cell;
    vec3 id = floor(pt);
    float h = nfHash(id.xz + id.y * 3.1 + seed);
    if (h < prob) return 0.0;
    vec3 ctr = (id + vec3(0.25 + 0.5 * nfHash(id.xz + id.y + seed + 1.3),
                          0.25 + 0.5 * nfHash(id.zx + id.y * 1.7 + seed + 5.1),
                          0.25 + 0.5 * nfHash(id.xy + id.z * 2.3 + seed + 9.7))) * cell - o;
    float t = dot(ctr, vdir);
    float perp = length(ctr - vdir * t);
    float slab = smoothstep(cell * 0.9, cell * 0.2, abs(t - d));
    return slab * smoothstep(rad, rad * 0.3, perp);
}

void main() {
    vec2 uv = texcoord;
    vec3 c;

#ifdef UNDER_LAVA_FX
    if (isEyeInWater == 2) {
        c = underLava(texcoord);
    } else
#endif
    if (isEyeInWater == 1) {
        // gentle wavy distortion
        float t = frameTimeCounter;
        uv += vec2(
            sin(uv.y * 18.0 + t * 1.6) + sin(uv.y * 41.0 - t * 1.1) * 0.5,
            cos(uv.x * 16.0 + t * 1.3) + cos(uv.x * 37.0 - t * 0.9) * 0.5
        ) * 0.0021;
        uv = clamp(uv, vec2(0.002), vec2(0.998));

        // cheap soft blur (5 taps)
        vec2 px = 1.6 / vec2(viewWidth, viewHeight);
        c  = texture(colortex0, uv).rgb * 0.4;
        c += texture(colortex0, uv + vec2( px.x, 0.0)).rgb * 0.15;
        c += texture(colortex0, uv - vec2( px.x, 0.0)).rgb * 0.15;
        c += texture(colortex0, uv + vec2(0.0,  px.y)).rgb * 0.15;
        c += texture(colortex0, uv - vec2(0.0,  px.y)).rgb * 0.15;

        // murky blue-green haze, stronger toward edges
        float edge = length(texcoord - 0.5);
        vec3 haze = vec3(0.10, 0.30, 0.38);
        c = mix(c, haze, 0.18 + 0.30 * smoothstep(0.15, 0.75, edge));
        c *= vec3(0.80, 0.96, 1.05);
    } else {
        float wet = clamp(lensWet, 0.0, 1.0);
        if (wet > 0.01) {
            // droplets + slight wobble that settles as the lens dries
            uv += lensDrops(uv, wet, frameTimeCounter);
            uv.x += sin(uv.y * 30.0 + frameTimeCounter * 2.0) * 0.0012 * wet;
            uv = clamp(uv, vec2(0.002), vec2(0.998));
            vec2 px = 1.4 * wet / vec2(viewWidth, viewHeight);
            c  = texture(colortex0, uv).rgb * 0.4;
            c += texture(colortex0, uv + vec2(px.x, 0.0)).rgb * 0.15;
            c += texture(colortex0, uv - vec2(px.x, 0.0)).rgb * 0.15;
            c += texture(colortex0, uv + vec2(0.0, px.y)).rgb * 0.15;
            c += texture(colortex0, uv - vec2(0.0, px.y)).rgb * 0.15;
            c = mix(c, c * vec3(0.94, 0.98, 1.02), 0.5 * wet);
        } else {
#ifdef FXAA
            c = fxaa(uv);
#else
            c = texture(colortex0, uv).rgb;
#endif
        }
    }

#ifdef DOF
    if (isEyeInWater == 0) {
        c = dofApply(texcoord, c);
    }
#endif

    // vibrance: boost muted colors more than saturated ones
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
    c = mix(vec3(l), c, 1.0 + VIBRANCE * (1.0 - sat));

    // gentle contrast + warmth
    c = (c - 0.5) * CONTRAST + 0.5;
    c *= vec3(1.06, 1.04, 1.01);

#ifdef EYE_ADAPTATION
    {
        // Nether auto-exposure from nearby block light: near lava the eyes squint (darker),
        // in the dark they slowly open up (brighter).
        float exv = pow((1.0 + 0.25) / (netherAdapt + 0.25), 0.5);
        exv = clamp(mix(1.0, exv, EYE_ADAPTATION_STRENGTH), 0.82, 1.3);
        c *= exv;
        float over = clamp(exv - 1.0, 0.0, 1.0);
        c = mix(c, vec3(max(max(c.r, c.g), c.b)), over * 0.15);
    }
#endif

    // NETHER step 2: red grade + dark red distance haze
    float nL = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(nL) * vec3(1.55, 0.78, 0.36), 0.5);
    float nZ = dofLinear(texture(depthtex0, texcoord).r);
    float nH = clamp(1.0 - exp(-nZ * 0.02), 0.0, 0.9);
    // NETHER step 3: orange lava fog + rising silk strands
    float nGlow = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.785398;
        vec2 dir = vec2(cos(ang), sin(ang) * viewWidth / viewHeight);
        nGlow += lavaMask(texcoord + dir * 0.03) + lavaMask(texcoord + dir * 0.07);
    }
    nGlow = clamp(nGlow / 8.0, 0.0, 1.0);
    // flickering glow on lava-lit surfaces
#ifdef NETHER_LAVA_FLICKER
    float fl = 0.75 + 0.15 * sin(frameTimeCounter * 7.0) + 0.1 * sin(frameTimeCounter * 13.0 + 2.0);
#else
    float fl = 0.8;
#endif
    // orange distance haze + dark, devilish vignette so the lava is the focus
    c = mix(c, vec3(0.22, 0.05, 0.01), nH * 0.30);
    c *= 0.72 * mix(1.0, 0.35, smoothstep(0.2, 0.85, length(texcoord - 0.5)));
    c = mix(c, c * c * 1.3, 0.2);   // slightly deeper blacks
    c = mix(c, vec3(0.80, 0.30, 0.06), nGlow * (0.16 + 0.2 * nH) * fl);
    c *= 1.0 + nGlow * 0.12 * fl;

    // glowing hot edges: orange rim on silhouettes, stronger in the fog
    float zc = dofLinear(texture(depthtex0, texcoord).r);
    vec2 ep = 1.5 / vec2(viewWidth, viewHeight);
    float ez = abs(dofLinear(texture(depthtex0, texcoord + vec2(ep.x, 0.0)).r) - zc)
             + abs(dofLinear(texture(depthtex0, texcoord - vec2(ep.x, 0.0)).r) - zc)
             + abs(dofLinear(texture(depthtex0, texcoord + vec2(0.0, ep.y)).r) - zc)
             + abs(dofLinear(texture(depthtex0, texcoord - vec2(0.0, ep.y)).r) - zc);
#ifdef NETHER_HOT_EDGES
    float edge = smoothstep(0.7, 1.6, ez / max(zc, 1.0)) * smoothstep(24.0, 70.0, zc);
    c += vec3(1.0, 0.33, 0.07) * edge * (0.08 + 0.3 * nH) * fl;
#endif

    // world-anchored embers (rise) + ash (fall), hidden behind geometry
    vec4 pv = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
    vec3 vdir = normalize((gbufferModelViewInverse * vec4(pv.xyz / pv.w, 0.0)).xyz);
    float emb = 0.0;
    float ash = 0.0;
    float tm = frameTimeCounter;
    vec3 oE = cameraPosition + vec3(sin(tm * 0.6) * 0.5, -tm * 0.5, cos(tm * 0.5) * 0.5);
    vec3 oA = cameraPosition + vec3(sin(tm * 0.4) * 0.6, tm * 0.35, cos(tm * 0.3) * 0.6) + 31.7;
    for (int i = 0; i < 5; i++) {
        float d = 3.0 + float(i) * 3.5;
        if (d > zc) break;
        float rad = 0.02 + 0.005 * d;
#ifdef NETHER_EMBERS
        emb += nfParticle(oE, vdir, d, 3.5, rad, 0.88, 0.0);
#endif
#ifdef NETHER_ASH
        ash += nfParticle(oA, vdir, d, 3.5, rad * 1.1, 0.9, 17.0);
#endif
    }
    float emberAmt = 0.25 + 0.75 * clamp(nGlow * 3.0, 0.0, 1.0);
    c += vec3(1.0, 0.42, 0.1) * clamp(emb, 0.0, 1.0) * emberAmt * (0.6 + 0.4 * sin(frameTimeCounter * 9.0 + vdir.x * 40.0));
    c = mix(c, vec3(0.07, 0.04, 0.04), clamp(ash, 0.0, 1.0) * 0.55);
    color = vec4(max(c, 0.0), 1.0);
}
