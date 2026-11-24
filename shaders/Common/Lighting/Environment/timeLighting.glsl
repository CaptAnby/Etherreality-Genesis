// ============================================================
// ETHERREALITY GENESIS :: TIME LIGHTING
//
// Central dynamic world-lighting cycle.
//
// sunAngle:
//
//   0.00 = Sunrise
//   0.25 = Noon
//   0.50 = Sunset
//   0.75 = Midnight
//   1.00 = Sunrise again
//
// Etherreality Genesis™ LIGHTING REVAMP
//
// Goals:
//   - bright, elegant daylight
//   - warm but controlled sunlight
//   - softer overall transitions
//   - subtle pale sky-blue world tone
//   - cool but properly dark nighttime
//   - smoother day/night transitions
//   - prevent bright surfaces from appearing blown out
//   - prevent deep areas from becoming pitch black
//
// Designed so Cloud Lighting can later consume the same
// WorldLighting result.
// ============================================================


// ============================================================
// WORLD LIGHTING STATE
// ============================================================

struct WorldLighting {

    vec3 sunColor;
    float sunIntensity;

    vec3 ambientColor;
    float ambientStrength;

    vec3 skyColor;

    vec3 moonColor;
    float moonIntensity;
};


// ============================================================
// COLOR HELPERS
// ============================================================

vec3 grandMixColor(
    vec3 a,
    vec3 b,
    float t
) {

    return mix(
        a,
        b,
        clamp(
            t,
            0.0,
            1.0
        )
    );
}


// ============================================================
// SEGMENT HELPERS
// ============================================================

float grandSegment(
    float value,
    float startValue,
    float endValue
) {

    float t =
        (
            value -
            startValue
        ) /
        max(
            endValue -
            startValue,
            0.0001
        );

    t =
        clamp(
            t,
            0.0,
            1.0
        );

    return
        t *
        t *
        (
            3.0 -
            2.0 *
            t
        );
}


// ============================================================
// SUN COLOR
// ============================================================
//
// Sunrise:
//   warm yellow with subtle orange
//
// Morning:
//   gradually becomes clean warm daylight
//
// Noon:
//   bright warm-white with a tiny cool atmospheric influence
//
// Afternoon:
//   slightly warmer
//
// Sunset:
//   stronger golden/orange influence
//
// Night:
//   cool blue
//
// Midnight:
//   deeper cool blue-gray
// ============================================================

vec3 getGrandSunColor(
    float angle
) {

    vec3 sunriseYellow =
        vec3(
            1.00,
            0.80,
            0.30
        );


    vec3 sunriseOrange =
        vec3(
            1.00,
            0.50,
            0.16
        );


    vec3 sunriseColor =
        mix(
            sunriseYellow,
            sunriseOrange,
            0.22
        );


    // Slightly warmer than the original noon,
    // but not pure white.
    vec3 noonColor =
        vec3(
            1.00,
            0.945,
            0.84
        );


    vec3 afternoonColor =
        vec3(
            1.00,
            0.91,
            0.70
        );


    vec3 goldenColor =
        vec3(
            1.00,
            0.77,
            0.34
        );


    vec3 sunsetColor =
        mix(
            vec3(
                1.00,
                0.73,
                0.28
            ),
            vec3(
                1.00,
                0.45,
                0.16
            ),
            0.50
        );


    vec3 nightColor =
        vec3(
            0.56,
            0.72,
            1.00
        );


    vec3 midnightColor =
        mix(
            vec3(
                0.16,
                0.19,
                0.24
            ),
            vec3(
                0.36,
                0.49,
                0.75
            ),
            0.50
        );


    // --------------------------------------------------------
    // Sunrise → Noon
    // --------------------------------------------------------

    if (
        angle < 0.25
    ) {

        float t =
            grandSegment(
                angle,
                0.00,
                0.25
            );


        return
            grandMixColor(
                sunriseColor,
                noonColor,
                t
            );
    }


    // --------------------------------------------------------
    // Noon → Sunset
    // --------------------------------------------------------

    if (
        angle < 0.50
    ) {

        float t =
            grandSegment(
                angle,
                0.25,
                0.50
            );


        vec3 noonToAfternoon =
            grandMixColor(
                noonColor,
                afternoonColor,
                t *
                0.70
            );


        float golden =
            smoothstep(
                0.42,
                0.92,
                t
            );


        vec3 warmTransition =
            grandMixColor(
                noonToAfternoon,
                goldenColor,
                golden
            );


        return
            grandMixColor(
                warmTransition,
                sunsetColor,
                t *
                t
            );
    }


    // --------------------------------------------------------
    // Sunset → Midnight
    // --------------------------------------------------------

    if (
        angle < 0.75
    ) {

        float t =
            grandSegment(
                angle,
                0.50,
                0.75
            );


        return
            grandMixColor(
                sunsetColor,
                midnightColor,
                t
            );
    }


    // --------------------------------------------------------
    // Midnight → Sunrise
    // --------------------------------------------------------

    float t =
        grandSegment(
            angle,
            0.75,
            1.00
        );


    return
        grandMixColor(
            midnightColor,
            sunriseColor,
            t
        );
}


// ============================================================
// SUN INTENSITY
// ============================================================
//
// Etherreality Genesis™:
//
// Bright, elegant daylight.
// Noon remains strong but restrained by the base curve.
//
// Horizon light remains present but controlled.
// ============================================================

float getGrandSunIntensity(
    float angle
) {

    float daylight =
        sin(
            angle *
            6.28318530718
        );


    daylight =
        max(
            daylight,
            0.0
        );


    // Softer daylight response.
    float daylightPower =
        pow(
            daylight,
            0.52
        );


    float horizonWarmth =
        1.0 -
        clamp(
            abs(
                daylight
            ),
            0.0,
            1.0
        );


    // Base intensity used by the direct sunlight system.
    float intensity =
        mix(
            0.06,
            0.95,
            daylightPower
        );


    // Small horizon lift for elegant sunrise/sunset light.
    intensity +=
        horizonWarmth *
        0.08;


    // The sun contributes nothing once it is below the horizon
    // (night light comes from the moon only).
    intensity *=
        smoothstep(
            0.0,
            0.10,
            sin(
                angle *
                6.28318530718
            )
        );

    return
        clamp(
            intensity,
            0.0,
            1.0
        );
}


// ============================================================
// AMBIENT COLOR
// ============================================================
//
// Etherreality Genesis™ permanent atmospheric character:
//
//   pale/cool blue remains present throughout the world
//   without turning the whole scene blue.
//
// Noon:
//   bright pale blue
//
// Afternoon:
//   pale blue with slight warmth
//
// Sunset:
//   warm influence
//
// Night:
//   cool-blue ambience
//
// Midnight:
//   dark gray + cool blue
// ============================================================

vec3 getGrandAmbientColor(
    float angle
) {

    vec3 dawnBlue =
        vec3(
            0.50,
            0.67,
            0.94
        );


    vec3 noonBlue =
        vec3(
            0.76,
            0.86,
            0.985
        );


    vec3 afternoonBlue =
        vec3(
            0.77,
            0.85,
            0.96
        );


    vec3 goldenAmbient =
        mix(
            vec3(
                1.00,
                0.78,
                0.38
            ),
            vec3(
                0.97,
                0.55,
                0.26
            ),
            0.20
        );


    vec3 sunsetAmbient =
        mix(
            vec3(
                1.00,
                0.70,
                0.32
            ),
            vec3(
                0.95,
                0.47,
                0.22
            ),
            0.50
        );


    vec3 nightBlue =
        vec3(
            0.46,
            0.62,
            0.90
        );


    vec3 midnightGrayBlue =
        mix(
            vec3(
                0.14,
                0.17,
                0.21
            ),
            vec3(
                0.34,
                0.47,
                0.72
            ),
            0.50
        );


    // --------------------------------------------------------
    // Sunrise → Noon
    // --------------------------------------------------------

    if (
        angle < 0.25
    ) {

        float t =
            grandSegment(
                angle,
                0.00,
                0.25
            );


        return
            grandMixColor(
                dawnBlue,
                noonBlue,
                t
            );
    }


    // --------------------------------------------------------
    // Noon → Sunset
    // --------------------------------------------------------

    if (
        angle < 0.50
    ) {

        float t =
            grandSegment(
                angle,
                0.25,
                0.50
            );


        vec3 afternoon =
            grandMixColor(
                noonBlue,
                afternoonBlue,
                t
            );


        float golden =
            smoothstep(
                0.52,
                0.94,
                t
            );


        return
            grandMixColor(
                afternoon,
                goldenAmbient,
                golden
            );
    }


    // --------------------------------------------------------
    // Sunset → Midnight
    // --------------------------------------------------------

    if (
        angle < 0.75
    ) {

        float t =
            grandSegment(
                angle,
                0.50,
                0.75
            );


        return
            grandMixColor(
                sunsetAmbient,
                midnightGrayBlue,
                t
            );
    }


    // --------------------------------------------------------
    // Midnight → Sunrise
    // --------------------------------------------------------

    float t =
        grandSegment(
            angle,
            0.75,
            1.00
        );


    return
        grandMixColor(
            midnightGrayBlue,
            dawnBlue,
            t
        );
}


// ============================================================
// AMBIENT STRENGTH
// ============================================================
//
// Etherreality Genesis™ DARK-AREA REVAMP
//
// Day:
//   stronger soft fill
//
// Night:
//   restrained cool fill
//
// The ambient floor is enough to preserve readable detail,
// but nighttime remains distinctly dark.
// ============================================================

float getGrandAmbientStrength(
    float angle
) {

    float daylight =
        max(
            sin(
                angle *
                6.28318530718
            ),
            0.0
        );


    float daylightPower =
        pow(
            daylight,
            0.48
        );


    // Strong daytime fill.
    float dayAmbient =
        mix(
            0.34,
            0.44,
            daylightPower
        );


    // Reduced nighttime floor.
    float nightAmbient =
        0.020;


    // Night keeps its calm dark level; day gets a soft, bright fill.
    return
        mix(
            0.13,
            dayAmbient,
            smoothstep(
                0.0,
                0.25,
                daylight
            )
        );
}


// ============================================================
// SKY COLOR
// ============================================================
//
// Target:
//
//   Real-life atmosphere
//          +
//   Anime clarity
//
// The sky remains cool/pale blue for most of the cycle,
// while the horizon receives stronger warm transition colors.
//
// The permanent cool atmosphere is intentional.
// ============================================================

vec3 getGrandSkyColor(
    float angle
) {

    vec3 dawn =
        vec3(
            0.38,
            0.56,
            0.90
        );


    vec3 sunriseSky =
        vec3(
            0.66,
            0.78,
            0.97
        );


    vec3 noon =
        vec3(
            0.73,
            0.85,
            0.99
        );


    vec3 afternoon =
        vec3(
            0.76,
            0.85,
            0.97
        );


    vec3 laterAfternoon =
        vec3(
            0.84,
            0.85,
            0.90
        );


    vec3 sunset =
        mix(
            vec3(
                1.00,
                0.78,
                0.32
            ),
            vec3(
                1.00,
                0.50,
                0.21
            ),
            0.50
        );


    vec3 night =
        vec3(
            0.50,
            0.66,
            0.94
        );


    vec3 midnight =
        mix(
            vec3(
                0.11,
                0.14,
                0.18
            ),
            vec3(
                0.30,
                0.42,
                0.66
            ),
            0.50
        );


    // --------------------------------------------------------
    // Dawn → Noon
    // --------------------------------------------------------

    if (
        angle < 0.25
    ) {

        float dawnToSunrise =
            grandSegment(
                angle,
                0.00,
                0.10
            );


        if (
            angle < 0.10
        ) {

            return
                grandMixColor(
                    dawn,
                    sunriseSky,
                    dawnToSunrise
                );
        }


        float sunriseToNoon =
            grandSegment(
                angle,
                0.10,
                0.25
            );


        return
            grandMixColor(
                sunriseSky,
                noon,
                sunriseToNoon
            );
    }


    // --------------------------------------------------------
    // Noon → Sunset
    // --------------------------------------------------------

    if (
        angle < 0.50
    ) {

        float t =
            grandSegment(
                angle,
                0.25,
                0.50
            );


        if (
            t < 0.60
        ) {

            float afternoonT =
                grandSegment(
                    t,
                    0.0,
                    0.60
                );


            return
                grandMixColor(
                    noon,
                    afternoon,
                    afternoonT
                );
        }


        float goldenT =
            grandSegment(
                t,
                0.60,
                1.0
            );


        return
            grandMixColor(
                afternoon,
                laterAfternoon,
                goldenT
            );
    }


    // --------------------------------------------------------
    // Sunset transition
    // --------------------------------------------------------

    if (
        angle < 0.56
    ) {

        float t =
            grandSegment(
                angle,
                0.50,
                0.56
            );


        return
            grandMixColor(
                laterAfternoon,
                sunset,
                t
            );
    }


    // --------------------------------------------------------
    // Sunset → Midnight
    // --------------------------------------------------------

    if (
        angle < 0.75
    ) {

        float t =
            grandSegment(
                angle,
                0.56,
                0.75
            );


        return
            grandMixColor(
                sunset,
                midnight,
                t
            );
    }


    // --------------------------------------------------------
    // Midnight → Dawn
    // --------------------------------------------------------

    float t =
        grandSegment(
            angle,
            0.75,
            1.00
        );


    return
        grandMixColor(
            midnight,
            night,
            t
        );
}


// ============================================================
// MOON COLOR
// ============================================================
//
// Cool and elegant GM moonlight.
// ============================================================

vec3 getGrandMoonColor() {

    return
        vec3(
            0.62,
            0.76,
            1.00
        );
}


// ============================================================
// MOON INTENSITY
// ============================================================
//
// Moonlight remains visible at night,
// but is now restrained so the world does not become
// excessively illuminated after sunset.
// ============================================================

float getGrandMoonIntensity(
    float angle
) {

    float daylight =
        max(
            sin(
                angle *
                6.28318530718
            ),
            0.0
        );


    float nightAmount =
        1.0 -
        smoothstep(
            0.0,
            0.30,
            daylight
        );


    // Reduced from 0.70 so nighttime remains darker.
    return
        nightAmount *
        0.15;
}


// ============================================================
// COMPLETE WORLD LIGHTING
// ============================================================

WorldLighting getWorldLighting() {

    WorldLighting lighting;


    float angle =
        fract(
            sunAngle
        );


    // --------------------------------------------------------
    // Sun
    // --------------------------------------------------------

    lighting.sunColor =
        getGrandSunColor(
            angle
        );


    lighting.sunIntensity =
        getGrandSunIntensity(
            angle
        );


    // --------------------------------------------------------
    // Ambient
    // --------------------------------------------------------

    lighting.ambientColor =
        getGrandAmbientColor(
            angle
        );


    lighting.ambientStrength =
        getGrandAmbientStrength(
            angle
        );


    // --------------------------------------------------------
    // Sky
    // --------------------------------------------------------

    lighting.skyColor =
        getGrandSkyColor(
            angle
        );


    // --------------------------------------------------------
    // Moon
    // --------------------------------------------------------

    lighting.moonColor =
        getGrandMoonColor();


    lighting.moonIntensity =
        getGrandMoonIntensity(
            angle
        );


    return
        lighting;
}