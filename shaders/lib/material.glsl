#ifndef ENCHANTED_MATERIAL
#define ENCHANTED_MATERIAL
#include "/lib/lighting_settings.glsl"
// Enable with a LabPBR 1.3 resource pack; no resource pack is needed otherwise.
//#define LAB_PBR
#ifdef LAB_PBR
uniform sampler2D specular;
uniform sampler2D normals;
#endif
vec3 enchantedTangentNormal(vec3 position, vec3 n, vec2 texcoord, vec2 encoded) {
    vec3 dpdx = dFdx(position);
    vec3 dpdy = dFdy(position);
    vec2 duvdx = dFdx(texcoord);
    vec2 duvdy = dFdy(texcoord);
    float determinant = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
    if (abs(determinant) < 0.00000001) return n;
    vec3 tangent = (dpdx * duvdy.y - dpdy * duvdx.y) / determinant;
    tangent -= n * dot(n, tangent);
    if (dot(tangent, tangent) < 0.00000001) return n;
    tangent = normalize(tangent);
    vec3 bitangent = normalize(cross(n, tangent)) * sign(determinant);
    vec2 xy = encoded * 2.0 - 1.0;
    float z = sqrt(max(1.0 - dot(xy, xy), 0.0));
    return normalize(tangent * xy.x + bitangent * xy.y + n * z);
}
vec3 enchantedBumpNormal(vec3 position, vec3 normal, vec3 albedo) {
    float height = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    vec3 dpdx = dFdx(position), dpdy = dFdy(position);
    vec3 r1 = cross(dpdy, normal), r2 = cross(normal, dpdx);
    float det = dot(dpdx, r1);
    if (abs(det) < 0.00000001) return normal;
    vec3 gradient = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
    // Screen derivatives avoid fetching across neighbouring atlas tiles.
    return normalize(abs(det) * normal - TEXTURE_BUMP * 0.08 * gradient);
}
void enchantedMaterial(vec2 coord, vec3 position, vec3 albedo, inout vec3 n,
                        inout float reflectivity, inout float metallic,
                        inout float ao, inout float emission, inout float subsurface) {
#ifdef LAB_PBR
    vec4 normalMap = texture2D(normals, coord);
    vec4 spec = texture2D(specular, coord);
    if (dot(normalMap.rgb, normalMap.rgb) > 0.00001) {
        n = enchantedTangentNormal(position, n, coord, normalMap.rg);
        ao *= mix(1.0, normalMap.b, MATERIAL_AO);
    }
    reflectivity = max(reflectivity, spec.r * spec.r);
    metallic = max(metallic, step(229.5 / 255.0, spec.g));
    float sss = spec.b > (64.5 / 255.0) ? (spec.b * 255.0 - 65.0) / 190.0 : 0.0;
    subsurface = max(subsurface, sss);
    emission = max(emission, spec.a < (254.5 / 255.0) ? spec.a : 0.0);
#else
    if (TEXTURE_BUMP > 0.0) n = enchantedBumpNormal(position, n, albedo);
#endif
}
vec3 enchantedSpecular(vec3 n, vec3 v, vec3 l, vec3 albedo, float reflectivity, float metallic) {
    float nl = max(dot(n, l), 0.0), nv = max(dot(n, v), 0.001);
    if (nl <= 0.0 || SPECULAR_STRENGTH <= 0.0) return vec3(0.0);
    vec3 halfSum = v + l;
    if (dot(halfSum, halfSum) < 0.000001) return vec3(0.0);
    vec3 h = normalize(halfSum);
    float nh = max(dot(n, h), 0.0), vh = max(dot(v, h), 0.0);
    float roughness = max(0.055, 1.0 - reflectivity);
    float a = roughness * roughness, a2 = a * a;
    float denom = nh * nh * (a2 - 1.0) + 1.0;
    float distribution = a2 / max(3.14159265 * denom * denom, 0.000001);
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float geometry = nv / (nv * (1.0 - k) + k) * nl / (nl * (1.0 - k) + k);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 fresnel = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);
    // Finite-area highlight clamp limits fireflies from very smooth surfaces.
    return min(vec3(12.0), distribution * geometry * fresnel / max(4.0 * nv * nl, 0.001))
         * nl * SPECULAR_STRENGTH;
}
#endif
