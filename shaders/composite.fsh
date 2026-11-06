#version 120
#include "/lib/settings.glsl"
#include "/lib/post_settings.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float far;
uniform int isEyeInWater;
varying vec2 uv;
const int colortex1Format = RGBA16F;
const vec4 colortex1ClearColor = vec4(0.5, 0.5, 1.0, 0.0);
/* DRAWBUFFERS:0 */
vec3 positionAt(vec2 coord, float depth) {
    vec4 v = gbufferProjectionInverse * vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}
// Samples the visible sky along the ray toward the sun. These are screen-space
// shafts: objects and the sun outside the viewport cannot contribute.
float sunShafts(vec2 coord) {
    vec4 clip = gbufferProjection * vec4(sunPosition, 1.0);
    if (clip.w <= 0.0 || isEyeInWater != 0) return 0.0;
    vec2 sunUV = clip.xy / clip.w * 0.5 + 0.5;
    if (any(lessThan(sunUV, vec2(0.0))) || any(greaterThan(sunUV, vec2(1.0)))) return 0.0;
    float day = smoothstep(0.0, 0.12, dot(normalize(sunPosition), normalize(upPosition)));
    float visibility = 0.0;
    for (int i = 0; i < 12; i++) {
        float t = (float(i) + 0.5) / 12.0;
        vec2 sampleUV = mix(coord, sunUV, t * 0.9);
        visibility += step(0.99999, texture2D(depthtex0, sampleUV).r);
    }
    float falloff = 1.0 - smoothstep(0.0, 1.0, length(coord - sunUV));
    return visibility / 12.0 * falloff * day * (1.0 - rainStrength);
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
    // Use view distance so fog behaves consistently across the screen. Sky is
    // already rendered by Minecraft and must not receive the distance fog.
    if (depth < 1.0 && FOG_STRENGTH > 0.0) {
        float distanceToCamera = length(positionAt(uv, depth));
        float density = FOG_STRENGTH / max(far, 1.0);
        if (isEyeInWater != 0) density = max(density, 0.045);
        float fog = 1.0 - exp(-distanceToCamera * density);
        color = mix(color, fogColor, clamp(fog, 0.0, 0.9));
    }
    if (SUN_SHAFT_STRENGTH > 0.0) {
        color += mix(vec3(1.0, 0.78, 0.50), skyColor, 0.25)
                 * sunShafts(uv) * SUN_SHAFT_STRENGTH;
    }
    gl_FragData[0] = vec4(color, 1.0);
}
