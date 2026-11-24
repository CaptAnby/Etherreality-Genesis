#version 330 compatibility

out vec4 glcolor;
out vec3 normal;
out vec3 viewPos;

void main() {
	vec4 vp = gl_ModelViewMatrix * gl_Vertex;
	viewPos = vp.xyz;
	glcolor = gl_Color;
	normal = gl_NormalMatrix * gl_Normal;
	gl_Position = gl_ProjectionMatrix * vp;
}
