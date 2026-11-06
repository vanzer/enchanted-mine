#version 120
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;
varying vec4 skyVertexColor;
varying vec3 skyViewDirection;
varying vec3 skyWorldDirection;
/* DRAWBUFFERS:0 */
void main() {
    vec3 viewDir = normalize(skyViewDirection);
    vec3 worldDir = normalize(skyWorldDirection);
    vec3 sunDir = normalize(sunPosition);
    float sunHeight = (mat3(gbufferModelViewInverse) * sunDir).y;
    float sunVisible = smoothstep(-0.08, 0.12, sunHeight) * (1.0 - rainStrength);
    float horizon = pow(1.0 - clamp(abs(worldDir.y), 0.0, 1.0), 4.0);
    float skyBrightness = clamp(max(max(skyVertexColor.r, skyVertexColor.g), skyVertexColor.b) * 4.0, 0.0, 1.0);
    // Keep the vanilla black lower sky and stars; the gradient follows the current biome fog.
    vec3 color = mix(skyVertexColor.rgb, fogColor, horizon * 0.22 * skyBrightness);
    float glow = pow(max(dot(viewDir, sunDir), 0.0), 64.0) * sunVisible * skyBrightness;
    color += vec3(0.22, 0.13, 0.06) * glow;
    gl_FragData[0] = vec4(color, skyVertexColor.a);
}
