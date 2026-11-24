#version 330 compatibility

uniform vec3 sunPosition;

out vec2 texcoord;
out vec4 glcolor;
out vec3 vViewDir;
out float vIsSun;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	glcolor = gl_Color;
	vec3 vp = (gl_ModelViewMatrix * gl_Vertex).xyz;
	vViewDir = normalize(vp);
	vIsSun = step(0.0, dot(vViewDir, normalize(sunPosition)));
}
