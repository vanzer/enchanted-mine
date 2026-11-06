#include "/lib/post_settings.glsl"
#include "/lib/formats.glsl"
uniform sampler2D colortex2;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 uv;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
/* DRAWBUFFERS:3 */
void main() {
    vec3 emission = vec3(0.0);
    if (BLOOM_STRENGTH > 0.0) {
    // This buffer contains actual material emission, rather than scene
    // brightness. White stone and other matte objects cannot trigger bloom.
    // Prefiltering reduces the shimmer of small lamps during camera motion.
    vec2 pixel = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 p = clamp(uv + vec2(float(x), float(y)) * pixel,
                           pixel * 0.5, vec2(1.0) - pixel * 0.5);
            vec3 emitter = max(texture2D(colortex2, p).rgb, vec3(0.0));
            float brightness = max(max(emitter.r, emitter.g), emitter.b);
            float contribution = max(brightness - BLOOM_THRESHOLD, 0.0)
                               / max(brightness, 0.0001);
            float weight = float((2 - abs(x)) * (2 - abs(y))) / 16.0;
            emission += emitter * contribution * weight;
        }
    }
    }
    gl_FragData[0] = vec4(min(emission, vec3(128.0)), 1.0);
}
