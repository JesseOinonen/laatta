// Tile-size design-space sweep. Produces the table the RTL tile size gets
// chosen from: on-chip BRAM against DRAM traffic.
//
//   ./output/sweep [scene.obj] [width] [height]   > output/sweep.csv

#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#include "../render/renderer.h"
#include "../render/vertex_cache.h"
#include "obj_loader.h"

using namespace laatta;

int main(int argc, char* argv[])
{
    const std::string obj_path = (argc > 1) ? argv[1] : "testdata/nokia_mouse.obj";

    RenderConfig base;
    if (argc > 2) base.width  = std::atoi(argv[2]);
    if (argc > 3) base.height = std::atoi(argv[3]);

    Mesh mesh;
    try {
        mesh = load_obj(obj_path);
    } catch (const std::exception& e) {
        std::cerr << "load failed: " << e.what() << "\n";
        return 1;
    }

    const std::vector<int> tile_sizes = { 8, 16, 32, 64, 128 };

    std::ofstream csv("output/sweep.csv");
    csv << "tile_size,tiles,bram_bytes,list_entries,tiles_per_triangle,"
           "param_write,param_read,color_write,geometry_read,total_dram,"
           "fragments_tested,overdraw\n";

    std::cout << "=== tile size sweep: " << obj_path << " at "
              << base.width << "x" << base.height << " ===\n\n";

    std::cout << std::left << std::setw(7) << "tile"
              << std::right << std::setw(8)  << "tiles"
              << std::setw(11) << "BRAM B"
              << std::setw(11) << "entries"
              << std::setw(9)  << "t/tri"
              << std::setw(12) << "param wr"
              << std::setw(12) << "param rd"
              << std::setw(12) << "color wr"
              << std::setw(13) << "TOTAL DRAM" << "\n";

    const RenderResult imr = render_imr(mesh, base);

    for (int ts : tile_sizes) {
        RenderConfig cfg = base;
        cfg.tile_size = ts;

        const RenderResult r = render_tbdr(mesh, cfg);

        std::cout << std::left << std::setw(7) << ts
                  << std::right << std::setw(8)  << r.bin.tile_count
                  << std::setw(11) << r.tile_bram_bytes
                  << std::setw(11) << r.bin.list_entries
                  << std::setw(9)  << std::fixed << std::setprecision(2)
                  << r.bin.tiles_per_triangle
                  << std::setw(12) << r.traffic.param_write
                  << std::setw(12) << r.traffic.param_read
                  << std::setw(12) << r.traffic.color_write
                  << std::setw(13) << r.traffic.total_moved << "\n";
        std::cout.unsetf(std::ios::fixed);

        csv << ts << "," << r.bin.tile_count << "," << r.tile_bram_bytes << ","
            << r.bin.list_entries << "," << r.bin.tiles_per_triangle << ","
            << r.traffic.param_write << "," << r.traffic.param_read << ","
            << r.traffic.color_write << "," << r.traffic.geometry_read << ","
            << r.traffic.total_moved << "," << r.raster.fragments_tested << ","
            << r.raster.overdraw() << "\n";
    }

    std::cout << "\nimmediate mode, for reference: "
              << imr.traffic.total_moved << " B DRAM, no tile BRAM\n\n";

    // The vertex cache is sized from its own measurement, not from the tile
    // sweep: it depends on the index order, not on the screen.
    sweep_vertex_cache(mesh.indices, mesh.vertices.size(), base.burst_bytes,
                       std::cout);

    // Same measurement after reordering the triangles for locality. If this
    // beats a much larger cache, the answer is host software, not hardware.
    const std::vector<Index> reordered =
        optimize_index_order(mesh.indices,
                             static_cast<uint32_t>(mesh.vertices.size()), 32);
    std::cout << "\nafter triangle reordering only:\n";
    sweep_vertex_cache(reordered, mesh.vertices.size(), base.burst_bytes,
                       std::cout);

    const VertexRemap remapped =
        remap_vertices_by_first_use(reordered,
                                    static_cast<uint32_t>(mesh.vertices.size()));
    std::cout << "\nafter reordering + vertex renumbering (both host side):\n";
    sweep_vertex_cache(remapped.indices, remapped.old_of_new.size(),
                       base.burst_bytes, std::cout);

    std::ofstream vcsv("output/vertex_cache.csv");
    vcsv << "entries,policy,hit_rate,dram_bytes,transforms\n";
    for (uint32_t n : { 0u, 8u, 16u, 24u, 32u, 48u, 64u, 128u, 256u }) {
        for (CachePolicy p : { CachePolicy::Fifo, CachePolicy::Lru }) {
            VertexCache c(n, p, sizeof(Vertex), base.burst_bytes);
            for (Index i : mesh.indices) c.access(i);
            vcsv << n << "," << policy_name(p) << "," << c.stats().hit_rate() << ","
                 << c.stats().dram_bytes << "," << c.stats().misses << "\n";
        }
    }

    std::cout << "\nwrote output/sweep.csv, output/vertex_cache.csv\n";
    return 0;
}
