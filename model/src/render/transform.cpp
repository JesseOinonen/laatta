#include "transform.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace laatta {
namespace {

// A vertex mid-pipeline: clip-space position plus the attributes that survive
// to the rasteriser. Shading happens before clipping (Gouraud), so clipping
// only has to interpolate a colour.
struct ClipVertex {
    Vec4  pos;
    float r = 0, g = 0, b = 0;
};

ClipVertex lerp(const ClipVertex& a, const ClipVertex& b, float t)
{
    ClipVertex o;
    o.pos = a.pos + (b.pos - a.pos) * t;
    o.r   = a.r + (b.r - a.r) * t;
    o.g   = a.g + (b.g - a.g) * t;
    o.b   = a.b + (b.b - a.b) * t;
    return o;
}

// Distance to the near plane in clip space: inside when z + w >= 0.
float near_distance(const ClipVertex& v) { return v.pos.z + v.pos.w; }

// Sutherland-Hodgman against the near plane only. The other five planes are
// handled by clamping the screen bounding box, which is what a guard-band
// rasteriser does — the near plane is the one that cannot be skipped, since
// crossing it makes the perspective divide meaningless.
std::vector<ClipVertex> clip_near(const std::array<ClipVertex, 3>& tri, bool& was_clipped)
{
    std::vector<ClipVertex> out;
    out.reserve(4);
    was_clipped = false;

    for (int i = 0; i < 3; ++i) {
        const ClipVertex& cur  = tri[i];
        const ClipVertex& next = tri[(i + 1) % 3];
        const float d_cur  = near_distance(cur);
        const float d_next = near_distance(next);

        if (d_cur >= 0.0f) out.push_back(cur);

        if ((d_cur >= 0.0f) != (d_next >= 0.0f)) {
            was_clipped = true;
            const float t = d_cur / (d_cur - d_next);
            out.push_back(lerp(cur, next, t));
        }
    }
    return out;
}

uint8_t to_u8(float v)
{
    return static_cast<uint8_t>(std::lround(std::clamp(v, 0.0f, 1.0f) * 255.0f));
}

}  // namespace

ViewSetup make_view(const float bbox_min[3], const float bbox_max[3],
                    int width, int height, float yaw_rad, float pitch_rad)
{
    const Vec3 lo(bbox_min[0], bbox_min[1], bbox_min[2]);
    const Vec3 hi(bbox_max[0], bbox_max[1], bbox_max[2]);
    const Vec3 center = (lo + hi) * 0.5f;
    const Vec3 extent = (hi - lo) * 0.5f;
    const float radius = std::max(length(extent), 1e-4f);

    const float fov = 45.0f * 3.14159265f / 180.0f;
    const float aspect = static_cast<float>(width) / static_cast<float>(height);

    ViewSetup v;

    // Centre the model at the origin, then rotate it.
    Mat4 to_origin = Mat4::identity();
    to_origin.m[0][3] = -center.x;
    to_origin.m[1][3] = -center.y;
    to_origin.m[2][3] = -center.z;
    v.model = rotation_y(yaw_rad) * rotation_x(pitch_rad) * to_origin;

    // Frame from the projected bounding box rather than the bounding sphere: a
    // sphere around a long thin model wastes most of the screen, which would
    // make the fragment and traffic numbers unrepresentative.
    const float tan_v = std::tan(fov * 0.5f);
    const float tan_h = tan_v * aspect;

    float distance = radius;   // never closer than this
    for (int i = 0; i < 8; ++i) {
        const Vec3 corner((i & 1) ? extent.x : -extent.x,
                          (i & 2) ? extent.y : -extent.y,
                          (i & 4) ? extent.z : -extent.z);
        const Vec4 p = rotation_y(yaw_rad) * rotation_x(pitch_rad) * Vec4(corner, 1.0f);

        // Distance at which this corner just fits inside each frustum plane.
        distance = std::max(distance, p.z + std::fabs(p.x) / tan_h);
        distance = std::max(distance, p.z + std::fabs(p.y) / tan_v);
    }
    distance *= 1.08f;   // small margin so nothing touches the edge

    const Vec3 eye(0, 0, distance);
    const Mat4 view_m = look_at(eye, Vec3(0, 0, 0), Vec3(0, 1, 0));

    const float z_near = std::max(1e-4f, distance - radius * 1.5f);
    const float z_far  = distance + radius * 1.5f;
    const Mat4 proj = perspective(fov, aspect, z_near, z_far);

    v.mvp = proj * view_m * v.model;
    v.light_dir = normalize(Vec3(0.4f, 0.7f, 0.6f));
    return v;
}

std::vector<ScreenTriangle> transform_triangles(const Vertex* vertices,
                                                uint32_t vertex_count,
                                                const Index* indices,
                                                uint32_t index_count,
                                                const ViewSetup& view,
                                                int width, int height,
                                                bool cull_backface,
                                                GeometryStats& stats)
{
    std::vector<ScreenTriangle> out;
    out.reserve(index_count / 3);

    stats = GeometryStats{};

    // Maps a clip-space vertex to fixed-point screen coordinates.
    auto to_screen = [&](const ClipVertex& cv) {
        ScreenVertex sv;
        const float inv_w = 1.0f / cv.pos.w;
        const float ndc_x = cv.pos.x * inv_w;          // [-1, 1]
        const float ndc_y = cv.pos.y * inv_w;
        const float ndc_z = cv.pos.z * inv_w;

        const float sx = (ndc_x * 0.5f + 0.5f) * static_cast<float>(width);
        const float sy = (1.0f - (ndc_y * 0.5f + 0.5f)) * static_cast<float>(height);

        sv.x = static_cast<int32_t>(std::lround(sx * SUBPIXEL_SCALE));
        sv.y = static_cast<int32_t>(std::lround(sy * SUBPIXEL_SCALE));

        const float depth01 = std::clamp(ndc_z * 0.5f + 0.5f, 0.0f, 1.0f);
        sv.z = static_cast<Depth>(std::lround(depth01 * DEPTH_MAX));

        sv.color = { to_u8(cv.r), to_u8(cv.g), to_u8(cv.b), 255 };
        return sv;
    };

    auto emit = [&](const ScreenVertex& a, const ScreenVertex& b, const ScreenVertex& c) {
        // Signed area x2 in fixed point. Sign tells us the winding, which is
        // what backface culling is: front faces come out one way round after
        // the y-flip of the viewport transform.
        const int64_t area2 =
            static_cast<int64_t>(b.x - a.x) * (c.y - a.y) -
            static_cast<int64_t>(c.x - a.x) * (b.y - a.y);

        if (area2 == 0) { stats.degenerate++; return; }
        if (cull_backface && area2 > 0) { stats.culled_backface++; return; }

        ScreenTriangle t;
        t.v[0] = a;
        // Normalise winding so the rasteriser's edge functions are positive
        // inside the triangle. One branch here saves one everywhere later.
        if (area2 < 0) { t.v[1] = c; t.v[2] = b; }
        else           { t.v[1] = b; t.v[2] = c; }

        const int32_t lo_x = std::min({ t.v[0].x, t.v[1].x, t.v[2].x });
        const int32_t hi_x = std::max({ t.v[0].x, t.v[1].x, t.v[2].x });
        const int32_t lo_y = std::min({ t.v[0].y, t.v[1].y, t.v[2].y });
        const int32_t hi_y = std::max({ t.v[0].y, t.v[1].y, t.v[2].y });

        // Whole-pixel bounding box, clamped to the viewport. This clamp is
        // what stands in for clipping against the side planes.
        t.min_x = std::max(0,          static_cast<int32_t>(lo_x >> SUBPIXEL_BITS));
        t.min_y = std::max(0,          static_cast<int32_t>(lo_y >> SUBPIXEL_BITS));
        t.max_x = std::min(width  - 1, static_cast<int32_t>(hi_x >> SUBPIXEL_BITS));
        t.max_y = std::min(height - 1, static_cast<int32_t>(hi_y >> SUBPIXEL_BITS));

        if (t.min_x > t.max_x || t.min_y > t.max_y) {
            stats.culled_offscreen++;
            return;
        }

        out.push_back(t);
        stats.output_triangles++;
    };

    for (uint32_t i = 0; i + 2 < index_count; i += 3) {
        stats.input_triangles++;

        std::array<ClipVertex, 3> tri;
        bool valid = true;

        for (int k = 0; k < 3; ++k) {
            const Index idx = indices[i + k];
            if (idx >= vertex_count) { valid = false; break; }
            const Vertex& v = vertices[idx];

            // Vertex shading: Lambert against a single directional light.
            // Done before clipping so clipping only interpolates colour.
            const Vec4 world_n = view.model * Vec4(v.nx, v.ny, v.nz, 0.0f);
            const Vec3 n = normalize(Vec3(world_n.x, world_n.y, world_n.z));
            const float diffuse = std::max(0.0f, dot(n, view.light_dir));
            const float shade = 0.18f + 0.82f * diffuse;

            tri[k].pos = view.mvp * Vec4(v.px, v.py, v.pz, 1.0f);
            tri[k].r = shade * 0.85f;
            tri[k].g = shade * 0.88f;
            tri[k].b = shade * 0.95f;
        }
        if (!valid) { stats.degenerate++; continue; }

        bool was_clipped = false;
        const std::vector<ClipVertex> poly = clip_near(tri, was_clipped);
        if (was_clipped) stats.clipped_near++;
        if (poly.size() < 3) { stats.culled_offscreen++; continue; }

        // Fan-triangulate whatever the clip produced (3 or 4 vertices).
        const ScreenVertex first = to_screen(poly[0]);
        for (size_t k = 1; k + 1 < poly.size(); ++k) {
            emit(first, to_screen(poly[k]), to_screen(poly[k + 1]));
        }
    }

    return out;
}

}  // namespace laatta
