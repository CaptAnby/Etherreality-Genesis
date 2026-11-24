#version 330 compatibility
#include "/settings.glsl"
#include "/Common/Wind/globalWind.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
uniform float thunderStrength;
uniform float frameTimeCounter;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	// shear drops sideways with height: gentle wind in rain, strong in thunder
	vec3 w = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
	float slant = mix(0.14, 0.65, clamp(thunderStrength, 0.0, 1.0)) * RAIN_SLANT;
	slant *= 0.8 + 0.4 * glwsGust(frameTimeCounter, rainStrength, thunderStrength);   // SmGS gusts
	vec2 windDir = glwsDir();
	w.xz += windDir * w.y * slant;

	gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(w, 1.0));
}
