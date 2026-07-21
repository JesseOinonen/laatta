#ifndef DRAM_MODEL_H
#define DRAM_MODEL_H

#include <cstdint>
#include <ostream>
#include <string>
#include <vector>

#include "memory_map.h"

namespace laatta {

// Who issued a transaction. Traffic is accounted per client so the tile-size
// vs. DRAM-bandwidth trade-off is directly readable from the stats.
enum class Client {
    Cmd,
    VertexFetch,
    IndexFetch,
    ParamWrite,   // binner writing tile lists / transformed primitives
    ParamRead,    // tile scheduler reading them back
    Texture,
    ColorWrite,   // tile buffer flushed to the framebuffer
    ColorRead,    // immediate-mode only
    DepthRead,    // immediate-mode only; a TBDR never does this
    DepthWrite,   // immediate-mode only
    Other,
    NUM_CLIENTS
};

const char* client_name(Client c);

struct MemStats {
    uint64_t reads        = 0;
    uint64_t writes       = 0;
    uint64_t read_bytes   = 0;   // bytes the client asked for
    uint64_t write_bytes  = 0;
    uint64_t read_bursts  = 0;   // bursts DRAM actually moved
    uint64_t write_bursts = 0;
};

// Byte-addressable memory with burst-granular traffic accounting.
//
// Untimed on purpose: this is a golden reference, not a simulator. It answers
// "how many bytes cross the chip boundary", which is the question tile size
// and buffer budgets are chosen against. Cycle counts come from RTL later.
class DramModel {
public:
    explicit DramModel(uint32_t size_bytes  = mmap::DRAM_SIZE,
                       uint32_t burst_bytes = 64);

    // --- content access, not accounted ---
    void backdoor_write(uint32_t addr, const void* src, size_t n);
    void backdoor_read(uint32_t addr, void* dst, size_t n) const;
    void dump(const std::string& path, uint32_t addr, size_t n) const;

    template <typename T>
    void backdoor_poke(uint32_t addr, const T& value) {
        backdoor_write(addr, &value, sizeof(T));
    }
    template <typename T>
    T backdoor_peek(uint32_t addr) const {
        T value{};
        backdoor_read(addr, &value, sizeof(T));
        return value;
    }

    // --- accounted access ---
    void read(uint32_t addr, void* dst, size_t n, Client c);
    void write(uint32_t addr, const void* src, size_t n, Client c);

    // Accounting without touching memory, for traffic that the model computes
    // analytically (framebuffer flushes, parameter buffer re-reads).
    void account_read(uint32_t addr, size_t n, Client c);
    void account_write(uint32_t addr, size_t n, Client c);

    // Bursts DRAM must move for [addr, addr+n).
    uint64_t burst_count(uint32_t addr, size_t n) const;

    // --- statistics ---
    const MemStats& stats(Client c) const;
    MemStats total() const;
    uint64_t bytes_moved() const;   // burst-rounded, both directions
    void reset_stats();
    void report(std::ostream& os) const;

    uint32_t size() const { return static_cast<uint32_t>(mem_.size()); }
    uint32_t burst_bytes() const { return burst_bytes_; }

private:
    void bounds_check(uint32_t addr, size_t n, const char* what) const;

    std::vector<uint8_t> mem_;
    uint32_t             burst_bytes_;
    MemStats             stats_[static_cast<int>(Client::NUM_CLIENTS)];
};

}  // namespace laatta

#endif
