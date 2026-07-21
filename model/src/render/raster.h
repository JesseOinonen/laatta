#ifndef RASTER_H
#define RASTER_H

#include <cstdint>
#include <vector>

#include "geometry.h"

namespace laatta {

struct RasterStats {
    uint64_t fragments_tested = 0;   // pixels covered by a triangle
    uint64_t fragments_passed = 0;   // ... that also won the depth test
    uint64_t pixels_shaded    = 0;   // same as passed here; separate once
                                     // there is a real shader core
    double overdraw() const {
        return fragments_passed ? static_cast<double>(fragments_tested) /
                                  static_cast<double>(fragments_passed)
                                : 0.0;
    }
};

// On-chip colour + depth storage for one tile. In the FPGA this is BRAM, and
// its size is the central architecture trade-off: it must hold tile_size^2
// pixels of colour and depth for the whole tile's processing time.
class TileBuffer {
public:
    TileBuffer(int tile_size, Rgba8 clear);

    void reset(Rgba8 clear);

    Rgba8& color(int lx, int ly) { return color_[static_cast<size_t>(ly) * size_ + lx]; }
    Depth& depth(int lx, int ly) { return depth_[static_cast<size_t>(ly) * size_ + lx]; }

    int size() const { return size_; }

    // Bytes of on-chip memory this configuration needs.
    static uint32_t bram_bytes(int tile_size)
    {
        return static_cast<uint32_t>(tile_size) * tile_size *
               (sizeof(Rgba8) + sizeof(Depth));
    }

private:
    int size_;
    std::vector<Rgba8> color_;
    std::vector<Depth> depth_;
};

// Rasterises one triangle into the region [x0, x1] x [y0, y1] of the target,
// in screen coordinates. Used for both the tiled and the immediate-mode paths,
// which is how the two are guaranteed to produce identical pixels.
//
// `write_pixel` is called for fragments that pass the depth test:
//     void(int screen_x, int screen_y, Rgba8 color)
// `depth_at` returns a reference to the depth value for a screen pixel.
template <typename DepthAt, typename WritePixel>
void raster_triangle(const ScreenTriangle& t,
                     int x0, int y0, int x1, int y1,
                     DepthAt depth_at, WritePixel write_pixel,
                     RasterStats& stats);

}  // namespace laatta

#include "raster_impl.h"

#endif
