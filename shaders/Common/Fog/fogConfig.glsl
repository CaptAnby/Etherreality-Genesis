#ifndef GRAND_OVERLORD_FOG_CONFIG_GLSL
#define GRAND_OVERLORD_FOG_CONFIG_GLSL

// ============================================================
// ETHERREALITY GENESIS :: VOLUMETRIC FOG V9 :: LEVEL PRESETS
//
// Select one preset with GRAND_FOG_LEVEL:
//   GRAND_FOG_LEVEL_LOW  = small, visible ground patches
//   GRAND_FOG_LEVEL_MID  = larger, fuller banks (V8 baseline)
//   GRAND_FOG_LEVEL_HIGH = densest, taller banks for mountains
//
// Only the fog profile changes. Lighting colors/response remain
// the V8 thick-white-mist baseline. The density module consumes
// these macros; no raymarch or cloud files need replacement.
// ============================================================

#define GRAND_FOG_LEVEL_LOW   1
#define GRAND_FOG_LEVEL_MID   2
#define GRAND_FOG_LEVEL_HIGH  3

// EDIT THIS LINE TO SELECT LOW, MID, OR HIGH.
// Default is MID to preserve the familiar V8 appearance.
#define GRAND_FOG_LEVEL GRAND_FOG_LEVEL_MID

// ------------------------------------------------------------
// COMMON DISTANCE / RAYMARCH SETTINGS
// ------------------------------------------------------------
#define GRAND_FOG_RAYMARCH_STEPS            24
#define GRAND_FOG_MIN_STEPS                 8
#define GRAND_FOG_TARGET_STEP_LENGTH        32.0
#define GRAND_FOG_EMPTY_THRESHOLD           0.00001
#define GRAND_FOG_OPAQUE_TRANSMITTANCE      0.015
#define GRAND_FOG_TIME_SCALE                (0.0010 * VOL_FOG_WIND_SPEED)

// ------------------------------------------------------------
// PRESET-SPECIFIC FOG SHAPE AND DENSITY
// ------------------------------------------------------------
#if GRAND_FOG_LEVEL == GRAND_FOG_LEVEL_LOW

    // LOW: visible, smaller, separated patches.
    #define GRAND_FOG_MAX_DISTANCE              620.0
    #define GRAND_FOG_SKY_DISTANCE              320.0
    #define GRAND_FOG_BASE_DENSITY              (0.00215 * VOL_FOG_DENSITY)
    #define GRAND_FOG_EXTINCTION                1.04

    #define GRAND_FOG_BASE_HEIGHT               (60.0 + (70.0 - 60.0) * VOL_FOG_HEIGHT)
    #define GRAND_FOG_GROUND_SOFTNESS           43.0
    #define GRAND_FOG_HEIGHT_FALLOFF            0.034

    // Higher frequency means smaller bank patches.
    #define GRAND_FOG_BANK_NOISE_SCALE          (0.0090 / VOL_FOG_SCALE)
    #define GRAND_FOG_BANK_VERTICAL_SCALE       1.85
    #define GRAND_FOG_BANK_THRESHOLD_LOW        0.38
    #define GRAND_FOG_BANK_THRESHOLD_HIGH       0.69

    #define GRAND_FOG_DETAIL_NOISE_SCALE        (0.0260 / VOL_FOG_SCALE)
    #define GRAND_FOG_DETAIL_VERTICAL_SCALE     1.45
    #define GRAND_FOG_DETAIL_MIN                0.80
    #define GRAND_FOG_DETAIL_MAX                1.18
    #define GRAND_FOG_BANK_GAP_DENSITY          0.035
    #define GRAND_FOG_BANK_PEAK_DENSITY         1.32

#elif GRAND_FOG_LEVEL == GRAND_FOG_LEVEL_MID

    // MID: preserve V8's proven thick, visible white mist banks.
    #define GRAND_FOG_MAX_DISTANCE              760.0
    #define GRAND_FOG_SKY_DISTANCE              480.0
    #define GRAND_FOG_BASE_DENSITY              (0.00320 * VOL_FOG_DENSITY)
    #define GRAND_FOG_EXTINCTION                1.18

    #define GRAND_FOG_BASE_HEIGHT               (60.0 + (70.0 - 60.0) * VOL_FOG_HEIGHT)
    #define GRAND_FOG_GROUND_SOFTNESS           54.0
    #define GRAND_FOG_HEIGHT_FALLOFF            0.030

    #define GRAND_FOG_BANK_NOISE_SCALE          (0.0062 / VOL_FOG_SCALE)
    #define GRAND_FOG_BANK_VERTICAL_SCALE       1.70
    #define GRAND_FOG_BANK_THRESHOLD_LOW        0.28
    #define GRAND_FOG_BANK_THRESHOLD_HIGH       0.60

    #define GRAND_FOG_DETAIL_NOISE_SCALE        (0.0220 / VOL_FOG_SCALE)
    #define GRAND_FOG_DETAIL_VERTICAL_SCALE     1.35
    #define GRAND_FOG_DETAIL_MIN                0.72
    #define GRAND_FOG_DETAIL_MAX                1.28
    #define GRAND_FOG_BANK_GAP_DENSITY          0.075
    #define GRAND_FOG_BANK_PEAK_DENSITY         1.85

#elif GRAND_FOG_LEVEL == GRAND_FOG_LEVEL_HIGH

    // HIGH: denser, broader and taller mist banks. The expanded
    // height envelope helps fog remain visible around mountains
    // and tall structures. This is still an absolute world-height
    // envelope, not terrain-following fog.
    #define GRAND_FOG_MAX_DISTANCE              920.0
    #define GRAND_FOG_SKY_DISTANCE              540.0
    #define GRAND_FOG_BASE_DENSITY              (0.00425 * VOL_FOG_DENSITY)
    #define GRAND_FOG_EXTINCTION                1.26

    #define GRAND_FOG_BASE_HEIGHT               (60.0 + (100.0 - 60.0) * VOL_FOG_HEIGHT)
    #define GRAND_FOG_GROUND_SOFTNESS           96.0
    #define GRAND_FOG_HEIGHT_FALLOFF            0.014

    // Lower frequency creates larger chunks; weaker vertical
    // frequency stretches those banks higher into the scene.
    #define GRAND_FOG_BANK_NOISE_SCALE          (0.0052 / VOL_FOG_SCALE)
    #define GRAND_FOG_BANK_VERTICAL_SCALE       1.20
    #define GRAND_FOG_BANK_THRESHOLD_LOW        0.25
    #define GRAND_FOG_BANK_THRESHOLD_HIGH       0.58

    #define GRAND_FOG_DETAIL_NOISE_SCALE        (0.0190 / VOL_FOG_SCALE)
    #define GRAND_FOG_DETAIL_VERTICAL_SCALE     1.20
    #define GRAND_FOG_DETAIL_MIN                0.68
    #define GRAND_FOG_DETAIL_MAX                1.34
    #define GRAND_FOG_BANK_GAP_DENSITY          0.095
    #define GRAND_FOG_BANK_PEAK_DENSITY         2.15

#else
    #error Invalid GRAND_FOG_LEVEL. Choose LOW (1), MID (2), or HIGH (3).
#endif

// ------------------------------------------------------------
// WIND / WEATHER (shared by all levels)
// ------------------------------------------------------------
#define GRAND_FOG_WIND_DIRECTION             vec2(1.0, 0.28)
#define GRAND_FOG_WIND_SPEED                 0.075
#define GRAND_FOG_WEATHER_MULTIPLIER         1.0

// ------------------------------------------------------------
// LIGHTING — V8 WHITE MIST BASELINE, UNCHANGED
// ------------------------------------------------------------
#define GRAND_FOG_DAY_AMBIENT_COLOR          vec3(0.98, 0.985, 1.00)
#define GRAND_FOG_TWILIGHT_AMBIENT_COLOR     vec3(0.94, 0.82, 0.72)
#define GRAND_FOG_NIGHT_AMBIENT_COLOR        vec3(0.38, 0.43, 0.52)

#define GRAND_FOG_DAY_SUN_COLOR              vec3(1.00, 0.995, 0.98)
#define GRAND_FOG_TWILIGHT_SUN_COLOR         vec3(1.00, 0.79, 0.62)

#define GRAND_FOG_AMBIENT_STRENGTH           (0.60 * VOL_FOG_BRIGHTNESS)
#define GRAND_FOG_DIRECT_STRENGTH            (0.58 * VOL_FOG_BRIGHTNESS)
#define GRAND_FOG_NIGHT_AMBIENT_STRENGTH     0.24
#define GRAND_FOG_MAX_LIGHT                  1.35

#define GRAND_FOG_PHASE_G                    0.44
#define GRAND_FOG_PHASE_SCALE                1.65
#define GRAND_FOG_PHASE_MIN                  0.62
#define GRAND_FOG_PHASE_MAX                  1.25

#define GRAND_FOG_DAY_START                  0.025
#define GRAND_FOG_DAY_FULL                   0.17
#define GRAND_FOG_NIGHT_START                0.08
#define GRAND_FOG_NIGHT_FULL                 0.34
#define GRAND_FOG_TWILIGHT_WIDTH             0.24

#endif
