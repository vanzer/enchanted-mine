#include "/lib/settings.glsl"
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float frameTimeCounter;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;
uniform ivec2 atlasSize;
varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
varying float emission;
varying vec2 tileMid;
varying vec2 tileHalfSize;
/* DRAWBUFFERS:012 */
float heightAt(vec2 coord) {
    // Clamp to this sprite so neighbouring atlas tiles cannot cast false cavities.
    vec2 inset = 0.5 / max(vec2(atlasSize), vec2(1.0));
    vec2 extent = max(tileHalfSize - inset, vec2(0.0));
    return dot(texture2D(texture, clamp(coord, tileMid - extent, tileMid + extent)).rgb,
               vec3(0.2126, 0.7152, 0.0722));
}
void main() {
    vec4 texel = texture2D(texture, uv);
    vec4 base = texel * tint;
    if (base.a < 0.1) discard;
    base.rgb = pow(max(base.rgb, vec3(0.0)), vec3(2.2));
    vec3 n = normalize(normal);
    float shading = 1.0;
#ifdef TERRAIN
    float height = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 dx = dFdx(viewPos), dy = dFdy(viewPos);
    vec3 r1 = cross(dy, n), r2 = cross(n, dx);
    float det = dot(dx, r1);
    if (abs(det) > 0.0000001) {
        vec3 gradient = (r1 * dFdx(height) + r2 * dFdy(height)) / det;
        gradient *= min(0.12 * TEXTURE_DEPTH, 0.6 / max(length(gradient), 0.0001));
        vec3 bumped = normalize(n - gradient);
        vec3 lightDir = normalize(worldTime < 12785 || worldTime > 23215 ? sunPosition : moonPosition);
        shading += (dot(bumped, lightDir) - dot(n, lightDir)) * 0.55;
        n = bumped;
    }
    vec2 pixel = 1.0 / max(vec2(atlasSize), vec2(1.0));
    float neighbours = (heightAt(uv + vec2(pixel.x, 0.0)) + heightAt(uv - vec2(pixel.x, 0.0))
                      + heightAt(uv + vec2(0.0, pixel.y)) + heightAt(uv - vec2(0.0, pixel.y))) * 0.25;
    shading *= 1.0 - clamp(neighbours - height, 0.0, 1.0) * TEXTURE_DEPTH * 0.65;
#endif
    float tag = 0.0;
#ifdef HAND
    tag = 0.5;
#endif
#ifdef WATER
    if (material > 0.9) {
        vec3 world = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
        float t = frameTimeCounter;
        vec3 wave = vec3(0.045 * cos(world.x * 1.7 + t), 0.0,
                         0.045 * sin(world.z * 1.3 + t * 1.2));
        n = normalize(n + mat3(gbufferModelView) * wave);
        // Transmission is composed from the pre-translucent scene in composite.
        base.a = 1.0;
        tag = 1.0;
    }
#endif
    vec3 illumination = pow(texture2D(lightmap, lm).rgb, vec3(2.2));
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
    float hand = held * HAND_LIGHT * max(0.0, 1.0 - length(viewPos) / 12.0);
    illumination = max(illumination, vec3(1.0, 0.45, 0.12) * hand);
    // Only classified emissive blocks feed bloom; bright sky and white blocks do not.
    vec3 emissive = base.rgb * emission * 2.5;
    vec3 lit = base.rgb * max(illumination, vec3(0.005)) * shading;
    lit = max(lit, emissive);
    gl_FragData[0] = vec4(lit, base.a);
    gl_FragData[1] = vec4(n * 0.5 + 0.5, material);
    gl_FragData[2] = vec4(emissive, tag);
}
