#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

#include <cstdint>
#include <ostream>

// Address map of the modelled DRAM. Everything the pipeline touches lives here,
// so no stage needs to know how the scene was loaded.
namespace laatta {
namespace mmap {

constexpr uint32_t DRAM_BASE  = 0x00000000u;
constexpr uint32_t DRAM_SIZE  = 64u << 20;      // 64 MiB

constexpr uint32_t CMD_BASE   = 0x00000000u;    // draw descriptor
constexpr uint32_t VB_BASE    = 0x00100000u;    // vertex buffer
constexpr uint32_t IB_BASE    = 0x00800000u;    // index buffer
constexpr uint32_t TEX_BASE   = 0x01000000u;    // textures (phase 2)
constexpr uint32_t PARAM_BASE = 0x02000000u;    // binner tile lists
constexpr uint32_t FB_BASE    = 0x03000000u;    // framebuffer

}  // namespace mmap

// One vertex as the vertex fetch unit sees it: 32 bytes, burst friendly.
struct Vertex {
    float px, py, pz;
    float nx, ny, nz;
    float u, v;
};
static_assert(sizeof(Vertex) == 32, "Vertex must stay 32 bytes");

// sc_fifo<T> requires T to be printable (it uses this for tracing).
inline std::ostream& operator<<(std::ostream& os, const Vertex& v)
{
    return os << "pos(" << v.px << ", " << v.py << ", " << v.pz << ")"
              << " uv(" << v.u << ", " << v.v << ")";
}

using Index = uint32_t;

// Written to CMD_BASE by the loader, read back by the pipeline. Keeps the
// model free of hardcoded scene sizes.
struct DrawDescriptor {
    uint32_t magic;          // DRAW_MAGIC
    uint32_t vertex_count;
    uint32_t index_count;    // multiple of 3
    uint32_t vb_base;
    uint32_t ib_base;
    uint32_t vertex_stride;  // bytes
    uint32_t tex_base;       // 0 = no texture
    uint32_t flags;
};
static_assert(sizeof(DrawDescriptor) == 32, "DrawDescriptor must stay 32 bytes");

constexpr uint32_t DRAW_MAGIC = 0x4C414154u;  // "LAAT"

}  // namespace laatta

#endif
