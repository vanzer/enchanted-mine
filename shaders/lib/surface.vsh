#include "/lib/settings.glsl"
#include "/lib/temporal.glsl"
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
#include "/lib/wind.glsl"
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
varying float blockType;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
void main() {
    vec4 v = gl_ModelViewMatrix * gl_Vertex;
    blockType = 0.0;
#if defined(TERRAIN) || defined(WATER)
    blockType = mc_Entity.x;
    vec3 relativeWorld = (gbufferModelViewInverse * v).xyz;
    relativeWorld += enchantedWind(relativeWorld, cameraPosition, blockType, frameTimeCounter, step(gl_MultiTexCoord0.t, mc_midTexCoord.t));
    v = gbufferModelView * vec4(relativeWorld, 1.0);
#endif
    viewPos = v.xyz;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;
    material = 0.0;
    if (abs(blockType - 10001.0) < 0.5) material = 0.9;
    if (abs(blockType - 10002.0) < 0.5) material = 0.65;
    if (abs(blockType - 10000.0) < 0.5) material = 0.95;
    gl_Position = gl_ProjectionMatrix * v;
#ifndef HAND
    gl_Position.xy += enchantedJitter(frameCounter) * 2.0 / max(vec2(viewWidth, viewHeight), vec2(1.0)) * gl_Position.w;
#endif
}
