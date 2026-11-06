#version 120
#include "/lib/settings.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
varying vec2 uv;
#ifndef RGBA16F
#define RGBA16F 0x881A
#endif
const int colortex1Format = RGBA16F;
const vec4 colortex1ClearColor = vec4(0.5, 0.5, 1.0, 0.0);
/* DRAWBUFFERS:0 */
vec3 positionAt(vec2 coord, float depth) {
    vec4 v = gbufferProjectionInverse * vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}
void main() {
    vec3 color = texture2D(colortex0, uv).rgb;
    float depth = texture2D(depthtex0, uv).r;
    vec4 data = texture2D(colortex1, uv);
    if (depth < 1.0 && data.a > 0.1) {
        vec3 pos = positionAt(uv, depth);
        vec3 n = normalize(data.rgb * 2.0 - 1.0);
        vec3 direction = reflect(normalize(pos), n);
        vec3 ray = pos + n * 0.12;
        // Screen-space ray march; off-screen geometry cannot be reflected.
        vec3 reflected = vec3(0.22, 0.32, 0.45);
        for (int i = 0; i < REFLECTION_STEPS; i++) {
            ray += direction * (0.15 + float(i) * 0.045);
            vec4 clip = gbufferProjection * vec4(ray, 1.0);
            if (clip.w <= 0.0) break;
            vec2 coord = clip.xy / clip.w * 0.5 + 0.5;
            if (any(lessThan(coord, vec2(0.0))) || any(greaterThan(coord, vec2(1.0)))) break;
            float sceneDepth = texture2D(depthtex0, coord).r;
            vec3 scene = positionAt(coord, sceneDepth);
            float delta = scene.z - ray.z;
            if (sceneDepth < 1.0 && delta > 0.0 && delta < 0.5) {
                float edge = smoothstep(0.0, 0.08, min(min(coord.x, coord.y), min(1.0-coord.x, 1.0-coord.y)));
                reflected = mix(reflected, texture2D(colortex0, coord).rgb, edge);
                break;
            }
        }
        float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(-normalize(pos), n), 0.0), 5.0);
        color = mix(color, reflected, clamp(fresnel * data.a * REFLECTION_STRENGTH, 0.0, 1.0));
    }
    gl_FragData[0] = vec4(color, 1.0);
}
