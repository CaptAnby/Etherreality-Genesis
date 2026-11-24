#version 330 compatibility

uniform sampler2D gtexture;
#include "/settings.glsl"
uniform float sunAngle;
uniform float rainStrength;
uniform float thunderStrength;

uniform float alphaTestRef = 0.1;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	discard;
}
