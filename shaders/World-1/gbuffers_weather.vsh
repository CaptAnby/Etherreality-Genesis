#version 330 compatibility

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
uniform float thunderStrength;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	// shear drops sideways with height: gentle wind in rain, strong in thunder
	vec3 w = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
	float slant = mix(0.12, 0.65, clamp(thunderStrength, 0.0, 1.0));
	vec2 windDir = normalize(vec2(0.8, 0.6));
	w.xz += windDir * w.y * slant;

	gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(w, 1.0));
}
