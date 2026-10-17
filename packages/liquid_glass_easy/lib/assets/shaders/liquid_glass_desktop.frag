// Desktop GLES/Skia entry: builds the LIQUID_GLASS_DESKTOP code,
// which ANGLE's D3D compiler on Windows handles in seconds instead of minutes.
#if defined(IMPELLER_TARGET_OPENGLES) || defined(SKIA_GRAPHICS_BACKEND)
#define LIQUID_GLASS_DESKTOP
#endif
#include "liquid_glass.frag"
