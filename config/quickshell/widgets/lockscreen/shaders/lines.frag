#version 440
layout(location=0) in vec4 ink;
layout(location=0) out vec4 fragColor;
void main() { fragColor=ink; }
