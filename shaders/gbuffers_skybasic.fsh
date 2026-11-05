#version 120
varying vec4 tint;
/* DRAWBUFFERS:0 */
void main() {
    gl_FragData[0] = vec4(pow(max(tint.rgb, vec3(0.0)), vec3(2.2)), tint.a);
}
