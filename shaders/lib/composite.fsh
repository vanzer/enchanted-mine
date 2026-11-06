#include "/lib/settings.glsl"
#include "/lib/formats.glsl"
#include "/lib/post_settings.glsl"
#include "/lib/shadow_settings.glsl"
#include "/lib/temporal.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/ao.glsl"
#include "/lib/indirect.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform sampler2D shadowtex1;
uniform vec3 cameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;
uniform float far;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform int isEyeInWater;
uniform float viewWidth;
uniform float viewHeight;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
uniform int dhRenderDistance;
#endif
varying vec2 uv;
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const vec4 colortex1ClearColor = vec4(0.5, 0.5, 1.0, 0.0);
const vec4 colortex2ClearColor = vec4(0.0);
/* DRAWBUFFERS:02 */
vec2 viewport() { return max(vec2(viewWidth, viewHeight), vec2(1.0)); }
vec3 positionAt(vec2 coord, float depth) {
    return enchantedViewPosition(coord, depth, gbufferProjectionInverse, viewport(), frameCounter);
}
vec3 sceneAt(vec2 coord, bool opaque, out float valid) {
    float depth = opaque ? texture2D(depthtex1, coord).r : texture2D(depthtex0, coord).r;
    valid = depth < 1.0 ? 1.0 : 0.0;
    vec3 p = positionAt(coord, depth);
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
    float dhDepth = opaque ? texture2D(dhDepthTex1, coord).r : texture2D(dhDepthTex0, coord).r;
    if (dhDepth < 1.0) {
        vec3 dh = enchantedViewPosition(coord, dhDepth, dhProjectionInverse, viewport(), frameCounter);
        if (valid < 0.5 || length(dh) < length(p)) { p = dh; valid = 1.0; }
    }
#endif
    return p;
}
float volumeVisibility(vec3 relativeWorld) {
    vec4 clip = shadowProjection * shadowModelView * vec4(relativeWorld, 1.0);
    vec3 coord = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(lessThanEqual(coord, vec3(0.001))) || any(greaterThanEqual(coord, vec3(0.999)))) return 1.0;
    return step(coord.z - 0.0008, texture2D(shadowtex1, coord.xy).r);
}
vec3 volumeLight(vec3 viewRay, float distanceToSurface, vec3 worldSun) {
#if SHADOWS == 1 && !defined(DIM_NETHER) && !defined(DIM_END)
    if (VOLUMETRIC_LIGHT <= 0.0 || isEyeInWater != 0) return vec3(0.0);
    float extent = min(distanceToSurface, min(shadowDistance, 128.0));
    float stride = extent / float(VOLUMETRIC_STEPS);
    vec3 ray = normalize(viewRay);
    float phase = 0.2 + 10.0 * SUN_SHAFT_STRENGTH * pow(max(dot(ray, normalize(shadowLightPosition)), 0.0), 8.0);
    float day = smoothstep(-0.05, 0.15, worldSun.y);
    vec3 light = mix(vec3(0.035, 0.055, 0.10), vec3(1.0, 0.78, 0.48), day);
    float total = 0.0;
    float jitter = fract(sin(dot(uv * viewport(), vec2(12.9898, 78.233))) * 43758.5453);
    for (int i = 0; i < VOLUMETRIC_STEPS; ++i) {
        float distance = (float(i) + jitter) * stride;
        vec3 relative = (gbufferModelViewInverse * vec4(ray * distance, 1.0)).xyz;
        float heightDensity = exp(-max(cameraPosition.y + relative.y - 64.0, 0.0) / 100.0);
        total += volumeVisibility(relative) * heightDensity * exp(-distance * 0.009) * stride * 0.005;
    }
    return light * total * phase * VOLUMETRIC_LIGHT * (1.0 - rainStrength * 0.7);
#else
    return vec3(0.0);
#endif
}
vec3 reflectionColor(vec3 position, vec3 normal, bool water, vec3 worldSun) {
    vec3 direction = reflect(normalize(position), normal);
    vec3 worldDirection = normalize(mat3(gbufferModelViewInverse) * direction);
#if REFLECTION_CLOUDS == 1
    vec3 reflected = enchantedSky(worldDirection, worldSun, cameraPosition,
                                   frameTimeCounter, rainStrength, skyColor, fogColor);
#else
    vec3 reflected = enchantedClearSky(worldDirection, worldSun, frameTimeCounter,
                                        rainStrength, skyColor, fogColor);
#endif
    if (isEyeInWater == 1) reflected = mix(reflected, vec3(0.012, 0.07, 0.09), 0.9);
    vec3 origin = position + normal * 0.08;
    vec3 previousRay = origin;
    float previousDelta = -1.0;
    mat4 projection = enchantedJitteredProjection(gbufferProjection, viewport(), frameCounter);
    for (int i = 0; i < REFLECTION_STEPS; ++i) {
        float fi = float(i) + 1.0;
        vec3 ray = origin + direction * (0.12 * fi + 0.022 * fi * fi);
        vec4 clip = projection * vec4(ray, 1.0);
        if (clip.w <= 0.0) break;
        vec2 coord = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThanEqual(coord, vec2(0.001))) || any(greaterThanEqual(coord, vec2(0.999)))) break;
        float valid;
        vec3 scene = sceneAt(coord, water, valid);
        float delta = scene.z - ray.z;
        float thickness = 0.15 + min(length(ray) * 0.002, 0.4);
        if (valid > 0.5 && previousDelta < 0.0 && delta > 0.0 && delta < length(ray - previousRay) + thickness
            && texture2D(colortex2, coord).a < 1.5 && length(coord - uv) > 2.0 / viewHeight) {
            vec3 lo = previousRay;
            vec3 hi = ray;
            for (int refine = 0; refine < 5; ++refine) {
                vec3 mid = (lo + hi) * 0.5;
                vec4 midClip = projection * vec4(mid, 1.0);
                coord = midClip.xy / midClip.w * 0.5 + 0.5;
                scene = sceneAt(coord, water, valid);
                if (valid > 0.5 && scene.z > mid.z) hi = mid; else lo = mid;
            }
            vec4 hitClip = projection * vec4(hi, 1.0);
            coord = hitClip.xy / hitClip.w * 0.5 + 0.5;
            scene = sceneAt(coord, water, valid);
            if (valid > 0.5 && abs(scene.z - hi.z) < thickness && texture2D(colortex2, coord).a < 1.5) {
                float edge = smoothstep(0.0, 0.06, min(min(coord.x, coord.y), min(1.0 - coord.x, 1.0 - coord.y)));
                vec3 hitColor = water ? texture2D(colortex6, coord).rgb : texture2D(colortex0, coord).rgb;
                return mix(reflected, hitColor, edge);
            }
        }
        previousDelta = valid > 0.5 ? delta : -1.0;
        previousRay = ray;
    }
    return reflected;
}
void main() {
    float valid;
    vec3 position = sceneAt(uv, false, valid);
    vec3 worldSun = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 worldDirection = normalize(mat3(gbufferModelViewInverse) * position);
    vec3 color = texture2D(colortex0, uv).rgb;
    vec4 data = texture2D(colortex1, uv);
    vec4 effects = texture2D(colortex2, uv);
    vec3 emission = effects.rgb;
    bool hand = effects.a > 1.5;
    bool water = effects.a > 0.5 && effects.a < 1.5;
    if (valid < 0.5) {
        color = enchantedSky(worldDirection, worldSun, cameraPosition, frameTimeCounter,
                              rainStrength, skyColor, fogColor);
    } else if (data.a > 0.005 && !hand) {
        vec3 normal = normalize(data.rgb * 2.0 - 1.0);
        if (!water) {
            mat4 projection = enchantedJitteredProjection(gbufferProjection, viewport(), frameCounter);
            mat4 inverseProjection = enchantedJitteredInverse(gbufferProjectionInverse, viewport(), frameCounter);
            // SSAO/SSGI operate on the vanilla depth layer; DH is lit by its own pass.
            float nearDepth = texture2D(depthtex0, uv).r;
            if (nearDepth < 1.0 && abs(positionAt(uv, nearDepth).z - position.z) < 0.01) {
                color *= ambientOcclusion(depthtex0, projection, inverseProjection, uv, viewport(), position, normal);
                color *= 1.0 + indirectBounce(uv, position, normal, depthtex0, colortex1, colortex0, projection, inverseProjection);
#if !defined(DIM_NETHER) && !defined(DIM_END)
                color *= contactShadow(position, normal, shadowLightPosition, depthtex0, projection, inverseProjection);
#endif
            }
        }
        if (water && isEyeInWater == 0) {
            float behindValid;
            vec3 behind = sceneAt(uv, true, behindValid);
            vec2 refractedUV = clamp(uv + normal.xy * WATER_REFRACTION * 0.012 / max(-position.z * 0.015, 1.0), vec2(0.001), vec2(0.999));
            float refractedValid;
            vec3 refractedPosition = sceneAt(refractedUV, true, refractedValid);
            if (refractedValid < 0.5 || -refractedPosition.z < -position.z || texture2D(colortex2, refractedUV).a > 1.5)
                refractedUV = uv;
            float thickness = behindValid > 0.5 ? clamp(length(behind) - length(position), 0.0, 32.0) : 12.0;
            vec3 transmission = exp(-vec3(0.23, 0.065, 0.035) * thickness * WATER_ABSORPTION);
            vec3 refracted = mix(color, texture2D(colortex6, refractedUV).rgb, WATER_REFRACTION);
            color = refracted * transmission + vec3(0.015, 0.08, 0.105) * (1.0 - transmission);
            emission += texture2D(colortex7, refractedUV).rgb * transmission;
        }
        float reflectivity = clamp((data.a - 0.01) / 0.99, 0.0, 1.0);
        if (reflectivity > 0.04 && REFLECTION_STRENGTH > 0.0) {
            float facing = clamp(dot(-normalize(position), normal), 0.0, 1.0);
            float minimum = water ? REFLECTION_MINIMUM : mix(0.04, 0.55, reflectivity * reflectivity);
            float fresnel = minimum + (1.0 - minimum) * pow(1.0 - facing, 5.0);
            vec3 reflected = reflectionColor(position, normal, water, worldSun);
            color = mix(color, reflected, clamp(fresnel * reflectivity * REFLECTION_STRENGTH, 0.0, 1.0));
        }
    }
    if (!hand) {
        float distance = valid > 0.5 ? length(position) : far;
        if (isEyeInWater == 1 && UNDERWATER_FOG > 0.0) {
            vec3 transmittance = exp(-distance * vec3(0.16, 0.055, 0.033) * UNDERWATER_FOG);
            color = color * transmittance + vec3(0.008, 0.055, 0.075) * (1.0 - transmittance);
            emission *= transmittance;
        } else if (isEyeInWater == 2) {
            color = mix(color, vec3(1.8, 0.18, 0.015), 1.0 - exp(-distance * 2.0));
        } else if (valid > 0.5 && FOG_STRENGTH > 0.0) {
            vec3 relative = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;
            float range = far;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
            range = max(range, float(dhRenderDistance));
#endif
            float horizontal = length(relative.xz);
            float lastChunk = smoothstep(max(range - 16.0, 0.0), range, horizontal);
            float edgeFog = max(lastChunk * lastChunk * min(FOG_STRENGTH + 0.3, 1.0), smoothstep(max(range - 3.0, 0.0), range, horizontal));
            float heightDensity = exp(-max(cameraPosition.y + relative.y - 64.0, 0.0) / 65.0);
            float heightFog = 1.0 - exp(-distance * 0.004 * HEIGHT_FOG * heightDensity);
            float fog = 1.0 - (1.0 - edgeFog) * (1.0 - heightFog);
            color = mix(color, pow(max(fogColor, vec3(0.0)), vec3(2.2)), clamp(fog, 0.0, 1.0));
            emission *= 1.0 - clamp(fog, 0.0, 1.0);
        }
        color += volumeLight(position, distance, worldSun);
    }
    gl_FragData[0] = vec4(max(color, vec3(0.0)), 1.0);
    gl_FragData[1] = vec4(max(emission, vec3(0.0)), effects.a);
}
