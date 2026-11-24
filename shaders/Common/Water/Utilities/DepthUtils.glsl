uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

// reconstruct view-space position from depth
vec3 getViewPos(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

// world-space depth of solid terrain behind water, minus water surface depth
float getWaterDepth(vec2 uv, float waterDepthSample) {
    float terrainDepth = texture(depthtex1, uv).r;
    vec3 terrainView = getViewPos(uv, terrainDepth);
    vec3 waterView = getViewPos(uv, waterDepthSample);
    return length(terrainView - waterView);
}