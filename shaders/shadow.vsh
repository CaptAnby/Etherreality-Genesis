#version 330 compatibility

#include "/settings.glsl"
#include "/Common/Shadows/Utilities/shadowDistortion.glsl"

in vec2 mc_Entity;
out vec2 texcoord;
out vec4 glcolor;

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;

	gl_Position = ftransform();

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