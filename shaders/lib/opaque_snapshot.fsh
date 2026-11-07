#include "/lib/formats.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex2;
varying vec2 uv;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;
/* DRAWBUFFERS:67 */
void main() {
    // Iris runs deferred after opaque terrain and before translucent water.
    gl_FragData[0] = vec4(texture2D(colortex0, uv).rgb, 1.0);
    gl_FragData[1] = vec4(texture2D(colortex2, uv).rgb, 1.0);
}
