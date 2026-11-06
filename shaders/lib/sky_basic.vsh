// Vanilla sky geometry supplies its own colour (including stars).
uniform mat4 gbufferModelViewInverse;
varying vec4 skyVertexColor;
varying vec3 skyViewDirection;
varying vec3 skyWorldDirection;
void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    skyViewDirection = viewPosition.xyz;
    skyWorldDirection = mat3(gbufferModelViewInverse) * viewPosition.xyz;
    skyVertexColor = gl_Color;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
