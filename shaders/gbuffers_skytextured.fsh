#version 120
uniform sampler2D texture;
varying vec2 uv;
varying vec4 tint;
/* DRAWBUFFERS:0 */
void main() {
    vec4 base = texture2D(texture, uv) * tint;
    gl_FragData[0] = vec4(pow(max(base.rgb, vec3(0.0)), vec3(2.2)), base.a);
}
