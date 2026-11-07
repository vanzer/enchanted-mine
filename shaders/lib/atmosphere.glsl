#ifndef ENCHANTED_ATMOSPHERE
#define ENCHANTED_ATMOSPHERE
#include "/lib/sky_settings.glsl"

// These helpers deliberately avoid the reserved GLSL noise1/2/3/4 names.
float enchantedAtmosHash(vec3 cell) {
    // A world-space tile prevents loss of precision far from the origin.
    cell = mod(cell, 32.0);
    return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float enchantedAtmosNoise(vec3 point) {
    vec3 cell = floor(point);
    vec3 f = fract(point);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(enchantedAtmosHash(cell), enchantedAtmosHash(cell + vec3(1.0, 0.0, 0.0)), f.x);
    float b = mix(enchantedAtmosHash(cell + vec3(0.0, 1.0, 0.0)), enchantedAtmosHash(cell + vec3(1.0, 1.0, 0.0)), f.x);
    float c = mix(enchantedAtmosHash(cell + vec3(0.0, 0.0, 1.0)), enchantedAtmosHash(cell + vec3(1.0, 0.0, 1.0)), f.x);
    float d = mix(enchantedAtmosHash(cell + vec3(0.0, 1.0, 1.0)), enchantedAtmosHash(cell + vec3(1.0, 1.0, 1.0)), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

vec2 enchantedCloudWind(float time) {
    // Circular advection joins continuously at Iris's 3600-second timer wrap.
    float phase = mod(time, 3600.0) * 0.001745329252;
    return vec2(cos(phase), sin(phase)) * 512.0 * CLOUD_SPEED;
}

float enchantedCloudDensity(vec3 world, float time, float rain) {
    float height = (world.y - CLOUD_HEIGHT) / CLOUD_THICKNESS;
    if (height <= 0.0 || height >= 1.0) return 0.0;
    vec2 horizontal = mod(world.xz + enchantedCloudWind(time), 8192.0);
    vec3 p = vec3(horizontal.x, world.y * 1.5, horizontal.y) / 256.0;
    float shape = enchantedAtmosNoise(p) * 0.57;
    shape += enchantedAtmosNoise(p * 2.0 + vec3(7.0, 0.0, 13.0)) * 0.29;
    shape += enchantedAtmosNoise(p * 4.0) * 0.14;
    float envelope = smoothstep(0.0, 0.18, height) * (1.0 - smoothstep(0.65, 1.0, height));
    float threshold = 0.72 - CLOUD_COVERAGE * 0.50 - rain * 0.12;
    return smoothstep(threshold, threshold + 0.20, shape) * envelope * CLOUD_DENSITY;
}

// Reuses the same 3-D density as the visible cloud volume, so its shadow moves
// with the cloud rather than being an unrelated dark pattern on the terrain.
float enchantedCloudShadow(vec3 worldPos, vec3 worldLight, float time, float rain) {
#if CLOUD_SHADOWS == 1 && VOLUMETRIC_CLOUDS == 1 && !defined(DIM_NETHER) && !defined(DIM_END)
    if (worldLight.y <= 0.04 || worldPos.y >= CLOUD_HEIGHT + CLOUD_THICKNESS) return 1.0;
    float opticalDepth = 0.0;
    float start = max((CLOUD_HEIGHT - worldPos.y) / worldLight.y, 0.0);
    float end = min((CLOUD_HEIGHT + CLOUD_THICKNESS - worldPos.y) / worldLight.y, start + 600.0);
    float stepLength = (end - start) / 3.0;
    for (int i = 0; i < 3; ++i) {
        vec3 p = worldPos + worldLight * (start + (float(i) + 0.5) * stepLength);
        opticalDepth += enchantedCloudDensity(p, time, rain) * stepLength * 0.035;
    }
    return mix(1.0, exp(-opticalDepth), CLOUD_SHADOW_STRENGTH);
#else
    return 1.0;
#endif
}

// A direction-based sky also provides consistent off-screen reflection color.
// Inputs skyColor/fogColor use Minecraft's display color space; output is linear.
vec3 enchantedClearSky(vec3 direction, vec3 sun, float time, float rain,
                        vec3 biomeSky, vec3 biomeFog) {
    vec3 d = normalize(direction);
    vec3 light = normalize(sun);
    vec3 fog = pow(max(biomeFog, vec3(0.0)), vec3(2.2));
#if defined(DIM_NETHER)
    return fog * (0.55 + 0.20 * max(d.y, 0.0));
#elif defined(DIM_END)
    float star = pow(max(enchantedAtmosNoise(d * 280.0) - 0.80, 0.0) * 5.0, 3.0);
    return vec3(0.018, 0.009, 0.030) + vec3(0.16, 0.10, 0.24) * star * STAR_STRENGTH;
#else
    float day = smoothstep(-0.10, 0.16, light.y);
    float night = 1.0 - smoothstep(-0.18, -0.02, light.y);
    float horizon = pow(1.0 - clamp(abs(d.y), 0.0, 1.0), 3.0);
    float sunset = (1.0 - smoothstep(0.0, 0.32, abs(light.y))) * (1.0 - rain);
    vec3 zenith = mix(vec3(0.002, 0.004, 0.014), pow(max(biomeSky, vec3(0.0)), vec3(2.2)), day);
    vec3 color = mix(zenith, mix(vec3(0.008, 0.012, 0.025), fog, day), horizon * 0.85);
    float facingSun = max(dot(d, light), 0.0);
    color += vec3(0.78, 0.20, 0.048) * sunset * horizon * pow(facingSun, 3.0) * SUNSET_STRENGTH;
    float sunDisc = smoothstep(0.99977, 0.99986, dot(d, light));
    float halo = pow(facingSun, 48.0) * 0.22 + pow(facingSun, 6.0) * 0.025;
    vec3 sunTint = mix(vec3(1.0, 0.32, 0.10), vec3(1.0, 0.91, 0.72), smoothstep(0.0, 0.3, light.y));
    color += sunTint * (sunDisc * 6.0 + halo * SUN_GLOW) * smoothstep(-0.04, 0.04, light.y) * (1.0 - rain);
    float moonDot = max(dot(d, -light), 0.0);
    float moon = smoothstep(0.99974, 0.99986, moonDot) * 0.65 + pow(moonDot, 90.0) * 0.018 * SUN_GLOW;
    color += vec3(0.50, 0.65, 1.0) * moon * night * (1.0 - rain);

    // Quantize direction, then test proximity to a randomized point in each
    // cell: actual tiny stars, rather than a full-screen layer of noisy grain.
    vec3 cell = floor(d * 240.0);
    vec3 local = fract(d * 240.0);
    float random = enchantedAtmosHash(cell);
    float size = length(local - vec3(0.5));
    float stars = (1.0 - smoothstep(0.04, 0.13, size)) * step(0.88, random);
    float twinkle = 0.8 + 0.2 * sin(mod(time, 3600.0) * 0.0523598776 + random * 48.0);
    color += mix(vec3(0.42, 0.62, 1.0), vec3(1.0, 0.76, 0.48), random)
             * stars * twinkle * night * STAR_STRENGTH * smoothstep(0.0, 0.12, d.y) * (1.0 - rain);

    // Layered curtains at virtual high-altitude planes. Their positions depend
    // on world direction, keeping aurora coherent as the camera turns.
    if (AURORA_STRENGTH > 0.0 && night > 0.001 && d.y > 0.025) {
        vec3 aurora = vec3(0.0);
        float phase = mod(time, 3600.0) * 0.001745329252;
        for (int i = 0; i < 6; ++i) {
            float layer = float(i) / 5.0;
            vec2 p = d.xz / max(d.y + layer * 0.12, 0.04) * (1.0 + layer * 0.15);
            float bend = sin(p.y * 1.6 + sin(phase) * 1.8) * 0.55;
            float ribbon = exp(-abs(p.x + bend - 0.5 * sin(p.y * 0.6 + phase)) * 7.0);
            float fibers = 0.35 + 0.65 * enchantedAtmosNoise(vec3(p.y * 9.0, layer * 3.0, sin(phase) * 2.0));
            vec3 tint = mix(vec3(0.08, 0.90, 0.42), vec3(0.48, 0.08, 0.78), layer);
            aurora += tint * ribbon * fibers * (1.0 - layer * 0.65) / 6.0;
        }
        color += aurora * AURORA_STRENGTH * night * (1.0 - rain) * smoothstep(0.025, 0.20, d.y);
    }
    color = mix(color, mix(fog * 0.65, vec3(0.015), night), rain * 0.65);
    return max(color, vec3(0.0)) * SKY_BRIGHTNESS;
#endif
}

vec3 enchantedSky(vec3 worldDir, vec3 worldSun, vec3 camera, float time,
                   float rain, vec3 skyColor, vec3 fogColor) {
    vec3 direction = normalize(worldDir);
    vec3 light = normalize(worldSun);
    vec3 sky = enchantedClearSky(direction, light, time, rain, skyColor, fogColor);
#if VOLUMETRIC_CLOUDS == 1 && !defined(DIM_NETHER) && !defined(DIM_END)
    if (abs(direction.y) < 0.008) return sky;
    float a = (CLOUD_HEIGHT - camera.y) / direction.y;
    float b = (CLOUD_HEIGHT + CLOUD_THICKNESS - camera.y) / direction.y;
    float start = max(min(a, b), 0.0);
    float end = min(max(a, b), 1800.0);
    if (end <= start) return sky;
    float stepLength = (end - start) / float(CLOUD_STEPS);
    float transmittance = 1.0;
    vec3 scattering = vec3(0.0);
    float day = smoothstep(-0.10, 0.16, light.y);
    vec3 activeLight = light.y > -0.02 ? light : -light;
    vec3 ambient = mix(vec3(0.006, 0.010, 0.022), vec3(0.23, 0.31, 0.43), day);
    vec3 sunColor = mix(vec3(0.045, 0.065, 0.11), mix(vec3(1.0, 0.37, 0.12), vec3(1.0, 0.93, 0.80), smoothstep(0.0, 0.25, light.y)), day);
    float forward = pow(max(dot(direction, activeLight), 0.0), 12.0);
    for (int i = 0; i < CLOUD_STEPS; ++i) {
        vec3 position = camera + direction * (start + (float(i) + 0.5) * stepLength);
        float density = enchantedCloudDensity(position, time, rain);
        if (density > 0.001) {
            // Two light-space samples give the cloud its illuminated edge and
            // shaded interior. This is volume self-shadowing, not a sky decal.
            float optical = enchantedCloudDensity(position + activeLight * 18.0, time, rain) * 18.0;
            optical += enchantedCloudDensity(position + activeLight * 48.0, time, rain) * 30.0;
            float visibility = exp(-optical * 0.065);
            float opacity = 1.0 - exp(-density * stepLength * 0.055);
            vec3 illumination = ambient + sunColor * visibility * (0.55 + forward * 0.85) * (1.0 - rain * 0.55);
            scattering += transmittance * opacity * illumination;
            transmittance *= 1.0 - opacity;
            if (transmittance < 0.015) break;
        }
    }
    vec3 cloudy = sky * transmittance + scattering;
    // Hide the finite ray extent in the existing atmosphere at the horizon.
    return mix(sky, cloudy, smoothstep(0.008, 0.05, abs(direction.y)));
#else
    return sky;
#endif
}
#endif
