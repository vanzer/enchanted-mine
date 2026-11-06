#ifndef ENCHANTED_DH_DEPTH
#define ENCHANTED_DH_DEPTH
#include "/lib/temporal.glsl"

// DH depth uses its own clipping planes. It must be reconstructed with
// dhProjectionInverse before comparing it with ordinary view-space positions.
// The same jitter as the near terrain is removed before either reconstruction.
vec3 enchantedDistantPosition(vec2 coord, float depth, mat4 dhInverse,
                               vec2 viewport, int frame) {
    return enchantedViewPosition(coord, depth, dhInverse, viewport, frame);
}
#endif
