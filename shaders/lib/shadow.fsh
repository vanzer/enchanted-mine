uniform sampler2D texture;
varying vec2 shadowUV;
varying vec4 shadowTint;
varying float shadowMaterial;
void main() {
    // Transparent water does not cast an opaque shadow; cutouts retain texture shape.
    if (abs(shadowMaterial - 10000.0) < 0.5) discard;
    if ((texture2D(texture, shadowUV) * shadowTint).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
