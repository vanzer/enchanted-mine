#include "/lib/settings.glsl"
#include "/lib/shadow_settings.glsl"
#include "/lib/lighting_settings.glsl"
#include "/lib/material.glsl"
#include "/lib/atmosphere.glsl"
#ifdef WATER
#include "/lib/water.glsl"
uniform mat4 gbufferModelView;
#endif
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float frameTimeCounter;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;
#if SHADOWS == 1 && !defined(HAND) && !defined(DIM_NETHER) && !defined(DIM_END)
uniform sampler2D shadowtex0;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
float surfaceShadow(vec3 position, vec3 surfaceNormal) {
    // Use geometric normals here: texture bump/normal maps must not move the
    // receiver below the real surface or modulate the self-shadow bias.
    float facing = max(dot(surfaceNormal, normalize(shadowLightPosition)), 0.0);
    float worldTexel = 2.0 * shadowDistance / float(shadowMapResolution);
    float normalOffset = min(worldTexel * 0.4, 0.10) * (1.0 - facing * 0.5);
    vec4 world = gbufferModelViewInverse * vec4(position + surfaceNormal * normalOffset, 1.0);
    vec4 clip = shadowProjection * shadowModelView * world;
    vec3 coord = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(lessThanEqual(coord, vec3(0.0))) || any(greaterThanEqual(coord, vec3(1.0)))) return 1.0;
    float bias = 0.00015;
    // Match each PCF tap to the receiver plane instead of comparing the
    // centre depth against neighbours on a sloping surface (striped acne).
    vec3 dx = dFdx(coord);
    vec3 dy = dFdy(coord);
    float determinant = dx.x * dy.y - dx.y * dy.x;
    vec2 gradient = vec2(0.0);
    if (abs(determinant) > 0.000000000001)
        gradient = vec2(dy.y * dx.z - dx.y * dy.z,
                        dx.x * dy.z - dy.x * dx.z) / determinant;
    float texel = SHADOW_SOFTNESS / float(shadowMapResolution);
    float visibility = 0.0;
#if SHADOW_FILTER == 0
    vec2 sampleCoord = (floor(coord.xy * float(shadowMapResolution)) + 0.5) / float(shadowMapResolution);
    float receiver = coord.z + dot(gradient, sampleCoord - coord.xy);
    visibility = receiver - bias <= texture2D(shadowtex0, sampleCoord).r ? 1.0 : 0.0;
#else
    // A wider Gaussian PCF kernel softens edges without changing block lighting.
    float weightSum = 0.0;
    for (int x = -SHADOW_FILTER; x <= SHADOW_FILTER; ++x) {
        for (int y = -SHADOW_FILTER; y <= SHADOW_FILTER; ++y) {
            vec2 offset = vec2(float(x), float(y));
            float weight = exp(-dot(offset, offset) * 0.5);
            vec2 sampleCoord = (floor((coord.xy + offset * texel) * float(shadowMapResolution)) + 0.5)
                             / float(shadowMapResolution);
            sampleCoord = clamp(sampleCoord, vec2(0.0), vec2(1.0));
            float closest = texture2D(shadowtex0, sampleCoord).r;
            float receiver = coord.z + dot(gradient, sampleCoord - coord.xy);
            visibility += (receiver - bias <= closest ? 1.0 : 0.0) * weight;
            weightSum += weight;
        }
    }
    visibility /= max(weightSum, 0.001);
#endif
    float edge = min(min(coord.x, coord.y), min(1.0 - coord.x, 1.0 - coord.y));
    float distanceFade = 1.0 - smoothstep(shadowDistance * 0.8, shadowDistance, length(world.xz));
    return mix(1.0, visibility, smoothstep(0.0, 0.06, edge) * distanceFade);
}
#endif
varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
varying float blockType;
/* DRAWBUFFERS:012 */
void main() {
    vec4 texel = texture2D(texture, uv);
    vec4 base = texel * tint;
    if (base.a < 0.1) discard;
    vec3 albedo = pow(max(base.rgb, vec3(0.0)), vec3(2.2));
    vec3 n = normalize(normal);
    bool waterSurface = abs(blockType - 10000.0) < 0.5;
    if (!gl_FrontFacing) n = -n;
    float reflectivity = material;
    float metallic = abs(blockType - 10001.0) < 0.5 ? 0.85 : 0.0;
    float subsurface = (abs(blockType - 10003.0) < 0.5 || abs(blockType - 10004.0) < 0.5) ? 1.0 : 0.0;
    float emission = 0.0;
    if (abs(blockType - 10005.0) < 0.5 || abs(blockType - 10006.0) < 0.5) {
        // Dark fixture pixels remain dark; the luminous texture itself supplies the hue.
        emission = smoothstep(0.18, 0.75, max(max(texel.r, texel.g), texel.b));
    }
    if (abs(blockType - 10007.0) < 0.5) emission = 1.0;
    float ao = 1.0;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
#ifdef WATER
    if (waterSurface) {
        n = enchantedWaterNormal(n, relativeWorld, cameraPosition, frameTimeCounter,
                                 gbufferModelViewInverse, gbufferModelView);
        // Absorption and refraction are applied in composite from opaque depth.
        albedo = mix(albedo, vec3(0.025, 0.12, 0.15), 0.65);
        base.a = WATER_OPACITY;
        metallic = 0.0;
    } else
#endif
    {
        enchantedMaterial(uv, viewPos, albedo, n, reflectivity, metallic, ao, emission, subsurface);
    }
    vec3 worldN = normalize(mat3(gbufferModelViewInverse) * n);
    vec3 worldSun = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 worldLight = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
    vec3 lightDir = normalize(shadowLightPosition);
    vec3 viewDir = normalize(-viewPos);
    float day = smoothstep(-0.08, 0.12, worldSun.y);
    float sky = clamp((lm.y - 0.03125) / 0.9375, 0.0, 1.0);
    float skyAccess = pow(sky, 3.0);
    float block = clamp((lm.x - 0.03125) / 0.9375, 0.0, 1.0);
    vec3 local = vec3(1.0, 0.56, 0.25) * pow(block, 2.3) * BLOCK_LIGHT;
    // Retain colour and dynamic-light contributions supplied by the engine lightmap.
    local = max(local, pow(max(texture2D(lightmap, vec2(lm.x, 0.03125)).rgb, vec3(0.0)), vec3(2.2)) * BLOCK_LIGHT);
    vec3 ambient = mix(vec3(0.013, 0.022, 0.045), vec3(0.15, 0.24, 0.38), day)
                 * SKY_LIGHT * skyAccess * mix(0.75, 1.1, max(worldN.y, 0.0));
    vec3 lightColor = mix(vec3(0.33, 0.46, 0.75) * MOON_LIGHT,
                         mix(vec3(1.0, 0.56, 0.28), vec3(1.0, 0.89, 0.72), smoothstep(0.05, 0.6, worldSun.y)) * SUN_LIGHT, day);
    float visibility = 1.0;
#if SHADOWS == 1 && !defined(HAND) && !defined(DIM_NETHER) && !defined(DIM_END)
    vec3 geometricNormal = normalize(normal) * (gl_FrontFacing ? 1.0 : -1.0);
    visibility = mix(1.0, surfaceShadow(viewPos, geometricNormal), SHADOW_STRENGTH);
#endif
#if !defined(DIM_NETHER) && !defined(DIM_END)
    visibility *= enchantedCloudShadow(relativeWorld + cameraPosition, worldLight, frameTimeCounter, rainStrength);
#endif
    float diffuse = mix(0.55, max(dot(n, lightDir), 0.0), DIRECT_CONTRAST);
    vec3 direct = lightColor * diffuse * visibility * skyAccess * (1.0 - rainStrength * 0.7);
    float backlight = pow(max(dot(-viewDir, lightDir), 0.0), 3.0);
    direct += lightColor * backlight * subsurface * LEAF_TRANSLUCENCY * visibility * skyAccess * 0.4;
#if defined(DIM_NETHER)
    ambient = vec3(0.075, 0.025, 0.012) * SKY_LIGHT;
    direct = vec3(0.0);
#elif defined(DIM_END)
    ambient = vec3(0.11, 0.08, 0.16) * SKY_LIGHT;
    direct = vec3(0.0);
#endif
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    float attenuation = max(0.0, 1.0 - length(viewPos) / 12.0);
    local = max(local, vec3(1.0, 0.57, 0.26) * held * HAND_LIGHT * attenuation * attenuation);
    vec3 specularLight = enchantedSpecular(n, viewDir, lightDir, albedo, reflectivity, metallic)
                       * lightColor * visibility * skyAccess * (1.0 - rainStrength * 0.7);
#if defined(DIM_NETHER) || defined(DIM_END)
    specularLight = vec3(0.0);
#endif
    vec3 radiance = albedo * (ambient * ao + direct + local) * (1.0 - metallic * 0.75) + specularLight;
    vec3 emitted = albedo * emission * EMISSION_STRENGTH;
    radiance += emitted;
    gl_FragData[0] = vec4(radiance, base.a);
    gl_FragData[1] = vec4(n * 0.5 + 0.5, 0.01 + 0.99 * clamp(reflectivity, 0.0, 1.0));
    float type = waterSurface ? 1.0 : 0.0;
#ifdef HAND
    type = 2.0;
#endif
    gl_FragData[2] = vec4(emitted, type);
}
