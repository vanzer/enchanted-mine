uniform sampler2D texture;
varying vec2 skyUV;
varying vec4 skyVertexColor;
/* DRAWBUFFERS:0 */
void main() {
    gl_FragData[0] = texture2D(texture, skyUV) * skyVertexColor;
}
