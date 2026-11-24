// ============================================================
// ETHERREALITY GENESIS™ :: VIGNETTE
//
// Subtle cinematic edge falloff.
//
// Etherreality Genesis™ philosophy:
//   - barely visible
//   - soft
//   - elegant
//   - never crush the corners
//
// This module only calculates the vignette.
// It does NOT apply the effect to the final image by itself.
// ============================================================


// ============================================================
// VIGNETTE FACTOR
// ============================================================

float calculateGrandVignette(
    vec2 texcoord
) {

    // --------------------------------------------------------
    // Toggle
    // --------------------------------------------------------

    if (
        !GM_CAMERA_VIGNETTE
    ) {
        return 1.0;
    }


    // --------------------------------------------------------
    // Distance from screen center
    // --------------------------------------------------------

    vec2 centered =
        texcoord -
        0.5;


    // Correct for screen aspect ratio so the vignette remains
    // visually balanced on non-square resolutions.
    float aspect =
        float(
            viewWidth
        ) /
        float(
            viewHeight
        );


    centered.x *=
        aspect;


    float distanceFromCenter =
        length(
            centered
        );


    // --------------------------------------------------------
    // Soft edge
    // --------------------------------------------------------

    float vignette =
        smoothstep(
            0.30,
            0.78,
            distanceFromCenter
        );


    // --------------------------------------------------------
    // Etherreality Genesis™ strength
    // --------------------------------------------------------
    //
    // Convert the edge factor into subtle image attenuation.
    // --------------------------------------------------------

    vignette *=
        GM_VIGNETTE_STRENGTH;


    return
        1.0 -
        vignette;
}