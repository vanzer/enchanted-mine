#ifndef ENCHANTED_FORMATS
#define ENCHANTED_FORMATS
// Keep the symbolic token in *Format directives for Iris's directive parser.
// A preprocessor macro would replace it before Iris reads the format name.
// GLSL still needs a constant declaration because this is not a built-in enum.
#ifndef RGBA16F
const int RGBA16F = 34842;
#endif
#endif
