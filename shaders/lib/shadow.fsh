uniform sampler2D texture;
varying vec2 shadowUV;
varying vec4 shadowTint;
varying float shadowMaterial;
void main() {
    // Water should not cast an opaque silhouette. Cutout geometry must still
    // use its texture alpha, otherwise foliage and fences become solid shadows.
    if (shadowMaterial > 9999.5 && shadowMaterial < 10000.5) discard;
    if ((texture2D(texture, shadowUV) * shadowTint).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
