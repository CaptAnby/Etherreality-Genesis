#version 330 compatibility

uniform float far;

in vec4 glcolor;
in vec3 normal;
in vec3 viewPos;

/* RENDERTARGETS: 0,1,2,3,4 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 lightmapData;
layout(location = 4) out vec4 localLightData;

void main() {
	color = vec4(glcolor.rgb, 1.0);
	normalData = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
	materialData = vec4(0.0, 0.0, 0.0, 1.0);
	lightmapData = vec4(0.0, 0.95, 0.0, 1.0);
	localLightData = vec4(0.5, 0.5, 0.5, 0.0);
}
