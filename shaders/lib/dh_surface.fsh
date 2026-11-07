#include "/lib/settings.glsl"
#include "/lib/lighting_settings.glsl"
#include "/lib/atmosphere.glsl"
#ifdef WATER
#include "/lib/water.glsl"
#endif

uniform sampler2D lightmap;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform float rainStrength;
varying vec2 dhLightmap;
varying vec4 dhTint;
varying vec3 dhViewPosition;
varying vec3 dhNormal;
varying float dhReflectivity;
varying float dhWater;
varying float dhEmission;
varying float dhLeaves;
/* DRAWBUFFERS:012 */

void main() {
#if !defined(DISTANT_HORIZONS) || DH_SUPPORT == 0
    discard;
#else
    if (dhTint.a < 0.01) discard;
    vec3 albedo = pow(max(dhTint.rgb, vec3(0.0)), vec3(2.2));
    vec3 n = normalize(dhNormal);
    float opacity = dhTint.a;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(dhViewPosition, 1.0)).xyz;
#ifdef WATER
    if (dhWater > 0.5) {
        n = enchantedWaterNormal(n, relativeWorld, cameraPosition, frameTimeCounter,
                                 gbufferModelViewInverse, gbufferModelView);
        albedo = mix(albedo, vec3(0.008, 0.045, 0.065), 0.45);
        opacity = WATER_OPACITY;
    }
#endif

    vec3 vanillaLight = pow(max(texture2D(lightmap, dhLightmap).rgb, vec3(0.0)), vec3(2.2));
    vec3 illumination = vanillaLight * SKY_LIGHT;
#if !defined(DIM_NETHER) && !defined(DIM_END)
    vec3 sun = normalize(sunPosition);
    vec3 worldSun = normalize(mat3(gbufferModelViewInverse) * sun);
    float day = smoothstep(-0.08, 0.12, worldSun.y);
    vec3 activeLight = worldSun.y > -0.02 ? sun : -sun;
    vec3 worldLight = normalize(mat3(gbufferModelViewInverse) * activeLight);
    float facing = max(dot(n, activeLight), 0.0);
    facing += dhLeaves * LEAF_TRANSLUCENCY * max(dot(-n, activeLight), 0.0);
    float skylight = smoothstep(0.10, 0.96, dhLightmap.y);
    float cloud = enchantedCloudShadow(relativeWorld + cameraPosition, worldLight,
                                        frameTimeCounter, rainStrength);
    vec3 directTint = mix(vec3(0.36, 0.48, 0.78), vec3(1.0, 0.89, 0.70), day);
    float intensity = mix(MOON_LIGHT, SUN_LIGHT, day) * (1.0 - rainStrength * 0.75);
    // Distant LOD geometry cannot supply detailed block textures or normal maps.
    // Match the near pipeline's linear direct/ambient light, retaining its lightmap.
    illumination *= 1.0 - DIRECT_CONTRAST * skylight;
    illumination += directTint * intensity * facing * skylight * cloud;
#endif
    vec3 emitted = albedo * dhEmission * EMISSION_STRENGTH;
    vec3 color = albedo * max(illumination, vec3(0.006)) + emitted;
    gl_FragData[0] = vec4(color, opacity);
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 0.01 + 0.99 * dhReflectivity);
    gl_FragData[2] = vec4(emitted, dhWater);
#endif
}
