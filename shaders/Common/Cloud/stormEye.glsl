#ifndef GM_STORM_EYE_GLSL
#define GM_STORM_EYE_GLSL

// ============================================================
// EYE OF THE STORM (thunderstorms only)
// A calm column through the cloud deck, world-anchored and reachable (see below). Needs settings.glsl (CLOUD_ALTITUDE, CLOUD_THICKNESS, STORM_EYE_*).
// ============================================================

uniform float stormEyeForm;
uniform float wxRain;      // slow, natural versions of rain / thunder strength (visual only)
uniform float wxThunder;   // 0..1, rises slowly (~60 s) after thunder is fully on, falls in ~8 s

// storm build-up (visual only): clouds sink to a reachable height and grow into tall cumulonimbus
float stormBuild() { return smoothstep(0.0, 0.3, stormEyeForm); }   // clouds build in ~20 s, the eye stays slow
float rainBuild()  { return smoothstep(0.0, 0.6, wxRain); }
float stormAlt()   { return mix(mix(CLOUD_ALTITUDE, 110.0, rainBuild()), 70.0, stormBuild()); }
float stormThick() { return mix(mix(CLOUD_THICKNESS, 190.0, rainBuild()), 250.0, stormBuild()); }
// 1 when the camera is above the storm tops (rain stops, storm dimming gone)
float stormAboveCloud(float camY) {
    float top = stormAlt() + stormThick();
    return max(stormBuild(), rainBuild()) * smoothstep(top - 25.0, top + 15.0, camY);
}

// The eye is a real, world-anchored place: a tall vertical column through the cloud deck that you can walk or fly to and
// climb up inside. Its wall leans outward with height ("stadium effect": narrow at the cloud base, wide at the tops), like the
// tunnel of billowing cloud seen when looking up through a real eye. One eye per STORM_EYE_CELL x STORM_EYE_CELL block cell,
// with a jittered centre, so there is always one within reach and they never move (the cloud flows past them).
#define STORM_EYE_CELL 1400.0

float seHash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

vec2 stormEyeCenterOf(vec2 cell) {
    vec2 h = vec2(seHash(cell + 3.7), seHash(cell + 17.3));
    return (cell + 0.5 + (h - 0.5) * 0.5) * STORM_EYE_CELL;
}

// nearest eye centre to a world xz position; returns the distance to it
float stormEyeNearest(vec2 xz, out vec2 c) {
    vec2 b = floor(xz / STORM_EYE_CELL);
    float best = 1.0e12;
    c = xz;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 cc = stormEyeCenterOf(b + vec2(float(i), float(j)));
            vec2 dv = xz - cc;
            float d2 = dot(dv, dv);
            if (d2 < best) { best = d2; c = cc; }
        }
    }
    return sqrt(best);
}

// 0 = no storm, 1 = full thunderstorm (thunder only, rain alone does nothing)
float stormEyeAmount(float thunder) {
#ifdef STORM_EYE
    // small delay (first ~15% of the timer), then the hole opens slowly
    return smoothstep(0.35, 1.0, clamp(thunder, 0.0, 1.0)) * smoothstep(0.15, 1.0, stormEyeForm);
#else
    return 0.0;
#endif
}

float stormEyeHF(float y) { return clamp((y - stormAlt()) / max(stormThick(), 1.0), 0.0, 1.5); }
// clear radius and soft wall width, both growing with height (stadium effect)
float stormEyeClearR(float y) { return STORM_EYE_SIZE * (50.0 + 150.0 * stormEyeHF(y)); }
float stormEyeWallW(float y)  { return STORM_EYE_SIZE * (50.0 + 90.0 * stormEyeHF(y)); }

float stormEyeSmooth(float k) {
    k = clamp(k, 0.0, 1.0);
    return k * k * k * (k * (k * 6.0 - 15.0) + 10.0);   // smootherstep
}

// bell-shaped weight on the eye wall (0..1), d = distance from the eye axis
float stormEyeWallBell(float d, float y) {
    float w = stormEyeWallW(y);
    float x = (d - (stormEyeClearR(y) + 0.5 * w)) / (0.7 * w);
    return exp(-x * x);
}

// smooth (no billow noise) hole at a world position: 1 = clear, 0 = untouched cloud
float stormEyeHoleP(vec3 p, float amt) {
    vec2 c;
    float d = stormEyeNearest(p.xz, c);
    return amt * (1.0 - stormEyeSmooth((d - stormEyeClearR(p.y)) / stormEyeWallW(p.y)));
}

// 1 when the camera stands in / under an eye (calm air: no rain, no storm dimming), smooth toward its edge
float stormEyeCalm(vec3 camPos, float amt) {
    if (amt <= 0.0) return 0.0;
    return stormEyeHoleP(vec3(camPos.x, max(camPos.y, stormAlt() + 10.0), camPos.z), amt);
}

// gentle spiral: rotates the cloud pattern around the eye, more at height (the wall spirals upward). Local to the eye
// (gaussian), so nothing changes where two eyes' areas meet.
vec2 stormEyeSwirl(vec2 xz, vec2 c, float amt, float y) {
    vec2 r = xz - c;
    float q = length(r) / (330.0 * STORM_EYE_SIZE);
    float a = amt * 0.9 * exp(-q * q) * (0.6 + 0.9 * stormEyeHF(y));
    float cs = cos(a), sn = sin(a);
    return c + vec2(cs * r.x - sn * r.y, sn * r.x + cs * r.y);
}

// the same hole seen along a view ray (sky / sun / fog passes): clear only if the ray is inside the column at
// the base, middle and top of the cloud deck
float stormEyeSkyHole(vec3 camPos, vec3 dirW, vec3 sunW, float thunder) {
    float amt = stormEyeAmount(thunder);
    if (amt <= 0.0 || dirW.y < 0.02) return 0.0;
    float a = stormAlt();
    float th = stormThick();
    float h = 1.0;
    for (int i = 0; i < 3; i++) {
        float y = a + th * 0.5 * float(i);
        float t = (y - camPos.y) / dirW.y;
        if (t > 0.0) h = min(h, stormEyeHoleP(camPos + dirW * t, 1.0));
    }
    return amt * h;
}

#endif
