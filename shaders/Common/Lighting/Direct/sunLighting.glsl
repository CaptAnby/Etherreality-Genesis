// ============================================================
// ETHERREALITY GENESIS :: SUN LIGHTING
//
// Dynamic direct sunlight.
//
// Receives the world-lighting state from:
//   Environment/timeLighting.glsl
//
// Etherreality Genesis™ LIGHTING REVAMP
//
// Current goals:
//   - strong, bright sunlight
//   - warm daylight
//   - readable realtime shadows
//   - softer noon brightness
//   - subtle cool-blue shadow character
//   - prevent bright blocks from clipping
//
// The shadow system itself is NOT rebuilt here.
// ============================================================


// ============================================================
// DYNAMIC SUN LIGHT
// ============================================================

vec3 calculateGrandSunLight(
    vec3 albedo,
    vec3 normal,
    vec3 lightDirection,
    float shadowFactor,
    WorldLighting worldLighting
) {

    // --------------------------------------------------------
    // Surface-to-sun response
    // --------------------------------------------------------

    float NdotL =
        max(
            dot(
                normal,
                lightDirection
            ),
            0.0
        );


    // --------------------------------------------------------
    // Shadow strength
    // --------------------------------------------------------

    float shadowStrength =
        clamp(SHADOW_STRENGTH * SUN_CONTRAST, 0.0, 0.95);


    float shadowVisibility =
        mix(
            1.0 -
            shadowStrength,
            1.0,
            shadowFactor
        );


    // ========================================================
    // TIME / NOON RESPONSE
    // ========================================================

    float angle =
        fract(
            sunAngle
        );


    float daylight =
        max(
            sin(
                angle *
                6.28318530718
            ),
            0.0
        );


    float noonMask =
        smoothstep(
            0.78,
            0.98,
            daylight
        );


    // ========================================================
    // SUN COLOR
    // ========================================================

    vec3 warmSunTint =
        vec3(
            1.06,
            1.00,
            0.88
        );


    vec3 noonCoolTint =
        vec3(
            1.08,
            0.99,
            0.84
        );


    vec3 sunTint =
        mix(
            warmSunTint,
            noonCoolTint,
            noonMask
        );
    sunTint = max(mix(vec3(1.0), sunTint, SUN_WARMTH), vec3(0.0));


    vec3 sunColor =
        worldLighting.sunColor *
        sunTint;


    // ========================================================
    // SURFACE RESPONSE
    // ========================================================

    float wrapW = 0.35 * SUN_SOFTNESS;
    float wrapN = (NdotL + wrapW) / (1.0 + wrapW);

    float softNdotL =
        pow(
            wrapN,
            mix(
                1.0,
                0.90,
                noonMask
            )
        );


    // ========================================================
    // SUNLIGHT STRENGTH
    // ========================================================

    float daylightBoost =
        1.85;


    float noonBoost =
        1.55;


    float sunlightBoost =
        mix(
            daylightBoost,
            noonBoost,
            noonMask
        );


    // ========================================================
    // DIRECT SUNLIGHT
    // ========================================================

    vec3 sunLight =
        sunColor *
        softNdotL *
        worldLighting.sunIntensity *
        sunlightBoost *
        SUN_BRIGHTNESS *
        shadowVisibility;


    // ========================================================
    // ETHERREALITY GENESIS SHADOW COLOR
    // ========================================================
    //
    // Fully lit:
    //   warm daylight remains dominant.
    //
    // Shadowed:
    //   direct sunlight is subtly shifted toward a cool blue.
    //
    // This is intentionally restrained. The shadow should read
    // as cool atmosphere, not as a blue-painted shadow.
    // ========================================================

#ifdef RAYLEIGH
    // Rayleigh: sunlight reddens with air mass (noon stays neutral).
    float rayAm = 1.0 / (daylight + 0.08);
    float rayAm0 = 1.0 / 1.08;
    vec3 rayBeta = vec3(0.58, 1.35, 3.31) * 0.13 * RAYLEIGH_STRENGTH * RAYLEIGH_SUNSET;
    sunLight *= exp(-rayBeta * max(rayAm - rayAm0, 0.0));
#endif

    // Soft golden warmth: gentle all day, strongest at sunrise/sunset.
    float goldenMask =
        smoothstep(0.0, 0.06, daylight) *
        (1.0 - smoothstep(0.12, 0.55, daylight));
    vec3 goldenTint = mix(
        vec3(1.10, 0.97, 0.80),
        vec3(1.28, 0.90, 0.62),
        goldenMask
    );
    float goldenAmt = clamp((0.30 + 0.55 * goldenMask) * SUN_GOLDEN_STRENGTH, 0.0, 1.0);
    sunLight *= mix(vec3(1.0), goldenTint, goldenAmt);
    sunLight *= 1.0 + 0.12 * goldenMask * SUN_GOLDEN_STRENGTH;

    // Vivid: slightly more saturated direct light.
    float sunLuma = dot(sunLight, vec3(0.299, 0.587, 0.114));
    sunLight = max(mix(vec3(sunLuma), sunLight, 1.0 + 0.25 * SUN_GOLDEN_STRENGTH), vec3(0.0));

    float shadowAmount =
        1.0 -
        shadowFactor;


    vec3 shadowCoolTint =
        vec3(
            0.94,
            0.98,
            1.05
        );


    vec3 shadowTintedLight =
        sunLight *
        shadowCoolTint;


    sunLight =
        mix(
            sunLight,
            shadowTintedLight,
            shadowAmount *
            0.55 * SHADOW_COOLNESS
        );


    // ========================================================
    // APPLY TO SURFACE
    // ========================================================

    return
        albedo *
        sunLight;
}