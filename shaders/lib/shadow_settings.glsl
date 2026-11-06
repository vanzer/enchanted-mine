// Shadow map configuration. Kept in one place so PCF uses the actual map size.
#define SHADOWS 1 // [0 1]
#define SHADOW_STRENGTH 0.65 // [0.0 0.25 0.45 0.65 0.85 1.0]
const int shadowMapResolution = 2048; // [1024 2048 4096]
const float shadowDistance = 128.0; // [64.0 128.0 192.0]
