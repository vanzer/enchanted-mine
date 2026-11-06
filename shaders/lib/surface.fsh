#include "/lib/settings.glsl"
#include "/lib/shadow_settings.glsl"
#include "/lib/material.glsl"
#ifdef WATER
#include "/lib/water.glsl"
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
#endif
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float frameTimeCounter;
uniform mat4 gbufferModelViewInverse;
#if SHADOWS == 1 && (defined(TERRAIN) || defined(WATER))
uniform sampler2D shadowtex0;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 shadowLightPosition;

float surfaceShadow(vec3 position, vec3 surfaceNormal) {
    vec4 world = gbufferModelViewInverse * vec4(position, 1.0);
    vec4 clip = shadowProjection * shadowModelView * world;
    vec3 coord = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(lessThanEqual(coord, vec3(0.0))) || any(greaterThanEqual(coord, vec3(1.0)))) return 1.0;

    // Increase bias on grazing surfaces to limit self-shadowing (shadow acne).
    float facing = max(dot(surfaceNormal, normalize(shadowLightPosition)), 0.0);
    float bias = mix(0.0015, 0.0005, facing);
    float texel = 1.0 / float(shadowMapResolution);
    float visibility = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            float closest = texture2D(shadowtex0, coord.xy + vec2(float(x), float(y)) * texel).r;
            visibility += coord.z - bias <= closest ? 1.0 : 0.0;
        }
    }
    visibility /= 9.0;
    // Fade at the map boundary instead of drawing a hard square around the player.
    float edge = min(min(coord.x, coord.y), min(1.0 - coord.x, 1.0 - coord.y));
    return mix(1.0, visibility, smoothstep(0.0, 0.06, edge));
}
#endif
varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
/* DRAWBUFFERS:01 */
void main() {
    vec4 base = texture2D(texture, uv) * tint;
    if (base.a < 0.1) discard;
    vec3 n = normalize(normal);
    float reflectivity = material;
#ifdef WATER
    if (material > 0.9) {
        vec3 world = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        n = enchantedWaterNormal(n, world, cameraPosition, frameTimeCounter,
                                 gbufferModelViewInverse, gbufferModelView);
        base.rgb = mix(base.rgb, vec3(0.035, 0.15, 0.19), 0.45);
        base.a = 0.78;
    }
#endif
    vec3 illumination = texture2D(lightmap, lm).rgb;
#if SHADOWS == 1 && (defined(TERRAIN) || defined(WATER))
    // The vanilla lightmap already contains block and ambient light. Apply the
    // occlusion primarily where skylight is available; keep hand light separate.
    float sky = smoothstep(0.2, 0.95, lm.y);
    float visibility = surfaceShadow(viewPos, n);
    illumination *= 1.0 - (1.0 - visibility) * SHADOW_STRENGTH * sky;
#endif
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    float hand = held * HAND_LIGHT * max(0.0, 1.0 - length(viewPos) / 12.0);
    illumination = max(illumination, vec3(1.0, 0.66, 0.32) * hand);
#if defined(LAB_PBR) && !defined(WATER)
    applyLabPBR(uv, viewPos, n, reflectivity, illumination);
#endif
    base.rgb *= max(illumination, vec3(0.025));
    gl_FragData[0] = base;
    gl_FragData[1] = vec4(n * 0.5 + 0.5, reflectivity);
}
