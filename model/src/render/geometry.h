#ifndef GEOMETRY_H
#define GEOMETRY_H

#include <cstdint>

#include "math3d.h"

namespace laatta {

// Rasterisation precision. Screen coordinates are snapped to 1/16 of a pixel,
// the same trick real GPUs use: it makes edge functions exact integer
// arithmetic, so coverage is deterministic and reproducible in RTL.
constexpr int SUBPIXEL_BITS  = 4;
constexpr int SUBPIXEL_SCALE = 1 << SUBPIXEL_BITS;   // 16

// Depth is 16-bit unsigned, 0 = near plane, 65535 = far plane. Picking the
// width here is an architecture decision: it sets the tile depth buffer size.
using Depth = uint16_t;
constexpr Depth DEPTH_MAX = 0xFFFF;

struct Rgba8 {
    uint8_t r = 0, g = 0, b = 0, a = 255;
};

// A vertex after transform, clip and viewport mapping. This is what the
// parameter buffer stores in a TBDR, so its size drives the write traffic.
struct ScreenVertex {
    int32_t x = 0;      // fixed point, SUBPIXEL_BITS fractional bits
    int32_t y = 0;
    Depth   z = 0;      // window depth
    Rgba8   color;      // shaded per vertex (Gouraud)
};

// A triangle ready for binning and rasterisation.
struct ScreenTriangle {
    ScreenVertex v[3];

    // Screen-space bounding box in whole pixels, already clamped to the
    // viewport. The binner works from this.
    int32_t min_x = 0, min_y = 0, max_x = 0, max_y = 0;
};

// Byte cost of one triangle in the parameter buffer: three screen vertices as
// the hardware would store them (2x int32 position, 1x uint16 depth padded,
// 1x rgba8) plus a small header. Adjusting this changes the measured parameter
// buffer traffic, so keep it honest with what the RTL will actually write.
constexpr uint32_t PARAM_BYTES_PER_VERTEX   = 12;   // x, y, (z | rgba)
constexpr uint32_t PARAM_BYTES_PER_TRIANGLE = 3 * PARAM_BYTES_PER_VERTEX + 4;
constexpr uint32_t PARAM_BYTES_PER_LIST_ENTRY = 4;  // triangle index in a tile list

}  // namespace laatta

#endif
