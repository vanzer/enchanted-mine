uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 uv;
vec3 bloomSample(vec2 coord) {
#ifdef BLOOM_HORIZONTAL
    return texture2D(colortex2, clamp(coord, vec2(0.0), vec2(1.0))).rgb;
#else
    return texture2D(colortex3, clamp(coord, vec2(0.0), vec2(1.0))).rgb;
#endif
}
void main() {
#ifdef BLOOM_HORIZONTAL
    vec2 stepUV = vec2(2.5 / viewWidth, 0.0);
#else
    vec2 stepUV = vec2(0.0, 2.5 / viewHeight);
#endif
    vec3 bloom = bloomSample(uv) * 0.227027;
    bloom += (bloomSample(uv + stepUV * 1.384615) + bloomSample(uv - stepUV * 1.384615)) * 0.316216;
    bloom += (bloomSample(uv + stepUV * 3.230769) + bloomSample(uv - stepUV * 3.230769)) * 0.070270;
    gl_FragData[0] = vec4(bloom, 1.0);
}
