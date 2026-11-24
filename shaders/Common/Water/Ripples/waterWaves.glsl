// ============================================================
// ETHERREALITY GENESIS :: WATER
// SMALLER + THINNER CONTINUOUS MOVING WAVE FIELD
// ============================================================

#ifndef GRAND_OVERLORD_WATER_WAVES_GLSL
#define GRAND_OVERLORD_WATER_WAVES_GLSL


// ============================================================
// WAVE SCALES
// ============================================================
//
// Smaller scale = more frequent, tighter waves.
//

const float WATER_SCALE_LARGE =
    48.0;

const float WATER_SCALE_MEDIUM =
    30.0;

const float WATER_SCALE_SMALL =
    17.0;

const float WATER_SCALE_WIND =
    10.0;


// ============================================================
// WAVE HEIGHTS
// ============================================================
//
// Lower heights = thinner / less bulky wave shape.
//

const float WATER_HEIGHT_LARGE =
    0.07;

const float WATER_HEIGHT_MEDIUM =
    0.045;

const float WATER_HEIGHT_SMALL =
    0.025;

const float WATER_HEIGHT_WIND =
    0.015;


// ============================================================
// WAVE SPEED
// ============================================================
//
// Noticeably moving, but still gentle.
//

const float WATER_LARGE_SPEED =
    0.022;

const float WATER_MEDIUM_SPEED =
    0.030;

const float WATER_SMALL_SPEED =
    0.040;

const float WATER_WIND_SPEED =
    0.050;


// ============================================================
// GLOBAL TIME
// ============================================================

const float WATER_TIME_SCALE =
    45.0;


// ============================================================
// FLOW DIRECTIONS
// ============================================================

const vec2 WATER_LARGE_FLOW =
    normalize(
        vec2(
            1.0,
            0.22
        )
    );

const vec2 WATER_MEDIUM_FLOW =
    normalize(
        vec2(
            0.72,
            0.69
        )
    );

const vec2 WATER_SMALL_FLOW =
    normalize(
        vec2(
            -0.44,
            0.90
        )
    );

const vec2 WATER_WIND_FLOW =
    normalize(
        vec2(
            -0.82,
            0.57
        )
    );


// ============================================================
// DETAIL FADE
// ============================================================

const float WATER_DETAIL_FADE_START =
    18.0;

const float WATER_DETAIL_FADE_END =
    135.0;


const float WATER_DISPLACEMENT_FADE_START =
    40.0;

const float WATER_DISPLACEMENT_FADE_END =
    190.0;


// ============================================================
// NOISE
// ============================================================

float waterHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float waterNoise(
    vec2 position,
    float scale
) {
    // procedural, rotated, 2-octave value noise: no texture tiling / grid
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    vec2 q = rot * (position / scale) * 6.0 + scale;
    float sum = 0.0;
    float amp = 0.65;
    for (int i = 0; i < 2; i++) {
        vec2 i0 = floor(q);
        vec2 f = fract(q);
        f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        float h = mix(
            mix(waterHash(i0), waterHash(i0 + vec2(1.0, 0.0)), f.x),
            mix(waterHash(i0 + vec2(0.0, 1.0)), waterHash(i0 + vec2(1.0, 1.0)), f.x),
            f.y);
        sum += h * amp;
        amp *= 0.35;
        q = rot * q * 2.07 + 11.3;
    }
    return clamp(sum / 1.0, 0.0, 1.0);
}


// ============================================================
// SMOOTH WAVE SHAPE
// ============================================================
//
// Sharper profile = thinner, more defined wave bands.
//

float waterShapeNoise(
    float value
) {
    return clamp(value, 0.0, 1.0) * 2.0 - 1.0;
}


// ============================================================
// STATIC DOMAIN WARP
// ============================================================
//
// IMPORTANT:
// The warp itself does NOT animate.
// This keeps the wave shape stable and prevents twitching.
//

vec2 waterDomainWarp(
    vec2 position
) {

    float warpX =
        waterNoise(
            position +
            vec2(
                71.0,
                -37.0
            ),
            170.0
        )
        *
        2.0 -
        1.0;


    float warpZ =
        waterNoise(
            position +
            vec2(
                -53.0,
                83.0
            ),
            155.0
        )
        *
        2.0 -
        1.0;


    return
        position +
        vec2(
            warpX,
            warpZ
        )
        *
        8.0;
}


// ============================================================
// SINGLE CONTINUOUS WAVE
// ============================================================

float waterContinuousWave(
    vec2 position,
    vec2 flow,
    float scale,
    float speed,
    float amplitude,
    float phase,
    float time
) {

    vec2 movingPosition =
        position
        +
        normalize(flow)
        *
        (
            time *
            speed
        );


    movingPosition +=
        vec2(
            phase * 37.17,
            phase * -21.43
        );


    float noise =
        waterNoise(
            movingPosition,
            scale
        );


    return
        waterShapeNoise(
            noise
        )
        *
        amplitude;
}


// ============================================================
// LARGE WAVE
// ============================================================

float waterLargeWave(
    vec2 position,
    float time
) {

    return
        waterContinuousWave(
            position,
            WATER_LARGE_FLOW,
            WATER_SCALE_LARGE,
            WATER_LARGE_SPEED,
            WATER_HEIGHT_LARGE,
            0.17,
            time
        );
}


// ============================================================
// MEDIUM WAVE
// ============================================================

float waterMediumWave(
    vec2 position,
    float time
) {

    return
        waterContinuousWave(
            position,
            WATER_MEDIUM_FLOW,
            WATER_SCALE_MEDIUM,
            WATER_MEDIUM_SPEED,
            WATER_HEIGHT_MEDIUM,
            0.43,
            time
        );
}


// ============================================================
// SMALL WAVE
// ============================================================

float waterSmallWave(
    vec2 position,
    float time
) {

    return
        waterContinuousWave(
            position,
            WATER_SMALL_FLOW,
            WATER_SCALE_SMALL,
            WATER_SMALL_SPEED,
            WATER_HEIGHT_SMALL,
            0.81,
            time
        );
}


// ============================================================
// WIND WAVE
// ============================================================

float waterWindWave(
    vec2 position,
    float time
) {

    return
        waterContinuousWave(
            position,
            WATER_WIND_FLOW,
            WATER_SCALE_WIND,
            WATER_WIND_SPEED,
            WATER_HEIGHT_WIND,
            1.27,
            time
        );
}


// ============================================================
// BROAD HEIGHT FIELD
// ============================================================

float waterBroadHeight(
    vec2 position,
    float time
) {

    vec2 warped =
        waterDomainWarp(
            position
        );


    float large =
        waterLargeWave(
            warped,
            time
        );


    float medium =
        waterMediumWave(
            warped +
            vec2(
                41.0,
                -67.0
            ),
            time
        );


    float small =
        waterSmallWave(
            warped +
            vec2(
                -73.0,
                29.0
            ),
            time
        );


    float wind =
        waterWindWave(
            warped +
            vec2(
                19.0,
                83.0
            ),
            time
        );


    return
        large
        +
        medium
        +
        small
        +
        wind;
}


// ============================================================
// DETAIL FADE
// ============================================================

float waterDetailFade(
    vec2 position
) {
    // constant: no camera-distance dependence (prevents shimmer while moving)
    return 1.0;
}


// ============================================================
// FINE NORMAL DETAIL
// ============================================================

float waterFineHeight(
    vec2 position,
    float time
) {

    float fade =
        waterDetailFade(
            position
        );


    /*
        Small amount only.
        This affects the normal much more than geometry.
    */

    float small =
        waterSmallWave(
            position +
            vec2(
                19.0,
                -31.0
            ),
            time
        )
        *
        0.16;


    float wind =
        waterWindWave(
            position +
            vec2(
                -43.0,
                57.0
            ),
            time
        )
        *
        0.10;


    return
        (
            small +
            wind
        )
        *
        fade;
}


// ============================================================
// COMPLETE HEIGHT
// ============================================================

float waterHeight(
    vec2 position,
    float time
) {

    return
        waterBroadHeight(
            position,
            time
        )
        +
        waterFineHeight(
            position,
            time
        );
}


// ============================================================
// DISPLACEMENT FADE
// ============================================================

float waterDisplacementFade(
    vec2 position
) {
    // constant: no camera-distance dependence (prevents shimmer while moving)
    return 1.0;
}


// ============================================================
// GEOMETRY DISPLACEMENT
// ============================================================
//
// ONLY LARGE + A LITTLE MEDIUM.
//
// Small and wind layers NEVER physically shake the mesh.
//

float waterDisplacementHeight(
    vec2 position,
    float time
) {

    float fade =
        waterDisplacementFade(
            position
        );


    float large =
        waterLargeWave(
            position,
            time
        );


    float medium =
        waterMediumWave(
            position,
            time
        );


    /*
        Smaller rolling movement.

        Large wave remains dominant.
        Medium wave remains subtle.
    */
    float height =
        (
            large
            +
            medium * 0.30
        )
        *
        0.30;


    return
        height *
        fade;
}


// ============================================================
// WAVE NORMAL
// ============================================================

vec3 waterWaveNormal(
    vec2 position,
    float time
) {

    const float DELTA =
        1.20;


    float center =
        waterHeight(
            position,
            time
        );


    float sampleX =
        waterHeight(
            position +
            vec2(
                DELTA,
                0.0
            ),
            time
        );


    float sampleZ =
        waterHeight(
            position +
            vec2(
                0.0,
                DELTA
            ),
            time
        );


    float slopeX =
        (
            sampleX -
            center
        )
        /
        DELTA;


    float slopeZ =
        (
            sampleZ -
            center
        )
        /
        DELTA;


    /*
        Slightly sharper normal response
        so smaller waves remain visible.
    */
    slopeX *=
        2.6;

    slopeZ *=
        2.6;


    return normalize(
        vec3(
            -slopeX,
            1.0,
            -slopeZ
        )
    );
}


// ============================================================
// CREST
// ============================================================

float waterCrest(
    vec3 normal
) {

    float slope =
        1.0 -
        normal.y;


    return
        smoothstep(
            0.022,
            0.20,
            slope
        );
}


#endif