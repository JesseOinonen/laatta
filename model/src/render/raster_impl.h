#ifndef RASTER_IMPL_H
#define RASTER_IMPL_H

// Rasteriser inner loop. Kept in a header because it is a template: the tiled
// and immediate-mode paths share this exact code, so any coverage or depth
// behaviour is identical between them by construction.

#include <algorithm>

#include "geometry.h"

namespace laatta {
namespace raster_detail {

// Edge function: twice the signed area of the triangle (a, b, p). Positive
// means p is on the inside, given the winding normalised by the transform
// stage. int64 because the inputs are 28-bit fixed point and this is a product.
inline int64_t edge(const ScreenVertex& a, const ScreenVertex& b,
                    int32_t px, int32_t py)
{
    return static_cast<int64_t>(b.x - a.x) * (py - a.y) -
           static_cast<int64_t>(b.y - a.y) * (px - a.x);
}

// Fill rule. A pixel exactly on a shared edge must be drawn by exactly one of
// the two triangles, or seams show up as gaps or double-blended lines. The
// top-left convention: an edge counts as inside if it is a top edge or a left
// edge of the triangle.
inline bool is_top_left(const ScreenVertex& a, const ScreenVertex& b)
{
    const int32_t dy = b.y - a.y;
    const int32_t dx = b.x - a.x;
    return (dy > 0) || (dy == 0 && dx < 0);
}

// Interpolates an 8-bit channel with integer barycentric weights. Screen-space
// linear (affine), not perspective correct: that matches what simple
// fixed-function hardware does, and keeps the whole path in integers.
inline uint8_t interp_u8(int64_t w0, int64_t w1, int64_t w2, int64_t area,
                         uint8_t c0, uint8_t c1, uint8_t c2)
{
    const int64_t v = (w0 * c0 + w1 * c1 + w2 * c2 + area / 2) / area;
    return static_cast<uint8_t>(std::clamp<int64_t>(v, 0, 255));
}

}  // namespace raster_detail

template <typename DepthAt, typename WritePixel>
void raster_triangle(const ScreenTriangle& t,
                     int x0, int y0, int x1, int y1,
                     DepthAt depth_at, WritePixel write_pixel,
                     RasterStats& stats)
{
    using namespace raster_detail;

    const int bx0 = std::max(x0, t.min_x);
    const int by0 = std::max(y0, t.min_y);
    const int bx1 = std::min(x1, t.max_x);
    const int by1 = std::min(y1, t.max_y);
    if (bx0 > bx1 || by0 > by1) return;

    const ScreenVertex& a = t.v[0];
    const ScreenVertex& b = t.v[1];
    const ScreenVertex& c = t.v[2];

    // Twice the triangle area; also the sum of the three edge functions, which
    // is what makes the weights sum to one.
    const int64_t area = static_cast<int64_t>(b.x - a.x) * (c.y - a.y) -
                         static_cast<int64_t>(c.x - a.x) * (b.y - a.y);
    if (area <= 0) return;

    // Bias applied to the coverage test only, never to interpolation.
    const int64_t bias0 = is_top_left(b, c) ? 0 : -1;
    const int64_t bias1 = is_top_left(c, a) ? 0 : -1;
    const int64_t bias2 = is_top_left(a, b) ? 0 : -1;

    for (int py = by0; py <= by1; ++py) {
        // Sample at the pixel centre, in the same fixed-point grid.
        const int32_t sy = (py << SUBPIXEL_BITS) + (SUBPIXEL_SCALE / 2);

        for (int px = bx0; px <= bx1; ++px) {
            const int32_t sx = (px << SUBPIXEL_BITS) + (SUBPIXEL_SCALE / 2);

            const int64_t w0 = edge(b, c, sx, sy);
            const int64_t w1 = edge(c, a, sx, sy);
            const int64_t w2 = edge(a, b, sx, sy);

            if (w0 + bias0 < 0 || w1 + bias1 < 0 || w2 + bias2 < 0) continue;

            stats.fragments_tested++;

            const int64_t z = (w0 * a.z + w1 * b.z + w2 * c.z + area / 2) / area;
            const Depth   frag_z = static_cast<Depth>(
                std::clamp<int64_t>(z, 0, DEPTH_MAX));

            Depth& dst_z = depth_at(px, py);
            if (frag_z >= dst_z) continue;   // depth test: strictly nearer wins

            dst_z = frag_z;
            stats.fragments_passed++;
            stats.pixels_shaded++;

            Rgba8 col;
            col.r = interp_u8(w0, w1, w2, area, a.color.r, b.color.r, c.color.r);
            col.g = interp_u8(w0, w1, w2, area, a.color.g, b.color.g, c.color.g);
            col.b = interp_u8(w0, w1, w2, area, a.color.b, b.color.b, c.color.b);
            col.a = 255;

            write_pixel(px, py, col);
        }
    }
}

}  // namespace laatta

#endif
