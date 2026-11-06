#include "/lib/shadow_settings.glsl"
attribute vec4 mc_Entity;
varying vec2 shadowUV;
varying vec4 shadowTint;
varying float shadowMaterial;
void main() {
    shadowUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    shadowTint = gl_Color;
    shadowMaterial = mc_Entity.x;
    gl_Position = ftransform();
}
