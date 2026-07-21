#include "renderer.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <unordered_set>

namespace laatta {
namespace {

constexpr float DEG2RAD = 3.14159265f / 180.0f;

// Per-tile list header in the parameter buffer: entry count plus a link to the
// next block, which is how real binners handle unbounded lists.
constexpr uint32_t TILE_HEADER_BYTES = 8;

// Rounds a byte count up to whole bursts, the granularity DRAM moves.
uint64_t to_bursts(uint64_t bytes, uint32_t burst)
{
    return (bytes + burst - 1) / burst;
}

// Geometry fetch, shared by both paths. The index buffer is streamed
// sequentially; vertices go through the post-transform cache, so the traffic
// is whatever the cache actually misses on rather than an assumption about it.
void account_geometry(const Mesh& mesh, const RenderConfig& cfg,
                      DramModel& dram, TrafficBreakdown& out,
                      VertexCacheStats& vstats)
{
    const uint64_t ib_bytes = mesh.indices.size() * sizeof(Index);
    dram.account_read(mmap::IB_BASE, ib_bytes, Client::IndexFetch);

    VertexCache cache(cfg.vertex_cache_entries, cfg.vertex_cache_policy,
                      sizeof(Vertex), cfg.burst_bytes, mmap::VB_BASE);
    for (Index i : mesh.indices) cache.access(i);
    vstats = cache.stats();

    dram.account_read(mmap::VB_BASE, vstats.dram_bytes, Client::VertexFetch);

    out.geometry_read = to_bursts(ib_bytes, cfg.burst_bytes) * cfg.burst_bytes +
                        vstats.dram_bytes;

    // Bounds on either side of the measured number.
    out.vertex_fetch_uncached =
        mesh.indices.size() * static_cast<uint64_t>(cfg.burst_bytes);
    out.vertex_fetch_ideal =
        to_bursts(mesh.vertices.size() * sizeof(Vertex), cfg.burst_bytes) *
        cfg.burst_bytes;
}

}  // namespace

void RenderResult::report(std::ostream& os, const char* title) const
{
    const double mib = 1024.0 * 1024.0;

    os << title << "\n";
    os << "  geometry      : " << geom.input_triangles << " in -> "
       << geom.output_triangles << " rasterised"
       << " (backface " << geom.culled_backface
       << ", offscreen " << geom.culled_offscreen
       << ", near-clipped " << geom.clipped_near
       << ", degenerate " << geom.degenerate << ")\n";

    if (bin.tile_count) {
        os << "  tiles         : " << bin.tiles_x << " x " << bin.tiles_y
           << " = " << bin.tile_count
           << ", " << bin.empty_tiles << " empty\n";
        os << std::fixed << std::setprecision(2);
        os << "  binning       : " << bin.list_entries << " list entries, "
           << bin.tiles_per_triangle << " tiles/triangle, "
           << bin.avg_entries_per_tile << " avg/tile, "
           << bin.max_entries_per_tile << " max\n";
        os << "  tile BRAM     : " << tile_bram_bytes << " B on chip\n";
        os.unsetf(std::ios::fixed);
    }

    os << std::fixed << std::setprecision(2);
    os << "  fragments     : " << raster.fragments_tested << " tested, "
       << raster.fragments_passed << " passed, overdraw "
       << raster.overdraw() << "x\n";

    if (vcache.lookups) {
        os << std::fixed << std::setprecision(1);
        os << "  vertex cache  : " << vcache.entries << " entries "
           << policy_name(vcache.policy) << ", "
           << vcache.hit_rate() * 100.0 << " % hit, "
           << vcache.misses << " transforms\n";
        os.unsetf(std::ios::fixed);
    }

    os << "  DRAM traffic  :\n"
       << "      geometry  " << std::setw(10) << traffic.geometry_read << " B\n";
    if (traffic.param_write || traffic.param_read) {
        os << "      param wr  " << std::setw(10) << traffic.param_write << " B\n"
           << "      param rd  " << std::setw(10) << traffic.param_read  << " B\n";
    }
    if (traffic.depth_traffic) {
        os << "      depth     " << std::setw(10) << traffic.depth_traffic << " B\n";
    }
    if (traffic.color_read) {
        os << "      color rd  " << std::setw(10) << traffic.color_read << " B\n";
    }
    os << "      color wr  " << std::setw(10) << traffic.color_write << " B\n"
       << "      TOTAL     " << std::setw(10) << traffic.total_moved << " B  ("
       << traffic.total_moved / mib << " MiB)\n";
    os.unsetf(std::ios::fixed);
}

RenderResult render_tbdr(const Mesh& mesh, const RenderConfig& cfg)
{
    RenderResult r;
    r.fb = std::make_unique<Framebuffer>(cfg.width, cfg.height, cfg.clear);

    // Accounting-only memory: no storage, just the burst arithmetic and the
    // per-client breakdown.
    DramModel dram(0, cfg.burst_bytes);
    account_geometry(mesh, cfg, dram, r.traffic, r.vcache);

    const ViewSetup view = make_view(mesh.bbox_min, mesh.bbox_max,
                                     cfg.width, cfg.height,
                                     cfg.yaw_deg * DEG2RAD,
                                     cfg.pitch_deg * DEG2RAD);

    const std::vector<ScreenTriangle> tris =
        transform_triangles(mesh.vertices.data(),
                            static_cast<uint32_t>(mesh.vertices.size()),
                            mesh.indices.data(),
                            static_cast<uint32_t>(mesh.indices.size()),
                            view, cfg.width, cfg.height,
                            cfg.cull_backface, r.geom);

    TileGrid grid(cfg.width, cfg.height, cfg.tile_size);
    grid.bin(tris);
    r.bin = grid.stats();
    r.tile_bram_bytes = TileBuffer::bram_bytes(cfg.tile_size);

    // Parameter buffer: transformed triangles written once, tile lists written
    // once. This is the price of tiling, paid in DRAM before any pixel exists.
    const uint64_t param_tri_bytes  = static_cast<uint64_t>(tris.size()) *
                                      PARAM_BYTES_PER_TRIANGLE;
    const uint64_t param_list_bytes = r.bin.list_entries * PARAM_BYTES_PER_LIST_ENTRY +
                                      static_cast<uint64_t>(r.bin.tile_count) *
                                      TILE_HEADER_BYTES;

    dram.account_write(mmap::PARAM_BASE, param_tri_bytes + param_list_bytes,
                       Client::ParamWrite);
    r.traffic.param_write =
        to_bursts(param_tri_bytes + param_list_bytes, cfg.burst_bytes) * cfg.burst_bytes;

    TileBuffer tile(cfg.tile_size, cfg.clear);
    uint64_t param_read_bytes = 0;

    for (uint32_t ti = 0; ti < grid.tile_count(); ++ti) {
        const std::vector<uint32_t>& list = grid.tile_list(ti);

        const int ox = grid.tile_origin_x(ti);
        const int oy = grid.tile_origin_y(ti);
        const int x1 = std::min(ox + cfg.tile_size - 1, cfg.width  - 1);
        const int y1 = std::min(oy + cfg.tile_size - 1, cfg.height - 1);

        // Reading the tile's list, and every triangle record it points at.
        // A triangle touching N tiles gets read N times: that re-read is the
        // fundamental cost of tiling, and it grows as tiles shrink.
        param_read_bytes += TILE_HEADER_BYTES +
                            list.size() * PARAM_BYTES_PER_LIST_ENTRY +
                            list.size() * PARAM_BYTES_PER_TRIANGLE;

        tile.reset(cfg.clear);

        auto depth_at = [&](int px, int py) -> Depth& {
            return tile.depth(px - ox, py - oy);
        };
        auto write_pixel = [&](int px, int py, Rgba8 c) {
            tile.color(px - ox, py - oy) = c;
        };

        for (uint32_t idx : list) {
            raster_triangle(tris[idx], ox, oy, x1, y1,
                            depth_at, write_pixel, r.raster);
        }

        // Flush: colour goes out once, in one clean burst-aligned block per
        // tile row. Depth stays on chip and never reaches DRAM at all — that
        // is the whole point of the architecture.
        for (int py = oy; py <= y1; ++py) {
            const int row_pixels = x1 - ox + 1;
            const uint32_t addr = mmap::FB_BASE +
                static_cast<uint32_t>((py * cfg.width + ox) * sizeof(Rgba8));
            dram.account_write(addr, row_pixels * sizeof(Rgba8), Client::ColorWrite);

            for (int px = ox; px <= x1; ++px) {
                r.fb->at(px, py) = tile.color(px - ox, py - oy);
            }
        }
    }

    dram.account_read(mmap::PARAM_BASE, param_read_bytes, Client::ParamRead);
    r.traffic.param_read = to_bursts(param_read_bytes, cfg.burst_bytes) * cfg.burst_bytes;

    const MemStats& cw = dram.stats(Client::ColorWrite);
    r.traffic.color_write = cw.write_bursts * cfg.burst_bytes;
    r.traffic.depth_traffic = 0;

    r.traffic.total_moved = r.traffic.geometry_read + r.traffic.param_write +
                            r.traffic.param_read + r.traffic.color_write;
    return r;
}

RenderResult render_imr(const Mesh& mesh, const RenderConfig& cfg)
{
    RenderResult r;
    r.fb = std::make_unique<Framebuffer>(cfg.width, cfg.height, cfg.clear);

    DramModel dram(0, cfg.burst_bytes);
    account_geometry(mesh, cfg, dram, r.traffic, r.vcache);

    const ViewSetup view = make_view(mesh.bbox_min, mesh.bbox_max,
                                     cfg.width, cfg.height,
                                     cfg.yaw_deg * DEG2RAD,
                                     cfg.pitch_deg * DEG2RAD);

    const std::vector<ScreenTriangle> tris =
        transform_triangles(mesh.vertices.data(),
                            static_cast<uint32_t>(mesh.vertices.size()),
                            mesh.indices.data(),
                            static_cast<uint32_t>(mesh.indices.size()),
                            view, cfg.width, cfg.height,
                            cfg.cull_backface, r.geom);

    // Full-screen depth buffer, which in immediate mode lives in DRAM.
    std::vector<Depth> depth(static_cast<size_t>(cfg.width) * cfg.height, DEPTH_MAX);

    // Cache lines touched, counted per triangle. Assuming reuse within a
    // triangle but none across triangles is generous to immediate mode: it
    // models a cache big enough for one triangle's footprint.
    std::unordered_set<uint64_t> depth_lines, color_lines;
    uint64_t depth_read_lines = 0, depth_write_lines = 0, color_write_lines = 0;

    const uint32_t burst = cfg.burst_bytes;

    for (const ScreenTriangle& t : tris) {
        depth_lines.clear();
        color_lines.clear();

        auto depth_at = [&](int px, int py) -> Depth& {
            const uint64_t byte = static_cast<uint64_t>(py) * cfg.width * sizeof(Depth) +
                                  static_cast<uint64_t>(px) * sizeof(Depth);
            depth_lines.insert(byte / burst);
            return depth[static_cast<size_t>(py) * cfg.width + px];
        };
        auto write_pixel = [&](int px, int py, Rgba8 c) {
            const uint64_t byte = static_cast<uint64_t>(py) * cfg.width * sizeof(Rgba8) +
                                  static_cast<uint64_t>(px) * sizeof(Rgba8);
            color_lines.insert(byte / burst);
            r.fb->at(px, py) = c;
        };

        raster_triangle(t, 0, 0, cfg.width - 1, cfg.height - 1,
                        depth_at, write_pixel, r.raster);

        // Every depth line touched is read, and written back if anything in it
        // passed. Colour lines are written for the fragments that survived.
        depth_read_lines  += depth_lines.size();
        depth_write_lines += depth_lines.size();
        color_write_lines += color_lines.size();
    }

    // The framebuffer still has to be cleared at the start of the frame.
    const uint64_t clear_bytes = static_cast<uint64_t>(cfg.width) * cfg.height *
                                 (sizeof(Rgba8) + sizeof(Depth));

    r.traffic.depth_traffic = (depth_read_lines + depth_write_lines) * burst;
    r.traffic.color_write   = color_write_lines * burst +
                              to_bursts(clear_bytes, burst) * burst;
    r.traffic.param_write   = 0;
    r.traffic.param_read    = 0;

    r.traffic.total_moved = r.traffic.geometry_read + r.traffic.depth_traffic +
                            r.traffic.color_write;

    r.bin = BinStats{};
    r.tile_bram_bytes = 0;
    return r;
}

}  // namespace laatta
