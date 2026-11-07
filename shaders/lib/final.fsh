#include "/lib/settings.glsl"
#include "/lib/post_settings.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 uv;
#include "/lib/camera_effects.glsl"

vec2 finalCoord(vec2 coord) {
    vec2 pixel = 0.5 / max(vec2(viewWidth, viewHeight), vec2(1.0));
    return clamp(coord, pixel, vec2(1.0) - pixel);
}

vec3 finalScene(vec2 coord) {
    return max(texture2D(colortex0, finalCoord(coord)).rgb, vec3(0.0));
}

float finalLuma(vec3 color) {
    // Approximate display-space luminance for FXAA while keeping colour
    // samples in linear HDR; actual tone mapping happens once below.
    return sqrt(max(dot(color, vec3(0.2126, 0.7152, 0.0722)), 0.0));
}

vec3 finalFXAA(vec2 coord, vec3 source) {
#if FXAA == 1
    if (FXAA_STRENGTH <= 0.0) return source;
    vec2 pixel = 1.0 / max(vec2(viewWidth, viewHeight), vec2(1.0));
    vec3 nw = finalScene(coord + vec2(-1.0, -1.0) * pixel);
    vec3 ne = finalScene(coord + vec2( 1.0, -1.0) * pixel);
    vec3 sw = finalScene(coord + vec2(-1.0,  1.0) * pixel);
    vec3 se = finalScene(coord + vec2( 1.0,  1.0) * pixel);
    float lnw = finalLuma(nw), lne = finalLuma(ne);
    float lsw = finalLuma(sw), lse = finalLuma(se);
    float lm = finalLuma(source);
    float low = min(lm, min(min(lnw, lne), min(lsw, lse)));
    float high = max(lm, max(max(lnw, lne), max(lsw, lse)));
    if (high - low < max(0.0312, high * 0.125)) return source;
    vec2 direction = vec2(-((lnw + lne) - (lsw + lse)),
                           (lnw + lsw) - (lne + lse));
    float reduction = max((lnw + lne + lsw + lse) * 0.03125, 0.0078125);
    float reciprocal = 1.0 / (min(abs(direction.x), abs(direction.y)) + reduction);
    direction = clamp(direction * reciprocal, vec2(-8.0), vec2(8.0)) * pixel;
    vec3 a = 0.5 * (finalScene(coord + direction * (-1.0 / 6.0))
                  + finalScene(coord + direction * ( 1.0 / 6.0)));
    vec3 b = a * 0.5 + 0.25 * (finalScene(coord - direction * 0.5)
                             + finalScene(coord + direction * 0.5));
    float lb = finalLuma(b);
    return mix(source, lb < low || lb > high ? a : b, FXAA_STRENGTH);
#else
    return source;
#endif
}

void main() {
    vec3 cameraColor = finalScene(uv);
    cameraColor = finalFXAA(uv, cameraColor);
#ifdef DEPTH_OF_FIELD
    cameraColor = applyDepthOfField(uv, cameraColor, vec2(viewWidth, viewHeight));
#endif
#ifdef MOTION_BLUR
    cameraColor = applyMotionBlur(uv, cameraColor);
#endif
    // Scene and emitter blur remain linear and HDR through optical effects.
    vec3 c = max(cameraColor, vec3(0.0));
    if (BLOOM_STRENGTH > 0.0)
        c += max(texture2D(colortex3, finalCoord(uv)).rgb, vec3(0.0)) * BLOOM_STRENGTH;
    c *= EXPOSURE;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    c = pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
    float luminance = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(luminance), c, SATURATION);
    c = (c - 0.5) * CONTRAST + 0.5;
    gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
