
#version 330 compatibility
#include "/settings.glsl"
#include "/Common/Wind/globalWind.glsl"
#undef WIND_STREAKS
#undef SUNRAYS
#undef SUN_GLARE
#undef SUN_FLARE


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
        0.56,
        0.70,
        0.90
    );

    vec3 twilightColor = vec3(
        0.91,
        0.66,
        0.49
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
    vec2 c = vec2(dot(q, dir) * 0.045 + d, dot(q, perp) * 0.12 + P.y * 0.10);
    float n = windVNoise(c) * 0.65 + windVNoise(c * 2.3 + 5.0) * 0.35;
    return smoothstep(mix(0.45, 0.22, th), 0.80, n);
}

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
            horizonFactor *
            0.24 *
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

    float blurAmount = clamp(
        hazeAmount * 0.40,
        0.0,
        0.18
    );

    if (blurAmount > 0.012) {
        vec2 texelSize = 1.0 / vec2(
            textureSize(colortex0, 0)
        );

        float blurRadius = mix(
            0.85,
            1.80,
            clamp(hazeAmount / 0.45, 0.0, 1.0)
        );

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
        clamp(hazeAmount / 0.45 * HAZE_COOLNESS, 0.0, 1.0) * mix(0.5, 1.0, daylight)
    );

    // --------------------------------------------------------
    // ATMOSPHERIC VEIL
    // --------------------------------------------------------

    result = mix(
        result,
        hazeColor,
        hazeAmount
    );

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
        for (int i = 0; i < STEPS; i++) {
            float t = (float(i) + jitter) * stepLen;
            vec3 wp = cameraPosition + wDir * t;
            float deepS = smoothstep(62.0, -48.0, wp.y);
            float n = caveNoise3(wp * 0.11 + vec3(frameTimeCounter * 0.03, 0.0, frameTimeCounter * 0.02));
            n = 0.35 + 0.65 * n;
            optical += (0.35 + 0.65 * deepS) * n * stepLen;
        }
        optical *= 0.028 * caveness * CAVE_FOG_DENSITY;
        float trans = exp(-optical);
        float torch = float(eyeBrightnessSmooth.x) / 240.0;
        vec3 caveFogCol = mix(vec3(0.075, 0.09, 0.115), vec3(0.42, 0.25, 0.11), torch * 0.55);
        result = mix(caveFogCol, result, trans);
    }
#endif

    // --------------------------------------------------------
    // WIND BREEZE STREAKS
    // --------------------------------------------------------
    {
#ifdef WIND_STREAKS
        float th = clamp(thunderStrength, 0.0, 1.0);
        float rn = clamp(rainStrength, 0.0, 1.0);
        float dist = length(viewPosition);
        vec3 rayDir = normalize(mat3(gbufferModelViewInverse) * viewPosition);
        float s = 0.0;
        s += windStreakLayer(rayDir, 5.0, th, rn) * smoothstep(0.5, 5.0, dist);
        s += windStreakLayer(rayDir, 11.0, th, rn) * 0.8 * smoothstep(2.0, 11.0, dist);
        s += windStreakLayer(rayDir, 19.0, th, rn) * 0.6 * smoothstep(4.0, 19.0, dist);

        float gust = 0.55 + 0.45 * glwsGust(frameTimeCounter, rn, th);
        float alpha = mix(0.16, 0.26, rn);
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
            float jit = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
            float acc = 0.0;
            for (int i = 0; i < 14; i++) {
                float f = (float(i) + jit) / 14.0;
                vec2 uv = clamp(texcoord + toSun * f * 0.9, vec2(0.001), vec2(0.999));
                float d = texture(depthtex0, uv).r;
                if (d >= 0.999999) {
                    vec3 c = texture(colortex0, uv).rgb;
                    float clear = 1.0 - smoothstep(0.40, 0.80, min(c.r, min(c.g, c.b)));
                    acc += 0.25 + 0.75 * clear;
                }
            }
            acc /= 14.0;
            float near = 1.0 - smoothstep(0.0, 1.4, length(toSun));
            float twr = 1.0 - smoothstep(0.05, 0.4, sh2);
            vec3 rayCol = mix(vec3(1.0, 0.93, 0.78), vec3(1.0, 0.62, 0.32), twr);
            float rs = acc * near * edge * rayDay * mix(0.28, 0.45, twr);
            rs *= (1.0 - 0.85 * clamp(rainStrength, 0.0, 1.0));
            result += rayCol * rs * SUNRAY_STRENGTH;
        }
#endif
    }

    color = vec4(
        max(result, vec3(0.0)),
        scene.a
    );
}
