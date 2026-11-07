#include "/lib/settings.glsl"
#include "/lib/formats.glsl"
#include "/lib/temporal.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
uniform mat4 dhPreviousProjection;
#endif
varying vec2 uv;
const int colortex5Format = RGBA16F;
const bool colortex5Clear = false;
/* DRAWBUFFERS:05 */
void main() {
    vec3 color = texture2D(colortex0, uv).rgb;
    vec2 size = max(vec2(viewWidth, viewHeight), vec2(1.0));
    float depth = texture2D(depthtex0, uv).r;
    bool valid = depth < 1.0;
    bool distantSelected = false;
    vec3 view = enchantedViewPosition(uv, depth, gbufferProjectionInverse, size, frameCounter);
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
    float dhDepth = texture2D(dhDepthTex0, uv).r;
    if (dhDepth < 1.0) {
        vec3 distant = enchantedViewPosition(uv, dhDepth, dhProjectionInverse, size, frameCounter);
        if (!valid || length(distant) < length(view)) { view = distant; valid = true; distantSelected = true; }
    }
#endif
    float storedDepth = valid ? -view.z : 0.0;
#if TAA == 1
    vec3 cameraDelta = cameraPosition - previousCameraPosition;
    if (frameCounter > 1 && length(cameraDelta) < 3.0 && texture2D(colortex2, uv).a < 1.5) {
        // Sky uses a direction, so camera translation cannot move the stars.
        vec4 relative = gbufferModelViewInverse * vec4(valid ? view : normalize(view), valid ? 1.0 : 0.0);
        if (valid) relative.xyz += cameraDelta;
        vec4 previousView = gbufferPreviousModelView * relative;
        vec4 clip = gbufferPreviousProjection * previousView;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
        if (distantSelected) clip = dhPreviousProjection * previousView;
#endif
        if (clip.w > 0.0) {
            vec2 previousUV = clip.xy / clip.w * 0.5 + 0.5;
            // History was written at the previous jittered raster locations.
            previousUV += enchantedJitter(frameCounter - 1) / size;
            if (all(greaterThan(previousUV, vec2(0.0))) && all(lessThan(previousUV, vec2(1.0)))) {
                vec4 history = texture2D(colortex5, previousUV);
                float expectedDepth = valid ? -previousView.z : 0.0;
                bool matchDepth = valid ? (history.a > 0.0 && abs(history.a - expectedDepth) < max(expectedDepth * 0.015, 0.12)) : history.a == 0.0;
                if (matchDepth) {
                    vec3 lo = color;
                    vec3 hi = color;
                    for (int x = -1; x <= 1; ++x) {
                        for (int y = -1; y <= 1; ++y) {
                            vec3 sampleColor = texture2D(colortex0, clamp(uv + vec2(float(x), float(y)) / size, vec2(0.0), vec2(1.0))).rgb;
                            lo = min(lo, sampleColor); hi = max(hi, sampleColor);
                        }
                    }
                    vec3 historyColor = clamp(history.rgb, lo, hi);
                    float motionPixels = length((uv - previousUV) * size);
                    float weight = TAA_STRENGTH * (1.0 - 0.5 * smoothstep(0.0, 20.0, motionPixels));
                    color = mix(color, historyColor, weight);
                }
            }
        }
    }
#endif
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(color, storedDepth);
}
