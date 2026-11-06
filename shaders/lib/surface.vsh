varying vec2 uv;
varying vec2 lm;
varying vec4 tint;
varying vec3 viewPos;
varying vec3 normal;
varying float material;
attribute vec4 mc_Entity;
void main() {
    vec4 v = gl_ModelViewMatrix * gl_Vertex;
    viewPos = v.xyz;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lm = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;
    material = 0.0;
#ifdef TERRAIN
    if (mc_Entity.x == 10001.0) material = 1.0;
    if (mc_Entity.x == 10002.0) material = 0.65;
#endif
#ifdef WATER
    if (mc_Entity.x == 10000.0) material = 0.95;
#endif
    gl_Position = gl_ProjectionMatrix * v;
}
