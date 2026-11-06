#version 120
#include "/lib/settings.glsl"
#include "/lib/post_settings.glsl"
uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 uv;

// Extract highlights in linear light; clamp coordinates to avoid wrap at edges.
vec3 highlight(vec2 coord) {
    vec3 sampleColor = pow(max(texture2D(colortex0, clamp(coord, vec2(0.0), vec2(1.0))).rgb,
                               vec3(0.0)), vec3(2.2));
    float brightness = max(max(sampleColor.r, sampleColor.g), sampleColor.b);
    float contribution = max(brightness - 0.5, 0.0) / max(brightness, 0.0001);
    return sampleColor * contribution;
}

vec3 bloomRing(vec2 pixel, float radius) {
    vec2 d = pixel * radius;
    return (highlight(uv + vec2(d.x, 0.0)) + highlight(uv - vec2(d.x, 0.0))
          + highlight(uv + vec2(0.0, d.y)) + highlight(uv - vec2(0.0, d.y))
          + highlight(uv + d) + highlight(uv - d)
          + highlight(uv + vec2(d.x, -d.y)) + highlight(uv + vec2(-d.x, d.y))) * 0.125;
}

void main() {
    vec3 c = pow(max(texture2D(colortex0, uv).rgb, vec3(0.0)), vec3(2.2));
    if (BLOOM_STRENGTH > 0.0) {
        vec2 pixel = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));
        vec3 bloom = highlight(uv) * 0.2 + bloomRing(pixel, 3.0) * 0.35
                   + bloomRing(pixel, 10.0) * 0.3 + bloomRing(pixel, 24.0) * 0.15;
        c += bloom * BLOOM_STRENGTH;
    }
    c *= EXPOSURE;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    gl_FragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
