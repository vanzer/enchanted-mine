// Optional screen-space lighting approximations. These cannot see geometry
// hidden from the camera, so neither effect is a replacement for full GI.
#define INDIRECT_STRENGTH 0.0 // [0.0 0.1 0.2 0.35]
#define CONTACT_SHADOW_STRENGTH 0.0 // [0.0 0.15 0.3 0.5]

vec3 indirectViewPosition(vec2 uv, float depth, mat4 projectionInverse) {
    vec4 view = projectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return view.xyz / view.w;
}

// Estimates a single bounce from eight nearby visible surfaces. Returned light
// is linear RGB; multiply it by the receiver's linear color before applying it.
vec3 indirectBounce(vec2 uv, vec3 position, vec3 normal,
                    sampler2D depthBuffer, sampler2D normalBuffer,
                    sampler2D colorBuffer, mat4 projection,
                    mat4 projectionInverse) {
    const float radius = 1.4;
    float viewDepth = max(-position.z, 0.1);
    vec2 footprint = min(abs(vec2(projection[0][0], projection[1][1]))
                         * (radius * 0.5 / viewDepth), vec2(0.08));
    vec3 bounce = vec3(0.0);
    for (int i = 0; i < 8; ++i) {
        // Two rings reduce directional bias without relying on random textures.
        float angle = 1.57079632679 * mod(float(i), 4.0) + ((i < 4) ? 0.0 : 0.78539816339);
        float ring = (i < 4) ? 0.5 : 1.0;
        vec2 sampleUV = uv + vec2(cos(angle), sin(angle)) * footprint * ring;
        if (any(lessThanEqual(sampleUV, vec2(0.0))) ||
            any(greaterThanEqual(sampleUV, vec2(1.0)))) continue;
        float sampleDepth = texture2D(depthBuffer, sampleUV).r;
        if (sampleDepth >= 1.0) continue;
        vec3 samplePosition = indirectViewPosition(sampleUV, sampleDepth, projectionInverse);
        vec3 displacement = samplePosition - position;
        float distanceSquared = dot(displacement, displacement);
        if (distanceSquared < 0.0025 || distanceSquared > radius * radius) continue;
        vec3 direction = displacement * inversesqrt(distanceSquared);
        vec4 sampleData = texture2D(normalBuffer, sampleUV);
        if (sampleData.a <= 0.005) continue;
        vec3 encodedNormal = sampleData.rgb * 2.0 - 1.0;
        float normalLengthSquared = dot(encodedNormal, encodedNormal);
        if (normalLengthSquared < 0.01) continue;
        vec3 sampleNormal = encodedNormal * inversesqrt(normalLengthSquared);
        float facing = max(dot(normal, direction), 0.0)
                     * max(dot(sampleNormal, -direction), 0.0);
        float falloff = 1.0 - smoothstep(0.0, radius * radius, distanceSquared);
        vec3 source = pow(max(texture2D(colorBuffer, sampleUV).rgb, vec3(0.0)), vec3(2.2));
        bounce += min(source, vec3(1.0)) * facing * falloff;
    }
    // Fixed normalization avoids amplifying light when samples leave the frame.
    return bounce * (INDIRECT_STRENGTH / 8.0);
}

// Trace a short view-space ray toward the shadow-casting light. Geometry hidden
// behind the camera depth layer and off-screen occluders cannot cast shadows.
float contactShadow(vec3 position, vec3 normal, vec3 lightPosition,
                    sampler2D depthBuffer, mat4 projection, mat4 projectionInverse) {
    float lightLength = length(lightPosition);
    if (lightLength < 0.001) return 1.0;
    vec3 lightDirection = lightPosition / lightLength;
    if (dot(normal, lightDirection) <= 0.05) return 1.0;
    float distanceFade = 1.0 - smoothstep(24.0, 64.0, length(position));
    if (distanceFade <= 0.0) return 1.0;
    vec3 origin = position + normal * 0.06;
    float blocked = 0.0;
    for (int i = 0; i < 8; ++i) {
        float distanceAlongRay = (float(i) + 1.0) * 0.14;
        vec3 ray = origin + lightDirection * distanceAlongRay;
        vec4 clip = projection * vec4(ray, 1.0);
        if (clip.w <= 0.0) break;
        vec2 sampleUV = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThanEqual(sampleUV, vec2(0.0))) ||
            any(greaterThanEqual(sampleUV, vec2(1.0)))) break;
        float depth = texture2D(depthBuffer, sampleUV).r;
        if (depth >= 1.0) continue;
        vec3 scene = indirectViewPosition(sampleUV, depth, projectionInverse);
        float thickness = scene.z - ray.z;
        // Reject unrelated foreground surfaces; depth alone cannot distinguish
        // thickness from distant occluders behind the visible depth layer.
        if (thickness > 0.015 && thickness < 0.14) {
            blocked = 1.0;
            break;
        }
    }
    return 1.0 - blocked * CONTACT_SHADOW_STRENGTH * distanceFade;
}
