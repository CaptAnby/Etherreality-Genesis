#version 330 compatibility
#include "/settings.glsl"

// ============================================================
// ETHERREALITY GENESIS :: REAL-LIFE SKY (soft, Rayleigh-style)
// Zenith AND horizon colors both change with sun elevation.
// ============================================================

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;
uniform int renderStage;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform int worldDay;
#include "/Common/Cloud/stormEye.glsl"
#include "/Common/Wind/globalWind.glsl"
#ifdef CONSTELLATIONS
#include "/Common/Sky/constellations.glsl"
#endif

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// 7-key ramp over sun elevation (sin of angle). Keys follow real twilight stages:
// night(<-18deg) | astronomical(-12) | nautical/civil end(-6) | sunset(0) | low sun | morning | noon
vec3 ramp7(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f, vec3 g) {
    vec3 r = mix(a, b, smoothstep(-0.31, -0.21, s));
    r = mix(r, c, smoothstep(-0.21, -0.105, s));
    r = mix(r, d, smoothstep(-0.105, -0.02, s));
    r = mix(r, e, smoothstep(-0.02, 0.08, s));
    r = mix(r, f, smoothstep(0.08, 0.30, s));
    r = mix(r, g, smoothstep(0.30, 1.0, s));
    return r;
}

#ifdef NEBULA_SKY
float nHash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float nNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(nHash(i), nHash(i + vec3(1,0,0)), f.x),
                   mix(nHash(i + vec3(0,1,0)), nHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(nHash(i + vec3(0,0,1)), nHash(i + vec3(1,0,1)), f.x),
                   mix(nHash(i + vec3(0,1,1)), nHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float nFbm(vec3 p) {
    float a = 0.5, r = 0.0;
    for (int i = 0; i < 4; i++) { r += a * nNoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
    return r;
}
#endif

#ifdef HORIZON_CIRRUS
// ---- low horizon cirrus (pure visual, unreachable) ----
float hzHash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float hzNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hzHash(i), hzHash(i + vec2(1.0, 0.0)), f.x),
               mix(hzHash(i + vec2(0.0, 1.0)), hzHash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float hzFbm(vec2 p) {
    float a = 0.5, r = 0.0;
    for (int i = 0; i < 3; i++) { r += a * hzNoise(p); p = p * 2.07 + 5.3; a *= 0.5; }
    return r;
}
#endif

void main() {
    float rainW  = clamp(wxRain, 0.0, 1.0);
    float stormW = clamp(wxThunder, 0.0, 1.0);

    vec3 sunDir  = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);
    vec3 up      = normalize(upPosition);

    float sh    = dot(sunDir, up);
    float day   = smoothstep(-0.12, 0.30, sh);
    float tw    = exp(-pow((sh + 0.02) * 2.9, 2.0));
    float night = 1.0 - smoothstep(-0.20, 0.02, sh);

    // ---------------- STARS ----------------
    if (renderStage == MC_RENDER_STAGE_STARS) {
        float vis = night * (1.0 - rainW) * (1.0 - 0.5 * tw);
        float tw2 = 0.88 + 0.12 * sin(frameTimeCounter * 1.7 + gl_FragCoord.x * 0.37 + gl_FragCoord.y * 0.53);
        color = vec4(vec3(0.82, 0.90, 1.0) * 1.6 * tw2 * STAR_BRIGHTNESS, clamp(vis, 0.0, 1.0));
        return;
    }

    // ---------------- VIEW RAY ----------------
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec3 dir = normalize(p.xyz / p.w);

    float h  = dot(dir, up);
    float hp = max(h, 0.0);

    // eye of the storm: clear, un-dimmed sky seen through the hole in the clouds
    float eyeSkyK = 0.0;
    {
        vec3 wDir = normalize(mat3(gbufferModelViewInverse) * dir);
        vec3 wSun = normalize(mat3(gbufferModelViewInverse) * sunDir);
        float eyeSky = stormEyeSkyHole(cameraPosition, wDir, wSun, thunderStrength);
        float aboveK = stormAboveCloud(cameraPosition.y);
        eyeSkyK = eyeSky * (1.0 - aboveK);
        rainW  *= (1.0 - eyeSky) * (1.0 - aboveK);
        stormW *= (1.0 - eyeSky) * (1.0 - aboveK);
    }
    float t  = pow(clamp(hp, 0.0, 1.0), 0.55);   // soft gradient

    // ---------------- TIME-DEPENDENT PALETTE ----------------
    //                         night                   deep twi                civil twi               low sun                 morning/late            noon
    vec3 zen = ramp7(sh, vec3(0.004,0.008,0.028), vec3(0.025,0.045,0.130), vec3(0.075,0.105,0.250),
                         vec3(0.115,0.150,0.320), vec3(0.200,0.285,0.500), vec3(0.350,0.550,0.860), vec3(0.310,0.520,0.860));
    vec3 hor = ramp7(sh, vec3(0.020,0.034,0.080), vec3(0.090,0.110,0.240), vec3(0.220,0.245,0.410),
                         vec3(0.340,0.365,0.530), vec3(0.500,0.600,0.770), vec3(0.630,0.780,0.950), vec3(0.650,0.790,0.960));

    vec3 sky = mix(hor, zen, t);
    // Rayleigh-style whitening toward the horizon
    sky = mix(sky, hor, exp(-hp * 7.0) * 0.15);

    // ---------------- SUN-SIDE / OPPOSITE ----------------
    vec3 dirH = dir - up * h;
    vec3 sunH = sunDir - up * sh;
    dirH = dirH / max(length(dirH), 0.0001);
    sunH = sunH / max(length(sunH), 0.0001);
    float facing = dot(dirH, sunH);

    float band = exp(-hp * 3.0);
    float high = exp(-hp * 1.3);

    // soft golden hour tint on the sun side (afternoon / morning)
    float golden = 1.0 - smoothstep(0.05, 0.72, sh);
    golden *= smoothstep(-0.10, 0.05, sh);
    float side = pow(max(facing, 0.0), 1.5);
    vec3 glowCol = mix(vec3(0.96, 0.40, 0.16), vec3(0.96, 0.52, 0.28), exp(-hp * 9.0));
    sky += glowCol * side * (exp(-hp * 7.0) * 1.0 + exp(-hp * 2.5) * 0.10) * max(tw * 0.55, golden * 0.45) * 0.14 * SKY_SUN_SIDE_GLOW;
    sky += vec3(0.90, 0.50, 0.64) * side * exp(-hp * 3.0) * tw * 0.04 * SKY_SUN_SIDE_GLOW;   // pink/magenta upper glow

    // gentle sunrise/sunset: warm colour only low in the sky on the sun's half of the horizon,
    // wrapping ~half way round and fading smoothly. Coral -> peach -> faded pink -> pale blue.
    {
        // one broad orange glow covering almost half of the horizon and sky, fading out softly at its edges
        vec3 ss = mix(vec3(1.00, 0.56, 0.20), vec3(0.98, 0.44, 0.30), smoothstep(0.0, 0.12, hp));   // golden orange -> salmon
        ss = mix(ss, vec3(0.80, 0.38, 0.52), smoothstep(0.10, 0.34, hp));                           // dusty rose
        ss = mix(ss, vec3(0.42, 0.32, 0.64), smoothstep(0.30, 0.72, hp));                           // mauve, then into navy
        // strongest toward the sun, but the orange continues all the way round the horizon (weaker behind you)
        float sunMask = mix(0.42, 1.0, smoothstep(-0.9, 0.7, facing));
        float hFade = 1.0 - smoothstep(0.0, 1.0, hp);
        hFade = pow(hFade, 1.4);                                             // tall, smooth fade upward
        // gentler right around the sun so the sun itself stays clearly visible
        float sunDip = 1.0 - 0.80 * pow(max(dot(dir, sunDir), 0.0), 5.0);
        float sw = sunMask * (0.80 + 0.20 * side) * hFade * tw * sunDip;
        sky = mix(sky, ss, clamp(sw * 0.80 * SUNSET_STRENGTH, 0.0, 0.80));
        // warm Mie-like glow wrapping the sun: golden core, pink outer halo
        float sunCos = max(dot(dir, sunDir), 0.0);
        sky += vec3(1.0, 0.58, 0.22) * pow(sunCos, 14.0) * tw * 0.45;
        sky += vec3(0.95, 0.42, 0.40) * pow(sunCos, 4.0) * tw * 0.16;
        // opposite side: cold, pale blue-white horizon and sky
        float antiS = smoothstep(0.0, 0.95, -facing);
        vec3 cold = mix(vec3(0.34, 0.40, 0.58), vec3(0.20, 0.27, 0.46), smoothstep(0.02, 0.45, hp));
        sky = mix(sky, cold, antiS * tw * 0.22 * (1.0 - smoothstep(0.0, 0.8, hp)));
        // faint warm light scattered across the lower sky at low sun
        sky += vec3(0.022, 0.012, 0.008) * tw * exp(-hp * 4.0) * (0.3 + 0.7 * side);
    }

    // Earth's shadow wedge (gray-blue band low on the anti-solar side) topped by the
    // pink "Belt of Venus", visible mostly in civil twilight
    {
        float anti = pow(max(-facing, 0.0), 1.1);
        float civil = smoothstep(-0.20, -0.03, sh) * (1.0 - smoothstep(-0.03, 0.06, sh));
        float wedge = (1.0 - smoothstep(0.02, 0.10, hp)) * anti * civil;
        float belt = smoothstep(0.03, 0.10, hp) * (1.0 - smoothstep(0.10, 0.32, hp)) * anti * civil;
        sky = mix(sky, vec3(0.18, 0.22, 0.38), wedge * 0.55);
        sky = mix(sky, vec3(0.92, 0.55, 0.62), belt * 0.35);
    }

    // daytime realism: deeper blue overhead, cooler away from the sun, gentle warm Mie glow near it
    {
        float dayOnly = day * (1.0 - tw) * (1.0 - rainW);
        sky = mix(sky, sky * vec3(0.92, 0.96, 1.02), smoothstep(0.25, 0.95, hp) * dayOnly * 0.6);
        sky = mix(sky, sky * vec3(0.95, 0.98, 1.04), max(-facing, 0.0) * dayOnly * 0.4);
        float mieD = max(dot(dir, sunDir), 0.0);
        sky += vec3(1.0, 0.90, 0.72) * pow(mieD, 3.0) * 0.022 * dayOnly * SUN_HALO_STRENGTH;
    }

    // faint night-time airglow layer low in the sky (only after full darkness)
    sky += vec3(0.012, 0.030, 0.026) * night * (1.0 - smoothstep(-0.31, -0.18, sh) * 0.0)
         * smoothstep(-0.12, -0.31, sh) * exp(-hp * 5.0) * (1.0 - rainW);

    // opposite side: cold, soft blue (belt of Venus)
    float opp = pow(max(-facing, 0.0), 1.4);
    sky = mix(sky, vec3(0.30, 0.38, 0.58), opp * band * tw * 0.15);

    // soft Mie forward-scatter around the sun, tiny halo at the moon
    float sd = max(dot(dir, sunDir), 0.0);
    vec3 haloCol = mix(vec3(1.0, 0.95, 0.85), vec3(0.95, 0.62, 0.40), max(tw * 0.8, golden * 0.8));
    sky += haloCol * (pow(sd, 6.0) * 0.05 + pow(sd, 60.0) * 0.10) * mix(0.50, 0.22, tw) * SUN_HALO_STRENGTH
         * smoothstep(-0.10, 0.05, sh) * (1.0 - 0.9 * rainW);

    float md = max(dot(dir, moonDir), 0.0);
    sky += vec3(0.30, 0.45, 0.90) * (pow(md, 40.0) * 0.20 + pow(md, 6.0) * 0.03) * night * (1.0 - rainW);
    // large faint cool halo + soft light disc around the moon
    sky += vec3(0.42, 0.55, 0.95) * (pow(md, 14.0) * 0.045 + pow(md, 3.0) * 0.012) * night * (1.0 - rainW) * MOON_HALO_STRENGTH;
    sky += vec3(0.78, 0.86, 1.0) * pow(md, 700.0) * 0.10 * night * (1.0 - rainW) * MOON_HALO_STRENGTH;

    sky *= mix(1.0, 0.85, smoothstep(0.0, -0.30, h));

    // ---------------- PALE, REAL-LIFE SKY ----------------
    // Real daytime skies are softer and less saturated than a pure blue gradient.
    // Sunrises/sunsets keep their colour (paleness fades with twilight strength).
    {
        float pk = clamp(day * (1.0 - 0.7 * tw) * SKY_PALENESS, 0.0, 1.3);
        float L = dot(sky, vec3(0.3333));
        sky = mix(sky, vec3(L), clamp(0.34 * pk, 0.0, 0.8));
        sky = mix(sky, vec3(0.50, 0.62, 0.78), clamp(0.16 * pk, 0.0, 0.4) * (1.0 - rainW));
        // real-life blue: keep the brightness, move the hue toward a pale Rayleigh blue
        // (palest at the horizon, a little deeper overhead)
        float bk = day * (1.0 - tw) * (1.0 - rainW) * (1.0 - stormW) * SKY_BLUENESS;
        vec3 bluePale = mix(vec3(0.62, 0.76, 0.95), vec3(0.36, 0.58, 0.94), smoothstep(0.0, 0.75, hp));
        float L2 = dot(sky, vec3(0.3333));
        sky = mix(sky, L2 * bluePale / dot(bluePale, vec3(0.3333)), clamp(0.55 * bk, 0.0, 0.8));
    }

    // evening feel: slightly desaturated, pale navy dusk (only around sunrise/sunset)
    {
        float Ld = dot(sky, vec3(0.3333));
        sky = mix(sky, mix(vec3(Ld), sky, 0.62), tw * (1.0 - rainW) * 0.55 * smoothstep(0.10, 0.50, hp));
    }

    // low, soft glow hugging the horizon: dim blue at the line, decaying upward into a faint brownish
    // tone, then dissolving into the sky colour (daytime only, none in rain)
    {
        float gH = exp(-hp * 14.0);
        vec3 gTint = mix(vec3(0.54, 0.64, 0.78), vec3(0.50, 0.44, 0.40), smoothstep(0.01, 0.10, hp));
        float gAmt = 0.20 * gH * day * (1.0 - tw * 0.7) * (1.0 - rainW) * (1.0 - stormW);
        sky = mix(sky, gTint, clamp(gAmt, 0.0, 0.25));
    }

    {
        // Physically based sky: Rayleigh (blue, ~1/lambda^4) + Mie (white haze, forward lobe) single scattering.
        // Air mass grows toward the horizon (whiter, brighter horizon); sunlight is reddened by its own long
        // path at low sun (golden hour / sunset); Earth's shadow fades the sky through twilight.
        float cosV = max(h, 0.0);
        float mV = min(1.0 / (cosV + 0.03), 30.0);
        float mS = min(1.0 / (max(sh + 0.07, 0.0) + 0.03), 28.0);
        vec3 tauR = vec3(0.046, 0.108, 0.265);
        float tauM = 0.030 * (1.0 + 1.5 * rainW);
        vec3 tauV = (tauR + tauM) * mV;
        vec3 tauS = (tauR + tauM) * mS * 0.55;
        float csn = dot(dir, sunDir);
        float phR = 0.75 * (1.0 + csn * csn);
        float gM = 0.76;
        float phM = (1.0 - gM * gM) / pow(max(1.0 + gM * gM - 2.0 * gM * csn, 0.02), 1.5) * 0.06;
        vec3 ratio = (tauR * phR + tauM * phM) / (tauR + tauM);
        vec3 Lp = ratio * (vec3(1.0) - exp(-tauV)) * exp(-tauS) * 2.4;
        Lp *= smoothstep(-0.32, -0.04, sh);
        Lp = vec3(1.0) - exp(-Lp * 1.1);
        float kPhys = SKY_PHYSICS * (1.0 - rainW) * smoothstep(-0.30, -0.05, sh);
        sky = mix(sky, Lp, clamp(kPhys, 0.0, 1.0));
    }
#ifdef NEBULA_SKY
    // Nebula: night/midnight only. Filaments (streaks), dense clumps, bright knots, embedded stars.
    {
        float nightDeep = 1.0 - smoothstep(-0.31, -0.12, sh);
        vec3 wdir = normalize(mat3(gbufferModelViewInverse) * dir);
        float vis = nightDeep * smoothstep(-0.05, 0.25, h) * (1.0 - rainW) * NEBULA_STRENGTH;
        // purple/blue night tint
        sky += vec3(0.020, 0.010, 0.050) * nightDeep * (1.0 - rainW) * (0.4 + 0.6 * t);
        if (vis > 0.001) {
            vec3 q = wdir * 2.0;
            // domain warp -> swirling structure
            vec3 w = vec3(nFbm(q + 3.1), nFbm(q + 7.7), nFbm(q + 1.3)) - 0.5;
            vec3 pw = q + w * 2.2;
            float base = nFbm(pw);
            // streaks: stretch noise along one axis, ridged
            vec3 sp = pw * vec3(1.0, 5.0, 1.0) + vec3(0.0, base * 2.0, 0.0);
            float fil = 1.0 - abs(nFbm(sp * 1.3) * 2.0 - 1.0);
            fil = pow(fil, 2.2);
            // clumps: high-contrast dense cores
            float clump = smoothstep(0.35, 0.95, nFbm(pw * 2.6 + 9.0));
            float env = smoothstep(0.25, 0.85, base);
            float dens = env * (0.35 + 0.9 * fil) + clump * 0.9 * env;

            vec3 cPurple = vec3(0.50, 0.14, 0.80);
            vec3 cBlue   = vec3(0.12, 0.30, 0.90);
            vec3 cPink   = vec3(0.90, 0.30, 0.60);
            vec3 cTeal   = vec3(0.10, 0.60, 0.80);
            float m1 = smoothstep(0.3, 0.7, nFbm(q * 0.7 + 20.0));
            vec3 neb = mix(cPurple, cBlue, m1);
            neb = mix(neb, cPink, smoothstep(0.6, 0.9, nFbm(pw * 1.4 + 5.0)) * 0.6);
            neb = mix(neb, cTeal, clump * 0.5);
            sky += neb * dens * 0.20 * vis;

            // dark dust lanes carve the glow
            float dust = smoothstep(0.45, 0.95, nFbm(pw * 3.0 + 40.0));
            sky *= 1.0 - dust * env * 0.22 * vis;

            // individual stars embedded in the nebula
            vec3 sc = wdir * 90.0;
            vec3 cell = floor(sc);
            float r = nHash(cell);
            if (r > 0.93) {
                vec3 fc = fract(sc) - 0.5 + (vec3(nHash(cell + 1.7), nHash(cell + 5.3), nHash(cell + 9.1)) - 0.5) * 0.5;
                float sd2 = dot(fc, fc);
                vec3 scol = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.9), nHash(cell + 3.3));
                sky += scol * exp(-sd2 * 90.0) * (0.5 + 1.5 * env) * vis * 0.8;
            }
        }
    }
#endif

#ifdef CONSTELLATIONS
    // Real constellations: celestial frame follows the sun's own path (works with any sunPathRotation).
    {
        float cVis = night * (1.0 - rainW) * (1.0 - stormW) * (1.0 - 0.6 * tw) * smoothstep(-0.02, 0.10, h);
        if (cVis > 0.01) {
            vec3 w = normalize(mat3(gbufferModelViewInverse) * dir);
            vec3 Sw = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            vec3 U = length(Sw.yz) > 0.02 ? normalize(vec3(0.0, Sw.y, Sw.z)) * (Sw.y < 0.0 ? -1.0 : 1.0)
                                          : vec3(0.0, 0.9063, 0.4226);
            vec3 A = vec3(0.0, -U.z, U.y);
            float cth = Sw.x;
            float sth = dot(Sw, U);
            float wE = w.x;
            float wU = dot(w, U);
            float sE = wE * cth + wU * sth;
            float sU = -wE * sth + wU * cth;
            float sA = dot(w, A);
            vec3 cel = vec3(sE, -sU, -sA);
            float ra0 = 4.712389;   // sun at RA 18h: winter sky (Orion, Taurus, Gemini) at midnight
#ifdef CONSTELLATION_SEASONS
            ra0 += float(worldDay) * 0.19635;   // sky slowly changes: full cycle every 32 days
#endif
            float cr = cos(ra0), sr = sin(ra0);
            cel = vec3(cel.x * cr + cel.y * sr, -cel.x * sr + cel.y * cr, cel.z);
            float cg = gmConstellations(cel);
            sky += vec3(0.55, 0.72, 1.0) * cg * 0.30 * cVis * CONSTELLATION_STRENGTH;
        }
    }
#endif

#ifdef HORIZON_CIRRUS
    // faint, wispy cirrus-like mist low on the horizon. It drifts with the global wind (GlWS),
    // slowly deforms, and takes the same sun / twilight / night lighting as the clouds.
    {
        vec3 wDir = normalize(mat3(gbufferModelViewInverse) * dir);
        float wy = wDir.y;
        float cBand = smoothstep(0.004, 0.030, wy) * (1.0 - smoothstep(0.060, 0.240, wy));
        if (cBand > 0.001) {
            float tt = frameTimeCounter;
            vec2 wd = glwsDir();
            float wsp = glwsStrength(rainW, stormW);
            float az = atan(wDir.z, wDir.x);
            // wind drift: along the horizon (azimuth) plus a slight slide outward
            float drift = tt * 0.020 * wsp * (wd.x * 0.6 + wd.y * 0.8 + 0.35);
            vec2 c = vec2(az * 3.2 - drift, sqrt(max(wy, 0.0)) * 11.0 - tt * 0.004 * wsp);
            // deformation: slow domain warp that keeps changing the streak shapes
            vec2 wp = vec2(hzNoise(c * 0.7 + vec2(tt * 0.010, 3.1)),
                           hzNoise(c * 0.7 + vec2(7.7, -tt * 0.008))) - 0.5;
            c += wp * 1.6;
            float cn = hzFbm(c * vec2(0.9, 1.7));
            float cs = smoothstep(0.46, 0.80, cn);
            // thin out into streaks
            cs *= 0.55 + 0.45 * hzNoise(c * vec2(0.5, 3.4) + 11.0);
            float cOp = cs * cBand * 0.42 * HORIZON_CIRRUS_STRENGTH * (1.0 - rainW) * (1.0 - stormW);

            // cloud-style lighting
            vec3 cLit = mix(vec3(0.80, 0.84, 0.90), vec3(0.97, 0.97, 0.98), 0.5);
            vec3 cWarm = mix(vec3(1.0, 0.62, 0.38), vec3(1.0, 0.80, 0.58), exp(-hp * 20.0));
            float warmK = clamp(max(tw, golden * 0.7) * (0.35 + 0.65 * side), 0.0, 1.0);
            vec3 cCol = mix(cLit, cWarm, warmK);
            cCol += vec3(1.0, 0.90, 0.72) * pow(max(dot(dir, sunDir), 0.0), 8.0) * 0.25 * day;   // silver edge toward the sun
            cCol *= mix(0.10, 1.0, day);
            cCol += vec3(0.10, 0.14, 0.24) * night * 0.6;                       // faint moon/sky light at night
            sky = mix(sky, cCol, clamp(cOp, 0.0, 0.5));
        }
    }
#endif

    // ---------------- WEATHER ----------------
    float dk = mix(0.10, 1.0, day);
    vec3 rainSky = mix(vec3(0.57, 0.59, 0.63), vec3(0.46, 0.48, 0.53), t) * dk
                 + vec3(0.008, 0.012, 0.026) * (1.0 - day);
    vec3 stormSky = mix(vec3(0.25, 0.26, 0.30), vec3(0.085, 0.09, 0.115), t)
                  * mix(0.22, 1.0, day);
    rainSky += glowCol * side * band * tw * 0.08;

    // overcast layers keep the time-of-day colour cast (warm at dusk, cool at night)
    vec3 castT = hor / max(dot(hor, vec3(0.3333)), 0.01);
    rainSky *= mix(vec3(1.0), castT, 0.45);
    stormSky *= mix(vec3(1.0), castT, 0.30);

    sky = mix(sky, rainSky, rainW);
    sky = mix(sky, stormSky, stormW);

    // seen through the eye the sky is not pure clear blue: it is paler, hazier and a bit dimmer (storm light,
    // moisture), and fades smoothly into the surrounding storm sky instead of a hard blue disc
    {
        float sl = dot(sky, vec3(0.3333));
        vec3 hazy = mix(sky, vec3(sl) * vec3(0.96, 0.99, 1.04) + vec3(0.05, 0.05, 0.055) * day, 0.38);
        sky = mix(sky, hazy * 0.88, eyeSkyK);
    }

    float n = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    sky += (n - 0.5) / 255.0;

    color = vec4(max(sky * SKY_BRIGHTNESS, vec3(0.0)), 1.0);
}
