// Optional single-layer procedural sky clouds. Disabled until tested in Iris.
// The 4096-block tile and its wind period keep the noise stable across the
// world-coordinate wrap and the default 3600-second frameTimeCounter wrap.
#define PROCEDURAL_CLOUDS 0 // [0 1]
#define CLOUD_COVERAGE 0.5 // [0.3 0.4 0.5 0.6 0.7]

#if PROCEDURAL_CLOUDS == 1
float enchantedCloudHash(vec2 cell) {
    cell = mod(cell, 32.0);
    return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float enchantedCloudNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = enchantedCloudHash(cell);
    float b = enchantedCloudHash(cell + vec2(1.0, 0.0));
    float c = enchantedCloudHash(cell + vec2(0.0, 1.0));
    float d = enchantedCloudHash(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 enchantedClouds(vec3 sky, vec3 worldDirection, vec3 worldSunDirection,
                     vec3 cameraWorldPosition, float time, float rain,
                     vec3 atmosphereColor) {
    // Intersect a fixed-altitude layer; avoid unstable near-horizontal rays.
    float altitude = 192.0 - cameraWorldPosition.y;
    if (abs(worldDirection.y) < 0.035 || altitude * worldDirection.y <= 0.0)
        return sky;
    float distanceToLayer = altitude / worldDirection.y;
    vec2 origin = mod(cameraWorldPosition.xz, 4096.0);
    float wind = mod(time, 3600.0) * (4096.0 / 3600.0);
    vec2 point = mod(origin + worldDirection.xz * distanceToLayer
                     + vec2(wind, wind * 2.0), 4096.0) * (32.0 / 4096.0);
    float shape = enchantedCloudNoise(point) * 0.5333333;
    shape += enchantedCloudNoise(point * 2.0) * 0.2666667;
    shape += enchantedCloudNoise(point * 4.0) * 0.1333333;
    shape += enchantedCloudNoise(point * 8.0) * 0.0666667;
    float coverage = clamp(CLOUD_COVERAGE + rain * 0.16, 0.0, 0.9);
    float opacity = smoothstep(1.0 - coverage, 1.12 - coverage, shape);
    opacity *= smoothstep(0.035, 0.14, abs(worldDirection.y));
    float day = smoothstep(-0.08, 0.22, worldSunDirection.y);
    float forwardLight = pow(max(dot(worldDirection, worldSunDirection), 0.0), 12.0);
    vec3 nightCloud = atmosphereColor * 0.45;
    vec3 dayCloud = mix(atmosphereColor, vec3(0.95, 0.96, 1.0), 0.72);
    vec3 cloudColor = mix(nightCloud, dayCloud, day);
    cloudColor *= 1.0 - 0.35 * rain;
    cloudColor += vec3(0.12, 0.09, 0.06) * forwardLight * day * (1.0 - rain);
    return mix(sky, cloudColor, opacity * 0.85);
}
#endif
