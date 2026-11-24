#version 330 compatibility

#include "/settings.glsl"
#include "/Common/Shadows/Utilities/shadowDistortion.glsl"
#include "/Common/End/endShadow.glsl"
uniform mat4 shadowModelViewInverse;

in vec2 mc_Entity;
out vec2 texcoord;
out vec4 glcolor;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	vec3 endPP = (shadowModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;
	gl_Position = vec4(endShadowClip(endPP), 1.0);

	gl_Position.xyz = distortShadowClipPos(
		gl_Position.xyz
	);
	if (mc_Entity.x == 31000.0) {
		gl_Position = vec4(2.0, 2.0, 2.0, 1.0); // water casts no shadow
	}
#ifndef REALTIME_SHADOWS
	gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
#endif
}