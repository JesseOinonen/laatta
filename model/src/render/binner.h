#ifndef BINNER_H
#define BINNER_H

#include <cstdint>
#include <vector>

#include "geometry.h"

namespace laatta {

struct BinStats {
    uint32_t tiles_x = 0, tiles_y = 0;
    uint32_t tile_count = 0;
    uint64_t list_entries = 0;      // total (tile, triangle) pairs
    uint32_t max_entries_per_tile = 0;
    uint32_t empty_tiles = 0;
    double   avg_entries_per_tile = 0.0;
    // How many tiles the average triangle lands in. This is the number that
    // grows as tiles get smaller, and it is what makes the parameter buffer
    // expensive.
    double   tiles_per_triangle = 0.0;
};

// Screen divided into square tiles, each holding the list of triangles whose
// bounding box overlaps it. Bounding-box binning is what most hardware does:
// exact edge testing costs more than the false positives it saves.
class TileGrid {
public:
    TileGrid(int width, int height, int tile_size);

    void bin(const std::vector<ScreenTriangle>& triangles);

    const std::vector<uint32_t>& tile_list(uint32_t tile_index) const {
        return lists_[tile_index];
    }

    int tile_size() const  { return tile_size_; }
    uint32_t tiles_x() const { return tiles_x_; }
    uint32_t tiles_y() const { return tiles_y_; }
    uint32_t tile_count() const { return tiles_x_ * tiles_y_; }

    int tile_origin_x(uint32_t idx) const {
        return static_cast<int>(idx % tiles_x_) * tile_size_;
    }
    int tile_origin_y(uint32_t idx) const {
        return static_cast<int>(idx / tiles_x_) * tile_size_;
    }

    const BinStats& stats() const { return stats_; }

private:
    int      width_, height_, tile_size_;
    uint32_t tiles_x_, tiles_y_;
    std::vector<std::vector<uint32_t>> lists_;
    BinStats stats_;
};

}  // namespace laatta

#endif
