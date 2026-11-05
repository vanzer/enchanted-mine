#version 120
#include "/lib/settings.glsl"
#include "/lib/buffers.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int isEyeInWater;
varying vec2 uv;
#include "/lib/space.glsl"
/* DRAWBUFFERS:02 */
vec3 environment(vec3 direction, bool water) {
    vec3 worldDir = mat3(gbufferModelViewInverse) * direction;
    vec3 fog = pow(max(fogColor, vec3(0.0)), vec3(2.2));
    if (water && isEyeInWater == 1) return fog * 0.35;
    float horizon = pow(1.0 - max(worldDir.y, 0.0), 4.0);
    return mix(pow(max(skyColor, vec3(0.0)), vec3(2.2)), fog, horizon);
}
bool traceReflection(vec3 pos, vec3 n, vec3 direction, out vec2 hit, out float confidence) {
    // Trace opaque depth and colour saved before water, including the lake bed.
    vec3 origin = pos + n * 0.08;
    float previousDelta = -1.0;
    float previousTravel = 0.0;
    for (int i = 0; i < REFLECTION_STEPS; i++) {
        float f = float(i + 1) / float(REFLECTION_STEPS);
        float travel = 0.12 + f * f * min(far, 96.0);
        vec3 ray = origin + direction * travel;
        vec4 clip = gbufferProjection * vec4(ray, 1.0);
        if (clip.w <= 0.0) break;
        vec2 coord = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThanEqual(coord, vec2(0.001))) || any(greaterThanEqual(coord, vec2(0.999)))) break;
        float sceneDepth = texture2D(depthtex1, coord).r;
        float delta = positionAt(coord, sceneDepth).z - ray.z;
        if (sceneDepth < 1.0 && delta > 0.0 && previousDelta <= 0.0) {
            float lo = previousTravel, hi = travel;
            for (int j = 0; j < 6; j++) {
                float mid = (lo + hi) * 0.5;
                vec3 probe = origin + direction * mid;
                vec4 p = gbufferProjection * vec4(probe, 1.0);
                vec2 st = p.xy / p.w * 0.5 + 0.5;
                float d = texture2D(depthtex1, st).r;
                if (positionAt(st, d).z - probe.z > 0.0) hi = mid;
                else lo = mid;
            }
            vec3 probe = origin + direction * hi;
            vec4 p = gbufferProjection * vec4(probe, 1.0);
            hit = p.xy / p.w * 0.5 + 0.5;
            float d = texture2D(depthtex1, hit).r;
            float error = positionAt(hit, d).z - probe.z;
            if (d < 1.0 && error >= 0.0 && error < 0.25 + travel * 0.01
                && length((hit - uv) * vec2(viewWidth, viewHeight)) > 2.0) {
                float edge = min(min(hit.x, hit.y), min(1.0 - hit.x, 1.0 - hit.y));
                confidence = smoothstep(0.0, 0.06, edge);
                return true;
            }
        }
        previousDelta = sceneDepth < 1.0 ? delta : -1.0;
        previousTravel = travel;
    }
    confidence = 0.0;
    hit = uv;
    return false;
}
float ambientOcclusion(vec3 pos, vec3 n) {
    float obscurance = 0.0;
    vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
    float radius = clamp(viewHeight * 0.6 / max(-pos.z, 0.1), 2.0, 24.0);
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 2.399963;
        vec2 coord = uv + vec2(cos(angle), sin(angle)) * pixel * radius * (0.4 + 0.075 * float(i));
        float d = texture2D(depthtex0, coord).r;
        vec3 offset = positionAt(coord, d) - pos;
        float distanceToSample = length(offset);
        if (d < 1.0 && distanceToSample > 0.02) {
            obscurance += max(dot(n, offset / distanceToSample) - 0.12, 0.0)
                         * (1.0 - smoothstep(0.15, 1.6, distanceToSample));
        }
    }
    return 1.0 - obscurance * (AO_STRENGTH / 8.0);
}
void main() {
    vec3 color = texture2D(colortex0, uv).rgb;
    vec4 aux = texture2D(colortex2, uv);
    float depth = texture2D(depthtex0, uv).r;
    vec3 pos = positionAt(uv, depth);
    bool hand = aux.a > 0.25 && aux.a < 0.75;
    bool water = aux.a > 0.75;
    if (depth < 1.0 && !hand) {
        vec4 data = texture2D(colortex1, uv);
        vec3 n = normalize(data.rgb * 2.0 - 1.0);
        vec3 incident = normalize(pos);
        if (dot(n, -incident) < 0.0) n = -n;
        if (!water) color *= ambientOcclusion(pos, n);
        if (data.a > 0.1) {
            vec3 direction = reflect(incident, n);
            vec3 reflected = environment(direction, water);
            vec3 reflectedEmission = vec3(0.0);
            vec2 hit;
            float confidence;
            if (traceReflection(pos, n, direction, hit, confidence)) {
                reflected = mix(reflected, texture2D(colortex5, hit).rgb, confidence);
                vec4 hitAux = texture2D(colortex2, hit);
                reflectedEmission = hitAux.rgb * confidence * (1.0 - step(0.75, hitAux.a));
            }
            float cosI = clamp(dot(-incident, n), 0.0, 1.0);
            float fresnel = 0.04 + 0.96 * pow(1.0 - cosI, 5.0);
            float weight = fresnel * data.a * REFLECTION_STRENGTH;
            if (water) {
                float eta = isEyeInWater == 1 ? 1.333 : 1.0 / 1.333;
                float sinT2 = eta * eta * (1.0 - cosI * cosI);
                bool tir = sinT2 >= 1.0;
                float cosT = sqrt(max(1.0 - sinT2, 0.0));
                float rs = (eta * cosI - cosT) / max(eta * cosI + cosT, 0.0001);
                float rp = (cosI - eta * cosT) / max(cosI + eta * cosT, 0.0001);
                fresnel = tir ? 1.0 : 0.5 * (rs * rs + rp * rp);
                weight = tir ? 1.0 : fresnel * REFLECTION_STRENGTH;
                float opaqueDepth = texture2D(depthtex1, uv).r;
                float thickness = opaqueDepth < 1.0 ? length(positionAt(uv, opaqueDepth) - pos) : 32.0;
                if (isEyeInWater == 1) thickness = 0.0;
                vec3 transmission = exp(-vec3(0.16, 0.055, 0.025) * min(thickness, 64.0));
                vec3 waterTint = pow(max(fogColor, vec3(0.02)), vec3(2.2));
                if (isEyeInWater != 1) waterTint = max(color, vec3(0.015, 0.06, 0.08));
                color = texture2D(colortex5, uv).rgb * transmission + waterTint * (1.0 - transmission) * 0.3;
            }
            color = mix(color, reflected, clamp(weight, 0.0, 1.0));
            aux.rgb = mix(aux.rgb, reflectedEmission, clamp(weight, 0.0, 1.0));
        }
    }
    if (!hand) {
        vec3 fog = pow(max(fogColor, vec3(0.0)), vec3(2.2));
        float fogAmount = 0.0;
        if (isEyeInWater == 1) fogAmount = 1.0 - exp(-length(pos) * 0.055);
        else if (isEyeInWater == 2) fogAmount = 1.0 - exp(-length(pos) * 2.0);
        else if (isEyeInWater == 3) fogAmount = 1.0 - exp(-length(pos) * 0.3);
        else if (depth < 1.0) {
            vec3 relativeWorld = mat3(gbufferModelViewInverse) * pos;
            float distanceXZ = length(relativeWorld.xz);
            fogAmount = smoothstep(max(far - 16.0, 0.0), max(far, 1.0), distanceXZ);
        }
        color = mix(color, fog, fogAmount);
        aux.rgb *= 1.0 - fogAmount;
    }
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = aux;
}
