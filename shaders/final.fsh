#version 330 compatibility
#include "/settings.glsl"

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
uniform float sunAngle;

#ifdef UNDER_LAVA_FX
#include "/Common/Lava/underLava.glsl"
#endif

#define CLOUD_UNIFORMS_PROVIDED
#include "/Common/Cloud/cloudSystem.glsl"

// ---- FXAA (Bliss-style: edge-only, sharp, cheap) ----
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
    // only real edges get touched (higher threshold = no blur on textures)
    if (lMax - lMin < max(0.0312, lMax * 0.100)) return rgbM;

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
    // sub-pixel fill: blend toward the 4-corner average (already fetched, free) so thin gaps and
    // shimmering cut-out edges close up and blocks look fuller
    vec3 soft = 0.25 * (rgbNW + rgbNE + rgbSW + rgbSE);
    return mix(rgbM, mix(fx, soft, AA_SOFTNESS), FXAA_STRENGTH);
}

// ---- Depth of field (Bliss-style: sharp focus zone, blur only when clearly out of focus) ----
float dofLinear(float d) {
    return 2.0 * near * far / (far + near - (2.0 * d - 1.0) * (far - near));
}

vec3 dofApply(vec2 uv, vec3 base) {
    float d0 = texture(depthtex0, uv).r;
    if (d0 >= 0.99999) return base;                   // sky: nothing to blur
    float z = dofLinear(d0);
    if (z < 1.2) return base;                         // keep held items sharp
    float focus = min(dofLinear(centerDepthSmooth), 48.0);
    float raw = abs(1.0 / focus - 1.0 / z) * 2.0;
    float coc = smoothstep(0.14, 1.2, raw);           // sharp focus zone, gentle ramp
    // mid/far terrain always gets a light fill so it reads full instead of sparkly
    coc = max(coc, smoothstep(40.0, 200.0, z) * 0.30);
    if (coc < 0.03) return base;

    float r = coc * 2.0 * DOF_STRENGTH * (viewHeight / 1080.0);
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    float jit = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))) * 6.2831853;
    vec3 acc = base;
    float w = 1.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i) + 0.5;
        float ang = fi * 2.399963 + jit;
        float rad = sqrt(fi / 6.0) * r;
        vec2 o = vec2(cos(ang), sin(ang)) * rad * px;
        vec2 suv = clamp(uv + o, vec2(0.001), vec2(0.999));
        float sz = dofLinear(texture(depthtex0, suv).r);
        float sw = (sz < z - 2.0 && sz < focus) ? 0.0 : 1.0;
        acc += texture(colortex0, suv).rgb * sw;
        w += sw;
    }
    vec3 col = mix(base, acc / w, clamp(coc * 0.75 * DOF_STRENGTH, 0.0, 1.0));
    // duller: soften saturation and contrast a little with distance / defocus
    float dull = clamp(coc * 0.30, 0.0, 0.14);
    col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), dull);
    return col;
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



#ifdef SCREEN_RAIN_DROPS
uniform float screenRain;

// Rain beads on the lens. One layer = a grid of cells, each possibly holding one drop.
// slide=true: the drop slides down its cell leaving a thin trail; slide=false: a static bead that swells and dries.
// Returns vec4(uv offset, rim highlight, coverage mask).
vec4 rainLayer(vec2 uv, float t, float scale, float seed, float dens, float spd, float sizeK, bool slide) {
    float aspect = viewWidth / viewHeight;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    vec2 id = floor(p);
    vec2 f = fract(p) - 0.5;
    float h1 = dH(id + seed);
    if (h1 > dens) return vec4(0.0);
    float h2 = dH(id + seed + 17.3);
    float h3 = dH(id + seed + 41.7);
    float R = (0.11 + 0.09 * h2) * sizeK;
    float dx = (h3 - 0.5) * 0.5;
    float dy, life, trail = 0.0;
    vec2 tOff = vec2(0.0);
    if (slide) {
        float cyc = fract(t * spd * (0.05 + 0.08 * h2) + h1 * 7.0 / max(dens, 0.05));
        cyc = mix(cyc, smoothstep(0.0, 1.0, cyc), 0.6);           // slow start, quick slide
        dy = 0.40 - 0.80 * cyc;
        life = smoothstep(0.0, 0.10, cyc) * (1.0 - smoothstep(0.88, 1.0, cyc));
        float above = f.y - dy;
        float tw = 0.020 * sizeK;
        trail = smoothstep(tw, 0.0, abs(f.x - dx)) * step(0.0, above) * step(f.y, 0.40)
              * (1.0 - clamp(above / max(0.80 * cyc, 0.01), 0.0, 1.0)) * life * 0.6;
        tOff = vec2(f.x - dx, 0.0) / tw * trail * 0.25;
    } else {
        float c = fract(t * spd * 0.03 + h2);
        dy = (h1 / max(dens, 0.01) - 0.5) * 0.7;
        life = smoothstep(0.0, 0.2, c) * (1.0 - smoothstep(0.65, 1.0, c));
        R *= 0.55;
    }
    vec2 d = f - vec2(dx, dy);
    d.y /= 1.25;                                                  // slightly teardrop-shaped
    float r = length(d) / R;
    float m = (1.0 - smoothstep(0.78, 1.0, r)) * life;
    float rim = smoothstep(0.45, 0.92, r) * (1.0 - smoothstep(0.92, 1.0, r)) * life;
    vec2 off = (-d / R * m + tOff) * (R / scale) * vec2(1.0 / aspect, 1.0) * 1.6;
    return vec4(off, rim, max(m, trail));
}

vec4 rainDrops(vec2 uv, float I, float T, float t) {
    float k = clamp((0.16 + 0.40 * I) * RAIN_LENS_DENSITY * (1.0 + 0.7 * T), 0.0, 0.92);
    float sp = RAIN_LENS_SPEED * (0.7 + 0.5 * I) * (1.0 + 1.8 * T);   // calm in drizzle, fast in thunderstorms
    float sz = RAIN_LENS_SIZE;
    vec4 a = rainLayer(uv, t, 4.5, 3.0, k * 0.55, sp, sz, true);
    vec4 b = rainLayer(uv, t, 8.0, 11.0, k * 0.80, sp * 1.2, sz, true);
    vec4 c = rainLayer(uv, t, 13.0, 23.0, k, sp, sz, false);
    vec4 d = rainLayer(uv, t, 22.0, 37.0, k, sp, sz, false);
    float st = RAIN_LENS_STRENGTH * (0.8 + 0.5 * T);
    vec4 r = a + b + c + d;
    return vec4(r.xy * st, r.z, clamp(r.w, 0.0, 1.0));
}
#endif

// ClDS: camera density inside the cloud volume (0 outside); smooth, so it fades in/out naturally
float cloudCamDensity() {
#if defined(CLOUD_DROPLETS) && CLOUD_MODE != 0 && CLOUD_MODE != 3
    float y0 = cloudOverallMinY();
    float y1 = cloudOverallMaxY();
    if (cameraPosition.y < y0 || cameraPosition.y > y1) return 0.0;
    pcDomeC = cameraPosition.xz;
    pcCamPos = cameraPosition;
    pcSetTime(pcSunWorld().y);
    pcEyeSetup();
    return smoothstep(0.02, 0.40, pcDensity(cameraPosition, frameTimeCounter * 0.05, false));
#else
    return 0.0;
#endif
}

// How much sunlight gets through the cloud layer toward the sun (1 = clear, 0 = fully covered).
// Marches from the camera along the sun direction through the real cloud density.
float sunCloudTransmit() {
#if CLOUD_MODE != 0 && CLOUD_MODE != 3
    vec3 Ls = pcSunWorld();
    if (Ls.y < 0.03) return 1.0;
    float y0 = cloudOverallMinY();
    float y1 = cloudOverallMaxY();
    float tE = max((y0 - cameraPosition.y) / Ls.y, 0.0);
    float tX = min((y1 - cameraPosition.y) / Ls.y, tE + 2500.0);
    if (tX <= tE) return 1.0;
    pcDomeC = cameraPosition.xz;
    pcCamPos = cameraPosition;
    pcSetTime(Ls.y);
    pcEyeSetup();
    float dt = (tX - tE) / 5.0;
    float od = 0.0;
    for (int i = 0; i < 5; i++) {
        vec3 p = cameraPosition + Ls * (tE + (float(i) + 0.5) * dt);
        od += pcDensity(p, frameTimeCounter * 0.05, false) * dt;
    }
    return exp(-od * pcSigma() * 0.9);
#else
    return 1.0;
#endif
}

// ClDS: water droplets on the lens. Each drop is a tiny lens (inverted refraction), appears at a random
// place, fades in, slides down slowly, fades out, then re-rolls a new position. Returns (uv offset, highlight).
vec3 cloudDrops(vec2 uv, float amt, float t) {
    float aspect = viewWidth / viewHeight;
    vec2 off = vec2(0.0);
    float shade = 0.0;
    for (int i = 0; i < 3; i++) {
        float sc = 5.0 + 5.5 * float(i);
        vec2 g = vec2(uv.x * aspect, uv.y) * sc + vec2(float(i) * 3.7, float(i) * 1.3);
        vec2 id = floor(g);
        vec2 f = fract(g);
        float h = dH(id + float(i) * 17.0);
        float cycle = 5.0 + 6.0 * dH(id + 2.3);
        float tt = t / cycle + h * 3.1;
        float ph = fract(tt);
        float gen = floor(tt);                                   // new random drop each cycle
        float life = smoothstep(0.0, 0.22, ph) * (1.0 - smoothstep(0.62, 1.0, ph));
        float present = step(0.30, dH(id + gen * 1.7 + 5.0));
        vec2 c = vec2(0.22 + 0.56 * dH(id + gen * 2.9 + 9.7), 0.85 - ph * 0.75 * (0.4 + 0.6 * h));
        float r = (0.11 + 0.10 * dH(id + gen + 4.4)) * (0.55 + 0.45 * amt);
        vec2 d = f - c;
        d.y *= 0.9;                                               // slightly elongated vertically
        float dist = length(d) / r;
        float k = life * present * amt;
        if (dist < 1.0) {
            float lens = 1.0 - dist * dist;
            off += (d / r) * lens * 0.034 * k;                    // lens: sampling away from centre = flipped, magnified image
            off.x += sin(d.y * 28.0 / r + t * 3.0) * 0.004 * lens * k;   // liquid wobble inside the drop
        }
        // thin wet trail left above the sliding drop (also pure distortion)
        float trail = smoothstep(0.035, 0.0, abs(d.x)) * step(0.0, d.y) * smoothstep(0.45, 0.0, d.y) * step(1.0, dist);
        off += vec2(d.x * 0.35, 0.0) * trail * 0.03 * k;
    }
    return vec3(off, shade);
}

float dN(vec2 p) {
    vec2 i = floor(p);
    vec2 fr = fract(p);
    fr = fr * fr * (3.0 - 2.0 * fr);
    return mix(mix(dH(i), dH(i + vec2(1.0, 0.0)), fr.x),
               mix(dH(i + vec2(0.0, 1.0)), dH(i + vec2(1.0, 1.0)), fr.x), fr.y);
}

// Water film on the lens after leaving water: the whole screen is warped in wavy horizontal bands,
// the bands scroll downward, and the film slides off from the top as the lens dries. Returns UV offset.
vec2 waterSlide(vec2 uv, float wet, float t) {
    float aspect = viewWidth / viewHeight;
    // film front: distortion stays below the line; the line sinks as wet falls (water slides down the screen)
    float line = wet * 1.35 - 0.15 + 0.05 * sin(uv.x * 6.0 + t * 0.8);
    float mask = 1.0 - smoothstep(line - 0.22, line, uv.y);
    float amt = clamp(wet * 1.6, 0.0, 1.0) * mask;
    if (amt < 0.001) return vec2(0.0);

    vec2 off = vec2(0.0);
    for (int i = 0; i < 3; i++) {
        float fy = (i == 0) ? 4.0 : ((i == 1) ? 9.0 : 19.0);       // band frequency (vertical)
        float sp = (i == 0) ? 0.55 : ((i == 1) ? 0.95 : 1.60);     // downward scroll speed
        float ax = (i == 0) ? 0.070 : ((i == 1) ? 0.030 : 0.012);  // horizontal push
        vec2 p = vec2(uv.x * aspect * 0.9 + float(i) * 3.1, uv.y * fy + t * sp);
        float n = dN(p) - 0.5;
        float m = dN(p * vec2(1.7, 1.0) + vec2(11.0, 5.0)) - 0.5;
        off.x += n * ax * 2.0;
        off.y += m * ax * 0.8;
    }
    return off * amt;
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

#ifdef UNDER_LAVA_FX
    if (isEyeInWater == 2) {
        c = underLava(texcoord);
    } else
#endif
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
        float cd = cloudCamDensity();
        if (cd > 0.01) {
            // ClDS: the droplets themselves are the screen distortion (like water on the lens after leaving water)
            vec3 dr = cloudDrops(uv, cd, frameTimeCounter);
            vec2 cuv = clamp(uv + dr.xy, vec2(0.002), vec2(0.998));
            c = texture(colortex0, cuv).rgb;
        } else if (wet > 0.01) {
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
#ifdef SCREEN_RAIN_DROPS
            float rainI = screenRain * smoothstep(0.35, 0.8, clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0));
            if (rainI > 0.01) {
                vec4 rd = rainDrops(uv, rainI, thunderStrength * rainI, frameTimeCounter);
                if (rd.w > 0.003) {
                    vec3 dc = texture(colortex0, clamp(uv + rd.xy, vec2(0.002), vec2(0.998))).rgb;
                    dc = dc * (1.0 - 0.10 * rd.w) + rd.z * 0.10 * vec3(0.85, 0.93, 1.0);
                    c = mix(c, dc, clamp(rd.w * 1.4, 0.0, 1.0));
                }
            }
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
    if (!UW_ON && isEyeInWater != 2) {
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
                    vec2 cuv = (cwp.xz + csd.xz / max(csd.y, 0.2) * dw) * 0.45 * CAUSTIC_SCALE;
                    float ct = frameTimeCounter * CAUSTIC_SPEED * 0.7;
                    float cau = causticPat(cuv * 0.6, ct * 0.6) + 0.4 * causticPat(cuv * 1.1 + 7.0, -ct * 0.7);
                    cau = smoothstep(0.25, 1.6, cau) * 0.45;   // soft, faint, blurry
                    float cf = exp(-dw * 0.05) * exp(-length(cp.xyz / cp.w) * 0.02) * cSun;
                    c += c * cau * cf * 1.0 * CAUSTIC_STRENGTH * vec3(0.55, 1.0, 0.95)
                       + vec3(0.30, 0.65, 0.65) * cau * cf * 0.04 * CAUSTIC_STRENGTH;
                }
            }
        }
#endif
        // blue-green water absorption: red dies first, then blue, leaving a murky teal
        // physically based absorption from the selected water type (red first, then blue-green murk)
        float uwDay = 0.25 + 0.75 * smoothstep(-0.1, 0.3, normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
        float uwCamD = max(UNDERWATER_SURFACE_Y - cameraPosition.y, 0.0);
        float uwDark = mix(exp(-uwCamD * 0.035 * PW_UW_DEPTH_DARKEN), 1.0, 0.12);   // deeper = darker, like real water
        vec3 uwFog = WATER_SCATTER * vec3(1.1, 1.25, 0.8) * 1.5 * UNDERWATER_BRIGHTNESS * uwDay * uwDark;
        c *= exp(-WATER_SIGMA * min(uz, 70.0) * 0.30 * UNDERWATER_ABSORB * UNDERWATER_FOG_STRENGTH / WATER_CLARITY);
        c *= mix(1.0, uwDark, 0.6);
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
        vec3 uCol = mix(uwFog * 0.45, uwFog * 1.3, clamp(uAcc, 0.0, 1.0) * 0.5);
        c = mix(c, uCol, clamp(uAcc, 0.0, 0.95));
        c = mix(c, uwFog * 0.55, smoothstep(18.0, 50.0, uz));   // nothing far away is visible underwater
        c = mix(c, uwFog * 0.55, 1.0 - exp(-uz * 0.045 * UNDERWATER_FOG_STRENGTH));
        // Snell's window: looking up you see a bright circle of sky (about 97 degrees wide); outside it the
        // surface mirrors the dark water, like in real underwater photography
        if (texture(depthtex0, texcoord).r > 0.9999 && uvd.y > 0.0) {
            float wob = 0.025 * sin(uvd.x * 38.0 + frameTimeCounter * 1.3) * sin(uvd.z * 33.0 - frameTimeCounter * 1.1);
            float win = smoothstep(0.6585 - 0.05, 0.6585 + 0.07, uvd.y + wob);
            vec3 winSky = vec3(0.45, 0.80, 0.82) * uwDay * 1.1 * (1.0 - 0.5 * clamp(rainStrength, 0.0, 1.0));
            c = mix(c, mix(uwFog * 0.5, winSky, win), PW_UW_SNELL * smoothstep(0.0, 0.25, uvd.y) * exp(-uwCamD * 0.05));
        }
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
                c += vec3(0.38, 0.75, 0.62) * uwDay * uwDark * clamp(ur, 0.0, 0.3);
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
        exv = clamp(mix(1.0, exv, EYE_ADAPTATION_STRENGTH), 0.8, 1.5);
        exv *= 1.0 - 0.10 * stormAboveCloud(cameraPosition.y);   // bright sun above the storm: eyes squint a little
        c *= exv;
        // overexposure bleaches highlights toward white and softens contrast
        float over = clamp(exv - 1.0, 0.0, 1.0);
        c = mix(c, vec3(max(max(c.r, c.g), c.b)), over * 0.15);
        c = mix(c, vec3(1.0), over * over * 0.05);
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
        // clouds in front of the sun really block its glare and lens flare
        float sunT = 1.0;
        if (sunUp > 0.01 && inB > 0.5) sunT = sunCloudTransmit();
        vis *= mix(0.10, 1.0, smoothstep(0.05, 0.70, sunT));
        float halo = pow(cs, 12.0) * 0.045 + pow(cs, 60.0) * 0.07 + pow(cs, 400.0) * 0.06;
        vec2 dd = (texcoord - sUV) * vec2(viewWidth / viewHeight, 1.0);
        float streak = exp(-abs(dd.y) * 55.0) * exp(-abs(dd.x) * 3.5) * 0.03 * inB;
        float gl = (halo + streak) * sunUp * vis * (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength) * (1.0 - stormAboveCloud(cameraPosition.y)))) * SUN_GLARE_STRENGTH;
        c += vec3(1.0, 0.88, 0.68) * gl * 0.7;
#ifdef SUN_FLARE
        {
            vec2 asp = vec2(viewWidth / viewHeight, 1.0);
            float fOff = smoothstep(0.1, 0.7, length(sUV - 0.5) * 2.0);
            float fAmt = inB * sunUp * mix(0.3, 1.0, vis) * (0.4 + 0.6 * fOff)
                       * (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength) * (1.0 - stormAboveCloud(cameraPosition.y)))) * SUN_FLARE_STRENGTH;
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
                float mWx = (1.0 - smoothstep(0.0, 0.3, max(rainStrength, thunderStrength) * (1.0 - stormAboveCloud(cameraPosition.y))));
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
