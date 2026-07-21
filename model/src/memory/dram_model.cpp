#include "dram_model.h"

#include <cstring>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace laatta {

const char* client_name(Client c)
{
    switch (c) {
        case Client::Cmd:         return "cmd";
        case Client::VertexFetch: return "vertex_fetch";
        case Client::IndexFetch:  return "index_fetch";
        case Client::ParamWrite:  return "param_write";
        case Client::ParamRead:   return "param_read";
        case Client::Texture:     return "texture";
        case Client::ColorWrite:  return "color_write";
        case Client::ColorRead:   return "color_read";
        case Client::DepthRead:   return "depth_read";
        case Client::DepthWrite:  return "depth_write";
        default:                  return "other";
    }
}

DramModel::DramModel(uint32_t size_bytes, uint32_t burst_bytes)
    : mem_(size_bytes, 0), burst_bytes_(burst_bytes)
{
    if (burst_bytes_ == 0 || (burst_bytes_ & (burst_bytes_ - 1)) != 0) {
        throw std::invalid_argument("DramModel: burst_bytes must be a power of two");
    }
}

void DramModel::bounds_check(uint32_t addr, size_t n, const char* what) const
{
    if (static_cast<uint64_t>(addr) + n > mem_.size()) {
        std::ostringstream os;
        os << "DramModel: " << what << " out of range: addr=0x" << std::hex << addr
           << " len=" << std::dec << n << " size=" << mem_.size();
        throw std::out_of_range(os.str());
    }
}

// The request is widened to burst boundaries: DRAM cannot move less than a
// burst, which is exactly what makes small scattered accesses expensive.
uint64_t DramModel::burst_count(uint32_t addr, size_t n) const
{
    if (n == 0) return 0;
    const uint64_t first = addr / burst_bytes_;
    const uint64_t last  = (static_cast<uint64_t>(addr) + n - 1) / burst_bytes_;
    return last - first + 1;
}

void DramModel::backdoor_write(uint32_t addr, const void* src, size_t n)
{
    bounds_check(addr, n, "backdoor_write");
    std::memcpy(mem_.data() + addr, src, n);
}

void DramModel::backdoor_read(uint32_t addr, void* dst, size_t n) const
{
    bounds_check(addr, n, "backdoor_read");
    std::memcpy(dst, mem_.data() + addr, n);
}

void DramModel::dump(const std::string& path, uint32_t addr, size_t n) const
{
    bounds_check(addr, n, "dump");
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("DramModel: cannot open " + path);
    f.write(reinterpret_cast<const char*>(mem_.data() + addr),
            static_cast<std::streamsize>(n));
}

void DramModel::account_read(uint32_t addr, size_t n, Client c)
{
    MemStats& s = stats_[static_cast<int>(c)];
    s.reads++;
    s.read_bytes  += n;
    s.read_bursts += burst_count(addr, n);
}

void DramModel::account_write(uint32_t addr, size_t n, Client c)
{
    MemStats& s = stats_[static_cast<int>(c)];
    s.writes++;
    s.write_bytes  += n;
    s.write_bursts += burst_count(addr, n);
}

void DramModel::read(uint32_t addr, void* dst, size_t n, Client c)
{
    bounds_check(addr, n, "read");
    std::memcpy(dst, mem_.data() + addr, n);
    account_read(addr, n, c);
}

void DramModel::write(uint32_t addr, const void* src, size_t n, Client c)
{
    bounds_check(addr, n, "write");
    std::memcpy(mem_.data() + addr, src, n);
    account_write(addr, n, c);
}

const MemStats& DramModel::stats(Client c) const
{
    return stats_[static_cast<int>(c)];
}

MemStats DramModel::total() const
{
    MemStats t;
    for (int i = 0; i < static_cast<int>(Client::NUM_CLIENTS); ++i) {
        t.reads        += stats_[i].reads;
        t.writes       += stats_[i].writes;
        t.read_bytes   += stats_[i].read_bytes;
        t.write_bytes  += stats_[i].write_bytes;
        t.read_bursts  += stats_[i].read_bursts;
        t.write_bursts += stats_[i].write_bursts;
    }
    return t;
}

uint64_t DramModel::bytes_moved() const
{
    const MemStats t = total();
    return (t.read_bursts + t.write_bursts) * burst_bytes_;
}

void DramModel::reset_stats()
{
    for (int i = 0; i < static_cast<int>(Client::NUM_CLIENTS); ++i) {
        stats_[i] = MemStats();
    }
}

void DramModel::report(std::ostream& os) const
{
    auto row = [&](const char* name, const MemStats& s) {
        const uint64_t moved = (s.read_bursts + s.write_bursts) * burst_bytes_;
        const uint64_t asked = s.read_bytes + s.write_bytes;
        os << "  " << std::left << std::setw(14) << name << std::right
           << std::setw(12) << asked
           << std::setw(12) << moved
           << std::setw(9)
           << (asked ? static_cast<double>(moved) / static_cast<double>(asked) : 0.0)
           << "\n";
    };

    os << std::fixed << std::setprecision(2);
    os << "DRAM traffic (burst " << burst_bytes_ << " B)\n"
       << "  " << std::left << std::setw(14) << "client" << std::right
       << std::setw(12) << "requested" << std::setw(12) << "moved"
       << std::setw(9)  << "amp" << "\n";

    for (int i = 0; i < static_cast<int>(Client::NUM_CLIENTS); ++i) {
        const MemStats& s = stats_[i];
        if (s.reads || s.writes) row(client_name(static_cast<Client>(i)), s);
    }
    row("TOTAL", total());
    os.unsetf(std::ios::fixed);
}

}  // namespace laatta
