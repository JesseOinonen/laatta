#ifndef MATH3D_H
#define MATH3D_H

#include <algorithm>
#include <cmath>

namespace laatta {

struct Vec3 {
    float x = 0, y = 0, z = 0;

    Vec3() = default;
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

    Vec3 operator+(const Vec3& o) const { return { x + o.x, y + o.y, z + o.z }; }
    Vec3 operator-(const Vec3& o) const { return { x - o.x, y - o.y, z - o.z }; }
    Vec3 operator*(float s) const       { return { x * s, y * s, z * s }; }
};

struct Vec4 {
    float x = 0, y = 0, z = 0, w = 0;

    Vec4() = default;
    Vec4(float x_, float y_, float z_, float w_) : x(x_), y(y_), z(z_), w(w_) {}
    Vec4(const Vec3& v, float w_) : x(v.x), y(v.y), z(v.z), w(w_) {}

    Vec4 operator+(const Vec4& o) const { return { x + o.x, y + o.y, z + o.z, w + o.w }; }
    Vec4 operator-(const Vec4& o) const { return { x - o.x, y - o.y, z - o.z, w - o.w }; }
    Vec4 operator*(float s) const       { return { x * s, y * s, z * s, w * s }; }
};

inline float dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

inline Vec3 cross(const Vec3& a, const Vec3& b)
{
    return { a.y * b.z - a.z * b.y,
             a.z * b.x - a.x * b.z,
             a.x * b.y - a.y * b.x };
}

inline float length(const Vec3& v) { return std::sqrt(dot(v, v)); }

inline Vec3 normalize(const Vec3& v)
{
    const float len = length(v);
    return (len > 1e-20f) ? v * (1.0f / len) : Vec3{ 0, 0, 0 };
}

// Row-major 4x4. m[row][col], column vectors: result = M * v.
struct Mat4 {
    float m[4][4] = {};

    static Mat4 identity()
    {
        Mat4 r;
        for (int i = 0; i < 4; ++i) r.m[i][i] = 1.0f;
        return r;
    }

    Vec4 operator*(const Vec4& v) const
    {
        return {
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z + m[0][3] * v.w,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z + m[1][3] * v.w,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z + m[2][3] * v.w,
            m[3][0] * v.x + m[3][1] * v.y + m[3][2] * v.z + m[3][3] * v.w,
        };
    }

    Mat4 operator*(const Mat4& o) const
    {
        Mat4 r;
        for (int i = 0; i < 4; ++i) {
            for (int j = 0; j < 4; ++j) {
                float s = 0;
                for (int k = 0; k < 4; ++k) s += m[i][k] * o.m[k][j];
                r.m[i][j] = s;
            }
        }
        return r;
    }
};

// Right-handed, looking down -z, mapping to OpenGL-style clip space where the
// visible depth range is [-w, w].
inline Mat4 perspective(float fov_y_rad, float aspect, float z_near, float z_far)
{
    const float f = 1.0f / std::tan(fov_y_rad * 0.5f);
    Mat4 r;
    r.m[0][0] = f / aspect;
    r.m[1][1] = f;
    r.m[2][2] = (z_far + z_near) / (z_near - z_far);
    r.m[2][3] = (2.0f * z_far * z_near) / (z_near - z_far);
    r.m[3][2] = -1.0f;
    return r;
}

inline Mat4 look_at(const Vec3& eye, const Vec3& center, const Vec3& up)
{
    const Vec3 f = normalize(center - eye);
    const Vec3 s = normalize(cross(f, up));
    const Vec3 u = cross(s, f);

    Mat4 r = Mat4::identity();
    r.m[0][0] = s.x;  r.m[0][1] = s.y;  r.m[0][2] = s.z;  r.m[0][3] = -dot(s, eye);
    r.m[1][0] = u.x;  r.m[1][1] = u.y;  r.m[1][2] = u.z;  r.m[1][3] = -dot(u, eye);
    r.m[2][0] = -f.x; r.m[2][1] = -f.y; r.m[2][2] = -f.z; r.m[2][3] =  dot(f, eye);
    return r;
}

inline Mat4 rotation_y(float rad)
{
    Mat4 r = Mat4::identity();
    const float c = std::cos(rad), s = std::sin(rad);
    r.m[0][0] =  c; r.m[0][2] = s;
    r.m[2][0] = -s; r.m[2][2] = c;
    return r;
}

inline Mat4 rotation_x(float rad)
{
    Mat4 r = Mat4::identity();
    const float c = std::cos(rad), s = std::sin(rad);
    r.m[1][1] = c; r.m[1][2] = -s;
    r.m[2][1] = s; r.m[2][2] =  c;
    return r;
}

}  // namespace laatta

#endif
