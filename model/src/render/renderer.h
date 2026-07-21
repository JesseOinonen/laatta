#ifndef RENDERER_H
#define RENDERER_H

#include <cstdint>
#include <memory>
#include <ostream>

#include "../memory/dram_model.h"
#include "../tools/obj_loader.h"
#include "binner.h"
#include "framebuffer.h"
#include "raster.h"
#include "transform.h"
#include "vertex_cache.h"

namespace laatta {

struct RenderConfig {
    int   width       = 640;
    int   height      = 480;
    int   tile_size   = 16;
    float yaw_deg     = 35.0f;
    float pitch_deg   = -20.0f;
    bool  cull_backface = true;
    uint32_t burst_bytes = 64;
    Rgba8 clear = { 24, 26, 32, 255 };

    // Post-transform vertex cache. 0 disables it entirely, which is the
    // worst case worth knowing. 32 FIFO entries is typical hardware.
    uint32_t    vertex_cache_entries = 32;
    CachePolicy vertex_cache_policy  = CachePolicy::Fifo;
};

struct TrafficBreakdown {
    uint64_t geometry_read   = 0;   // vertex + index buffers
    uint64_t param_write     = 0;   // binner output
    uint64_t param_read      = 0;   // tile scheduler re-reading it
    uint64_t color_write     = 0;
    uint64_t color_read      = 0;   // immediate mode only
    uint64_t depth_traffic   = 0;   // immediate mode only
    uint64_t total_moved     = 0;   // burst-rounded

    // Bounds either side of the measured figure, so the effect of the cache
    // is never hidden inside a single number.
    uint64_t vertex_fetch_uncached = 0;   // no cache at all
    uint64_t vertex_fetch_ideal    = 0;   // every vertex fetched exactly once
};

struct RenderResult {
    std::unique_ptr<Framebuffer> fb;
    GeometryStats geom;
    BinStats      bin;
    RasterStats   raster;
    VertexCacheStats vcache;
    TrafficBreakdown traffic;

    // On-chip cost of the chosen tile size.
    uint32_t tile_bram_bytes = 0;

    void report(std::ostream& os, const char* title) const;
};

// Tile-based deferred path: transform everything, bin it, then render tile by
// tile with colour and depth kept on chip. Depth never reaches DRAM.
RenderResult render_tbdr(const Mesh& mesh, const RenderConfig& cfg);

// Immediate-mode path for comparison: same rasteriser, same pixels, but every
// fragment hits the DRAM depth and colour buffers. Exists to quantify what
// tiling actually saves.
RenderResult render_imr(const Mesh& mesh, const RenderConfig& cfg);

}  // namespace laatta

#endif
