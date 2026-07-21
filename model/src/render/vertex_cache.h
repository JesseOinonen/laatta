#ifndef VERTEX_CACHE_H
#define VERTEX_CACHE_H

#include <cstdint>
#include <ostream>
#include <vector>

#include "../memory/memory_map.h"

namespace laatta {

enum class CachePolicy { Fifo, Lru };

const char* policy_name(CachePolicy p);

struct VertexCacheStats {
    uint32_t entries = 0;
    CachePolicy policy = CachePolicy::Fifo;

    uint64_t lookups = 0;        // one per index in the stream
    uint64_t hits    = 0;
    uint64_t misses  = 0;        // = vertex shader invocations

    uint64_t line_fetches = 0;   // bursts actually pulled from DRAM
    uint64_t dram_bytes   = 0;   // line_fetches * burst_bytes

    double hit_rate() const {
        return lookups ? static_cast<double>(hits) / static_cast<double>(lookups) : 0.0;
    }
    // Vertex shader work relative to the ideal of one transform per vertex.
    double transform_factor(uint64_t unique_vertices) const {
        return unique_vertices ? static_cast<double>(misses) /
                                 static_cast<double>(unique_vertices) : 0.0;
    }
};

// Post-transform vertex cache, the standard fix for indexed drawing.
//
// A hit means the transformed vertex is still on chip: no DRAM fetch and no
// vertex shader invocation. A miss costs both. Real hardware uses a small FIFO
// of 16-32 entries, which is why measuring the hit rate matters more than
// intuition: it depends entirely on how the index buffer is ordered.
//
// Misses are served through a one-line buffer over the vertex buffer, so two
// vertices sharing a 64 B burst cost one fetch rather than two. That models the
// spatial locality a real fetch unit gets for free.
class VertexCache {
public:
    VertexCache(uint32_t entries, CachePolicy policy,
                uint32_t vertex_stride = sizeof(Vertex),
                uint32_t burst_bytes   = 64,
                uint32_t vb_base       = mmap::VB_BASE);

    // Returns true on a hit. On a miss the caller must transform the vertex.
    bool access(Index index);

    void reset();

    const VertexCacheStats& stats() const { return stats_; }

private:
    struct Entry {
        Index    index = 0;
        uint64_t stamp = 0;   // insertion order (FIFO) or last use (LRU)
        bool     valid = false;
    };

    void fetch_lines(Index index);

    std::vector<Entry> entries_;
    CachePolicy policy_;
    uint32_t vertex_stride_, burst_bytes_, vb_base_;
    uint64_t clock_ = 0;
    uint64_t last_line_ = UINT64_MAX;
    VertexCacheStats stats_;
};

// Reorders triangles so that consecutive ones share vertices, which is what
// makes a small post-transform cache work. Exporters emit whatever order the
// modelling tool happened to use, and that order is usually poor. This is host
// software, not hardware: it costs nothing in the GPU.
std::vector<Index> optimize_index_order(const std::vector<Index>& indices,
                                        uint32_t vertex_count,
                                        uint32_t cache_entries);

// Renumbers vertices into the order they are first used, and returns the
// permutation to apply to the vertex buffer. Reordering triangles alone helps
// the cache but scatters the fetch addresses; this puts them back in sequence,
// so both the cache and the burst locality win. The two passes belong together.
struct VertexRemap {
    std::vector<Index>    indices;      // rewritten index buffer
    std::vector<uint32_t> old_of_new;   // new vertex slot -> old vertex index
};
VertexRemap remap_vertices_by_first_use(const std::vector<Index>& indices,
                                        uint32_t vertex_count);

// Runs an index stream through a range of cache sizes and prints the table.
// This is the measurement the RTL cache size gets picked from.
void sweep_vertex_cache(const std::vector<Index>& indices,
                        uint64_t unique_vertices,
                        uint32_t burst_bytes,
                        std::ostream& os);

}  // namespace laatta

#endif
