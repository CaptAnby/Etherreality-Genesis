
#version 330 compatibility
#include "/settings.glsl"
#include "/Common/Cloud/stormEye.glsl"
#include "/Common/Wind/globalWind.glsl"

// ============================================================
// ETHERREALITY GENESIS :: SCREEN HAZE V1
// Lightweight atmospheric veil + selective five-tap blur
// ============================================================
//
// Features:
// - Distance-based atmospheric haze
// - Stronger haze near the horizon
// - Day / twilight / night haze colors
// - Selective five-tap screen-space blur
// - No volumetric raymarching
// - No extra noise textures or noise functions
//
// Performance design:
// - One color sample for the base image
// - One depth sample
// - Four additional color samples only when blur is visible
//
// This pass does not change the deferred volumetric pipeline.
// ============================================================

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif

const float sunPathRotation = -25.0;

uniform mat4 gbufferProjection;
uniform vec3 sunPosition;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform float sunAngle;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;

// ---- cave fog helpers ----
float caveHash3(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float caveNoise3(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(caveHash3(i), caveHash3(i + vec3(1,0,0)), f.x),
            mix(caveHash3(i + vec3(0,1,0)), caveHash3(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(caveHash3(i + vec3(0,0,1)), caveHash3(i + vec3(1,0,1)), f.x),
            mix(caveHash3(i + vec3(0,1,1)), caveHash3(i + vec3(1,1,1)), f.x), f.y),
        f.z);
}

#ifdef PATH_TRACING
// ------------------------------------------------------------
// Hybrid screen-space path tracer (1 bounce, 4 cosine-ish rays,
// depth-buffer march). Gathers lit radiance from nearby visible
// surfaces: indirect light + colour bleeding. Cheap: 32 depth taps.
// ------------------------------------------------------------
vec3 ptGather(vec3 P, vec3 N, vec2 fc) {
    vec3 up = abs(N.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(up, N));
    vec3 B = cross(N, T);
    int ip = (int(fc.x) & 3) + 4 * (int(fc.y) & 3);
    float rot = float(ip) * 0.3927;
    float jit = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
    vec3 acc = vec3(0.0);
    for (int r = 0; r < 4; r++) {
        float ang = float(r) * 1.5708 + rot;
        float z = (r == 0) ? 0.35 : (r == 1) ? 0.65 : (r == 2) ? 0.50 : 0.80;
        float sx = sqrt(1.0 - z * z);
        vec3 dir = normalize(T * (cos(ang) * sx) + B * (sin(ang) * sx) + N * z);
        for (int i = 0; i < 8; i++) {
            float f = (float(i) + jit) / 8.0;
            float t = PT_RADIUS * f * f + 0.1;
            vec3 rp = P + dir * t;
            vec4 rc = gbufferProjection * vec4(rp, 1.0);
            if (rc.w <= 0.0) break;
            vec2 ruv = rc.xy / rc.w * 0.5 + 0.5;
            if (ruv.x < 0.02 || ruv.x > 0.98 || ruv.y < 0.02 || ruv.y > 0.98) break;
            float rd = texture(depthtex0, ruv).r;
            if (rd >= 0.999999) continue;
            vec4 hv = gbufferProjectionInverse * vec4(vec3(ruv, rd) * 2.0 - 1.0, 1.0);
            float diff = hv.z / hv.w - rp.z;
            if (diff > 0.06 && diff < 0.5 + 0.25 * t) {
                vec3 hn = normalize(texture(colortex1, ruv).rgb * 2.0 - 1.0);
                float facing = clamp(-dot(hn, dir), 0.0, 1.0);
                float fall = 1.0 - t / PT_RADIUS;
                acc += min(texture(colortex0, ruv).rgb, vec3(2.5)) * fall * fall * facing;
                break;
            }
        }
    }
    return acc * 0.25;
}
#endif

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

// ============================================================
// SAFE VIEW-POSITION RECONSTRUCTION
// ============================================================

vec3 grandHazeReconstructViewPosition(
    vec2 uv,
    float depth
) {
    vec3 ndcPosition = vec3(
        uv,
        depth
    ) * 2.0 - 1.0;

    vec4 viewH = gbufferProjectionInverse *
        vec4(ndcPosition, 1.0);

    float safeW = abs(viewH.w) < 0.000001
        ? (viewH.w < 0.0 ? -0.000001 : 0.000001)
        : viewH.w;

    return viewH.xyz / safeW;
}

// ============================================================
// TIME-OF-DAY HAZE COLOR
// ============================================================

vec3 grandHazeColor(
    float sunHeight,
    float daylight,
    float twilight
) {
    vec3 nightColor = vec3(
        0.035,
        0.050,
        0.075
    );

    vec3 dayColor = vec3(
        0.67,
        0.77,
        0.89
    );

    vec3 twilightColor = vec3(
        0.62,
        0.40,
        0.32
    );

    vec3 hazeColor = mix(
        nightColor,
        dayColor,
        daylight
    );

    float twilightMix = clamp(
        twilight * (1.0 - daylight * 0.65),
        0.0,
        1.0
    );

    hazeColor = mix(
        hazeColor,
        twilightColor,
        twilightMix
    );

    return hazeColor;
}

// ============================================================
// MAIN
// ============================================================

float windHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float windVNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 fr = fract(p);
    fr = fr * fr * (3.0 - 2.0 * fr);
    return mix(mix(windHash(i), windHash(i + vec2(1.0, 0.0)), fr.x),
               mix(windHash(i + vec2(0.0, 1.0)), windHash(i + vec2(1.0, 1.0)), fr.x), fr.y);
}

// One layer of soft drifting wind haze (dense moving air) at a fixed distance.
float windStreakLayer(vec3 rayDir, float d, float th, float rn) {
    vec3 P = cameraPosition + rayDir * d;
    float spd = mix(4.0, 6.0, rn);
    spd = mix(spd, 22.0, th);
    vec2 dir = glwsDir();
    vec2 perp = vec2(-dir.y, dir.x);
    vec2 q = P.xz - dir * frameTimeCounter * spd;
    // stretched along the wind, broad across it
    // long, thin, gently undulating streaks that run with the wind, broken into gust fronts
    float along = dot(q, dir);
    vec2 c = vec2(along * 0.018 + d, dot(q, perp) * 0.55 + P.y * 0.35 + sin(along * 0.06 + frameTimeCounter * 0.5) * 0.35);
    float n = windVNoise(c) * 0.7 + windVNoise(c * 2.1 + 5.0) * 0.3;
    float front = 0.30 + 0.70 * smoothstep(0.25, 0.80, windVNoise(vec2(along * 0.010 - frameTimeCounter * 0.02, dot(q, perp) * 0.018)));
    return smoothstep(mix(0.60, 0.30, th), 0.92, n) * front;
}

#ifdef HAZE_VOLUMETRIC
// ---- distant volumetric haze: purely visual, only starts far from the camera (unreachable) ----
vec4 volHaze(vec3 rd, float maxDist, vec3 baseCol, float day, float tw, float jit) {
    float s0 = 100.0;                         // nothing within ~100 blocks, so medium range stays clear
    float endD = min(maxDist, 2600.0);
    if (endD <= s0) return vec4(0.0, 0.0, 0.0, 1.0);
    const int N = 6;
    float dt = (endD - s0) / float(N);
    vec3 sunW = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float cs = max(dot(rd, sunW), 0.0);
    float phase = 0.70 + 0.80 * pow(cs, 5.0) * (1.0 - 0.65 * tw);                    // soft forward-scatter toward the sun
    vec3 warm = mix(vec3(1.0, 0.86, 0.68), vec3(0.95, 0.48, 0.28), tw);
    // cinematic grade: cool, slightly teal shadow side, warm glow toward the sun
    vec3 cool = baseCol * vec3(0.92, 1.0, 1.06);
    // slightly brighter, off-white haze so it blends into the horizon (follows baseCol, so night/rain stay dim)
    cool = mix(cool, vec3(0.96, 0.95, 0.92) * dot(baseCol, vec3(0.3333)) * 1.25, 0.6 * (1.0 - 0.7 * tw));
    vec3 lit = mix(cool, warm * 0.85 * (0.4 + 0.6 * day), clamp(pow(cs, 3.0) * 0.55, 0.0, 0.55));
    lit *= phase * 1.0 * (1.0 - 0.45 * tw);
    vec2 wd = glwsDir();
    float T = 1.0;
    vec3 sc = vec3(0.0);
    for (int i = 0; i < N; i++) {
        float t = s0 + (float(i) + jit) * dt;
        vec3 p = cameraPosition + rd * t;
        float hgt = p.y - 62.0;
        float hf = exp(-max(hgt, 0.0) * 0.020);                  // dense low over the sea/land, thins with height
        vec2 q = p.xz * 0.0035 - wd * frameTimeCounter * 0.010;  // drifts with the global wind
        float n = windVNoise(q) * 0.6 + windVNoise(q * 2.7 + 7.0) * 0.4;
        float dens = 0.0009 * (0.45 + 1.10 * n) * hf;
        float a = 1.0 - exp(-dens * dt);
        sc += T * a * lit;
        T *= (1.0 - a);
    }
    return vec4(sc, T);
}
#endif

void main() {
    // --------------------------------------------------------
    // ORIGINAL SCENE
    // --------------------------------------------------------

    vec4 scene = texture(
        colortex0,
        texcoord
    );

    float depth = texture(
        depthtex0,
        texcoord
    ).r;

    bool skyPixel = depth >= 0.999999;
#ifdef DISTANT_HORIZONS
    if (skyPixel && texture(dhDepthTex0, texcoord).r < 0.999999) {
        skyPixel = false;
    }
#endif

    // --------------------------------------------------------
    // RECONSTRUCT CAMERA RAY AND LINEAR DISTANCE
    // --------------------------------------------------------

    vec3 viewPosition =
        grandHazeReconstructViewPosition(
            texcoord,
            depth
        );

    float sceneDistance = length(viewPosition);

    vec3 viewDirection = normalize(viewPosition);

    vec3 worldDirection = normalize(
        mat3(gbufferModelViewInverse) *
        viewDirection
    );

    // A horizon ray has a small absolute world-space Y component.
    float horizonFactor = 1.0 - smoothstep(
        0.025,
        0.28,
        abs(worldDirection.y)
    );

    // --------------------------------------------------------
    // SUN / ATMOSPHERE
    // --------------------------------------------------------

    float sunHeight = sin(
        6.28318530718 * sunAngle
    );

    float daylight = smoothstep(
        -0.10,
        0.18,
        sunHeight
    );

    float twilight = 1.0 - smoothstep(
        0.025,
        0.48,
        abs(sunHeight)
    );

    vec3 hazeColor = grandHazeColor(
        sunHeight,
        daylight,
        twilight
    );

    // horizon band: blend far haze toward the same off-white as the sky horizon so the sea
    // dissolves into it (short band, only rays within a few degrees of the horizon)
    float belowD = max(-worldDirection.y, 0.0);
    // soft glow band just BELOW the horizon line (sea glow): none above it, fades out downward
    // smooth gaussian profile centred just under the horizon; its soft top edge feathers into the sky
    float gy = (worldDirection.y + 0.022) / 0.040;
    // above the peak it fades quickly; below it a longer, slower tail that turns subtly brownish
    float seaGlow = exp(-gy * gy * (gy > 0.0 ? 0.30 : 1.0));
    float glowDecay = smoothstep(0.2, 2.2, max(gy, 0.0));
    vec3 seaGlowCol = mix(vec3(0.50, 0.62, 0.78), vec3(0.46, 0.40, 0.34), glowDecay);   // dim blue -> faint brown
    float horizonBand = 0.0;
    // the horizon glow only belongs to far scenery: never over nearby blocks, water or entities
    seaGlow *= smoothstep(180.0, 900.0, sceneDistance);

    // rain / thunder: distant haze turns darker gray (smooth blend, no white veil); gone above the clouds
    float wetK = clamp(max(wxRain, wxThunder), 0.0, 1.0) * (1.0 - stormAboveCloud(cameraPosition.y));
    hazeColor = mix(hazeColor, vec3(dot(hazeColor, vec3(0.3333))) * mix(0.62, 0.50, clamp(wxThunder, 0.0, 1.0)), wetK * 0.9);

    // horizon blend: far sea/land and the sky just above it dissolve into one shared haze colour,
    // so no lighter/bluer strip is left where the water ends (soft asymmetric band around the horizon line)
    float hzY = worldDirection.y + 0.012;
    float hzBand = exp(-hzY * hzY / (hzY > 0.0 ? 0.0028 : 0.0016));
    float hzFar = skyPixel ? 1.0 : smoothstep(120.0, 700.0, sceneDistance);
    float hzBlend = hzBand * hzFar * 0.80;

    // Retain some night haze, but keep it weaker than daylight.
    float timeStrength = max(
        daylight,
        max(twilight * 0.80, 0.45)
    );

    // --------------------------------------------------------
    // SCREEN HAZE AMOUNT
    // --------------------------------------------------------

    // Distant opaque scenery fades gradually instead of receiving
    // a hard fog cutoff.
    float distanceHaze = smoothstep(
        40.0,
        520.0,
        sceneDistance
    );

    float hazeAmount;

    if (skyPixel) {
        // Veil only the lower sky and horizon; preserve the
        // upper sky rather than covering the entire sky dome.
        float cloudAlt = smoothstep(110.0, 150.0, cameraPosition.y)
                       * (1.0 - smoothstep(340.0, 420.0, cameraPosition.y));
        hazeAmount =
            horizonBand *
            0.0 *
            timeStrength *
            (1.0 - 0.9 * cloudAlt);
    } else {
        // Distant terrain near the horizon receives the strongest
        // veil. Distant terrain elsewhere receives lighter haze.
        float horizonStrength = mix(
            0.20,
            0.45,
            horizonFactor
        );

        hazeAmount =
            distanceHaze *
            horizonStrength *
            timeStrength;
    }

    hazeAmount = clamp(
        hazeAmount * HAZE_STRENGTH,
        0.0,
        0.65
    );

    // --------------------------------------------------------
    // SELECTIVE FIVE-TAP BLUR
    // --------------------------------------------------------
    // Blur only when the haze is visible.
    // Five total color taps; no blur pyramid and no second
    // dedicated blur pass.
    // --------------------------------------------------------

    vec3 result = scene.rgb;

#ifdef PATH_TRACING
    if (!skyPixel && isEyeInWater == 0 && sceneDistance < 80.0) {
        vec3 ptN = normalize(texture(colortex1, texcoord).rgb * 2.0 - 1.0);
        vec3 ptG = ptGather(viewPosition, ptN, gl_FragCoord.xy);
        float ptMx = max(scene.r, max(scene.g, scene.b));
        vec3 ptTint = mix(vec3(1.0), scene.rgb / max(ptMx, 0.03), 0.7) * (0.35 + 0.65 * min(ptMx * 2.0, 1.0));
        float ptFade = 1.0 - smoothstep(40.0, 80.0, sceneDistance);
        result += ptG * ptTint * 0.55 * PT_STRENGTH * ptFade * (1.0 - 0.8 * clamp(rainStrength, 0.0, 1.0));
    }
#endif

#ifdef LIGHT_GLARE
    {
        // subtle glare: gather emissive pixels (torch flames, lamps, lava...) from nearby screen positions and
        // add their own color (so soul torches glare blue, redstone red, etc.) as a soft halo
        vec2 glPx = 1.0 / vec2(textureSize(colortex0, 0));
        vec3 glAcc = vec3(0.0);
        for (int ring = 0; ring < 3; ring++) {
            float rad = (ring == 0) ? 7.0 : (ring == 1) ? 17.0 : 34.0;
            float wr = (ring == 0) ? 1.0 : (ring == 1) ? 0.55 : 0.28;
            for (int k = 0; k < 4; k++) {
                float a = float(k) * 1.5708 + float(ring) * 0.7854 + 0.3;
                vec2 suv = texcoord + vec2(cos(a), sin(a)) * rad * glPx;
                if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) continue;
                float em = texture(colortex2, suv).g;
                if (em > 0.05) {
                    vec3 gc = texture(colortex0, suv).rgb;
                    float gm = max(gc.r, max(gc.g, gc.b));
                    glAcc += (gc / max(gm, 0.05)) * em * wr;
                }
            }
        }
        float glDark = 1.0 - 0.6 * smoothstep(0.2, 0.9, dot(result, vec3(0.3333)));   // more visible in dim scenes
        result += glAcc * (1.0 / 12.0) * 0.55 * LIGHT_GLARE_STRENGTH * glDark * (1.0 - 0.5 * clamp(rainStrength, 0.0, 1.0));
    }
#endif

    float blurAmount = clamp(
        hazeAmount * 0.70,
        0.0,
        0.32
    );
    // extra softening inside the horizon glow so it smears and blends instead of showing a line
    float glowBlur = skyPixel ? 0.0 : max(seaGlow * daylight * 0.30, hzBlend * 0.45);
    blurAmount = max(blurAmount, glowBlur);
    // clouds (sky pixels) blur out toward the horizon: strongest on the horizon line, fading upward
    float skyHzBlur = skyPixel ? (1.0 - smoothstep(0.0, 0.22, abs(worldDirection.y))) : 0.0;
    blurAmount = max(blurAmount, skyHzBlur * 0.85);

    if (blurAmount > 0.012) {
        vec2 texelSize = 1.0 / vec2(
            textureSize(colortex0, 0)
        );

        float blurRadius = mix(
            0.85,
            1.80,
            clamp(max(hazeAmount / 0.45, glowBlur * 3.0), 0.0, 1.0)
        );
        blurRadius = max(blurRadius, 1.5 + 3.5 * skyHzBlur);

        vec2 offset = texelSize * blurRadius;

        vec2 uvLeft = clamp(
            texcoord - vec2(offset.x, 0.0),
            vec2(0.0),
            vec2(1.0)
        );

        vec2 uvRight = clamp(
            texcoord + vec2(offset.x, 0.0),
            vec2(0.0),
            vec2(1.0)
        );

        vec2 uvDown = clamp(
            texcoord - vec2(0.0, offset.y),
            vec2(0.0),
            vec2(1.0)
        );

        vec2 uvUp = clamp(
            texcoord + vec2(0.0, offset.y),
            vec2(0.0),
            vec2(1.0)
        );

        vec3 blurLeft = texture(
            colortex0,
            uvLeft
        ).rgb;

        vec3 blurRight = texture(
            colortex0,
            uvRight
        ).rgb;

        vec3 blurDown = texture(
            colortex0,
            uvDown
        ).rgb;

        vec3 blurUp = texture(
            colortex0,
            uvUp
        ).rgb;

        // A center-weighted cross blur minimizes softness in
        // near objects while smoothing distant screen regions.
        vec3 blurred = scene.rgb * 0.50;

        blurred += blurLeft * 0.125;
        blurred += blurRight * 0.125;
        blurred += blurDown * 0.125;
        blurred += blurUp * 0.125;

        // wider 9-tap soft blur for clouds near the horizon (diagonals added only there)
        if (skyHzBlur > 0.05) {
            vec3 dNW = texture(colortex0, clamp(texcoord + vec2(-offset.x,  offset.y), vec2(0.0), vec2(1.0))).rgb;
            vec3 dNE = texture(colortex0, clamp(texcoord + vec2( offset.x,  offset.y), vec2(0.0), vec2(1.0))).rgb;
            vec3 dSW = texture(colortex0, clamp(texcoord + vec2(-offset.x, -offset.y), vec2(0.0), vec2(1.0))).rgb;
            vec3 dSE = texture(colortex0, clamp(texcoord + vec2( offset.x, -offset.y), vec2(0.0), vec2(1.0))).rgb;
            vec3 wide = scene.rgb * 0.28 + (blurLeft + blurRight + blurDown + blurUp) * 0.12
                      + (dNW + dNE + dSW + dSE) * 0.06;
            blurred = mix(blurred, wide, clamp(skyHzBlur * 1.4, 0.0, 1.0));
        }

        result = mix(
            scene.rgb,
            blurred,
            blurAmount
        );
    }

    // Cool distant tint: far things shift toward blue (aerial perspective).
    result *= mix(
        vec3(1.0),
        vec3(0.88, 0.96, 1.10),
        clamp(hazeAmount / 0.45 * HAZE_COOLNESS, 0.0, 1.0) * mix(0.5, 1.0, daylight) * (1.0 - 0.9 * wetK)
    );

    // --------------------------------------------------------
    // ATMOSPHERIC VEIL
    // --------------------------------------------------------

    // keep some of each block's own colour inside the veil so distant terrain blends
    // into the haze instead of turning flat white
    vec3 veilCol = mix(
        hazeColor,
        hazeColor * min(result / max(dot(result, vec3(0.3333)), 0.04), vec3(2.0)),
        0.35
    );

    result = mix(
        result,
        veilCol,
        hazeAmount
    );

#ifdef HAZE_VOLUMETRIC
    if (isEyeInWater == 0) {
        float vJit = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
        float vDist = skyPixel ? 2600.0 : sceneDistance;
        vec4 vh = volHaze(worldDirection, vDist, hazeColor, daylight, twilight, vJit);
        float skyL = smoothstep(0.08, 0.55, float(eyeBrightnessSmooth.y) / 240.0);   // none underground
        float vk = clamp(HAZE_VOL_STRENGTH * skyL * (1.0 - 0.85 * wetK), 0.0, 1.5);
        result = result * mix(1.0, vh.a, min(vk, 1.0)) + vh.rgb * vk;
    }
#endif

    result = mix(result, hazeColor * mix(0.55, 1.0, daylight), hzBlend);

    // sea glow: slightly brighter band on the water right under the horizon
    if (!skyPixel) {
        float glowK = seaGlow * daylight * (1.0 - twilight * 0.7) * (1.0 - wetK) * 0.07;
        result = mix(result, seaGlowCol, glowK);
    }

    // --------------------------------------------------------
    // 3D VOLUMETRIC CAVE FOG
    // Density scales with how enclosed (no sky light) and how deep you are.
    // --------------------------------------------------------
    float caveness = 1.0 - smoothstep(0.08, 0.55, float(eyeBrightnessSmooth.y) / 240.0);
#ifdef CAVE_FOG
    if (caveness > 0.01 && isEyeInWater == 0) {
        float maxDist = min(sceneDistance, 44.0);
        vec3 wDir = normalize(mat3(gbufferModelViewInverse) * viewDirection);
        float jitter = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
        const int STEPS = 10;
        float stepLen = maxDist / float(STEPS);
        float optical = 0.0;
        float dustAcc = 0.0;
        for (int i = 0; i < STEPS; i++) {
            float t = (float(i) + jitter) * stepLen;
            vec3 wp = cameraPosition + wDir * t;
            float deepS = smoothstep(62.0, -48.0, wp.y);
            float n = caveNoise3(wp * 0.11 + vec3(frameTimeCounter * 0.03, 0.0, frameTimeCounter * 0.02));
            n = 0.35 + 0.65 * n;
            optical += (0.35 + 0.65 * deepS) * n * stepLen;
#ifdef CAVE_DUST
            // dust motes carried by faint cave draughts (drift along the global wind, slow and sparse)
            float dn = caveNoise3(wp * 2.4 + vec3(frameTimeCounter * 0.04, frameTimeCounter * 0.01, frameTimeCounter * 0.03));
            dustAcc += smoothstep(0.80, 0.93, dn) * stepLen * (0.35 + 0.65 * deepS);
#endif
        }
        optical *= 0.028 * caveness * CAVE_FOG_DENSITY;
        float trans = exp(-optical);
        float torch = float(eyeBrightnessSmooth.x) / 240.0;
        vec3 caveFogCol = mix(vec3(0.010, 0.012, 0.018), vec3(0.26, 0.15, 0.07), torch * 0.55);
        result = mix(caveFogCol, result, trans);
#ifdef CAVE_DUST
        result += mix(vec3(0.05, 0.055, 0.065), vec3(0.45, 0.30, 0.16), torch * 0.6) * clamp(dustAcc * 0.02, 0.0, 0.18) * caveness * trans;
#endif
    }
#endif

    // --------------------------------------------------------
    // REAL-CAVE DARKNESS: unlit rock falls into near-black; only torch-lit surfaces stay visible
    // --------------------------------------------------------
    {
        float caveTorch = float(eyeBrightnessSmooth.x) / 240.0;
        float lumC = dot(result, vec3(0.3333));
        float dark = caveness * (1.0 - smoothstep(0.04, 0.34, lumC)) * (1.0 - smoothstep(0.10, 0.65, caveTorch));
        result *= 1.0 - 0.62 * dark;
    }
    // --------------------------------------------------------
    // WIND BREEZE STREAKS
    // --------------------------------------------------------
    {
#ifdef WIND_STREAKS
        float aboveW = stormAboveCloud(cameraPosition.y);   // above the storm: calm, white, clear-weather wind
        float th = clamp(thunderStrength, 0.0, 1.0) * (1.0 - aboveW);
        float rn = clamp(rainStrength, 0.0, 1.0) * (1.0 - aboveW);
        float dist = length(viewPosition);
        vec3 rayDir = normalize(mat3(gbufferModelViewInverse) * viewPosition);
        float s = 0.0;
        s += windStreakLayer(rayDir, 5.0, th, rn) * smoothstep(0.5, 5.0, dist);
        s += windStreakLayer(rayDir, 11.0, th, rn) * 0.8 * smoothstep(2.0, 11.0, dist);
        s += windStreakLayer(rayDir, 19.0, th, rn) * 0.6 * smoothstep(4.0, 19.0, dist);

        float gust = 0.55 + 0.45 * glwsGust(frameTimeCounter, rn, th);
        float alpha = mix(0.13, 0.22, rn) * WIND_STREAK_STRENGTH;
        alpha = mix(alpha, 0.62, th);

        float dayF = mix(0.25, 1.0, smoothstep(-0.1, 0.3, sin(sunAngle * 6.2832)));
        vec3 sCol = mix(vec3(0.95, 0.97, 1.0), vec3(0.72, 0.75, 0.80), rn);
        sCol = mix(sCol, vec3(0.30, 0.32, 0.37), th);
        sCol *= mix(1.0, dayF, 1.0 - th * 0.5);

        result = mix(result, sCol, clamp(s * alpha * gust, 0.0, 0.6) * (1.0 - caveness));
#endif
    }


    // --------------------------------------------------------
    // DIVINE SUNRAYS (screen-space, through cloud gaps / blocks)
    // --------------------------------------------------------
    {
        float sh2 = sin(6.28318530718 * sunAngle);
        float rayDay = smoothstep(-0.06, 0.14, sh2);
        vec4 sc = gbufferProjection * vec4(sunPosition, 1.0);
#ifdef SUNRAYS
        if (rayDay > 0.0 && sc.w > 0.0) {
            vec2 sunUV = sc.xy / sc.w * 0.5 + 0.5;
            vec2 toSun = sunUV - texcoord;
            float edge = 1.0 - smoothstep(0.9, 2.2, length(sunUV - 0.5) * 2.0);
#ifdef STORM_EYE
            float stormK = clamp(thunderStrength, 0.0, 1.0);
#else
            float stormK = 0.0;
#endif
            float jit = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
            float acc = 0.0;
            for (int i = 0; i < 14; i++) {
                float f = (float(i) + jit) / 14.0;
                vec2 uv = clamp(texcoord + toSun * f * 0.9, vec2(0.001), vec2(0.999));
                float d = texture(depthtex0, uv).r;
                if (d >= 0.999999) {
                    vec3 c = texture(colortex0, uv).rgb;
                    float clear = 1.0 - smoothstep(0.55, 0.95, min(c.r, min(c.g, c.b)));
                    float eyeLit = smoothstep(0.30, 0.55, dot(c, vec3(0.3333)));   // thunderstorm: only bright sky (the eye) passes light
                    acc += mix(0.25 + 0.75 * clear, eyeLit, stormK);
                }
            }
            acc /= 14.0;
            float near = 1.0 - smoothstep(0.0, 1.4, length(toSun));
            float twr = 1.0 - smoothstep(0.05, 0.4, sh2);
            vec3 rayCol = mix(vec3(1.0, 0.91, 0.74), vec3(1.0, 0.55, 0.25), twr);
            acc = smoothstep(0.08, 0.85, acc);   // crisper contrast between lit gaps and shade
            float rs = acc * near * edge * rayDay * mix(0.34, 0.60, twr);
            rs *= (1.0 - 0.85 * clamp(rainStrength, 0.0, 1.0) * (1.0 - stormK));
            rs *= 1.0 + stormK * 0.6 * STORM_EYE_LIGHT;
            result += rayCol * rs * SUNRAY_STRENGTH;
        }
#endif
    }

    color = vec4(
        max(result, vec3(0.0)),
        scene.a
    );
}
