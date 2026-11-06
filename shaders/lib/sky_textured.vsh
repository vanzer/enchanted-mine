varying vec2 skyUV;
varying vec4 skyVertexColor;
void main() {
    skyUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    skyVertexColor = gl_Color;
    gl_Position = ftransform();
}
