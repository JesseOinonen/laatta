#include "vertex_cache.h"

#include <algorithm>
#include <iomanip>
#include <limits>
#include <stdexcept>

namespace laatta {

const char* policy_name(CachePolicy p)
{
    return (p == CachePolicy::Lru) ? "LRU" : "FIFO";
}

VertexCache::VertexCache(uint32_t entries, CachePolicy policy,
                         uint32_t vertex_stride, uint32_t burst_bytes,
                         uint32_t vb_base)
    : entries_(entries),
      policy_(policy),
      vertex_stride_(vertex_stride),
      burst_bytes_(burst_bytes),
      vb_base_(vb_base)
{
    if (burst_bytes_ == 0) throw std::invalid_argument("VertexCache: burst_bytes = 0");
    stats_.entries = entries;
    stats_.policy  = policy;
}

void VertexCache::reset()
{
    for (Entry& e : entries_) e = Entry{};
    clock_ = 0;
    last_line_ = UINT64_MAX;

    const uint32_t n = stats_.entries;
    const CachePolicy p = stats_.policy;
    stats_ = VertexCacheStats{};
    stats_.entries = n;
    stats_.policy  = p;
}

// Pulls the burst(s) holding this vertex, unless the last miss already brought
// the same line in. Vertices are 32 B and bursts are 64 B, so neighbouring
// vertices commonly share one.
void VertexCache::fetch_lines(Index index)
{
    const uint64_t first_byte = static_cast<uint64_t>(vb_base_) +
                                static_cast<uint64_t>(index) * vertex_stride_;
    const uint64_t last_byte  = first_byte + vertex_stride_ - 1;

    const uint64_t first_line = first_byte / burst_bytes_;
    const uint64_t last_line  = last_byte  / burst_bytes_;

    for (uint64_t line = first_line; line <= last_line; ++line) {
        if (line == last_line_) continue;
        stats_.line_fetches++;
        stats_.dram_bytes += burst_bytes_;
        last_line_ = line;
    }
}

bool VertexCache::access(Index index)
{
    stats_.lookups++;
    ++clock_;

    // A zero-entry cache means no caching at all: every index is a miss.
    if (!entries_.empty()) {
        for (Entry& e : entries_) {
            if (e.valid && e.index == index) {
                stats_.hits++;
                if (policy_ == CachePolicy::Lru) e.stamp = clock_;
                return true;
            }
        }
    }

    stats_.misses++;
    fetch_lines(index);

    if (entries_.empty()) return false;

    // Victim: an invalid slot if there is one, otherwise the oldest stamp.
    // FIFO and LRU differ only in whether a hit refreshes the stamp.
    Entry* victim = nullptr;
    uint64_t oldest = std::numeric_limits<uint64_t>::max();
    for (Entry& e : entries_) {
        if (!e.valid) { victim = &e; break; }
        if (e.stamp < oldest) { oldest = e.stamp; victim = &e; }
    }

    victim->index = index;
    victim->stamp = clock_;
    victim->valid = true;
    return false;
}

// Greedy cache-aware reordering, in the spirit of Forsyth's algorithm: keep
// emitting the triangle that shares the most vertices with what is already in
// the cache, and fall back to scan order when nothing is adjacent.
std::vector<Index> optimize_index_order(const std::vector<Index>& indices,
                                        uint32_t vertex_count,
                                        uint32_t cache_entries)
{
    const size_t tri_count = indices.size() / 3;
    if (tri_count == 0 || cache_entries == 0) return indices;

    // Vertex -> triangles that use it.
    std::vector<std::vector<uint32_t>> adjacency(vertex_count);
    for (size_t t = 0; t < tri_count; ++t) {
        for (int k = 0; k < 3; ++k) {
            const Index v = indices[t * 3 + k];
            if (v < vertex_count) adjacency[v].push_back(static_cast<uint32_t>(t));
        }
    }

    std::vector<bool> emitted(tri_count, false);
    std::vector<Index> cache;            // most recent last
    std::vector<Index> out;
    out.reserve(indices.size());

    auto in_cache = [&](Index v) {
        return std::find(cache.begin(), cache.end(), v) != cache.end();
    };
    auto touch = [&](Index v) {
        if (in_cache(v)) return;
        cache.push_back(v);
        if (cache.size() > cache_entries) cache.erase(cache.begin());
    };

    size_t scan = 0;
    for (size_t done = 0; done < tri_count; ++done) {
        // Best candidate among triangles adjacent to anything still cached.
        int64_t best = -1;
        int best_score = -1;
        for (Index v : cache) {
            if (v >= vertex_count) continue;
            for (uint32_t t : adjacency[v]) {
                if (emitted[t]) continue;
                int score = 0;
                for (int k = 0; k < 3; ++k) if (in_cache(indices[t * 3 + k])) ++score;
                if (score > best_score) { best_score = score; best = static_cast<int64_t>(t); }
            }
        }

        if (best < 0) {
            while (scan < tri_count && emitted[scan]) ++scan;
            if (scan >= tri_count) break;
            best = static_cast<int64_t>(scan);
        }

        const size_t t = static_cast<size_t>(best);
        emitted[t] = true;
        for (int k = 0; k < 3; ++k) {
            const Index v = indices[t * 3 + k];
            out.push_back(v);
            touch(v);
        }
    }

    return out;
}

VertexRemap remap_vertices_by_first_use(const std::vector<Index>& indices,
                                        uint32_t vertex_count)
{
    VertexRemap out;
    out.indices.reserve(indices.size());

    constexpr uint32_t UNSEEN = 0xFFFFFFFFu;
    std::vector<uint32_t> new_of_old(vertex_count, UNSEEN);

    for (Index old_idx : indices) {
        if (old_idx >= vertex_count) { out.indices.push_back(0); continue; }
        if (new_of_old[old_idx] == UNSEEN) {
            new_of_old[old_idx] = static_cast<uint32_t>(out.old_of_new.size());
            out.old_of_new.push_back(old_idx);
        }
        out.indices.push_back(static_cast<Index>(new_of_old[old_idx]));
    }
    return out;
}

void sweep_vertex_cache(const std::vector<Index>& indices,
                        uint64_t unique_vertices,
                        uint32_t burst_bytes,
                        std::ostream& os)
{
    const std::vector<uint32_t> sizes = { 0, 8, 16, 24, 32, 48, 64, 128, 256 };

    os << "post-transform vertex cache (" << indices.size() << " indices, "
       << unique_vertices << " unique vertices)\n";
    os << "  " << std::left << std::setw(9) << "entries"
       << std::right << std::setw(10) << "FIFO hit"
       << std::setw(12) << "FIFO DRAM"
       << std::setw(10) << "LRU hit"
       << std::setw(12) << "LRU DRAM"
       << std::setw(12) << "transforms" << "\n";

    for (uint32_t n : sizes) {
        VertexCache fifo(n, CachePolicy::Fifo, sizeof(Vertex), burst_bytes);
        VertexCache lru (n, CachePolicy::Lru,  sizeof(Vertex), burst_bytes);
        for (Index i : indices) { fifo.access(i); lru.access(i); }

        os << std::fixed << std::setprecision(1);
        os << "  " << std::left << std::setw(9) << n << std::right
           << std::setw(9) << fifo.stats().hit_rate() * 100.0 << "%"
           << std::setw(12) << fifo.stats().dram_bytes
           << std::setw(9)  << lru.stats().hit_rate() * 100.0 << "%"
           << std::setw(12) << lru.stats().dram_bytes
           << std::setw(12) << fifo.stats().misses << "\n";
        os.unsetf(std::ios::fixed);
    }

    // The floor: every unique vertex fetched exactly once, in perfectly packed
    // bursts. No cache can beat this, and the model used to assume it.
    const uint64_t ideal_bytes =
        ((unique_vertices * sizeof(Vertex) + burst_bytes - 1) / burst_bytes) * burst_bytes;
    os << "  ideal (perfect cache, packed bursts): " << ideal_bytes << " B, "
       << unique_vertices << " transforms\n";
}

}  // namespace laatta
