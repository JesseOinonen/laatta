#include "binner.h"

#include <algorithm>
#include <stdexcept>

namespace laatta {

TileGrid::TileGrid(int width, int height, int tile_size)
    : width_(width), height_(height), tile_size_(tile_size)
{
    if (tile_size <= 0) throw std::invalid_argument("TileGrid: bad tile size");

    // Partial tiles at the right and bottom edges are normal; the rasteriser
    // clips against the framebuffer, not against the tile.
    tiles_x_ = static_cast<uint32_t>((width  + tile_size - 1) / tile_size);
    tiles_y_ = static_cast<uint32_t>((height + tile_size - 1) / tile_size);
    lists_.resize(static_cast<size_t>(tiles_x_) * tiles_y_);
}

void TileGrid::bin(const std::vector<ScreenTriangle>& triangles)
{
    for (auto& l : lists_) l.clear();

    for (uint32_t t = 0; t < triangles.size(); ++t) {
        const ScreenTriangle& tri = triangles[t];

        const uint32_t tx0 = static_cast<uint32_t>(tri.min_x / tile_size_);
        const uint32_t tx1 = static_cast<uint32_t>(tri.max_x / tile_size_);
        const uint32_t ty0 = static_cast<uint32_t>(tri.min_y / tile_size_);
        const uint32_t ty1 = static_cast<uint32_t>(tri.max_y / tile_size_);

        for (uint32_t ty = ty0; ty <= ty1 && ty < tiles_y_; ++ty) {
            for (uint32_t tx = tx0; tx <= tx1 && tx < tiles_x_; ++tx) {
                lists_[static_cast<size_t>(ty) * tiles_x_ + tx].push_back(t);
            }
        }
    }

    stats_ = BinStats{};
    stats_.tiles_x    = tiles_x_;
    stats_.tiles_y    = tiles_y_;
    stats_.tile_count = tile_count();

    for (const auto& l : lists_) {
        stats_.list_entries += l.size();
        stats_.max_entries_per_tile =
            std::max(stats_.max_entries_per_tile, static_cast<uint32_t>(l.size()));
        if (l.empty()) stats_.empty_tiles++;
    }

    if (stats_.tile_count) {
        stats_.avg_entries_per_tile =
            static_cast<double>(stats_.list_entries) / stats_.tile_count;
    }
    if (!triangles.empty()) {
        stats_.tiles_per_triangle =
            static_cast<double>(stats_.list_entries) / triangles.size();
    }
}

}  // namespace laatta
