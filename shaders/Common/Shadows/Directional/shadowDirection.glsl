// ============================================================
// ETHERREALITY GENESIS :: SHADOW LIGHT DIRECTION
//
// Returns the active celestial light direction.
//
// Day:
//   Sun
//
// Night:
//   Moon
//
// This keeps the rest of the shadow system unchanged.
// ============================================================


vec3 getShadowLightDirection() {

    float angle =
        fract(
            sunAngle
        );


    // --------------------------------------------------------
    // Day / night factor
    // --------------------------------------------------------
    //
    // 0.00 = sunrise
    // 0.25 = noon
    // 0.50 = sunset
    // 0.75 = midnight
    //
    // Positive sine = daylight.
    // --------------------------------------------------------

    float daylight =
        sin(
            angle *
            6.28318530718
        );


    // --------------------------------------------------------
    // Select celestial source
    // --------------------------------------------------------

    if (
        daylight >= 0.0
    ) {

        return normalize(
            sunPosition
        );

    }


    return normalize(
        moonPosition
    );
}