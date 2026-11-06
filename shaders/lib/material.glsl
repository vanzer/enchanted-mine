// Optional LabPBR 1.3 texture channels. Enable only with a LabPBR resource pack.
// The shader also works without a resource pack while this option is disabled.
//#define LAB_PBR

#ifdef LAB_PBR
uniform sampler2D specular;
uniform sampler2D normals;

// Construct a tangent frame from view-space derivatives. This avoids requiring
// tangent attributes, which are not supplied by every gbuffers program.
vec3 labPbrNormal(vec3 position, vec3 geometricNormal, vec2 texcoord, vec2 encoded) {
    vec3 dpdx = dFdx(position);
    vec3 dpdy = dFdy(position);
    vec2 duvdx = dFdx(texcoord);
    vec2 duvdy = dFdy(texcoord);
    float determinant = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
    if (abs(determinant) < 0.00000001) return geometricNormal;

    vec3 tangent = (dpdx * duvdy.y - dpdy * duvdx.y) / determinant;
    tangent -= geometricNormal * dot(geometricNormal, tangent);
    float tangentLength = length(tangent);
    if (tangentLength < 0.00001) return geometricNormal;
    tangent /= tangentLength;
    vec3 bitangent = normalize(cross(geometricNormal, tangent)) * sign(determinant);
    vec2 xy = encoded * 2.0 - 1.0;
    float z = sqrt(max(1.0 - dot(xy, xy), 0.0));
    return normalize(tangent * xy.x + bitangent * xy.y + geometricNormal * z);
}

void applyLabPBR(vec2 texcoord, vec3 position, inout vec3 surfaceNormal,
                 inout float reflectivity, inout vec3 illumination) {
    vec4 spec = texture2D(specular, texcoord);
    vec4 normalMap = texture2D(normals, texcoord);
    // Some loaders use a black fallback when the normal map is absent.
    // Avoid turning such surfaces black or perturbing their normals.
    bool hasNormal = dot(normalMap.rgb, normalMap.rgb) > 0.00001;
    vec3 mappedNormal = labPbrNormal(position, surfaceNormal, texcoord, normalMap.rg);
    if (hasNormal) {
        surfaceNormal = mappedNormal;
        illumination *= normalMap.b;
    }

    // Red is perceptual smoothness, not linear roughness. The existing SSR
    // pass has a single reflection-strength channel, so preserve its block
    // defaults and approximate the contribution of the resource-pack map.
    reflectivity = max(reflectivity, spec.r * spec.r);
    // In LabPBR, alpha=255 means "no emission" rather than full emission.
    float emission = spec.a < (254.5 / 255.0) ? spec.a : 0.0;
    illumination += vec3(emission);
}
#endif
