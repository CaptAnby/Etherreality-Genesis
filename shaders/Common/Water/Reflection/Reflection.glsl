 // ============================================================
// ETHERREALITY GENESIS™ :: REALTIME WATER REFLECTION
//
// STABLE SSR WATER REFLECTION
//
// Goals:
//
//     - real rendered scene reflection
//     - surface-attached reflection
//     - reduced stretching
//     - reduced false hits
//     - tighter depth intersection
//     - binary-search refinement
//     - screen-edge rejection
//
// Reflection RGB:
//
//     actual colortex0 scene image
//
// Reflection alpha:
//
//     confidence
//
// Uniforms are supplied by composite.fsh / Iris:
// 
//     colortex0
//     colortex7
//     depthtex1
//     gbufferProjection
//     getViewPos()
// ============================================================


// ============================================================
// WATER FRESNEL
// ============================================================

float waterFresnel(
    vec3 viewToCamera,
    vec3 normal,
    float ior
) {
    float cosTheta =
        clamp(
            dot(
                viewToCamera,
                normal
            ),
            0.0,
            1.0
        );


    float r0 =
        (1.0 - ior) /
        (1.0 + ior);


    r0 *= r0;


    return
        r0 +
        (1.0 - r0) *
        pow(
            1.0 - cosTheta,
            5.0
        );
}


// ============================================================
// PROJECT VIEW POSITION → SCREEN
// ============================================================
//
// Returns:
//
//     uv    = screen coordinates
//     depth = projected 0..1 depth
// ============================================================

bool projectReflectionPoint(
    vec3 viewPosition,
    out vec2 uv,
    out float depth
) {
    vec4 clipPosition =
        gbufferProjection *
        vec4(
            viewPosition,
            1.0
        );


    if (
        clipPosition.w <= 0.0
    ) {
        return false;
    }


    vec3 ndc =
        clipPosition.xyz /
        clipPosition.w;


    uv =
        ndc.xy *
        0.5 +
        0.5;


    depth =
        ndc.z *
        0.5 +
        0.5;


    if (
        uv.x <= 0.002 ||
        uv.x >= 0.998 ||
        uv.y <= 0.002 ||
        uv.y >= 0.998
    ) {
        return false;
    }


    if (
        depth < 0.0 ||
        depth > 1.0
    ) {
        return false;
    }


    return true;
}


// ============================================================
// SCREEN EDGE CONFIDENCE
// ============================================================

float reflectionEdgeConfidence(
    vec2 uv
) {
    float edgeX =
        min(
            uv.x,
            1.0 - uv.x
        );


    float edgeY =
        min(
            uv.y,
            1.0 - uv.y
        );


    float edge =
        min(
            edgeX,
            edgeY
        );


    return smoothstep(
        0.0,
        0.085,
        edge
    );
}


// ============================================================
// DISTANCE CONFIDENCE
// ============================================================

float reflectionDistanceConfidence(
    float distanceTravelled
) {
    return
        1.0 -
        smoothstep(
            26.0,
            48.0,
            distanceTravelled
        );
}


// ============================================================
// LINEAR VIEW DEPTH
// ============================================================
//
// Minecraft/OpenGL view space looks down -Z.
//
// Therefore:
//
//     -viewPosition.z
//
// is the positive distance from the camera along view depth.
// ============================================================

float getLinearViewDepth(
    vec3 viewPosition
) {
    return max(
        -viewPosition.z,
        0.0
    );
}


// ============================================================
// REALTIME SCREEN-SPACE REFLECTION
// ============================================================
//
// Returns:
//
//     RGB = actual reflected scene image
//     A   = confidence
// ============================================================

vec4 screenSpaceReflection(
    vec3 viewPos,
    vec3 normal,
    vec3 skyFallback
) {
    normal =
        normalize(
            normal
        );


    // ========================================================
    // INCIDENT DIRECTION
    // ========================================================

    vec3 incidentDir =
        normalize(
            viewPos
        );


    // ========================================================
    // REFLECTION DIRECTION
    // ========================================================

    vec3 reflectDir =
        normalize(
            reflect(
                incidentDir,
                normal
            )
        );


    // ========================================================
    // VALIDATE RAY
    // ========================================================

    if (
        dot(
            reflectDir,
            normal
        ) <= 0.0
    ) {
        return vec4(
            skyFallback,
            0.0
        );
    }


    // ========================================================
    // START ABOVE WATER
    // ========================================================

    vec3 rayPos =
        viewPos +
        reflectDir *
        0.045;


    vec3 previousRayPos =
        rayPos;


    // ========================================================
    // RAY SETTINGS
    // ========================================================

    float stepSize =
        0.055;


    float travelled =
        0.0;


    const float MAX_DISTANCE =
        48.0;


    const int MAX_STEPS =
        96;


    const int BINARY_STEPS =
        10;


    // ========================================================
    // RAYMARCH
    // ========================================================

    for (
        int i = 0;
        i < MAX_STEPS;
        i++
    ) {

        previousRayPos =
            rayPos;


        rayPos +=
            reflectDir *
            stepSize;


        travelled +=
            stepSize;


        // ----------------------------------------------------
        // MAX RAY DISTANCE
        // ----------------------------------------------------

        if (
            travelled >
            MAX_DISTANCE
        ) {
            return vec4(
                skyFallback,
                0.0
            );
        }


        // ----------------------------------------------------
        // PROJECT
        // ----------------------------------------------------

        vec2 rayUV;

        float rayProjectedDepth;


        if (
            !projectReflectionPoint(
                rayPos,
                rayUV,
                rayProjectedDepth
            )
        ) {
            return vec4(
                skyFallback,
                0.0
            );
        }


        // ----------------------------------------------------
        // SCENE DEPTH
        // ----------------------------------------------------

        float sceneDepth =
            texture2D(
                depthtex1,
                rayUV
            ).r;


        // ----------------------------------------------------
        // SKY
        // ----------------------------------------------------

        if (
            sceneDepth >=
            0.999999
        ) {
            return vec4(
                skyFallback,
                0.0
            );
        }


        // ----------------------------------------------------
        // SCENE POSITION
        // ----------------------------------------------------

        vec3 sceneView =
            getViewPos(
                rayUV,
                sceneDepth
            );


        // ----------------------------------------------------
        // LINEAR DEPTH COMPARISON
        // ----------------------------------------------------

        float rayLinearDepth =
            getLinearViewDepth(
                rayPos
            );


        float sceneLinearDepth =
            getLinearViewDepth(
                sceneView
            );


        // ----------------------------------------------------
        // DEPTH THICKNESS
        // ----------------------------------------------------
        //
        // Small near the camera.
        // Gradually increases at distance to tolerate depth
        // precision without producing huge false intersections.
        // ----------------------------------------------------

        float thickness =
            0.035 +
            sceneLinearDepth *
            0.002;


        thickness =
            clamp(
                thickness,
                0.035,
                0.18
            );


        // ====================================================
        // HIT
        // ====================================================

        if (
            rayLinearDepth >
            sceneLinearDepth +
            thickness
        ) {

            // =================================================
            // BINARY SEARCH
            // =================================================

            vec3 lo =
                previousRayPos;


            vec3 hi =
                rayPos;


            for (
                int j = 0;
                j < BINARY_STEPS;
                j++
            ) {

                vec3 mid =
                    (lo + hi) *
                    0.5;


                vec2 midUV;

                float midProjectedDepth;


                if (
                    !projectReflectionPoint(
                        mid,
                        midUV,
                        midProjectedDepth
                    )
                ) {

                    hi =
                        mid;

                    continue;
                }


                float midSceneDepth =
                    texture2D(
                        depthtex1,
                        midUV
                    ).r;


                if (
                    midSceneDepth >=
                    0.999999
                ) {

                    lo =
                        mid;

                    continue;
                }


                vec3 midSceneView =
                    getViewPos(
                        midUV,
                        midSceneDepth
                    );


                float midRayDepth =
                    getLinearViewDepth(
                        mid
                    );


                float midSceneLinearDepth =
                    getLinearViewDepth(
                        midSceneView
                    );


                float midThickness =
                    clamp(
                        0.035 +
                        midSceneLinearDepth *
                        0.002,
                        0.035,
                        0.18
                    );


                if (
                    midRayDepth >
                    midSceneLinearDepth +
                    midThickness
                ) {

                    hi =
                        mid;

                } else {

                    lo =
                        mid;
                }
            }


            // =================================================
            // FINAL REFLECTION POSITION
            // =================================================

            vec2 finalUV;

            float finalProjectedDepth;


            if (
                !projectReflectionPoint(
                    hi,
                    finalUV,
                    finalProjectedDepth
                )
            ) {

                return vec4(
                    skyFallback,
                    0.0
                );
            }


            // =================================================
            // FINAL DEPTH VALIDATION
            // =================================================

            float finalSceneDepth =
                texture2D(
                    depthtex1,
                    finalUV
                ).r;


            if (
                finalSceneDepth >=
                0.999999
            ) {

                return vec4(
                    skyFallback,
                    0.0
                );
            }


            vec3 finalSceneView =
                getViewPos(
                    finalUV,
                    finalSceneDepth
                );


            float finalRayDepth =
                getLinearViewDepth(
                    hi
                );


            float finalSceneLinearDepth =
                getLinearViewDepth(
                    finalSceneView
                );


            float finalThickness =
                clamp(
                    0.035 +
                    finalSceneLinearDepth *
                    0.002,
                    0.035,
                    0.18
                );


            float finalError =
                abs(
                    finalRayDepth -
                    finalSceneLinearDepth
                );


            // Reject suspicious / stretched hits.
            if (
                finalError >
                finalThickness *
                2.5
            ) {

                return vec4(
                    skyFallback,
                    0.0
                );
            }


            // =================================================
            // DON'T REFLECT ANOTHER WATER PIXEL
            // =================================================

            float hitWater =
                texture2D(
                    colortex7,
                    finalUV
                ).r;


            if (
                hitWater >
                0.5
            ) {

                return vec4(
                    skyFallback,
                    0.0
                );
            }


            // =================================================
            // ACTUAL REFLECTED IMAGE
            // =================================================

            float blurR = REFLECTION_BLUR * (0.002 + travelled * 0.0008);
            vec3 reflectionColor = texture2D(colortex0, finalUV).rgb * 0.25;
            const vec2 bo[8] = vec2[8](vec2(1,0),vec2(-1,0),vec2(0,1),vec2(0,-1),
                                       vec2(0.7,0.7),vec2(-0.7,0.7),vec2(0.7,-0.7),vec2(-0.7,-0.7));
            for (int b = 0; b < 8; b++) {
                reflectionColor += texture2D(colortex0, clamp(finalUV + bo[b] * blurR, vec2(0.002), vec2(0.998))).rgb * 0.09375;
            }


            // Vertical stretch: makes reflections taller, like rippled water.
            {
                float sH = WATER_REFLECTION_HEIGHT * 0.012;
                vec3 tall = reflectionColor;
                float wsum = 1.0;
                for (int k = 1; k <= 6; k++) {
                    float w = 1.0 - float(k) / 7.0;
                    vec2 o = vec2(0.0, float(k) * sH);
                    tall += texture2D(colortex0, clamp(finalUV - o, vec2(0.002), vec2(0.998))).rgb * w;
                    tall += texture2D(colortex0, clamp(finalUV + o * 0.35, vec2(0.002), vec2(0.998))).rgb * w * 0.5;
                    wsum += w * 1.5;
                }
                reflectionColor = mix(reflectionColor, tall / wsum, clamp(WATER_REFLECTION_HEIGHT, 0.0, 1.0));
            }


            // =================================================
            // CONFIDENCE
            // =================================================

            float edgeConfidence =
                reflectionEdgeConfidence(
                    finalUV
                );


            float distanceConfidence =
                reflectionDistanceConfidence(
                    travelled
                );


            float depthConfidence =
                1.0 -
                smoothstep(
                    0.0,
                    finalThickness * 2.5,
                    finalError
                );


            float confidence =
                edgeConfidence *
                distanceConfidence *
                depthConfidence;


            if (
                confidence <
                0.05
            ) {

                return vec4(
                    skyFallback,
                    0.0
                );
            }


            return vec4(
                reflectionColor,
                confidence
            );
        }


        // ====================================================
        // SLOW ADAPTIVE STEP GROWTH
        // ====================================================
        //
        // Much slower than the previous 1.055/1.06 growth.
        //
        // This greatly reduces giant UV jumps that create
        // stretched reflection streaks.
        // ====================================================

        stepSize =
            min(
                stepSize *
                1.018,
                0.65
            );
    }


    // ========================================================
    // NO HIT
    // ========================================================

    return vec4(
        skyFallback,
        0.0
    );
}