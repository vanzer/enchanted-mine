#ifndef ENCHANTED_TEMPORAL
#define ENCHANTED_TEMPORAL
#include "/lib/settings.glsl"
vec2 enchantedJitter(int frame) {
#if TAA == 1
    int index = int(mod(float(frame), 8.0));
    if (index == 0) return vec2(0.0, -0.16666667);
    if (index == 1) return vec2(-0.25, 0.16666667);
    if (index == 2) return vec2(0.25, -0.38888889);
    if (index == 3) return vec2(-0.375, -0.05555556);
    if (index == 4) return vec2(0.125, 0.27777778);
    if (index == 5) return vec2(-0.125, -0.27777778);
    if (index == 6) return vec2(0.375, 0.05555556);
    return vec2(-0.4375, 0.38888889);
#else
    return vec2(0.0);
#endif
}
vec3 enchantedViewPosition(vec2 coord, float depth, mat4 inverseProjection,
                            vec2 viewport, int frame) {
    vec2 unjittered = coord - enchantedJitter(frame) / max(viewport, vec2(1.0));
    vec4 p = inverseProjection * vec4(unjittered * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return p.xyz / p.w;
}
mat4 enchantedJitteredProjection(mat4 projection, vec2 viewport, int frame) {
    vec2 offset = enchantedJitter(frame) * 2.0 / max(viewport, vec2(1.0));
    projection[0].xy += offset * projection[0].w;
    projection[1].xy += offset * projection[1].w;
    projection[2].xy += offset * projection[2].w;
    projection[3].xy += offset * projection[3].w;
    return projection;
}
mat4 enchantedJitteredInverse(mat4 inverseProjection, vec2 viewport, int frame) {
    mat4 unjitter = mat4(1.0);
    unjitter[3].xy = -enchantedJitter(frame) * 2.0 / max(viewport, vec2(1.0));
    return inverseProjection * unjitter;
}
#endif
