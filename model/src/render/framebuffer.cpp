#include "framebuffer.h"

#include <algorithm>
#include <fstream>
#include <vector>
#include <stdexcept>

namespace laatta {

Framebuffer::Framebuffer(int width, int height, Rgba8 clear)
    : w_(width), h_(height),
      pixels_(static_cast<size_t>(width) * height, clear)
{
    if (width <= 0 || height <= 0) {
        throw std::invalid_argument("Framebuffer: bad dimensions");
    }
}

void Framebuffer::clear_to(Rgba8 c)
{
    std::fill(pixels_.begin(), pixels_.end(), c);
}

void Framebuffer::write_ppm(const std::string& path) const
{
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("Framebuffer: cannot open " + path);

    f << "P6\n" << w_ << " " << h_ << "\n255\n";
    for (const Rgba8& p : pixels_) {
        const char rgb[3] = { static_cast<char>(p.r),
                              static_cast<char>(p.g),
                              static_cast<char>(p.b) };
        f.write(rgb, 3);
    }
}

namespace {

uint32_t crc32_of(const uint8_t* data, size_t n, uint32_t crc = 0xFFFFFFFFu)
{
    static uint32_t table[256];
    static bool built = false;
    if (!built) {
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t c = i;
            for (int k = 0; k < 8; ++k) c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
        built = true;
    }
    for (size_t i = 0; i < n; ++i) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return crc;
}

void put_be32(std::vector<uint8_t>& v, uint32_t x)
{
    v.push_back(static_cast<uint8_t>(x >> 24));
    v.push_back(static_cast<uint8_t>(x >> 16));
    v.push_back(static_cast<uint8_t>(x >> 8));
    v.push_back(static_cast<uint8_t>(x));
}

void write_chunk(std::ofstream& f, const char type[4], const std::vector<uint8_t>& data)
{
    std::vector<uint8_t> header;
    put_be32(header, static_cast<uint32_t>(data.size()));
    f.write(reinterpret_cast<const char*>(header.data()),
            static_cast<std::streamsize>(header.size()));
    f.write(type, 4);
    if (!data.empty()) {
        f.write(reinterpret_cast<const char*>(data.data()),
                static_cast<std::streamsize>(data.size()));
    }

    uint32_t crc = crc32_of(reinterpret_cast<const uint8_t*>(type), 4);
    crc = crc32_of(data.data(), data.size(), crc) ^ 0xFFFFFFFFu;

    std::vector<uint8_t> tail;
    put_be32(tail, crc);
    f.write(reinterpret_cast<const char*>(tail.data()), 4);
}

}  // namespace

void Framebuffer::write_png(const std::string& path) const
{
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("Framebuffer: cannot open " + path);

    const uint8_t signature[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    f.write(reinterpret_cast<const char*>(signature), 8);

    std::vector<uint8_t> ihdr;
    put_be32(ihdr, static_cast<uint32_t>(w_));
    put_be32(ihdr, static_cast<uint32_t>(h_));
    ihdr.push_back(8);   // bit depth
    ihdr.push_back(2);   // colour type: truecolour RGB
    ihdr.push_back(0);   // deflate
    ihdr.push_back(0);   // adaptive filtering
    ihdr.push_back(0);   // no interlace
    write_chunk(f, "IHDR", ihdr);

    // Raw scanlines, each prefixed with filter type 0 (none).
    std::vector<uint8_t> raw;
    raw.reserve(static_cast<size_t>(h_) * (1 + static_cast<size_t>(w_) * 3));
    for (int y = 0; y < h_; ++y) {
        raw.push_back(0);
        for (int x = 0; x < w_; ++x) {
            const Rgba8& p = at(x, y);
            raw.push_back(p.r);
            raw.push_back(p.g);
            raw.push_back(p.b);
        }
    }

    // zlib stream wrapping stored (uncompressed) deflate blocks.
    std::vector<uint8_t> z;
    z.push_back(0x78);
    z.push_back(0x01);

    constexpr size_t MAX_BLOCK = 65535;
    for (size_t off = 0; off < raw.size(); off += MAX_BLOCK) {
        const size_t len = std::min(MAX_BLOCK, raw.size() - off);
        const bool   last = (off + len >= raw.size());
        z.push_back(last ? 1 : 0);
        z.push_back(static_cast<uint8_t>(len & 0xFF));
        z.push_back(static_cast<uint8_t>(len >> 8));
        z.push_back(static_cast<uint8_t>(~len & 0xFF));
        z.push_back(static_cast<uint8_t>((~len >> 8) & 0xFF));
        z.insert(z.end(), raw.begin() + off, raw.begin() + off + len);
    }

    uint32_t a = 1, b = 0;
    for (uint8_t byte : raw) {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    put_be32(z, (b << 16) | a);

    write_chunk(f, "IDAT", z);
    write_chunk(f, "IEND", {});
}

size_t Framebuffer::compare(const Framebuffer& other, const std::string& diff_path) const
{
    if (other.w_ != w_ || other.h_ != h_) return static_cast<size_t>(-1);

    Framebuffer diff(w_, h_, { 0, 0, 0, 255 });
    size_t bad = 0;

    for (int y = 0; y < h_; ++y) {
        for (int x = 0; x < w_; ++x) {
            const Rgba8& a = at(x, y);
            const Rgba8& b = other.at(x, y);
            if (a.r != b.r || a.g != b.g || a.b != b.b) {
                ++bad;
                diff.at(x, y) = { 255, 0, 0, 255 };
            } else {
                // Keep the matching image visible but dimmed, so the red
                // pixels stand out in context.
                diff.at(x, y) = { static_cast<uint8_t>(a.r / 4),
                                  static_cast<uint8_t>(a.g / 4),
                                  static_cast<uint8_t>(a.b / 4), 255 };
            }
        }
    }

    if (!diff_path.empty()) diff.write_png(diff_path);
    return bad;
}

}  // namespace laatta
