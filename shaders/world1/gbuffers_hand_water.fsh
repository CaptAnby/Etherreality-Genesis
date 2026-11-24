#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;

/* RENDERTARGETS: 0,1,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 3) out vec4 lightmapData;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	color *= texture(lightmap, lmcoord);

	if (color.a < alphaTestRef) {
		discard;
	}

	color.a = 1.0;

	normalData = vec4(
		normalize(normal) * 0.5 + 0.5,
		1.0
	);

	lightmapData = vec4(
		lmcoord,
		0.0,
		1.0
	);
}