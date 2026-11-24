#version 330 compatibility

#include "/Common/Shadows/Utilities/shadowDistortion.glsl"
#include "/Common/End/endShadow.glsl"
uniform mat4 shadowModelViewInverse;

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
}