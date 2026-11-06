#include "/lib/settings.glsl"
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float frameTimeCounter;
uniform mat4 gbufferModelViewInverse;
varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
/* DRAWBUFFERS:01 */
void main() {
    vec4 base = texture2D(texture, uv) * tint;
    if (base.a < 0.1) discard;
    vec3 n = normalize(normal);
    float reflectivity = material;
#ifdef WATER
    if (material > 0.9) {
        vec3 world = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        float t = frameTimeCounter;
        vec3 wave = vec3(0.06 * cos(world.x * 1.7 + t), 0.0,
                         0.06 * sin(world.z * 1.3 + t * 1.2));
        n = normalize(n + mat3(gl_ModelViewMatrix) * wave);
        base.rgb = mix(base.rgb, vec3(0.035, 0.15, 0.19), 0.45);
        base.a = 0.78;
    }
#endif
    vec3 illumination = texture2D(lightmap, lm).rgb;
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    float hand = held * HAND_LIGHT * max(0.0, 1.0 - length(viewPos) / 12.0);
    illumination = max(illumination, vec3(1.0, 0.66, 0.32) * hand);
    base.rgb *= max(illumination, vec3(0.025));
    gl_FragData[0] = base;
    gl_FragData[1] = vec4(n * 0.5 + 0.5, reflectivity);
}
