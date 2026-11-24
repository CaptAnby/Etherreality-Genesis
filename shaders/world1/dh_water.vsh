#version 330 compatibility

out vec4 glcolor;

void main() {
	glcolor = gl_Color;
	gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
}
