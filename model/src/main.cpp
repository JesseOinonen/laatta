// Golden model: renders a scene through the tile-based path and the
// immediate-mode path, checks that both produce identical pixels, and reports
// what each one costs in DRAM traffic.
//
//   ./output/laatta [scene.obj] [width] [height] [tile_size]

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>

#include "memory/dram_model.h"
#include "render/renderer.h"
#include "tools/obj_loader.h"

using namespace laatta;

int main(int argc, char* argv[])
{
    const std::string obj_path = (argc > 1) ? argv[1] : "testdata/nokia_mouse.obj";

    RenderConfig cfg;
    if (argc > 2) cfg.width     = std::atoi(argv[2]);
    if (argc > 3) cfg.height    = std::atoi(argv[3]);
    if (argc > 4) cfg.tile_size = std::atoi(argv[4]);
    if (argc > 5) cfg.cull_backface = std::atoi(argv[5]) != 0;

    Mesh mesh;
    try {
        mesh = load_obj(obj_path);
    } catch (const std::exception& e) {
        std::cerr << "load failed: " << e.what() << "\n";
        return 1;
    }

    std::cout << "=== laatta golden model ===\n";
    mesh.report(std::cout);
    std::cout << "  render        : " << cfg.width << " x " << cfg.height
              << ", " << cfg.tile_size << " x " << cfg.tile_size << " tiles\n\n";

    // Place the scene in DRAM and dump the buffers the RTL testbench will need.
    DramModel dram;
    upload_mesh(dram, mesh);
    if (!verify_mesh_in_dram(dram, mesh, std::cout)) {
        std::cerr << "scene did not survive the DRAM round trip\n";
        return 1;
    }
    const DrawDescriptor d = dram.backdoor_peek<DrawDescriptor>(mmap::CMD_BASE);
    dram.dump("output/vertex_buffer.bin", d.vb_base, d.vertex_count * sizeof(Vertex));
    dram.dump("output/index_buffer.bin",  d.ib_base, d.index_count  * sizeof(Index));

    const RenderResult tbdr = render_tbdr(mesh, cfg);
    const RenderResult imr  = render_imr(mesh, cfg);

    tbdr.report(std::cout, "tile-based deferred");
    std::cout << "\n";
    imr.report(std::cout, "immediate mode (reference for comparison)");
    std::cout << "\n";

    tbdr.fb->write_png("output/render_tbdr.png");
    imr.fb->write_png("output/render_imr.png");

    // The two paths share one rasteriser, so any pixel difference means the
    // tiling logic itself is broken. This is the model's own regression test.
    const size_t diff = tbdr.fb->compare(*imr.fb, "output/render_diff.png");
    const size_t pixels = static_cast<size_t>(cfg.width) * cfg.height;

    std::cout << "pixel comparison: " << diff << " of " << pixels
              << " pixels differ";
    if (diff == 0) std::cout << "  <- tiling is transparent, as it must be";
    std::cout << "\n\n";

    const double saving = imr.traffic.total_moved
        ? 100.0 * (1.0 - static_cast<double>(tbdr.traffic.total_moved) /
                         static_cast<double>(imr.traffic.total_moved))
        : 0.0;

    std::cout << std::fixed << std::setprecision(1);
    std::cout << "DRAM traffic  TBDR " << tbdr.traffic.total_moved << " B"
              << "  vs  IMR " << imr.traffic.total_moved << " B"
              << "   (" << saving << " % less)\n";
    std::cout << "on-chip cost  " << tbdr.tile_bram_bytes
              << " B of BRAM for a " << cfg.tile_size << "x" << cfg.tile_size
              << " tile\n";
    std::cout << "vertex cache  indexed fetch without one would cost "
              << tbdr.traffic.vertex_fetch_uncached << " B instead of "
              << tbdr.traffic.geometry_read << " B\n\n";

    std::cout << "wrote output/render_tbdr.png, output/render_imr.png, "
                 "output/render_diff.png\n"
              << "      output/vertex_buffer.bin, output/index_buffer.bin\n";

    return diff == 0 ? 0 : 1;
}
