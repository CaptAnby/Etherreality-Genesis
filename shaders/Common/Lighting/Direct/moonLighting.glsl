// ============================================================
// ETHERREALITY GENESIS :: MOON LIGHTING
//
// Direct nighttime illumination.
//
// Uses moonPosition directly.
// Moon shadows are intentionally softer than daytime shadows.
//
// Etherreality Genesis™ LIGHTING REVAMP
//
// This revision:
//   - slightly brighter moonlight
//   - cooler moonlight tone
//   - soft nighttime illumination
//   - preserves the existing soft shadow behavior
// ============================================================


vec3 calculateGrandMoonLightV2(
    vec3 albedo,
    vec3 normal,
    float shadowFactor,
    WorldLighting worldLighting
) {

    // --------------------------------------------------------
    // Moon direction
    // --------------------------------------------------------

    vec3 moonDirection =
        normalize(
            moonPosition
        );


    // --------------------------------------------------------
    // Surface response
    // --------------------------------------------------------

    float NdotMoon =
        max(
            dot(
                normal,
                moonDirection
            ),
            0.0
        );


    // --------------------------------------------------------
    // Softer realtime moon shadows
    // --------------------------------------------------------

    float moonShadowSoftness =
        0.30;


    float moonShadowVisibility =
        mix(
            shadowFactor,
            1.0,
            moonShadowSoftness
        );


    // --------------------------------------------------------
    // Etherreality Genesis™ moon color
    // --------------------------------------------------------
    //
    // Slightly cooler and cleaner than the base moon color.
    // The blue channel remains dominant without making the
    // entire nighttime scene aggressively blue.
    // --------------------------------------------------------

    vec3 moonTint =
        vec3(
            0.96,
            1.01,
            1.07
        );


    vec3 moonColor =
        worldLighting.moonColor *
        moonTint;


    // --------------------------------------------------------
    // Etherreality Genesis™ moon brightness
    // --------------------------------------------------------
    //
    // Night should remain visible and elegant, but moonlight
    // must stay clearly weaker than direct sunlight.
    // --------------------------------------------------------

    float moonlightBoost =
        1.00;


    vec3 moonLight =
        moonColor *
        NdotMoon *
        worldLighting.moonIntensity *
        moonlightBoost *
        moonShadowVisibility;


    // --------------------------------------------------------
    // Apply to surface
    // --------------------------------------------------------

    return
        albedo *
        moonLight;
}