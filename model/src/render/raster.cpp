#include "raster.h"

namespace laatta {

TileBuffer::TileBuffer(int tile_size, Rgba8 clear)
    : size_(tile_size),
      color_(static_cast<size_t>(tile_size) * tile_size, clear),
      depth_(static_cast<size_t>(tile_size) * tile_size, DEPTH_MAX)
{
}

void TileBuffer::reset(Rgba8 clear)
{
    std::fill(color_.begin(), color_.end(), clear);
    std::fill(depth_.begin(), depth_.end(), DEPTH_MAX);
}

}  // namespace laatta
