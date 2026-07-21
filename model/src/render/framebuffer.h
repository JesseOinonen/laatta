#ifndef FRAMEBUFFER_H
#define FRAMEBUFFER_H

#include <cstdint>
#include <string>
#include <vector>

#include "geometry.h"

namespace laatta {

// Full-screen colour target. In a TBDR this only ever exists in DRAM and is
// written once per tile flush; it is never read back.
class Framebuffer {
public:
    Framebuffer(int width, int height, Rgba8 clear = { 24, 26, 32, 255 });

    void clear_to(Rgba8 c);

    Rgba8& at(int x, int y)             { return pixels_[static_cast<size_t>(y) * w_ + x]; }
    const Rgba8& at(int x, int y) const { return pixels_[static_cast<size_t>(y) * w_ + x]; }

    int width() const  { return w_; }
    int height() const { return h_; }
    size_t byte_size() const { return pixels_.size() * sizeof(Rgba8); }

    void write_ppm(const std::string& path) const;

    // PNG so the result opens in any viewer without a conversion step.
    // Written with uncompressed deflate blocks: slightly larger files, but no
    // zlib dependency, which keeps the model buildable with just a compiler.
    void write_png(const std::string& path) const;

    // Pixel-exact comparison. Returns the number of differing pixels and,
    // if given, writes a difference image highlighting them.
    size_t compare(const Framebuffer& other, const std::string& diff_path = "") const;

private:
    int w_, h_;
    std::vector<Rgba8> pixels_;
};

}  // namespace laatta

#endif
