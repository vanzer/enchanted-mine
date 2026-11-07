#include "/lib/shadow_settings.glsl"
#include "/lib/wind.glsl"
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
varying vec2 shadowUV;
varying vec4 shadowTint;
varying float shadowMaterial;
void main() {
    shadowUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    shadowTint = gl_Color;
    shadowMaterial = mc_Entity.x;
    vec4 v = gl_ModelViewMatrix * gl_Vertex;
    vec3 relativeWorld = (shadowModelViewInverse * v).xyz;
    relativeWorld += enchantedWind(relativeWorld, cameraPosition, shadowMaterial, frameTimeCounter, step(gl_MultiTexCoord0.t, mc_midTexCoord.t));
    gl_Position = shadowProjection * shadowModelView * vec4(relativeWorld, 1.0);
}
