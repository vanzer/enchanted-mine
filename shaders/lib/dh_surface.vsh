#include "/lib/settings.glsl"
#include "/lib/temporal.glsl"

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
varying vec2 dhLightmap;
varying vec4 dhTint;
varying vec3 dhViewPosition;
varying vec3 dhNormal;
varying float dhReflectivity;
varying float dhWater;
varying float dhEmission;
varying float dhLeaves;

void main() {
    // Iris remaps these built-ins to the DH model-view and projection matrices.
    // DH has vertex colors and lightmap UVs, but no terrain-atlas UVs or mc_Entity.
    vec4 position = gl_ModelViewMatrix * gl_Vertex;
    dhViewPosition = position.xyz;
    dhNormal = normalize(gl_NormalMatrix * gl_Normal);
    dhLightmap = gl_MultiTexCoord2.xy;
    dhTint = gl_Color;
    dhReflectivity = 0.04;
    dhWater = 0.0;
    dhEmission = 0.0;
    dhLeaves = 0.0;

#if defined(DISTANT_HORIZONS) && DH_SUPPORT == 1
    // dhMaterialId is injected by Iris. Do not declare it as an attribute here.
#ifdef DH_BLOCK_METAL
    if (dhMaterialId == DH_BLOCK_METAL) dhReflectivity = 0.82;
#endif
#ifdef DH_BLOCK_WATER
    if (dhMaterialId == DH_BLOCK_WATER) {
        dhWater = 1.0;
        dhReflectivity = 0.95;
    }
#endif
#ifdef DH_BLOCK_LAVA
    if (dhMaterialId == DH_BLOCK_LAVA) dhEmission = 1.0;
#endif
#ifdef DH_BLOCK_ILLUMINATED
    if (dhMaterialId == DH_BLOCK_ILLUMINATED) dhEmission = 1.0;
#endif
#ifdef DH_BLOCK_LEAVES
    if (dhMaterialId == DH_BLOCK_LEAVES) dhLeaves = 1.0;
#endif
#endif
    gl_Position = gl_ProjectionMatrix * position;
    gl_Position.xy += enchantedJitter(frameCounter) * 2.0
                      / max(vec2(viewWidth, viewHeight), vec2(1.0)) * gl_Position.w;
}
