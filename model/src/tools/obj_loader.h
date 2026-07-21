#ifndef OBJ_LOADER_H
#define OBJ_LOADER_H

#include <cstdint>
#include <ostream>
#include <string>
#include <vector>

#include "../memory/memory_map.h"

namespace laatta {

class DramModel;

// Host-side geometry, already in the layout the vertex fetch unit expects.
struct Mesh {
    std::vector<Vertex> vertices;
    std::vector<Index>  indices;   // triangle list, size % 3 == 0

    // Verification aids: cheap invariants to compare against the DCC tool.
    float bbox_min[3] = { 0, 0, 0 };
    float bbox_max[3] = { 0, 0, 0 };

    // Source-file counts, before de-indexing. Should match Blender's stats.
    uint32_t src_positions = 0;
    uint32_t src_texcoords = 0;
    uint32_t src_normals   = 0;
    uint32_t src_faces     = 0;
    uint32_t triangles_from_ngons = 0;

    size_t triangle_count() const { return indices.size() / 3; }
    void   compute_bbox();
    void   report(std::ostream& os) const;
};

// Parses a Wavefront OBJ into a single triangle list.
//
// Handles the parts that matter for getting the reference right:
//   * per-attribute indices (f v/vt/vn) are de-indexed into unique vertices
//   * n-gons are fan-triangulated
//   * negative (relative) indices
//   * missing vt/vn (filled with zeros)
// Materials and object grouping are ignored on purpose — phase 0 draws one
// triangle list.
Mesh load_obj(const std::string& path);

// Places the mesh in DRAM at the addresses from memory_map.h and writes the
// draw descriptor to CMD_BASE. Backdoor only: consumes no simulation time.
void upload_mesh(DramModel& dram, const Mesh& mesh);

// Reads geometry back out of DRAM through the backdoor and checks it is
// bit-identical to `mesh`. Returns true on success, logs the first mismatch.
bool verify_mesh_in_dram(const DramModel& dram, const Mesh& mesh, std::ostream& os);

// Writes the DRAM contents back out as an .obj so the round trip can be
// eyeballed in Blender.
void export_obj_from_dram(const DramModel& dram, const std::string& path);

}  // namespace laatta

#endif
