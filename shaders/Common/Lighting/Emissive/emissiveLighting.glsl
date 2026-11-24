// ============================================================
// ETHERREALITY GENESIS :: EMISSIVE LIGHTING
//
// Stage 1 local-light foundation.
//
// Uses Minecraft's lightmap as the source of local/emissive
// illumination.
//
// This is intentionally separate from:
//   - sun lighting
//   - moon lighting
//   - ambient lighting
//
// Future Stage 2:
//   - explicit local light sources
//   - local-light shadowing
//   - torch / lantern point shadows
// ============================================================


// ============================================================
// EMISSIVE COLOR
// ============================================================
//
// Local Minecraft light is pushed toward a warm torch-like
// response while preserving the existing lightmap intensity.
// ============================================================

vec3 getGrandEmissiveColor(
    vec3 blockLight
) {

    float intensity =
        max(
            max(
                blockLight.r,
                blockLight.g
            ),
            blockLight.b
        );


    // Warm local-light response.
    vec3 warmLight =
        vec3(
            1.00,
            0.72,
            0.40
        );


    // Preserve brighter colored lightmap information while
    // giving ordinary torch-like light a warm appearance.
    vec3 coloredLight =
        mix(
            warmLight,
            max(
                blockLight,
                vec3(
                    0.0
                )
            ),
            0.35
        );


    return
        coloredLight *
        intensity;
}


// ============================================================
// LOCAL LIGHT CONTRIBUTION
// ============================================================

vec3 calculateGrandEmissiveLight(
    vec3 albedo,
    vec3 blockLight
) {

    vec3 emissiveColor =
        getGrandEmissiveColor(
            blockLight
        );


    // Keep local light independent from direct sunlight.
    float strength =
        0.85;


    return
        albedo *
        emissiveColor *
        strength;
}