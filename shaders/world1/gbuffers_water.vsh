#version 330 compatibility

// ============================================================
// ETHERREALITY GENESIS :: WATER VERTEX
// Gentle moving water
// ============================================================

in vec2 mc_Entity;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;

out vec3 waveNormal;
out float isWaterFlag;
out float isGlassFlag;
out vec3 waterWorldPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;

uniform sampler2D noisetex;

#include "/Common/Water/Ripples/waterWaves.glsl"


void main() {

    texcoord =
        (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;


    lmcoord =
        (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;


    glcolor =
        gl_Color;


    /*
        Original vertex -> view space.
    */
    vec3 viewPosition =
        (gl_ModelViewMatrix * gl_Vertex).xyz;


    /*
        View -> world.
    */
    vec3 worldPosition =
        mat3(gbufferModelViewInverse)
        *
        viewPosition
        +
        gbufferModelViewInverse[3].xyz
        +
        cameraPosition;


    /*
        Pass world position to the fragment shader.
    */
    waterWorldPosition =
        worldPosition;


    vec3 finalWorldPosition =
        worldPosition;


    /*
        Default normal.
    */
    waveNormal =
        normalize(
            gl_NormalMatrix *
            gl_Normal
        );


    /*
        --------------------------------------------------------
        WATER
        --------------------------------------------------------
    */
    isWaterFlag = (mc_Entity.x == 31000.0) ? 1.0 : 0.0;
    isGlassFlag = (mc_Entity.x == 31010.0) ? 1.0 : 0.0;

    if (mc_Entity.x == 31000.0) {

        /*
            Your chosen water wave speed.
        */
        float waterTime =
            frameTimeCounter
            *
            WATER_TIME_SCALE;


        /*
            Gentle moving wave displacement.
        */
        finalWorldPosition.y +=
            waterDisplacementHeight(
                worldPosition.xz,
                waterTime
            );


        /*
            Matching wave normal.
        */
        waveNormal =
            waterWaveNormal(
                worldPosition.xz,
                waterTime
            );
    }


    /*
        World -> view.
    */
    vec3 finalViewPosition =
        mat3(gbufferModelView)
        *
        (
            finalWorldPosition -
            cameraPosition
        )
        +
        gbufferModelView[3].xyz;


    gl_Position =
        gl_ProjectionMatrix
        *
        vec4(
            finalViewPosition,
            1.0
        );
}