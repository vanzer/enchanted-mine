#ifndef ENCHANTED_SHADOW_SETTINGS
#define ENCHANTED_SHADOW_SETTINGS
#define SHADOWS 1 // [0 1]
#define SHADOW_STRENGTH 0.65 // [0.0 0.25 0.45 0.65 0.85 1.0]
#define SHADOW_SOFTNESS 1.8 // [0.5 1.0 1.8 2.5 4.0]
#define SHADOW_FILTER 2 // [0 1 2]
const int shadowMapResolution = 2048; // [1024 2048 4096]
const float shadowDistance = 128.0; // [64.0 128.0 192.0 256.0]
const bool shadowtex0Nearest = true;
#endif
