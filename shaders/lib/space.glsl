vec3 positionAt(vec2 coord, float depth) {
    vec4 v = gbufferProjectionInverse * vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}
