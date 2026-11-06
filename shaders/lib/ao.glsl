// Screen-space ambient occlusion. This is an approximation based on visible
// depth; off-screen and hidden geometry cannot contribute.
#define AO_STRENGTH 0.45 // [0.0 0.25 0.45 0.7 1.0]
#define AO_RADIUS 1.5 // [0.5 1.0 1.5 2.0 3.0]

vec3 aoViewPosition(vec2 coord, float depth, mat4 projectionInverse) {
    vec4 p = projectionInverse * vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return p.xyz / p.w;
}

float ambientOcclusion(sampler2D sceneDepth, mat4 projection, mat4 projectionInverse,
                       vec2 coord, vec2 viewport, vec3 position, vec3 normal) {
    if (AO_STRENGTH <= 0.0) return 1.0;
    // Project a fixed world-space radius and cap it in pixels to avoid huge
    // near-camera halos. Account for the perspective and screen aspect ratio.
    vec2 size = max(viewport, vec2(1.0));
    vec2 projectedRadius = vec2(abs(projection[0][0]), abs(projection[1][1]))
                         * (0.5 * AO_RADIUS / max(-position.z, 0.1));
    vec2 radiusPixels = min(projectedRadius * size, vec2(40.0));
    vec2 radiusUV = radiusPixels / size;

    // A stable per-pixel rotation breaks up radial patterns without requiring
    // a noise texture or temporal history. Two rings provide local detail and
    // broader contact shadows at a fixed sample cost.
    float rotation = fract(sin(dot(floor(coord * size), vec2(12.9898, 78.233))) * 43758.5453) * 6.28318530718;
    float occlusion = 0.0;
    for (int i = 0; i < 12; ++i) {
        float fi = float(i);
        float angle = rotation + fi * 2.39996323;
        float ring = sqrt((fi + 0.5) / 12.0);
        vec2 sampleCoord = coord + vec2(cos(angle), sin(angle)) * radiusUV * ring;
        if (any(lessThanEqual(sampleCoord, vec2(0.0))) ||
            any(greaterThanEqual(sampleCoord, vec2(1.0)))) continue;
        float depth = texture2D(sceneDepth, sampleCoord).r;
        if (depth >= 0.999999) continue;
        vec3 delta = aoViewPosition(sampleCoord, depth, projectionInverse) - position;
        float distanceToSample = length(delta);
        if (distanceToSample < 0.0001 || distanceToSample >= AO_RADIUS) continue;
        float facing = max(dot(normal, delta / distanceToSample) - 0.12, 0.0);
        float attenuation = 1.0 - smoothstep(AO_RADIUS * 0.25, AO_RADIUS, distanceToSample);
        occlusion += facing * attenuation;
    }
    // A fixed denominator fades smoothly at image boundaries and avoids
    // over-darkening where many samples fall on sky or outside the viewport.
    return 1.0 - AO_STRENGTH * clamp(occlusion * (2.5 / 12.0), 0.0, 1.0);
}
