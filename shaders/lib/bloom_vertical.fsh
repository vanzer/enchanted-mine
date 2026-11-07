#include "/lib/post_settings.glsl"
uniform sampler2D colortex4;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 uv;
/* DRAWBUFFERS:3 */
void main() {
    vec3 glow = vec3(0.0);
    float weightSum = 0.0;
    if (BLOOM_STRENGTH > 0.0) {
    vec2 pixel = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));
    float resolutionScale = max(viewHeight / 720.0, 0.5);
    for (int i = -8; i <= 8; ++i) {
        float fi = float(i);
        float weight = exp(-fi * fi / 18.0);
        vec2 small = vec2(0.0, fi * 1.5 * BLOOM_RADIUS * resolutionScale) * pixel;
        vec2 large = small * 3.0;
        glow += texture2D(colortex4, clamp(uv + small, pixel * 0.5, vec2(1.0) - pixel * 0.5)).rgb * weight * 0.35;
        glow += texture2D(colortex4, clamp(uv + large, pixel * 0.5, vec2(1.0) - pixel * 0.5)).rgb * weight * 0.65;
        weightSum += weight;
    }
    }
    gl_FragData[0] = vec4(glow / max(weightSum, 0.0001), 1.0);
}
