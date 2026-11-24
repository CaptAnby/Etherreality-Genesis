#version 330 compatibility

uniform sampler2D lightmap;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec4 glcolor;
in vec3 normal;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;

void main() {
	color = glcolor * texture(lightmap, lmcoord);

	if (color.a < alphaTestRef) {
		discard;
	}

	normalData = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
}