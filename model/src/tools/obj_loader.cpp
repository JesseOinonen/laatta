#include "obj_loader.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <unordered_map>

#include "../memory/dram_model.h"

namespace laatta {
namespace {

struct Vec3 { float x = 0, y = 0, z = 0; };
struct Vec2 { float u = 0, v = 0; };

// One corner as written in the file: separate indices per attribute.
struct FaceVert {
    int32_t v  = 0;   // already resolved to 0-based, -1 = absent
    int32_t vt = -1;
    int32_t vn = -1;

    bool operator==(const FaceVert& o) const {
        return v == o.v && vt == o.vt && vn == o.vn;
    }
};

struct FaceVertHash {
    size_t operator()(const FaceVert& f) const {
        size_t h = static_cast<uint32_t>(f.v);
        h = h * 1000003u ^ static_cast<uint32_t>(f.vt);
        h = h * 1000003u ^ static_cast<uint32_t>(f.vn);
        return h;
    }
};

// OBJ indices are 1-based; negative means relative to the end of the list.
int32_t resolve(int32_t raw, size_t count)
{
    if (raw > 0) return raw - 1;
    if (raw < 0) return static_cast<int32_t>(count) + raw;
    return -1;
}

// Parses "12", "12/7", "12//3" or "12/7/3".
FaceVert parse_corner(const std::string& tok, size_t nv, size_t nvt, size_t nvn)
{
    int32_t idx[3] = { 0, 0, 0 };
    int     field  = 0;
    size_t  pos    = 0;

    while (pos <= tok.size() && field < 3) {
        size_t slash = tok.find('/', pos);
        size_t end   = (slash == std::string::npos) ? tok.size() : slash;
        if (end > pos) idx[field] = std::stoi(tok.substr(pos, end - pos));
        if (slash == std::string::npos) break;
        pos = slash + 1;
        ++field;
    }

    FaceVert fv;
    fv.v  = resolve(idx[0], nv);
    fv.vt = resolve(idx[1], nvt);
    fv.vn = resolve(idx[2], nvn);
    if (fv.v < 0) throw std::runtime_error("obj: face references vertex 0 or out of range");
    return fv;
}

}  // namespace

void Mesh::compute_bbox()
{
    if (vertices.empty()) {
        std::fill(bbox_min, bbox_min + 3, 0.0f);
        std::fill(bbox_max, bbox_max + 3, 0.0f);
        return;
    }
    float lo[3] = {  std::numeric_limits<float>::infinity(),
                     std::numeric_limits<float>::infinity(),
                     std::numeric_limits<float>::infinity() };
    float hi[3] = { -std::numeric_limits<float>::infinity(),
                    -std::numeric_limits<float>::infinity(),
                    -std::numeric_limits<float>::infinity() };
    for (const Vertex& vx : vertices) {
        const float p[3] = { vx.px, vx.py, vx.pz };
        for (int i = 0; i < 3; ++i) {
            lo[i] = std::min(lo[i], p[i]);
            hi[i] = std::max(hi[i], p[i]);
        }
    }
    std::copy(lo, lo + 3, bbox_min);
    std::copy(hi, hi + 3, bbox_max);
}

void Mesh::report(std::ostream& os) const
{
    os << "Mesh\n"
       << "  source        : v=" << src_positions << " vt=" << src_texcoords
       << " vn=" << src_normals << " f=" << src_faces << "\n"
       << "  de-indexed    : " << vertices.size() << " vertices, "
       << triangle_count() << " triangles";
    if (triangles_from_ngons) os << " (" << triangles_from_ngons << " from n-gons)";
    os << "\n"
       << "  vertex buffer : " << vertices.size() * sizeof(Vertex) << " B\n"
       << "  index buffer  : " << indices.size() * sizeof(Index) << " B\n"
       << "  bbox min      : " << bbox_min[0] << ", " << bbox_min[1] << ", " << bbox_min[2] << "\n"
       << "  bbox max      : " << bbox_max[0] << ", " << bbox_max[1] << ", " << bbox_max[2] << "\n";
}

Mesh load_obj(const std::string& path)
{
    std::ifstream f(path);
    if (!f) throw std::runtime_error("obj: cannot open " + path);

    std::vector<Vec3> positions;
    std::vector<Vec2> texcoords;
    std::vector<Vec3> normals;

    Mesh mesh;
    std::unordered_map<FaceVert, Index, FaceVertHash> unique;

    // Interns a file corner into the de-indexed vertex buffer.
    auto emit = [&](const FaceVert& fv) -> Index {
        auto it = unique.find(fv);
        if (it != unique.end()) return it->second;

        Vertex vx{};
        if (fv.v >= 0 && static_cast<size_t>(fv.v) < positions.size()) {
            vx.px = positions[fv.v].x;
            vx.py = positions[fv.v].y;
            vx.pz = positions[fv.v].z;
        }
        if (fv.vn >= 0 && static_cast<size_t>(fv.vn) < normals.size()) {
            vx.nx = normals[fv.vn].x;
            vx.ny = normals[fv.vn].y;
            vx.nz = normals[fv.vn].z;
        }
        if (fv.vt >= 0 && static_cast<size_t>(fv.vt) < texcoords.size()) {
            vx.u = texcoords[fv.vt].u;
            vx.v = texcoords[fv.vt].v;
        }

        const Index id = static_cast<Index>(mesh.vertices.size());
        mesh.vertices.push_back(vx);
        unique.emplace(fv, id);
        return id;
    };

    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;

        std::istringstream ls(line);
        std::string tag;
        ls >> tag;

        if (tag == "v") {
            Vec3 p; ls >> p.x >> p.y >> p.z;
            positions.push_back(p);
        } else if (tag == "vt") {
            Vec2 t; ls >> t.u >> t.v;
            texcoords.push_back(t);
        } else if (tag == "vn") {
            Vec3 n; ls >> n.x >> n.y >> n.z;
            normals.push_back(n);
        } else if (tag == "f") {
            std::vector<FaceVert> corners;
            std::string tok;
            while (ls >> tok) {
                corners.push_back(parse_corner(tok, positions.size(),
                                               texcoords.size(), normals.size()));
            }
            if (corners.size() < 3) continue;

            mesh.src_faces++;
            if (corners.size() > 3) mesh.triangles_from_ngons += static_cast<uint32_t>(corners.size() - 3);

            const Index i0 = emit(corners[0]);
            for (size_t k = 1; k + 1 < corners.size(); ++k) {   // fan
                mesh.indices.push_back(i0);
                mesh.indices.push_back(emit(corners[k]));
                mesh.indices.push_back(emit(corners[k + 1]));
            }
        }
    }

    mesh.src_positions = static_cast<uint32_t>(positions.size());
    mesh.src_texcoords = static_cast<uint32_t>(texcoords.size());
    mesh.src_normals   = static_cast<uint32_t>(normals.size());
    mesh.compute_bbox();
    return mesh;
}

void upload_mesh(DramModel& dram, const Mesh& mesh)
{
    const size_t vb_bytes = mesh.vertices.size() * sizeof(Vertex);
    const size_t ib_bytes = mesh.indices.size()  * sizeof(Index);

    if (mmap::VB_BASE + vb_bytes > mmap::IB_BASE) {
        throw std::runtime_error("upload_mesh: vertex buffer overruns index buffer region");
    }
    if (mmap::IB_BASE + ib_bytes > mmap::TEX_BASE) {
        throw std::runtime_error("upload_mesh: index buffer overruns texture region");
    }

    dram.backdoor_write(mmap::VB_BASE, mesh.vertices.data(), vb_bytes);
    dram.backdoor_write(mmap::IB_BASE, mesh.indices.data(), ib_bytes);

    DrawDescriptor d{};
    d.magic         = DRAW_MAGIC;
    d.vertex_count  = static_cast<uint32_t>(mesh.vertices.size());
    d.index_count   = static_cast<uint32_t>(mesh.indices.size());
    d.vb_base       = mmap::VB_BASE;
    d.ib_base       = mmap::IB_BASE;
    d.vertex_stride = sizeof(Vertex);
    d.tex_base      = 0;
    d.flags         = 0;
    dram.backdoor_poke(mmap::CMD_BASE, d);
}

bool verify_mesh_in_dram(const DramModel& dram, const Mesh& mesh, std::ostream& os)
{
    const DrawDescriptor d = dram.backdoor_peek<DrawDescriptor>(mmap::CMD_BASE);

    if (d.magic != DRAW_MAGIC) {
        os << "  FAIL: draw descriptor magic 0x" << std::hex << d.magic << std::dec << "\n";
        return false;
    }
    if (d.vertex_count != mesh.vertices.size() || d.index_count != mesh.indices.size()) {
        os << "  FAIL: descriptor counts " << d.vertex_count << "/" << d.index_count
           << " != mesh " << mesh.vertices.size() << "/" << mesh.indices.size() << "\n";
        return false;
    }
    if (d.vertex_stride != sizeof(Vertex)) {
        os << "  FAIL: descriptor stride " << d.vertex_stride << "\n";
        return false;
    }

    std::vector<Vertex> vb(d.vertex_count);
    std::vector<Index>  ib(d.index_count);
    dram.backdoor_read(d.vb_base, vb.data(), vb.size() * sizeof(Vertex));
    dram.backdoor_read(d.ib_base, ib.data(), ib.size() * sizeof(Index));

    if (std::memcmp(vb.data(), mesh.vertices.data(), vb.size() * sizeof(Vertex)) != 0) {
        for (size_t i = 0; i < vb.size(); ++i) {
            if (std::memcmp(&vb[i], &mesh.vertices[i], sizeof(Vertex)) != 0) {
                os << "  FAIL: vertex " << i << " differs\n";
                break;
            }
        }
        return false;
    }
    if (std::memcmp(ib.data(), mesh.indices.data(), ib.size() * sizeof(Index)) != 0) {
        os << "  FAIL: index buffer differs\n";
        return false;
    }

    // Every index must address a real vertex, or the pipeline reads garbage.
    for (size_t i = 0; i < ib.size(); ++i) {
        if (ib[i] >= d.vertex_count) {
            os << "  FAIL: index[" << i << "] = " << ib[i]
               << " >= vertex_count " << d.vertex_count << "\n";
            return false;
        }
    }
    return true;
}

void export_obj_from_dram(const DramModel& dram, const std::string& path)
{
    const DrawDescriptor d = dram.backdoor_peek<DrawDescriptor>(mmap::CMD_BASE);
    if (d.magic != DRAW_MAGIC) throw std::runtime_error("export: no valid draw descriptor");

    std::vector<Vertex> vb(d.vertex_count);
    std::vector<Index>  ib(d.index_count);
    dram.backdoor_read(d.vb_base, vb.data(), vb.size() * sizeof(Vertex));
    dram.backdoor_read(d.ib_base, ib.data(), ib.size() * sizeof(Index));

    std::ofstream f(path);
    if (!f) throw std::runtime_error("export: cannot open " + path);
    f << "# laatta: round-tripped from DRAM model\n";

    for (const Vertex& v : vb) f << "v "  << v.px << " " << v.py << " " << v.pz << "\n";
    for (const Vertex& v : vb) f << "vt " << v.u  << " " << v.v  << "\n";
    for (const Vertex& v : vb) f << "vn " << v.nx << " " << v.ny << " " << v.nz << "\n";

    for (size_t i = 0; i + 2 < ib.size(); i += 3) {
        f << "f";
        for (int k = 0; k < 3; ++k) {
            const uint32_t n = ib[i + k] + 1;   // back to 1-based
            f << " " << n << "/" << n << "/" << n;
        }
        f << "\n";
    }
}

}  // namespace laatta
