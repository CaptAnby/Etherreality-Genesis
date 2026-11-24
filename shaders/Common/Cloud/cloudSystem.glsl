#ifndef PHENYX_CLOUD_SYSTEM_GLSL
#define PHENYX_CLOUD_SYSTEM_GLSL
#include "/Common/Wind/globalWind.glsl"
#include "/Common/Cloud/stormEye.glsl"

// ============================================================
// CLOUD SYSTEM (new, compact, Photon/Bliss-inspired)
//  - one cumulus slab: coverage map + per-cloud height, flat bases, domed tops, billow erosion
//  - cheap 4-tap light march, Beer + multi-scatter approximation, silver lining, sunset colours
//  - thin stretched cirrus plane
//  - mode 2: blocky vanilla-style 3D slabs
//  - ground shadows from the same density field
// Entry points used by deferred passes:
//   renderVolumetricClouds, cloudOverallMinY/MaxY, grandCloudGroundShadowFactor, CLOUD_VIEW_DISTANCE
// ============================================================

#ifndef CLOUD_UNIFORMS_PROVIDED
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;
#endif

#define CLOUD_VIEW_DISTANCE 5000.0
#define CLOUD_CIRRUS_Y 720.0

// ---------------- noise ----------------
float pcHash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float pcNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(pcHash(i), pcHash(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(pcHash(i + vec3(0.0, 1.0, 0.0)), pcHash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(mix(pcHash(i + vec3(0.0, 0.0, 1.0)), pcHash(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(pcHash(i + vec3(0.0, 1.0, 1.0)), pcHash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
        f.z);
}

// cheap 2x2x2 cellular noise: returns 0 (cell centre) .. ~1 (cell border)
float pcWorley(vec3 p) {
    vec3 b = floor(p - 0.5);
    float d = 1.0;
    for (int k = 0; k < 8; k++) {
        vec3 o = vec3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1));
        vec3 c = b + o;
        vec3 fp = c + vec3(pcHash(c), pcHash(c + 13.7), pcHash(c + 29.3));
        d = min(d, length(p - fp));
    }
    return clamp(d, 0.0, 1.0);
}

// normalised to roughly 0..1
float pcFbm(vec3 p, int octaves) {
    float a = 0.5;
    float r = 0.0;
    float w = 0.0;
    for (int i = 0; i < 4; i++) {
        if (i >= octaves) break;
        r += a * pcNoise(p);
        w += a;
        p = p * 2.03 + 17.1;
        a *= 0.5;
    }
    return r / w;
}

// ---------------- dome (DyDP): clouds curve down toward the horizon ----------------
#define CLOUD_SLAB_THICK 18.0   // volumetric vanilla-style: slightly taller slabs
#define CLOUD_B_GAP 90.0
#define CLOUD_B_THICK 55.0
#define CLOUD_DOME_K 5.0e-5
#define CLOUD_DOME_MAX 180.0
#define CLOUD_DOME_LIFT 40.0
vec2 pcDomeC = vec2(0.0);
vec3 pcCamPos = vec3(0.0);   // absolute camera position (set by the pass)
vec3 pcSunDirG = vec3(0.0, 1.0, 0.0);   // world sun direction (set by the pass)
float pcNoonK = 0.0;                    // 0..1 how 'noon' the time of day is
float pcEyeAmt = 0.0;        // eye of the storm: strength (0 = off)
float pcDomeDrop(vec2 xz) {
    vec2 d = xz - pcDomeC;
    return min(dot(d, d) * CLOUD_DOME_K, CLOUD_DOME_MAX) - CLOUD_DOME_LIFT;
}

// ---------------- layer bounds ----------------
float cloudOverallMinY() {
#if CLOUD_MODE == 2
    return CLOUD_ALTITUDE;
#else
    return stormAlt() - CLOUD_DOME_MAX + CLOUD_DOME_LIFT;
#endif
}

float cloudOverallMaxY() {
#if CLOUD_MODE == 2
    return CLOUD_ALTITUDE + CLOUD_SLAB_THICK;
#else
    return stormAlt() + stormThick() + CLOUD_B_GAP + CLOUD_B_THICK + CLOUD_DOME_LIFT;
#endif
}

vec2 pcWind(float time, float mult) {
    // GlWS: shared direction; SmGS-style gust as a sum of slow sines (integrated, so position never jumps)
    float g = 0.35 * sin(time * 0.9) + 0.12 * sin(time * 2.3 + 1.7);
    g *= 1.0 + clamp(wxThunder, 0.0, 1.0);
    return glwsDir() * (time * 1.25 + g) * CLOUD_SPEED * 16.0 * mult;   // a bit stronger than before; constant so weather changes never jump clouds
}

// ---------------- density ----------------
// mode 2: vanilla-style flat, square slabs on a 12-block cell grid (small corner rounding only)
float pcCellOn(vec2 c) {
    // mostly smooth noise -> big connected, square-edged vanilla masses; only a little per-cell
    // randomness, so small isolated single-block clouds are rare
    float n = 0.92 * pcNoise(vec3(c * 0.2, 3.0)) + 0.08 * pcHash(vec3(c, 7.0));
    return step(0.545, n);
}
float pcSlabDensity(vec3 p, float time) {
    vec2 q = (p.xz + pcWind(time, 1.0)) / 12.0;
    vec2 c = floor(q);
    vec2 f = fract(q);
    f = smoothstep(0.38, 0.62, f);   // steep blend -> square blocks, only tiny corner rounding
    float a = pcCellOn(c);
    float b = pcCellOn(c + vec2(1.0, 0.0));
    float d = pcCellOn(c + vec2(0.0, 1.0));
    float e = pcCellOn(c + vec2(1.0, 1.0));
    // blending the binary cells rounds every corner; thresholding at 0.5 keeps block-sized shapes
    float m = mix(mix(a, b, f.x), mix(d, e, f.x), f.y) - 0.5;
    float cover = smoothstep(-0.02, 0.06, m);
    // pillow cross-section: thinner toward the edges so the sides curve over and under
    float h = (p.y - CLOUD_ALTITUDE) / CLOUD_SLAB_THICK;
    float halfH = 0.5 * sqrt(clamp((m + 0.04) / 0.12, 0.0, 1.0));
    float vert = 1.0 - smoothstep(halfH - 0.07, halfH, abs(h - 0.5));
    return cover * vert;
}

// ---------------- time-of-day formations ----------------
float pcTwi = 0.0;     // sunrise/sunset weight
float pcCovAdj = 0.0;  // coverage threshold shift (negative = more cloud)
float pcSclMul = 1.0;  // formation scale (smaller = larger clouds)
float pcRamp = 0.34;   // edge softness (bigger = mistier)
float pcYMul = 1.4;    // vertical noise stretch (smaller = taller clouds)
float pcBCov = 0.05;   // upper layer threshold offset
// Photon-style dynamic weather: slowly evolving, continuous weather noise over game time (not per-day steps).
// Coverage, tall 'congestus' towers, streaky altostratus-like sheets, high cirrus/cirrocumulus and clear-sunset spells all
// drift in and out smoothly, so the sky is different from day to day and morphs gradually within a day.
uniform int worldDay;
uniform int worldTime;
float pcCovRand = 0.0;    // weather coverage offset
float pcHero = 0.0;       // tall cumulus congestus towers
float pcStreakB = 0.0;    // streaky, wind-stretched altostratus-like zones
float pcClearK = 0.0;     // occasional clearer sunset: mostly stretched cirrus and small clouds

float pcDayRand(float n) {
    return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}
// smooth 1D value noise over game time
float pcWx1(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(pcDayRand(i), pcDayRand(i + 1.0), f);
}
// two octaves: slow main drift + a gentler faster ripple
float pcWx(float x, float seed) {
    x += seed;
    return 0.65 * pcWx1(x) + 0.35 * pcWx1(x * 2.7 + 9.1);
}

void pcSetTime(float sy) {
    float s0 = max(sy, 0.0);
    pcTwi = 1.0 - smoothstep(0.05, 0.38, s0);
    float noon = smoothstep(0.62, 0.85, sy);
    float day = clamp(1.0 - pcTwi - noon, 0.0, 1.0);
    // noon: clean sky, few LARGE cumulus | day: normal cumulus | sunrise/sunset: dense banks + cirrocumulus patches
    pcNoonK = noon;
    // morning/afternoon: dense, large formations | noon: almost clear sky | sunset: dense banks near sun/horizon + cirrus
    pcCovAdj = day * -0.12 + noon * 0.22 + pcTwi * -0.06;
    pcSclMul = day * 0.90 + noon * 0.55 + pcTwi * 0.90;
    pcBCov = pcTwi * 1.0 + day * 0.10;   // cirrus / cirrocumulus: strong at sunrise/sunset, none at noon

    // continuous game time in days (never jumps: worldDay and worldTime roll over together)
    float T = float(worldDay) + float(worldTime) / 24000.0;
    float ta = fract(sunAngle);                 // 0 sunrise, 0.25 noon, 0.5 sunset

    pcCovRand = (pcWx(T * 0.90, 3.0) - 0.5) * 0.30 * (1.0 - 0.75 * noon);   // weather randomness no longer overrides noon clearing
    pcHero    = smoothstep(0.52, 0.74, pcWx(T * 0.80, 11.0));
    pcHero    = max(pcHero, max(0.55 * day, 0.85 * noon));   // larger, bolder cumulus masses by day and especially at noon
    pcStreakB = smoothstep(0.52, 0.74, pcWx(T * 0.70, 23.0));
    pcBCov   += 0.5 * smoothstep(0.50, 0.72, pcWx(T * 0.60, 41.0)) * (1.0 - noon);   // days with lots of high cirrus / cirrocumulus

    // ---- occasional clear-sunset spells: the low clouds thin out and shrink, leaving a mostly open sky with
    // stretched cirrus and a few small clouds. The spell drifts in over the day, then eases out after dusk.
    float clearW = smoothstep(0.58, 0.74, pcWx(T * 0.55, 55.0));
    pcClearK = clearW * smoothstep(0.30, 0.44, ta) * (1.0 - smoothstep(0.54, 0.68, ta));
    pcCovAdj += pcTwi * 0.07 * pcClearK;
    pcBCov = max(pcBCov, pcClearK);
}

// mode 1: two altitude layers
//   layer A (low): cumulus with crisp cauliflower edges, flat bases; at sunrise/sunset flat dense banks near the horizon
//   layer B (high): cirrocumulus - patches of small rippled rows
// detail=false skips the fine erosion (light march / ground shadows)
float pcCumulusDensityRaw(vec3 p, float time, bool detail) {
    float yy = p.y + pcDomeDrop(p.xz);
    float hA = (yy - stormAlt()) / stormThick();
    float hB = (yy - (stormAlt() + stormThick() + CLOUD_B_GAP)) / CLOUD_B_THICK;
    float sz = 1.0 / max(CLOUD_SIZE, 0.2);
    sz *= mix(mix(1.0, 0.78, rainBuild()), 0.6, stormBuild());   // rain: larger chunks, thunder: largest

    if (hB > 0.0 && hB < 1.0) {
        if (pcBCov < 0.05) return 0.0;
        vec2 xzB = p.xz + pcWind(time, 1.4);
        float cirPatch = pcFbm(vec3(xzB * 0.0048 * sz, 40.0), 2);
        float gate = smoothstep(0.60 - 0.14 * pcBCov - 0.10 * pcClearK, 0.82 - 0.14 * pcBCov - 0.10 * pcClearK, cirPatch);
        if (gate <= 0.001) return 0.0;
        // many small soft puffs (repeated, slightly aligned) sitting in a foggy patch
        float u = dot(xzB, vec2(0.6, 0.8));
        float warp = pcNoise(vec3(xzB * 0.006, 5.0)) * 6.0;
        float rows = 0.5 + 0.5 * sin(u * 0.10 + warp);
        vec2 wB = glwsDir();
        vec2 pB = vec2(-wB.y, wB.x);
        vec2 cq = mix(xzB * 0.045, vec2(dot(xzB, wB) * 0.010, dot(xzB, pB) * 0.085), pcClearK);   // stretched into cirrus streaks
        float cells = pcFbm(vec3(cq, 9.0), 2);
        float m = rows * 0.04 + cells * 0.96;
        float vp = smoothstep(0.0, 0.35, hB) * (1.0 - smoothstep(0.45, 1.0, hB));
        float puffs = smoothstep(0.34, 0.90, m);
        puffs *= puffs * (3.0 - 2.0 * puffs) * 0.8 + 0.2 * puffs;   // softer, cleaner puffs
        float fog = 0.22 * smoothstep(0.30, 0.70, cirPatch);   // thin haze between the puffs
        return clamp(puffs + fog, 0.0, 1.0) * gate * vp * 0.75;
    }

    if (hA <= 0.0 || hA >= 1.0) return 0.0;
    vec2 xz = p.xz;
    if (pcEyeAmt > 0.001) {
        vec2 ec;
        stormEyeNearest(p.xz, ec);
        xz = stormEyeSwirl(p.xz, ec, pcEyeAmt, p.y);
    }
    xz += pcWind(time, 1.0);

    // Nebula Cosmic Cloud texture: soft 3D fbm + soft smoothstep, with flat base / rounded top
    float far = smoothstep(300.0, 1800.0, length(p.xz - pcDomeC));
    float rel = hA;
    // NaRCF: formation regions - compact cumulus vs broad low stratocumulus; storms build cumulonimbus
    float fType = pcNoise(vec3(xz * 0.0009 * sz, 17.0));
    float strat = smoothstep(0.58, 0.72, fType);
    float stormW = clamp(wxThunder, 0.0, 1.0);
    // cinematic formations: occasional 'hero' cumulus towers (bold, tall, lumpy) and zones of wind-stretched streaky cloud
    float hero = smoothstep(0.62 - 0.14 * pcHero, 0.80 - 0.14 * pcHero, pcFbm(vec3(xz * 0.0007 * sz, 71.0), 2)) * (1.0 - strat);
    float streakZone = smoothstep(0.58 - 0.14 * pcStreakB, 0.76 - 0.14 * pcStreakB, pcFbm(vec3(xz * 0.0006 * sz, 83.0), 2)) * (1.0 - hero);
    rel = hA / (mix(1.0, 0.55, strat) * (1.0 - 0.35 * pcClearK));   // clear sunsets: smaller, shallower clouds
    if (rel >= 1.0) return 0.0;
    float hprof = smoothstep(0.0, 0.12, rel) * (1.0 - smoothstep(0.45, 1.0, rel));
    hprof *= mix(1.0, 0.6, far * pcTwi);                   // flatter horizon banks at sunrise/sunset

    // Photon-like layout: sunrise/sunset clouds stretch into long broken sheets along the horizon
    // constant noise scale (never tied to time of day) so time transitions can not make clouds slide fast
    vec3 q = vec3(xz.x, yy * 1.1 + time * 6.0, xz.y) * 0.0085 * sz;
    float n = pcFbm(q, 3);
    float thr = mix(0.62, 0.44, CLOUD_COVERAGE) + pcCovAdj - 0.08 * clamp(wxRain, 0.0, 1.0);
    thr += strat * -0.04 - stormW * 0.05;                 // stratocumulus broader, storms a bit denser (but still broken, textured)
    thr += pcCovRand;                                     // random formation variety through the day
    thr -= 0.07 * hero;                                   // hero towers: dense, well-defined masses
    thr += pcTwi * (0.06 * (1.0 - far) - 0.14 * far) * (1.0 - 0.85 * pcClearK);   // twilight: denser toward horizon (not on clear sunsets)
    // broad cloudy / clearer regions (Photon-style variety of coverage across the sky)
    // compact cloudy regions separated by clear gaps; individual clouds live inside the regions
    float region = smoothstep(0.32, 0.68, pcFbm(vec3(xz * 0.0019 * sz, 31.0), 2));
    thr += (0.5 - region) * 0.34 * (1.0 + 0.9 * pcNoonK);   // noon: wider clear gaps between the few clouds
    {   // sunrise/sunset: dense cloud banks gather around the sun
        vec3 toP = normalize(p - pcCamPos);
        float sunNear = pow(max(dot(toP, pcSunDirG), 0.0), 3.0);
        thr -= 0.12 * pcTwi * sunNear;
    }
    // cauliflower: cellular lumps modulate the soft fbm (placement still comes from the fbm, so no dots)
    float lump = 1.0 - pcWorley(q * 2.2 + 4.0);
    float v = n + 0.16 * (hprof - 0.5) + 0.26 * (1.0 + 0.35 * hero) * (lump - 0.45) * (0.4 + 0.6 * hprof);
    {
        vec2 wdc = glwsDir();
        vec2 prc = vec2(-wdc.y, wdc.x);
        float sn = pcNoise(vec3(dot(xz, wdc) * 0.0030 * sz, dot(xz, prc) * 0.0110 * sz, yy * 0.012 + 5.0));
        v += (sn - 0.5) * 0.34 * streakZone;                  // long, elongated streaks drifting with the wind
    }
    v += (pcNoise(q * 3.0 + 11.0) - 0.5) * 0.24;           // scattered, ragged edges
    float shape = smoothstep(thr - 0.10, thr + 0.38, v);   // wide ramp = dense fog fading out
    shape *= shape;                                        // edges thin and transparent, core stays dense
    if (shape <= 0.001) return 0.0;

    if (detail) {
        float l2 = 1.0 - pcWorley(q * 5.0 + 9.0);
        shape -= (0.5 - l2) * 0.14 * CLOUD_EROSION * (1.0 + 0.9 * stormW) * (1.0 - 0.5 * shape);   // storms: more billowy detail
    }
    return clamp(shape, 0.0, 1.0) * smoothstep(0.0, 0.08, rel);
}

// cloud density with the eye of the storm cut out (smooth hole) and a slightly denser eye wall
float pcCumulusDensity(vec3 p, float time, bool detail) {
    float d = pcCumulusDensityRaw(p, time, detail);
    if (pcEyeAmt > 0.001) {
        vec2 ec;
        float dd = stormEyeNearest(p.xz, ec);
        float er = stormEyeClearR(p.y);
        float ew = stormEyeWallW(p.y);
        if (dd < er + ew * 1.8) {
            // billowing, spiralling wall: the wall radius is pushed in and out by cloud-sized noise that twists with height,
            // so the tunnel is built from cumulus lobes (like looking up the inside of a real eye), not a smooth tube
            vec2 rel = p.xz - ec;
            float tw = p.y * 0.0045 + dd * 0.004;
            float cs = cos(tw), sn = sin(tw);
            vec2 rr = vec2(cs * rel.x - sn * rel.y, sn * rel.x + cs * rel.y);
            float bn = pcFbm(vec3(rr * 0.022, p.y * 0.030), 2);
            float dEff = dd + (bn - 0.5) * ew * 0.8;
            float hole = 1.0 - stormEyeSmooth((dEff - er) / ew);
            d *= 1.0 + 0.30 * pcEyeAmt * stormEyeWallBell(dEff, p.y);
            // erode rather than cut: thin cloud disappears first, so the rim frays into wisps
            d = max(d - pcEyeAmt * hole * 1.3, 0.0) * (1.0 - smoothstep(0.80, 1.0, hole) * pcEyeAmt);
        }
    }
    return min(d, 1.5);
}

float pcDensity(vec3 p, float time, bool detail) {
#if CLOUD_MODE == 2
    return step(CLOUD_ALTITUDE, p.y) * step(p.y, CLOUD_ALTITUDE + CLOUD_SLAB_THICK) * pcSlabDensity(p, time);
#else
    return pcCumulusDensity(p, time, detail);
#endif
}

float pcSigma() {
#if CLOUD_MODE == 2
    return 0.40;
#else
    return 0.055 * CLOUD_DENSITY;
#endif
}

// ---------------- celestial light ----------------
vec3 pcSunWorld() {
    return normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
}

vec3 pcMoonWorld() {
    return normalize(mat3(gbufferModelViewInverse) * normalize(moonPosition));
}

// call after pcSetTime(): places the eye of the storm for this frame
void pcEyeSetup() {
    pcEyeAmt = stormEyeAmount(thunderStrength);
}

// returns direction of the active light and fills colour + ambient
vec3 pcLight(out vec3 lightCol, out vec3 ambCol) {
    vec3 sunW = pcSunWorld();
    vec3 moonW = pcMoonWorld();
    float sy = sunW.y;
    float dayF = smoothstep(-0.12, 0.25, sy);
    float twi = (1.0 - smoothstep(0.0, 0.32, abs(sy))) * smoothstep(-0.2, 0.0, sy);

    float airMass = 1.0 / (max(sy, 0.0) + 0.10);
    vec3 trans = exp(-vec3(0.035, 0.085, 0.19) * airMass);
    trans /= max(max(trans.r, trans.g), trans.b);
    vec3 sunCol = mix(vec3(1.0, 0.93, 0.80), trans, twi) * mix(0.96, 0.68, twi) * smoothstep(-0.04, 0.12, sy);
    vec3 moonCol = vec3(0.42, 0.52, 0.78) * 0.20 * smoothstep(-0.04, 0.12, moonW.y);

    float s = sin(sunAngle * 6.2831853);
    vec3 L = (s >= 0.0) ? sunW : moonW;
    lightCol = (s >= 0.0) ? sunCol : moonCol;

    vec3 dayAmb = vec3(0.60, 0.64, 0.78) * 0.68;
    vec3 nightAmb = vec3(0.045, 0.060, 0.120);
    ambCol = mix(nightAmb, dayAmb, dayF) + vec3(0.30, 0.17, 0.18) * twi * 0.55;
    return L;
}

// ---------------- light march (4 taps) ----------------
float pcLightOD(vec3 p, vec3 L, float time) {
    float od = 0.0;
    float len = 10.0;
    float dist = 0.0;
    for (int i = 0; i < 3; i++) {
        dist += len;
        od += pcDensity(p + L * dist, time, false) * len;
        len *= 2.0;
    }
    return od * pcSigma() * 0.62;
}

// ---------------- main renderer ----------------
vec4 renderVolumetricClouds(
    vec3 ro,
    vec3 rd,
    vec3 lightDirIgnored,
    float dither,
    float maxDist
) {
    float time = frameTimeCounter * 0.05;
    pcDomeC = ro.xz;
    pcCamPos = ro;
    pcSunDirG = pcSunWorld();
    pcSetTime(pcSunDirG.y);
    pcEyeSetup();
    float y0 = cloudOverallMinY();
    float y1 = cloudOverallMaxY();

    vec3 lightCol;
    vec3 ambCol;
    vec3 L = pcLight(lightCol, ambCol);

    float aboveK = stormAboveCloud(pcCamPos.y);
    float rainW = clamp(wxRain, 0.0, 1.0) * (1.0 - aboveK);
    float stormW = clamp(wxThunder, 0.0, 1.0) * (1.0 - aboveK);   // above the tops: sunlit, not dimmed
    float weatherDim = mix(1.0, 0.55, rainW) * mix(1.0, 0.78, stormW);
    vec3 weatherTint = mix(vec3(1.0), vec3(0.82, 0.86, 0.92), max(rainW, stormW));

    float cosT = dot(rd, L);
    float phase = 0.75 + 0.42 * pow(max(cosT, 0.0), 6.0) * CLOUD_SILVER + 0.10 * max(-cosT, 0.0);
    float sigma = pcSigma();

    vec3 scattered = vec3(0.0);
    float T = 1.0;

    // ---------- cumulus slab ----------
    float tEnter = 0.0;
    float tExit = 0.0;
    bool hit = true;
    if (abs(rd.y) < 1e-4) {
        hit = (ro.y >= y0 && ro.y <= y1);
        tExit = CLOUD_VIEW_DISTANCE;
    } else {
        float ta = (y0 - ro.y) / rd.y;
        float tb = (y1 - ro.y) / rd.y;
        tEnter = max(min(ta, tb), 0.0);
        tExit = max(ta, tb);
        hit = tExit > 0.0;
    }
    tExit = min(tExit, min(maxDist, CLOUD_VIEW_DISTANCE));
    tExit = min(tExit, min(tEnter + 1800.0, 2400.0));

    if (hit && tExit > tEnter) {
#if CLOUD_QUALITY == 0
        const int STEPS = 18;
#elif CLOUD_QUALITY == 2
        const int STEPS = 36;
#else
        const int STEPS = 26;
#endif
        float dt = (tExit - tEnter) / float(STEPS);
        for (int i = 0; i < STEPS; i++) {
            if (T < 0.02) break;
            float t = tEnter + (float(i) + dither) * dt;
            vec3 p = ro + rd * t;
            float dens = pcDensity(p, time, true);
            float fade = 1.0 - smoothstep(500.0, 2400.0, t);
            dens *= fade;
            if (dens <= 0.003) continue;

            float od = pcLightOD(p, L, time);
            float beer = exp(-od);
            float multi = max(beer, mix(0.44, 0.26, stormW) * exp(-od * 0.20));   // soft, gentle self-shadow on the unlit side
            float hf = clamp((p.y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
            float thin = exp(-dens * 3.0);

            vec3 sunTerm = lightCol * multi * phase;
            sunTerm += lightCol * thin * CLOUD_SILVER * 0.22 * pow(max(cosT, 0.0), 3.0) * beer;
            vec3 ambTerm = ambCol * mix(0.55, 1.15, hf) * CLOUD_AMBIENT;

            // IlE: subtle, density-aware edge illumination (thin edges, light-facing side)
            float edgeI = (1.0 - smoothstep(0.02, 0.30, dens)) * (0.10 + 0.22 * pow(max(cosT, 0.0), 4.0));
            sunTerm += lightCol * edgeI * beer * 0.5;

            // eye of the storm: calm, sunlit clouds around the hole instead of dark storm clouds
            float eyeD = 1.0e5;
            float eyeR = 1.0;
            float eyeW = 1.0;
            if (pcEyeAmt > 0.001) {
                vec2 ec;
                eyeD = stormEyeNearest(p.xz, ec);
                eyeR = stormEyeClearR(p.y);
                eyeW = stormEyeWallW(p.y);
            }
            float eyeNear = pcEyeAmt * (1.0 - smoothstep(eyeR, eyeR + eyeW * 2.5, eyeD));
            float eyeWall = pcEyeAmt * stormEyeWallBell(eyeD, p.y);
            vec3 lit = (sunTerm * (1.0 + 0.30 * eyeNear * STORM_EYE_LIGHT) + ambTerm) * mix(weatherTint, vec3(1.0), eyeNear * 0.8);
            lit *= mix(weatherDim, 1.0, eyeNear * 0.55);
            lit += lightCol * eyeWall * (0.02 + 0.10 * thin) * (0.4 + 0.6 * beer) * STORM_EYE_LIGHT;   // bright sunlit eye wall

            // storm clouds: dark bases, bright tops, so the billows read as textured relief instead of a flat grey blanket
            float hSlab = clamp((p.y - stormAlt()) / max(stormThick(), 1.0), 0.0, 1.0);
            lit *= mix(1.0, 0.60 + 0.70 * hSlab, stormW);

            float stepT = exp(-dens * sigma * mix(1.0, 0.7, stormW) * dt);
            scattered += lit * (1.0 - stepT) * T;
            T *= stepT;
        }
    }

    // ---------- thin cirrus plane ----------
#if 0
    if (CLOUD_CIRRUS > 0.001 && rd.y > 0.02 && ro.y < CLOUD_CIRRUS_Y) {
        float tc = (CLOUD_CIRRUS_Y - ro.y) / rd.y;
        if (tc < maxDist) {
            vec2 cxz = ro.xz + rd.xz * tc + pcWind(time, 2.5);
            float cn = pcFbm(vec3(cxz.x * 0.0009, cxz.y * 0.0034, 5.0), 3);
            float cd = smoothstep(0.50, 0.80, cn) * CLOUD_CIRRUS * 0.60;
            cd *= 1.0 - smoothstep(9000.0, 30000.0, tc);
            if (cd > 0.003) {
                vec3 cLit = (lightCol * (0.75 + 0.5 * pow(max(cosT, 0.0), 6.0)) + ambCol * 0.9) * weatherTint * weatherDim;
                scattered += cLit * cd * T;
                T *= 1.0 - cd;
            }
        }
    }
#endif

    // smooth blend into the horizon: fade out as the ray flattens toward it (no hard cut)
    float hz = (ro.y < y1) ? smoothstep(0.0, 0.12, abs(rd.y)) : 1.0;
    // soft highlight shoulder: bright cloud areas roll off into a creamy off-white instead of clipping to pure white,
    // so cloud shapes and the terrain behind stay readable
    scattered = max(scattered, vec3(0.0));
    float cm = max(scattered.r, max(scattered.g, scattered.b));
    scattered /= 1.0 + 0.42 * max(cm - 0.86, 0.0);
    scattered *= mix(vec3(1.0), vec3(1.0, 0.955, 0.885), smoothstep(0.40, 1.0, cm)) * vec3(1.02, 1.0, 0.965);
    return vec4(scattered * hz, clamp(1.0 - T, 0.0, 1.0) * hz);
}

// ---------------- ground shadows ----------------
float grandCloudGroundShadowFactor(vec3 absPos, float time) {
#if CLOUD_MODE == 0 || CLOUD_MODE == 3
    return 1.0;
#else
    vec3 L = pcSunWorld();
    pcDomeC = absPos.xz;
    pcSetTime(L.y);
    pcEyeSetup();
    if (L.y < 0.08) return 1.0;
    float y0 = cloudOverallMinY();
    float y1 = cloudOverallMaxY();
    if (absPos.y >= y1) return 1.0;

    float od = 0.0;
    for (int i = 0; i < 4; i++) {
        float y = mix(y0, y1, (float(i) + 0.5) / 4.0);
        float t = (y - absPos.y) / L.y;
        if (t > 0.0) {
            od += pcDensity(absPos + L * t, time, false);
        }
    }
    float seg = (y1 - y0) / 4.0 / max(L.y, 0.25);
    float trans = exp(-od * seg * pcSigma() * 0.5);
    float sunFade = smoothstep(0.08, 0.30, L.y);
    return mix(1.0, mix(0.18, 1.0, trans), sunFade);
#endif
}

#endif
