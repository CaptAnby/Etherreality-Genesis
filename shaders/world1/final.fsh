#version 330 compatibility
#include "/settings.glsl"
#undef WIND_STREAKS
#undef SUNRAYS
#undef SUN_GLARE
#undef SUN_FLARE


uniform sampler2D colortex0;
uniform int isEyeInWater;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float lensWet;
uniform float eyeAdapt;
uniform ivec2 eyeBrightnessSmooth;
uniform sampler2D depthtex0;
uniform float centerDepthSmooth;
uniform float near;
uniform float far;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform float thunderStrength;

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

// Water sheeting off the lens: the whole screen is covered by large, individual chunks of water.
// Pure refraction (no beads/highlights). Each vertical "rope" of water slides down at its own speed with
// stop-and-go bursts, and its thickness swells and thins so it breaks into separate chunks.
// Returns vec4(uv offset, 0, 0).
float lensN1(float x, float seed) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(dH(vec2(i, seed)), dH(vec2(i + 1.0, seed)), f);
}

// water thickness along a rope (0 = dry gap, 1 = thick chunk); drops out as the lens dries
float lensMass(float y, float seed, float wet) {
    float n = 0.65 * lensN1(y, seed) + 0.35 * lensN1(y * 2.3 + 7.0, seed + 3.0);
    float thr = (1.0 - wet * LENS_DROP_DENSITY) * 0.30;
    return smoothstep(thr - 0.05, thr + 0.50, n);
}

vec4 lensDrops(vec2 uv, float wet, float t) {
    float aspect = viewWidth / viewHeight;
    vec2 off = vec2(0.0);
    float shade = 0.0;
    for (int i = 0; i < 2; i++) {
        float fi = float(i);
        float sc = ((i == 0) ? 2.6 : 4.4) / LENS_DROP_SIZE;          // ropes per screen height (fewer = wider chunks)
        float fy = ((i == 0) ? 1.9 : 3.1) / LENS_DROP_SIZE;          // chunk length along the slide direction
        // ropes wander sideways a little so they are not ruler-straight
        float q = uv.x * aspect * sc + fi * 4.7 + 0.30 * (lensN1(uv.y * 2.0 + fi * 9.0 + t * 0.25, 60.0 + fi) - 0.5) * 2.0;
        float cid = floor(q);
        float fx = fract(q);
        float hc = dH(vec2(cid, fi + 40.0));
        float spd = (1.3 + 1.1 * hc) * LENS_DROP_SPEED;
        // stop-and-go slide that never reverses
        float tt = spd * (t + 0.12 * sin(1.3 * t + hc * 6.2832));
        float y = uv.y * fy + tt + hc * 31.0;                       // +tt: features move down the screen
        float seed = cid * 1.7 + fi * 23.0;

        float m  = lensMass(y, seed, wet);
        float e  = 0.02;
        float dm = (lensMass(y + e, seed, wet) - lensMass(y - e, seed, wet)) / (2.0 * e);   // d(thickness)/d(y)

        // rope cross-section: thick in the middle, thin at the edges
        float sn = sin(3.14159 * fx);
        float s  = sn * sn;                                          // flat at the rope edges: no seams
        float ds = 3.14159 * sin(6.28318 * fx);
        // refraction = surface slope: sideways push from the cross-section, up/down push from thickness change
        vec2 slope = vec2(m * ds, clamp(dm, -3.0, 3.0) * s * 0.35);
        // waving: small ripples run down each rope and sway across it
        float ph = hc * 6.2832;
        vec2 rip = vec2(sin(uv.y * 34.0 + t * 11.0 + ph) + 0.6 * sin(uv.y * 71.0 + t * 17.0 - ph + fx * 4.0),
                        cos(uv.y * 27.0 + t * 8.0 - ph + fx * 6.0)) * (0.18 + 0.30 * m) * s * (0.35 + m);
        slope += rip;
        off += slope * vec2(0.115 / (sc * aspect), 0.07 / sc) * LENS_DROP_STRENGTH;
        // reflective sheen: surfaces tilted toward the sky/light catch a bright reflection, the others darken
        float lit = dot(slope, normalize(vec2(-0.55, 0.85)));
        shade += (smoothstep(0.45, 1.8, lit) * 0.30 - smoothstep(0.45, 1.8, -lit) * 0.12) * LENS_DROP_STRENGTH * (0.25 + 0.75 * m);
    }
    float fade = smoothstep(0.0, 0.35, wet);
    return vec4(off * fade, shade * fade, 0.0);
}

in vec2 texcoord;
out vec4 color;

float uwHash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float uwNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(uwHash(i), uwHash(i + vec3(1,0,0)), f.x),
                   mix(uwHash(i + vec3(0,1,0)), uwHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(uwHash(i + vec3(0,0,1)), uwHash(i + vec3(1,0,1)), f.x),
                   mix(uwHash(i + vec3(0,1,1)), uwHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 lensGhosts(vec2 tc, vec2 sUV, vec2 asp, vec3 tA, vec3 tB) {
    vec2 axis = vec2(0.5) - sUV;
    vec3 fl = vec3(0.0);
    for (int gi = 0; gi < 4; gi++) {
        float fi = float(gi);
        vec2 gp = sUV + axis * (0.45 + 0.55 * fi - 0.05 * fi * fi);
        float gr = 0.05 + 0.04 * fract(fi * 0.618 + 0.2);
        float gd = length((tc - gp) * asp);
        float disc = (1.0 - smoothstep(0.0, gr, gd)) * 0.5;
        float ring = exp(-pow((gd - gr) / (gr * 0.5), 2.0)) * 0.5;
        fl += mix(tA, tB, fract(fi * 0.37)) * (disc + ring) / (1.0 + fi * 0.5);
    }
    return fl;
}

float causticPat(vec2 p, float t) {
    float a = 0.0;
    vec2 q = p;
    for (int i = 0; i < 3; i++) {
        q += vec2(sin(q.y * 1.3 + t * (0.7 + float(i) * 0.3)), cos(q.x * 1.1 - t * 0.6)) * 0.7;
        float l = 0.5 * sin(q.x * 1.5) + 0.5 * sin(q.y * 1.5);
        a += pow(1.0 - abs(l), 2.2);
    }
    return a / 3.0;
}

#ifdef REALISTIC_WATER
#define UW_ON (isEyeInWater == 1)
#else
#define UW_ON false
#endif

void main() {
    vec2 uv = texcoord;
    vec3 c;

    if (UW_ON) {
        // gentle wavy distortion
        float t = frameTimeCounter;
        float wbD = texture(depthtex0, texcoord).r;
        float wbFar = 1.0 - 0.8 * smoothstep(0.97, 0.9995, wbD);
        uv += vec2(
            sin(uv.y * 10.0 + t * 1.4) + sin(uv.y * 23.0 - t * 1.0) * 0.5,
            cos(uv.x * 9.0 + t * 1.2) + cos(uv.x * 21.0 - t * 0.8) * 0.5
        ) * 0.0021 * UNDERWATER_WOBBLE * wbFar;
        uv = clamp(uv, vec2(0.002), vec2(0.998));

        // cheap soft blur (5 taps)
        vec2 px = 1.6 / vec2(viewWidth, viewHeight);
        c  = texture(colortex0, uv).rgb * 0.4;
        c += texture(colortex0, uv + vec2( px.x, 0.0)).rgb * 0.15;
        c += texture(colortex0, uv - vec2( px.x, 0.0)).rgb * 0.15;
        c += texture(colortex0, uv + vec2(0.0,  px.y)).rgb * 0.15;
        c += texture(colortex0, uv - vec2(0.0,  px.y)).rgb * 0.15;

        // murky blue-green haze, stronger toward edges
        float uwD = texture(depthtex0, texcoord).r;
        vec4 uwP = gbufferProjectionInverse * vec4(vec3(texcoord, uwD) * 2.0 - 1.0, 1.0);
        float uwDist = min(length(uwP.xyz / uwP.w), 160.0);
        vec3 uwT = exp(-WATER_SIGMA * (WATER_ABSORPTION / WATER_CLARITY) * uwDist * UNDERWATER_ABSORB);
        float uwEdge = length(texcoord - 0.5);
        float uwLit = clamp(dot(c, vec3(1.0)), 0.15, 1.0);
        c = c * mix(vec3(1.0), uwT, 0.8)
          + WATER_SCATTER * WATER_BRIGHTNESS * (vec3(1.0) - uwT) * 0.25 * uwLit
          + WATER_SCATTER * 0.04 * smoothstep(0.15, 0.75, uwEdge) * uwLit;
        c *= vec3(0.88, 1.0, 1.08) * UNDERWATER_BRIGHTNESS;
    } else {
        float wet = clamp(lensWet, 0.0, 1.0);
        if (wet > 0.01) {
            // droplets + slight wobble that settles as the lens dries
            vec4 ld = lensDrops(uv, wet, frameTimeCounter);
            uv += ld.xy;
            uv.x += sin(uv.y * 30.0 + frameTimeCounter * 2.0) * 0.0012 * wet;
            uv = clamp(uv, vec2(0.002), vec2(0.998));
            vec2 px = 0.8 * wet * wet * (1.0 - ld.w) / vec2(viewWidth, viewHeight);   // drops stay crisp, rest of the lens is slightly smeared
            c  = texture(colortex0, uv).rgb * 0.4;
            c += texture(colortex0, uv + vec2(px.x, 0.0)).rgb * 0.15;
            c += texture(colortex0, uv - vec2(px.x, 0.0)).rgb * 0.15;
            c += texture(colortex0, uv + vec2(0.0, px.y)).rgb * 0.15;
            c += texture(colortex0, uv - vec2(0.0, px.y)).rgb * 0.15;
            c = mix(c, c * vec3(0.94, 0.98, 1.02), 0.5 * wet);
            c = c * (1.0 + min(ld.z, 0.0)) + max(ld.z, 0.0) * vec3(0.85, 0.93, 1.0) * 0.7;   // drop rims + highlights
        } else {
#ifdef FXAA
            c = fxaa(uv);
#else
            c = texture(colortex0, uv).rgb;
#endif
        }
    }

#ifdef MOTION_BLUR
    if (!UW_ON) {
        float mbd = texture(depthtex0, texcoord).r;
        if (mbd > 0.56) {   // leave the held item sharp
            vec4 mp = gbufferProjectionInverse * vec4(vec3(texcoord, mbd) * 2.0 - 1.0, 1.0);
            vec3 mwp = (gbufferModelViewInverse * vec4(mp.xyz / mp.w, 1.0)).xyz + cameraPosition;
            vec4 mpv = gbufferPreviousModelView * vec4(mwp - previousCameraPosition, 1.0);
            vec4 mpc = gbufferPreviousProjection * mpv;
            if (mpc.w > 0.0) {
                vec2 vel = (texcoord - (mpc.xy / mpc.w * 0.5 + 0.5)) * 0.5 * MOTION_BLUR_STRENGTH;
                float vl = length(vel);
                if (vl > 0.0004) {
                    vel *= min(vl, 0.03) / vl;
                    vec3 macc = c;
                    for (int i = 1; i < 6; i++) {
                        float f = float(i) / 5.0 - 0.5;
                        macc += texture(colortex0, clamp(texcoord + vel * f, vec2(0.001), vec2(0.999))).rgb;
                    }
                    c = macc / 6.0;
                }
            }
        }
    }
#endif

#ifdef DOF
    if (!UW_ON) {
        c = dofApply(texcoord, c);
    }
#endif

#ifdef UNDERWATER_FOG
    if (UW_ON) {
        // slightly blurry underwater view
        float ub = UNDERWATER_BLUR;
        if (ub > 0.0) {
            vec2 upx = (1.6 * ub) / vec2(viewWidth, viewHeight);
            vec3 bacc = c;
            for (int i = 0; i < 8; i++) {
                float ang = (float(i) + 0.5) * 2.399963;
                float rad = sqrt((float(i) + 0.5) / 8.0);
                vec2 so = vec2(cos(ang), sin(ang)) * rad * upx * 2.0;
                bacc += texture(colortex0, clamp(uv + so, vec2(0.001), vec2(0.999))).rgb;
            }
            c = mix(c, bacc / 9.0, clamp(0.75 * ub, 0.0, 1.0));
        }
        // cheap 3D volumetric murk: denser in patches
        float uz = min(dofLinear(texture(depthtex0, texcoord).r), 160.0);
        vec4 up4 = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
        vec3 uvd = normalize((gbufferModelViewInverse * vec4(up4.xyz / up4.w, 0.0)).xyz);
#ifdef UNDERWATER_FOAM
        {
            // soft foam / bubbles clinging to the underside of the surface, plus faint drifting specks
            vec3 fsd = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            float fDay = 0.35 + 0.65 * smoothstep(-0.1, 0.3, fsd.y);
            float fDepthRaw = texture(depthtex0, texcoord).r;
            float ft = (UNDERWATER_SURFACE_Y - cameraPosition.y) / max(uvd.y, 0.001);
            if (uvd.y > 0.02 && ft > 0.0 && (fDepthRaw > 0.9999 || ft < uz + 0.5)) {
                vec2 fh = (cameraPosition + uvd * ft).xz * 0.35 * UNDERWATER_FOAM_SCALE;
                float fn = uwNoise(vec3(fh, frameTimeCounter * 0.08)) * 0.65
                         + uwNoise(vec3(fh * 2.7 + 5.0, frameTimeCounter * 0.12)) * 0.35;
                float foamU = smoothstep(0.5, 0.95, fn) * exp(-ft * 0.025);
                c = mix(c, vec3(0.62, 0.85, 0.90) * fDay, clamp(foamU * 0.45 * UNDERWATER_FOAM_STRENGTH, 0.0, 0.6));
            }
            // gentle suspended foam specks in the water column
            float sz = min(uz, 24.0);
            vec3 sp0 = cameraPosition + uvd * (sz * 0.5);
            float sn = uwNoise(sp0 * 0.9 * UNDERWATER_FOAM_SCALE + vec3(0.0, -frameTimeCounter * 0.15, 0.0));
            float specks = smoothstep(0.72, 0.95, sn) * clamp(sz / 24.0, 0.0, 1.0) * clamp((UNDERWATER_SURFACE_Y - sp0.y) / 6.0, 0.0, 1.0);
            c = mix(c, vec3(0.70, 0.90, 0.95) * fDay, specks * 0.10 * UNDERWATER_FOAM_STRENGTH);
        }
#endif
#ifdef UNDERWATER_CAUSTICS
        {
            float cd = texture(depthtex0, texcoord).r;
            vec3 csd = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            float cSun = smoothstep(0.05, 0.35, csd.y);
            if (cd < 0.9999 && cSun > 0.0) {
                vec4 cp = gbufferProjectionInverse * vec4(vec3(texcoord, cd) * 2.0 - 1.0, 1.0);
                vec3 cwp = cameraPosition + uvd * length(cp.xyz / cp.w);
                float dw = UNDERWATER_SURFACE_Y - cwp.y;
                if (dw > 0.0) {
                    vec2 cuv = (cwp.xz + csd.xz / max(csd.y, 0.2) * dw) * 0.7 * CAUSTIC_SCALE;
                    float ct = frameTimeCounter * CAUSTIC_SPEED;
                    float cau = causticPat(cuv * 0.6, ct * 0.6) + 0.4 * causticPat(cuv * 1.1 + 7.0, -ct * 0.7);
                    cau = smoothstep(0.35, 1.3, cau) * 0.6;
                    float cf = exp(-dw * 0.05) * exp(-length(cp.xyz / cp.w) * 0.02) * cSun;
                    c += c * cau * cf * 1.0 * CAUSTIC_STRENGTH * vec3(0.55, 1.0, 0.95)
                       + vec3(0.30, 0.65, 0.65) * cau * cf * 0.04 * CAUSTIC_STRENGTH;
                }
            }
        }
#endif
        float uAcc = 0.0;
        float uT = 1.0;
        for (int i = 0; i < 6; i++) {
            float f = (float(i) + 0.5) / 6.0;
            vec3 sp = cameraPosition + uvd * (f * uz);
            float n = uwNoise(sp * 0.13 + vec3(0.0, frameTimeCounter * 0.03, frameTimeCounter * 0.02));
            float dens = smoothstep(0.38, 0.8, n) * 1.6 + 0.12;
            float ex = exp(-dens * (uz / 6.0) * 0.08 * UNDERWATER_FOG_STRENGTH);
            uAcc += uT * (1.0 - ex);
            uT *= ex;
        }
        vec3 uCol = mix(vec3(0.02, 0.20, 0.36), vec3(0.10, 0.45, 0.62), clamp(uAcc, 0.0, 1.0) * 0.5);
        c = mix(c, uCol, clamp(uAcc, 0.0, 0.95));
        c = mix(c, vec3(0.03, 0.22, 0.38), 1.0 - exp(-uz * 0.026 * UNDERWATER_FOG_STRENGTH));
#ifdef UNDERWATER_RAYS
        {
            // physical-style shafts: sunlight enters through the rippling water
            // surface, is focused into beams by the waves, and fades with depth.
            vec3 usd = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            float uSunUp = smoothstep(0.05, 0.3, usd.y);
            if (uSunUp > 0.0) {
                float tt = frameTimeCounter;
                float shaft = 0.0;
                for (int i = 0; i < 12; i++) {
                    float f = (float(i) + 0.5) / 12.0;
                    vec3 sp = cameraPosition + uvd * (f * uz);
                    float up = (UNDERWATER_SURFACE_Y - sp.y) / max(usd.y, 0.05);   // distance up to the surface
                    if (up < 0.0) continue;
                    vec2 h = (sp + usd * up).xz;                                   // where this light entered
                    float w = sin(h.x * 0.9 + tt * 0.8 + sin(h.y * 0.7 + tt * 0.5) * 1.3)
                            * sin(h.y * 0.8 - tt * 0.6 + sin(h.x * 0.6 - tt * 0.3) * 1.5);
                    float beam = smoothstep(0.15, 0.9, 0.5 + 0.5 * w);
                    beam *= beam;
                    shaft += beam * exp(-up * 0.045) * (uz / 12.0);
                }
                float toSun = 0.45 + 0.55 * pow(max(dot(uvd, usd), 0.0), 2.0);
                float ur = shaft * 0.014 * toSun * uSunUp * UNDERWATER_RAY_STRENGTH;
                c += vec3(0.50, 0.90, 0.82) * clamp(ur, 0.0, 0.4);
            }
        }
#endif
    }
#endif

#ifdef EYE_ADAPTATION
    {
        // Auto-exposure (Bliss-style): exposure follows the adapted light level.
        // Leaving a cave: adapted level is still low -> overexposed, then eyes adjust.
        // Entering a cave: starts dark, then exposure slowly opens up.
        float exv = pow((1.0 + 0.25) / (eyeAdapt + 0.25), 0.5);
        exv = clamp(mix(1.0, exv, EYE_ADAPTATION_STRENGTH), 0.75, 2.0);
        c *= exv;
        // overexposure bleaches highlights toward white and softens contrast
        float over = clamp(exv - 1.0, 0.0, 1.0);
        c = mix(c, vec3(max(max(c.r, c.g), c.b)), over * 0.3);
        c = mix(c, vec3(1.0), over * over * 0.12);
    }
#endif

#if COLOR_GRADE > 0
    {
        float gl = dot(c, vec3(0.299, 0.587, 0.114));
#if COLOR_GRADE == 1
        // Cinematic: teal shadows, warm highlights
        c = mix(c, c * vec3(0.90, 1.0, 1.10), 1.0 - smoothstep(0.0, 0.5, gl));
        c = mix(c, c * vec3(1.08, 1.02, 0.92), smoothstep(0.45, 1.0, gl));
#elif COLOR_GRADE == 2
        // Vivid: richer saturation and punch
        c = mix(vec3(gl), c, 1.22);
#else
        // Muted film: softer color, lifted blacks
        c = mix(vec3(gl), c, 0.82);
        c = c * 0.94 + 0.03;
#endif
    }
#endif

    // vibrance: boost muted colors more than saturated ones
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
    c = mix(vec3(l), c, 1.0 + VIBRANCE * (1.0 - sat));

    // gentle contrast + warmth
    c = (c - 0.5) * CONTRAST + 0.5;
    c *= vec3(1.06, 1.04, 1.01);

#ifdef SUN_GLARE
    if (!UW_ON) {
        vec4 gpv = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
        vec3 gvd = normalize(gpv.xyz / gpv.w);
        vec3 gsd = normalize(sunPosition);
        float sunUp = smoothstep(-0.02, 0.12, (gbufferModelViewInverse * vec4(gsd, 0.0)).y);
        float cs = max(dot(gvd, gsd), 0.0);
        // is the sun itself visible (sky at its screen position)?
        vec4 gsc = gbufferProjection * vec4(gsd, 1.0);
        vec2 sUV = gsc.xy / gsc.w * 0.5 + 0.5;
        float inB = (gsd.z < 0.0 && sUV.x > 0.0 && sUV.x < 1.0 && sUV.y > 0.0 && sUV.y < 1.0) ? 1.0 : 0.0;
        float vis = 0.0;
        vec2 gpx = 6.0 / vec2(viewWidth, viewHeight);
        vis += step(0.9999, texture(depthtex0, clamp(sUV, 0.001, 0.999)).r);
        vis += step(0.9999, texture(depthtex0, clamp(sUV + vec2(gpx.x, 0.0), 0.001, 0.999)).r);
        vis += step(0.9999, texture(depthtex0, clamp(sUV - vec2(gpx.x, 0.0), 0.001, 0.999)).r);
        vis += step(0.9999, texture(depthtex0, clamp(sUV + vec2(0.0, gpx.y), 0.001, 0.999)).r);
        vis += step(0.9999, texture(depthtex0, clamp(sUV - vec2(0.0, gpx.y), 0.001, 0.999)).r);
        vis = mix(0.35, vis / 5.0, inB);
        float halo = pow(cs, 12.0) * 0.07 + pow(cs, 60.0) * 0.12 + pow(cs, 400.0) * 0.10;
        vec2 dd = (texcoord - sUV) * vec2(viewWidth / viewHeight, 1.0);
        float streak = exp(-abs(dd.y) * 55.0) * exp(-abs(dd.x) * 3.5) * 0.05 * inB;
        float gl = (halo + streak) * sunUp * vis * (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength))) * SUN_GLARE_STRENGTH;
        c += vec3(1.0, 0.86, 0.62) * gl;
#ifdef SUN_FLARE
        {
            vec2 asp = vec2(viewWidth / viewHeight, 1.0);
            float fOff = smoothstep(0.1, 0.7, length(sUV - 0.5) * 2.0);
            float fAmt = inB * sunUp * mix(0.3, 1.0, vis) * (0.4 + 0.6 * fOff)
                       * (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength))) * SUN_FLARE_STRENGTH;
            c += lensGhosts(texcoord, sUV, asp, vec3(1.0, 0.85, 0.65), vec3(0.65, 0.85, 1.0)) * fAmt * 0.42;
        }
#endif
        // ---- moon: soft cool glare streak + faint ghosts (subtler than the sun) ----
        {
            vec3 mgd = normalize(moonPosition);
            float sunY = (gbufferModelViewInverse * vec4(gsd, 0.0)).y;
            float moonUp = smoothstep(-0.02, 0.12, (gbufferModelViewInverse * vec4(mgd, 0.0)).y)
                         * (1.0 - smoothstep(-0.12, 0.05, sunY));
            vec4 mpc = gbufferProjection * vec4(mgd, 1.0);
            vec2 mUV = mpc.xy / mpc.w * 0.5 + 0.5;
            float mIn = (mgd.z < 0.0 && mUV.x > 0.0 && mUV.x < 1.0 && mUV.y > 0.0 && mUV.y < 1.0) ? 1.0 : 0.0;
            if (moonUp > 0.0 && mIn > 0.0) {
                float mvis = step(0.9999, texture(depthtex0, clamp(mUV, 0.001, 0.999)).r);
                vec2 masp = vec2(viewWidth / viewHeight, 1.0);
                vec2 mdd = (texcoord - mUV) * masp;
                float mStreak = exp(-abs(mdd.y) * 28.0) * exp(-abs(mdd.x) * 2.4) * 0.028;
                float mWx = (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength)));
                float mg = mStreak * moonUp * mvis * mWx * SUN_GLARE_STRENGTH * 2.0;
                c += vec3(0.62, 0.74, 1.0) * mg;
#ifdef SUN_FLARE
                c += lensGhosts(texcoord, mUV, masp, vec3(0.65, 0.78, 1.0), vec3(0.8, 0.88, 1.0))
                   * moonUp * mvis * mWx * SUN_FLARE_STRENGTH * 0.12;
#endif
            }
        }
    }
#endif

    // lens effects
    if (CHROMATIC_ABERRATION > 0.0) {
        vec2 cdir = (texcoord - 0.5) * 0.006 * CHROMATIC_ABERRATION;
        vec3 c0 = texture(colortex0, texcoord).rgb;
        c.r += texture(colortex0, clamp(texcoord + cdir, vec2(0.001), vec2(0.999))).r - c0.r;
        c.b += texture(colortex0, clamp(texcoord - cdir, vec2(0.001), vec2(0.999))).b - c0.b;
    }
    if (VIGNETTE_STRENGTH > 0.0) {
        float vr = length((texcoord - 0.5) * vec2(1.0, 0.85));
        c *= 1.0 - VIGNETTE_STRENGTH * smoothstep(0.25, 0.85, vr);
    }
    if (FILM_GRAIN > 0.0) {
        float gn = fract(sin(dot(gl_FragCoord.xy + frameTimeCounter * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
        c += (gn - 0.5) * 0.06 * FILM_GRAIN;
    }

    color = vec4(max(c, 0.0), 1.0);
}
