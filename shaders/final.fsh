#version 120
#include "/lib/settings.glsl"
uniform sampler2D colortex0;
varying vec2 uv;
void main() {
    vec3 c = pow(max(texture2D(colortex0, uv).rgb, vec3(0.0)), vec3(2.2)) * EXPOSURE;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    gl_FragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
