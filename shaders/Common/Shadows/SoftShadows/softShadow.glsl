#ifndef GRAND_OVERLORD_SOFT_SHADOWS_GLSL
#define GRAND_OVERLORD_SOFT_SHADOWS_GLSL

// ============================================================
// ETHERREALITY GENESIS :: SOFT SHADOWS V2
//
// Etherreality Genesis™ SHADOW REVAMP
//
// Goals:
//   - darker shadows
//   - more visible shadow definition
//   - sharper realtime shadow edges
//   - retain controlled 5x5 PCF cost
//   - avoid pitch-black collapse
//
// V2 changes:
//   - tighter penumbra
//   - stronger shadow contrast
//   - lower shadow floor
//   - slightly tighter blocker search
//   - controlled nonlinear contrast response
// ============================================================


// ============================================================
// BLOCKER SEARCH
// ============================================================

float findBlockerDepth(
    vec3 shadowPos,
    float searchRadius
) {

    float blockerDepth =
        0.0;

    float blockerCount =
        0.0;


    vec2 texelSize =
        1.0 /
        vec2(
            textureSize(
                shadowtex0,
                0
            )
        );


    for (
        int x = -2;
        x <= 2;
        x++
    ) {

        for (
            int y = -2;
            y <= 2;
            y++
        ) {

            vec2 offset =
                vec2(
                    x,
                    y
                ) *
                texelSize *
                searchRadius;


            float depth =
                sampleShadowDepth(
                    shadowPos.xy +
                    offset
                );


            if (
                depth <
                shadowPos.z
            ) {

                blockerDepth +=
                    depth;

                blockerCount +=
                    1.0;
            }
        }
    }


    if (
        blockerCount <=
        0.0
    ) {

        return -1.0;
    }


    return
        blockerDepth /
        blockerCount;
}


// ============================================================
// SOFT SHADOW
// ============================================================

float sampleSoftShadow(
    vec3 shadowPos
) {

    // --------------------------------------------------------
    // Outside shadow map
    // --------------------------------------------------------

    if (
        shadowPos.x < 0.0 ||
        shadowPos.x > 1.0 ||
        shadowPos.y < 0.0 ||
        shadowPos.y > 1.0
    ) {

        return 1.0;
    }


    // --------------------------------------------------------
    // Blocker search
    // --------------------------------------------------------
    //
    // Smaller search region keeps the blocker estimate local,
    // which helps preserve sharper shadow boundaries.
    // --------------------------------------------------------

    float blockerDepth =
        findBlockerDepth(
            shadowPos,
            0.80
        );


    if (
        blockerDepth < 0.0
    ) {

        return 1.0;
    }


    // --------------------------------------------------------
    // Receiver distance
    // --------------------------------------------------------

    float receiverDistance =
        max(
            shadowPos.z -
            blockerDepth,
            0.0
        );


    // --------------------------------------------------------
    // TIGHT GM PENUMBRA
    // --------------------------------------------------------
    //
    // Smaller than the previous 1.0 → 3.0 range.
    //
    // This keeps the shadow edge readable and avoids the
    // "blurred fog shadow" appearance.
    // --------------------------------------------------------

    float penumbraRadius =
        clamp(
            receiverDistance *
            8.0,
            0.90 * SHADOW_SOFTNESS,
            2.00 * SHADOW_SOFTNESS
        );


    // --------------------------------------------------------
    // PCF accumulation
    // --------------------------------------------------------

    float shadow =
        0.0;


    vec2 texelSize =
        1.0 /
        vec2(
            textureSize(
                shadowtex0,
                0
            )
        );


    for (
        int x = -2;
        x <= 2;
        x++
    ) {

        for (
            int y = -2;
        y <= 2;
        y++
        ) {

            vec2 offset =
                vec2(
                    x,
                    y
                ) *
                texelSize *
                penumbraRadius;


            float depth =
                sampleShadowDepth(
                    shadowPos.xy +
                    offset
                );


            shadow +=
                shadowPos.z <= depth
                ? 1.0
                : 0.0;
        }
    }


    float visibility =
        shadow /
        25.0;


    // --------------------------------------------------------
    // STRONGER SHADOW CONTRAST
    // --------------------------------------------------------
    //
    // Push intermediate visibility values darker while keeping
    // fully lit regions at 1.0.
    //
    // This makes cast shadows feel denser and more readable
    // without simply crushing everything to black.
    // --------------------------------------------------------

    visibility =
        pow(
            visibility,
            1.10
        );


    // --------------------------------------------------------
    // ETHERREALITY GENESIS SHADOW FLOOR
    // --------------------------------------------------------
    //
    // Darker than the previous 0.18 floor, but still prevents
    // a complete black collapse in heavily shadowed areas.
    // --------------------------------------------------------

    const float shadowFloor =
        0.14;


    visibility =
        max(
            visibility,
            shadowFloor
        );


    // --------------------------------------------------------
    // FINAL SHADOW RANGE
    // --------------------------------------------------------

    return
        clamp(
            visibility,
            shadowFloor,
            1.0
        );
}

#endif