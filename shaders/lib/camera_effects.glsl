#ifndef ENCHANTED_CAMERA_EFFECTS
#define ENCHANTED_CAMERA_EFFECTS
#include "/lib/settings.glsl"
#include "/lib/temporal.glsl"
// Optional optical effects, independent from anti-aliasing and colour grading.
//#define DEPTH_OF_FIELD
#define MOTION_BLUR
#define DOF_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define DOF_RADIUS 6.0 // [3.0 6.0 9.0 12.0]
#define MOTION_BLUR_STRENGTH 0.5 // [0.0 0.25 0.5 0.75 1.0]
#define MOTION_BLUR_SAMPLES 6 // [4 6 8 12]

#if defined(DEPTH_OF_FIELD) || defined(MOTION_BLUR)
uniform sampler2D depthtex0;
uniform sampler2D colortex2;
uniform mat4 gbufferProjectionInverse;
uniform int frameCounter;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif

vec3 cameraViewPosition(vec2 coord, float depth) {
    return enchantedViewPosition(coord, depth, gbufferProjectionInverse,
                                 vec2(viewWidth, viewHeight), frameCounter);
}

// A near-buffer sky pixel may contain DH terrain. Compare reconstructed
// distances rather than raw depths, because the two projections have different
// clipping planes. All optical effects use this same nearest scene selection.
vec3 cameraScenePosition(vec2 coord, out bool valid, out bool distant) {
    float depth = texture2D(depthtex0, coord).r;
    valid = depth < 1.0;
    distant = false;
    vec3 position = cameraViewPosition(coord, depth);
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
    float dhDepth = texture2D(dhDepthTex0, coord).r;
    if (dhDepth < 1.0) {
        vec3 dhPosition = enchantedViewPosition(coord, dhDepth, dhProjectionInverse,
                                                vec2(viewWidth, viewHeight), frameCounter);
        if (!valid || length(dhPosition) < length(position)) {
            position = dhPosition;
            valid = true;
            distant = true;
        }
    }
#endif
    return position;
}

bool cameraInsideScreen(vec2 coord) {
    vec2 halfPixel = 0.5 / max(vec2(viewWidth, viewHeight), vec2(1.0));
    return all(greaterThanEqual(coord, halfPixel))
        && all(lessThanEqual(coord, vec2(1.0) - halfPixel));
}

bool cameraHandPixel(vec2 coord) {
    return texture2D(colortex2, coord).a > 1.5;
}
#endif

#ifdef DEPTH_OF_FIELD
// Autofocus on the centre of the screen. First-person items retain the sharp
// foreground image, and depth rejection prevents foreground colour bleeding.
vec3 applyDepthOfField(vec2 coord, vec3 source, vec2 viewport) {
    if (DOF_STRENGTH <= 0.0 || cameraHandPixel(coord)) return source;
    bool valid, distant, focusValid, focusDistant;
    vec3 position = cameraScenePosition(coord, valid, distant);
    vec3 focusPosition = cameraScenePosition(vec2(0.5), focusValid, focusDistant);
    if (!focusValid || cameraHandPixel(vec2(0.5))) return source;
    float viewDistance = valid ? -position.z : 100000.0;
    float focus = max(-focusPosition.z, 0.05);
    // Thin-lens-like CoC: bound the aperture and preserve the focus plane.
    float coc = clamp(abs(1.0 / focus - 1.0 / max(viewDistance, 0.05)) * 4.0, 0.0, 1.0);
    float radius = coc * DOF_RADIUS * DOF_STRENGTH;
    if (radius < 0.1) return source;
    vec2 pixel = radius / max(viewport, vec2(1.0));
    vec3 sum = source * 2.0;
    float total = 2.0;
    for (int i = 0; i < 12; ++i) {
        float angle = float(i) * 2.39996323;
        float ring = sqrt((float(i) + 0.5) / 12.0);
        vec2 sampleCoord = coord + vec2(cos(angle), sin(angle)) * pixel * ring;
        if (cameraInsideScreen(sampleCoord) && !cameraHandPixel(sampleCoord)) {
            bool sampleValid, sampleDistant;
            vec3 samplePosition = cameraScenePosition(sampleCoord, sampleValid, sampleDistant);
            float sampleDistance = sampleValid ? -samplePosition.z : 100000.0;
            float separation = max(viewDistance * 0.08, 0.25);
            float weight = smoothstep(-separation, 0.0, sampleDistance - viewDistance);
            sum += texture2D(colortex0, sampleCoord).rgb * weight;
            total += weight;
        }
    }
    return sum / total;
}
#endif

#ifdef MOTION_BLUR
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
uniform mat4 dhPreviousProjection;
#endif
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// Camera reprojection only: moving entities require motion vectors supplied
// by a separate renderer. Teleports and the first frame invalidate motion.
vec3 applyMotionBlur(vec2 coord, vec3 source) {
    if (MOTION_BLUR_STRENGTH <= 0.0 || frameCounter < 2 || cameraHandPixel(coord)) return source;
    bool valid, distant;
    vec3 viewPosition = cameraScenePosition(coord, valid, distant);
    vec3 cameraDelta = cameraPosition - previousCameraPosition;
    if (!valid || dot(cameraDelta, cameraDelta) > 9.0) return source;
    vec3 previousRelative = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz + cameraDelta;
    vec4 previousView = gbufferPreviousModelView * vec4(previousRelative, 1.0);
    vec4 previousClip = gbufferPreviousProjection * previousView;
#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
    if (distant) previousClip = dhPreviousProjection * previousView;
#endif
    if (previousClip.w <= 0.0001) return source;
    vec2 previousCoord = previousClip.xy / previousClip.w * 0.5 + 0.5;
#if TAA == 1
    previousCoord += enchantedJitter(frameCounter - 1) / max(vec2(viewWidth, viewHeight), vec2(1.0));
#endif
    // Raster sample offsets are not camera motion. A still camera must have
    // zero shutter velocity even when optional temporal jitter is enabled.
    vec2 rasterMotion = (enchantedJitter(frameCounter) - enchantedJitter(frameCounter - 1))
                      / max(vec2(viewWidth, viewHeight), vec2(1.0));
    vec2 velocity = (coord - previousCoord - rasterMotion) * MOTION_BLUR_STRENGTH;
    float speed = length(velocity);
    if (speed < 0.0001) return source;
    velocity *= min(1.0, 0.035 / speed);
    vec3 sum = source;
    float total = 1.0;
    for (int i = 1; i <= MOTION_BLUR_SAMPLES; ++i) {
        vec2 sampleCoord = coord - velocity * (float(i) / float(MOTION_BLUR_SAMPLES));
        if (cameraInsideScreen(sampleCoord) && !cameraHandPixel(sampleCoord)) {
            bool sampleValid, sampleDistant;
            vec3 samplePosition = cameraScenePosition(sampleCoord, sampleValid, sampleDistant);
            if (sampleValid) {
                float sampleZ = samplePosition.z;
                float weight = 1.0 - smoothstep(max(-viewPosition.z * 0.02, 0.2),
                                                max(-viewPosition.z * 0.1, 1.0),
                                                abs(sampleZ - viewPosition.z));
                sum += texture2D(colortex0, sampleCoord).rgb * weight;
                total += weight;
            }
        }
    }
    return sum / total;
}
#endif
#endif
