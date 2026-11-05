#version 120
#include "/lib/buffers.glsl"
uniform sampler2D colortex0;
varying vec2 uv;
/* DRAWBUFFERS:5 */
void main() { gl_FragData[0] = texture2D(colortex0, uv); }
