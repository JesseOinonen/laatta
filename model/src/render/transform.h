#ifndef TRANSFORM_H
#define TRANSFORM_H

#include <cstdint>
#include <vector>

#include "../memory/memory_map.h"
#include "geometry.h"
#include "math3d.h"

namespace laatta {

struct GeometryStats {
    uint32_t input_triangles    = 0;
    uint32_t degenerate         = 0;   // zero area after snapping
    uint32_t culled_backface    = 0;
    uint32_t culled_offscreen   = 0;
    uint32_t clipped_near       = 0;   // triangles that crossed the near plane
    uint32_t output_triangles   = 0;   // what the binner actually sees
};

struct ViewSetup {
    Mat4  mvp;
    Mat4  model;      // for transforming normals
    Vec3  light_dir;  // world space, pointing towards the light
};

// Frames the whole model with a fixed camera and returns the matrices.
// Auto-fitting keeps the model useful for any .obj without hand-tuning.
ViewSetup make_view(const float bbox_min[3], const float bbox_max[3],
                    int width, int height, float yaw_rad, float pitch_rad);

// Vertex shading + near-plane clipping + backface culling + viewport mapping.
// Produces the triangles the binner works on.
std::vector<ScreenTriangle> transform_triangles(const Vertex* vertices,
                                                uint32_t vertex_count,
                                                const Index* indices,
                                                uint32_t index_count,
                                                const ViewSetup& view,
                                                int width, int height,
                                                bool cull_backface,
                                                GeometryStats& stats);

}  // namespace laatta

#endif
