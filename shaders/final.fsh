#version 120
#include "/lib/settings.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTime;
varying vec2 uv;
#include "/lib/space.glsl"
vec3 scene(vec2 coord) {
    return texture2D(colortex0, coord).rgb + texture2D(colortex4, coord).rgb * BLOOM_STRENGTH;
}
bool isHand(vec2 coord) {
    float tag = texture2D(colortex2, coord).a;
    return tag > 0.25 && tag < 0.75;
}
void main() {
    vec3 c = scene(uv);
    float depth = texture2D(depthtex0, uv).r;
    vec3 cameraDelta = cameraPosition - previousCameraPosition;
    if (MOTION_BLUR > 0.0 && !isHand(uv) && frameTime > 0.0 && frameTime < 0.2 && length(cameraDelta) < 8.0) {
        vec3 pos = positionAt(uv, depth);
        vec4 previous;
        if (depth >= 1.0) {
            vec3 direction = mat3(gbufferModelViewInverse) * normalize(pos);
            previous = gbufferPreviousProjection * vec4(mat3(gbufferPreviousModelView) * direction, 0.0);
        } else {
            vec3 world = (gbufferModelViewInverse * vec4(pos, 1.0)).xyz + cameraDelta;
            previous = gbufferPreviousProjection * gbufferPreviousModelView * vec4(world, 1.0);
        }
        if (previous.w > 0.0) {
            vec2 velocity = (uv - (previous.xy / previous.w * 0.5 + 0.5)) * MOTION_BLUR;
            vec2 pixels = vec2(viewWidth, viewHeight);
            float speed = length(velocity * pixels);
            velocity *= min(1.0, 32.0 / max(speed, 0.0001));
            if (speed > 0.5) {
                vec3 sum = c;
                float weight = 1.0;
                for (int i = 1; i < 8; i++) {
                    vec2 coord = uv - velocity * (float(i) / 7.0);
                    if (any(lessThan(coord, vec2(0.0))) || any(greaterThan(coord, vec2(1.0)))) continue;
                    if (isHand(coord)) continue;
                    float d = texture2D(depthtex0, coord).r;
                    float sampleZ = -positionAt(coord, d).z;
                    if ((depth < 1.0 && d >= 1.0) || (depth >= 1.0 && d < 1.0)) continue;
                    if (abs(sampleZ + pos.z) > max(0.35, -pos.z * 0.05)) continue;
                    sum += scene(coord);
                    weight += 1.0;
                }
                c = sum / weight;
            }
        }
    }
    c = max(c, vec3(0.0)) * EXPOSURE;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    gl_FragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
