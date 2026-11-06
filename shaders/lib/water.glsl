#include "/lib/lighting_settings.glsl"
// Analytic, world-anchored water waves. Positions passed to this function are
// camera-relative world coordinates (the result of gbufferModelViewInverse).
// A shared 64-block period allows the camera origin to be reduced before adding
// it, preserving detail far from spawn without visible seams at period edges.
vec3 enchantedWaterNormal(vec3 viewNormal, vec3 relativeWorldPosition,
                          vec3 cameraWorldPosition, float time,
                          mat4 viewToWorld, mat4 worldToView) {
    time *= WATER_WAVE_SPEED;
    const float waveScale = 0.0981747704; // 2 * pi / 64 blocks
    vec2 p = relativeWorldPosition.xz + mod(cameraWorldPosition.xz, 64.0);
    vec2 k0 = vec2(2.0, 1.0);
    vec2 k1 = vec2(3.0, -2.0);
    vec2 k2 = vec2(5.0, 4.0);
    vec2 k3 = vec2(9.0, -5.0);

    // Derivatives of four traveling sine waves, avoiding texture dependencies.
    // Fade the short waves in the distance to limit high-frequency shimmer.
    float distanceToCamera = length(relativeWorldPosition);
    float detailFade = 1.0 - smoothstep(24.0, 100.0, distanceToCamera);
    vec2 slope = 0.25 * k0 * cos(dot(p, k0) * waveScale + time * 0.75);
    slope += 0.12 * k1 * cos(dot(p, k1) * waveScale - time * 0.55);
    slope += detailFade * 0.045 * k2 * cos(dot(p, k2) * waveScale + time * 1.05);
    slope += detailFade * 0.018 * k3 * cos(dot(p, k3) * waveScale - time * 1.35);
    slope *= waveScale * WATER_WAVE_STRENGTH;

    // Keep side faces stable and perturb a normal in world space, then return
    // it to the view space expected by the reflection buffer.
    vec3 worldNormal = normalize(mat3(viewToWorld) * viewNormal);
    float horizontalFace = smoothstep(0.35, 0.8, abs(worldNormal.y));
    worldNormal = normalize(worldNormal + vec3(-slope.x, 0.0, -slope.y) * horizontalFace * sign(worldNormal.y));
    return normalize(mat3(worldToView) * worldNormal);
}
