// Optional screen-space camera effects. Both are disabled by default.
//#define DEPTH_OF_FIELD
//#define MOTION_BLUR
#define DOF_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define MOTION_BLUR_STRENGTH 0.5 // [0.0 0.25 0.5 0.75 1.0]

#if defined(DEPTH_OF_FIELD) || defined(MOTION_BLUR)
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;

// Returns a view-space position using the exact projection that produced depth.
vec3 cameraViewPosition(vec2 coord, float depth) {
    vec4 p = gbufferProjectionInverse * vec4(coord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return p.xyz / max(abs(p.w), 0.000001) * sign(p.w);
}

bool cameraInsideScreen(vec2 coord) {
    return all(greaterThanEqual(coord, vec2(0.0))) && all(lessThanEqual(coord, vec2(1.0)));
}
#endif

#ifdef DEPTH_OF_FIELD
// Centre-screen autofocus. Ignore a centre aimed at the sky rather than focus
// on an infinite background or abruptly blur the entire scene.
vec3 applyDepthOfField(vec2 coord, vec3 source, vec2 viewport) {
    float depth = texture2D(depthtex0, coord).r;
    float focusDepth = texture2D(depthtex0, vec2(0.5)).r;
    if (depth >= 0.999999 || focusDepth >= 0.999999) return source;
    float distance = -cameraViewPosition(coord, depth).z;
    float focus = -cameraViewPosition(vec2(0.5), focusDepth).z;
    float coc = clamp(abs(distance - focus) / max(focus, 2.0), 0.0, 1.0);
    float radius = coc * 6.0 * DOF_STRENGTH;
    if (radius < 0.1) return source;

    vec2 pixel = radius / max(viewport, vec2(1.0));
    vec3 sum = source * 2.0;
    float total = 2.0;
    for (int i = 0; i < 8; ++i) {
        float angle = float(i) * 0.7853981634;
        vec2 sampleCoord = coord + vec2(cos(angle), sin(angle)) * pixel;
        if (cameraInsideScreen(sampleCoord)) {
            float sampleDepth = texture2D(depthtex0, sampleCoord).r;
            if (sampleDepth < 0.999999) {
                float sampleDistance = -cameraViewPosition(sampleCoord, sampleDepth).z;
                // Avoid sampling near silhouettes into the background.
                float weight = smoothstep(-max(distance * 0.1, 0.5), 0.0,
                                          sampleDistance - distance);
                sum += texture2D(colortex0, sampleCoord).rgb * weight;
                total += weight;
            }
        }
    }
    return sum / total;
}
#endif

#ifdef MOTION_BLUR
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// Reproject current geometry to the previous camera. This describes camera
// motion only; moving entities and disocclusion have no motion vectors.
vec3 applyMotionBlur(vec2 coord, vec3 source) {
    float depth = texture2D(depthtex0, coord).r;
    vec3 cameraDelta = cameraPosition - previousCameraPosition;
    // A teleport, first frame, or sky depth cannot be reprojected reliably.
    if (depth >= 0.999999 || dot(cameraDelta, cameraDelta) > 9.0) return source;
    vec3 viewPosition = cameraViewPosition(coord, depth);
    vec3 previousRelative = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz + cameraDelta;
    vec4 previousClip = gbufferPreviousProjection * gbufferPreviousModelView * vec4(previousRelative, 1.0);
    if (previousClip.w <= 0.0001) return source;
    vec2 previousCoord = previousClip.xy / previousClip.w * 0.5 + 0.5;
    vec2 velocity = (coord - previousCoord) * MOTION_BLUR_STRENGTH;
    float speed = length(velocity);
    if (speed < 0.0001) return source;
    velocity *= min(1.0, 0.025 / speed);
    vec3 sum = source;
    float total = 1.0;
    for (int i = 1; i <= 6; ++i) {
        vec2 sampleCoord = coord - velocity * (float(i) / 6.0);
        if (cameraInsideScreen(sampleCoord)) {
            float sampleDepth = texture2D(depthtex0, sampleCoord).r;
            if (sampleDepth < 0.999999) {
                float sampleZ = cameraViewPosition(sampleCoord, sampleDepth).z;
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
