#ifndef ENCHANTED_WIND
#define ENCHANTED_WIND
#include "/lib/lighting_settings.glsl"
// Shared by scene and shadow vertices, anchored to absolute world coordinates.
vec3 enchantedWind(vec3 relativeWorld, vec3 camera, float id, float time, float vertexWeight) {
    bool leaves = abs(id - 10003.0) < 0.5;
    bool plant = abs(id - 10004.0) < 0.5;
    if ((!leaves && !plant) || WIND_STRENGTH <= 0.0) return vec3(0.0);
    vec3 p = relativeWorld + mod(camera, 256.0);
    float t = time * WIND_SPEED;
    float phase = dot(p.xz, vec2(0.19634954, 0.09817477));
    float gust = sin(phase + t * 1.6) * 0.65 + sin(phase * 2.0 - t * 2.3) * 0.35;
    // Short plants stay rooted at the lower vertex of the block.
    float weight = leaves ? 0.45 : vertexWeight;
    return vec3(gust, sin(phase * 3.0 + t * 2.0) * 0.12, gust * 0.47)
         * WIND_STRENGTH * weight * 0.18;
}
#endif
