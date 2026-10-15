// Derived from Pillow 12.2.0 (MIT-CMU, cli/third_party/pillow/LICENSE): Image.thumbnail/resize/reduce in Image.py and
// src/libImaging/Reduce.c and Resample.c, restricted to 8-bit RGB and the Lanczos filter. The fixed-point arithmetic is
// kept as is so the result is the same byte.

#include "resample.hpp"

#include "hct.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace burl::colour {

namespace {

constexpr int kPrecisionBits = 32 - 8 - 2;
constexpr double kLanczosSupport = 3.0;

struct Plane {
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> rgb;

    const std::uint8_t* row(int y) const {
        return this->rgb.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(this->width) * 3;
    }

    std::uint8_t* row(int y) {
        return this->rgb.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(this->width) * 3;
    }
};

struct Box {
    float x0;
    float y0;
    float x1;
    float y1;
};

double sincFilter(double x) {
    if (exactlyEqual(x, 0.0)) {
        return 1.0;
    }

    x = x * std::numbers::pi;
    return std::sin(x) / x;
}

double lanczosFilter(double x) {
    if (-3.0 <= x && x < 3.0) {
        return sincFilter(x) * sincFilter(x / 3);
    }

    return 0.0;
}

struct Coefficients {
    int ksize = 0;
    std::vector<int> bounds;
    std::vector<double> kk;
};

Coefficients precomputeCoeffs(int inSize, float in0, float in1, int outSize) {
    double scale = static_cast<double>(in1 - in0) / outSize;
    double filterScale = scale;
    if (filterScale < 1.0) {
        filterScale = 1.0;
    }

    const double support = kLanczosSupport * filterScale;
    const int ksize = static_cast<int>(std::ceil(support)) * 2 + 1;

    Coefficients result;
    result.ksize = ksize;
    result.kk.assign(static_cast<std::size_t>(outSize) * static_cast<std::size_t>(ksize), 0.0);
    result.bounds.assign(static_cast<std::size_t>(outSize) * 2, 0);

    for (int xx = 0; xx < outSize; ++xx) {
        const double center = static_cast<double>(in0) + (xx + 0.5) * scale;
        double ww = 0.0;
        const double ss = 1.0 / filterScale;
        int xmin = static_cast<int>(center - support + 0.5);
        if (xmin < 0) {
            xmin = 0;
        }

        int xmax = static_cast<int>(center + support + 0.5);
        if (xmax > inSize) {
            xmax = inSize;
        }

        xmax -= xmin;
        double* k = &result.kk[static_cast<std::size_t>(xx) * static_cast<std::size_t>(ksize)];
        for (int x = 0; x < xmax; ++x) {
            const double w = lanczosFilter((x + xmin - center + 0.5) * ss);
            k[x] = w;
            ww += w;
        }

        for (int x = 0; x < xmax; ++x) {
            if (!exactlyEqual(ww, 0.0)) {
                k[x] /= ww;
            }
        }

        result.bounds[static_cast<std::size_t>(xx) * 2] = xmin;
        result.bounds[static_cast<std::size_t>(xx) * 2 + 1] = xmax;
    }

    return result;
}

std::vector<std::int32_t> normalizeCoeffs(const std::vector<double>& prekk) {
    std::vector<std::int32_t> kk(prekk.size());
    for (std::size_t x = 0; x < prekk.size(); ++x) {
        if (prekk[x] < 0) {
            kk[x] = static_cast<std::int32_t>(-0.5 + prekk[x] * (1 << kPrecisionBits));
        } else {
            kk[x] = static_cast<std::int32_t>(0.5 + prekk[x] * (1 << kPrecisionBits));
        }
    }

    return kk;
}

std::uint8_t clip8(std::int32_t value) {
    return static_cast<std::uint8_t>(std::clamp(value >> kPrecisionBits, 0, 255));
}

Plane resampleHorizontal(const Plane& in, int outWidth, int offset, int outHeight, const Coefficients& coeffs) {
    const std::vector<std::int32_t> kk = normalizeCoeffs(coeffs.kk);
    Plane out;
    out.width = outWidth;
    out.height = outHeight;
    out.rgb.resize(static_cast<std::size_t>(outWidth) * static_cast<std::size_t>(outHeight) * 3);

    for (int yy = 0; yy < outHeight; ++yy) {
        const std::uint8_t* source = in.row(yy + offset);
        for (int xx = 0; xx < outWidth; ++xx) {
            const int xmin = coeffs.bounds[static_cast<std::size_t>(xx) * 2];
            const int xmax = coeffs.bounds[static_cast<std::size_t>(xx) * 2 + 1];
            const std::int32_t* k = &kk[static_cast<std::size_t>(xx) * static_cast<std::size_t>(coeffs.ksize)];
            std::int32_t ss0 = 1 << (kPrecisionBits - 1);
            std::int32_t ss1 = ss0;
            std::int32_t ss2 = ss0;
            for (int x = 0; x < xmax; ++x) {
                const std::uint8_t* pixel = source + static_cast<std::size_t>(x + xmin) * 3;
                ss0 += pixel[0] * k[x];
                ss1 += pixel[1] * k[x];
                ss2 += pixel[2] * k[x];
            }

            std::uint8_t* target = out.row(yy) + static_cast<std::size_t>(xx) * 3;
            target[0] = clip8(ss0);
            target[1] = clip8(ss1);
            target[2] = clip8(ss2);
        }
    }

    return out;
}

Plane resampleVertical(const Plane& in, int outHeight, const Coefficients& coeffs) {
    const std::vector<std::int32_t> kk = normalizeCoeffs(coeffs.kk);
    Plane out;
    out.width = in.width;
    out.height = outHeight;
    out.rgb.resize(static_cast<std::size_t>(in.width) * static_cast<std::size_t>(outHeight) * 3);

    for (int yy = 0; yy < outHeight; ++yy) {
        const std::int32_t* k = &kk[static_cast<std::size_t>(yy) * static_cast<std::size_t>(coeffs.ksize)];
        const int ymin = coeffs.bounds[static_cast<std::size_t>(yy) * 2];
        const int ymax = coeffs.bounds[static_cast<std::size_t>(yy) * 2 + 1];
        for (int xx = 0; xx < in.width; ++xx) {
            std::int32_t ss0 = 1 << (kPrecisionBits - 1);
            std::int32_t ss1 = ss0;
            std::int32_t ss2 = ss0;
            for (int y = 0; y < ymax; ++y) {
                const std::uint8_t* pixel = in.row(y + ymin) + static_cast<std::size_t>(xx) * 3;
                ss0 += pixel[0] * k[y];
                ss1 += pixel[1] * k[y];
                ss2 += pixel[2] * k[y];
            }

            std::uint8_t* target = out.row(yy) + static_cast<std::size_t>(xx) * 3;
            target[0] = clip8(ss0);
            target[1] = clip8(ss1);
            target[2] = clip8(ss2);
        }
    }

    return out;
}

// ImagingResample: horizontal then vertical, each skipped when it would be the identity.
Plane resample(const Plane& in, int xsize, int ysize, const Box& box) {
    const bool needHorizontal =
        xsize != in.width || !exactlyEqual(box.x0, 0) || !exactlyEqual(box.x1, static_cast<float>(xsize));
    const bool needVertical =
        ysize != in.height || !exactlyEqual(box.y0, 0) || !exactlyEqual(box.y1, static_cast<float>(ysize));

    const Coefficients horizontal = precomputeCoeffs(in.width, box.x0, box.x1, xsize);
    Coefficients vertical = precomputeCoeffs(in.height, box.y0, box.y1, ysize);

    const int yboxFirst = vertical.bounds[0];
    const int yboxLast = vertical.bounds[static_cast<std::size_t>(ysize) * 2 - 2] +
        vertical.bounds[static_cast<std::size_t>(ysize) * 2 - 1];

    Plane temp;
    const Plane* current = &in;
    if (needHorizontal) {
        for (int i = 0; i < ysize; ++i) {
            vertical.bounds[static_cast<std::size_t>(i) * 2] -= yboxFirst;
        }

        temp = resampleHorizontal(in, xsize, yboxFirst, yboxLast - yboxFirst, horizontal);
        current = &temp;
    }

    if (needVertical) {
        return resampleVertical(*current, ysize, vertical);
    }

    return *current;
}

std::uint32_t divisionUint32(int divider, int resultBits) {
    const std::uint32_t maxDividend = (std::uint32_t{ 1 } << resultBits) * static_cast<std::uint32_t>(divider);
    const float maxInt = 4294967296.0F;
    return static_cast<std::uint32_t>(maxInt / static_cast<float>(maxDividend));
}

// ImagingReduce over the whole image: every output pixel averages its (possibly clipped) block of source pixels.
Plane reduce(const Plane& in, int xscale, int yscale) {
    Plane out;
    out.width = (in.width + xscale - 1) / xscale;
    out.height = (in.height + yscale - 1) / yscale;
    out.rgb.resize(static_cast<std::size_t>(out.width) * static_cast<std::size_t>(out.height) * 3);

    for (int y = 0; y < out.height; ++y) {
        const int yFrom = y * yscale;
        const int yTo = std::min(yFrom + yscale, in.height);
        for (int x = 0; x < out.width; ++x) {
            const int xFrom = x * xscale;
            const int xTo = std::min(xFrom + xscale, in.width);
            const int scale = (xTo - xFrom) * (yTo - yFrom);
            const std::uint32_t multiplier = divisionUint32(scale, 8);
            const std::uint32_t amend = static_cast<std::uint32_t>(scale / 2);
            std::uint32_t ss0 = amend;
            std::uint32_t ss1 = amend;
            std::uint32_t ss2 = amend;
            for (int yy = yFrom; yy < yTo; ++yy) {
                for (int xx = xFrom; xx < xTo; ++xx) {
                    const std::uint8_t* pixel = in.row(yy) + static_cast<std::size_t>(xx) * 3;
                    ss0 += pixel[0];
                    ss1 += pixel[1];
                    ss2 += pixel[2];
                }
            }

            std::uint8_t* target = out.row(y) + static_cast<std::size_t>(x) * 3;
            target[0] = static_cast<std::uint8_t>((ss0 * multiplier) >> 24);
            target[1] = static_cast<std::uint8_t>((ss1 * multiplier) >> 24);
            target[2] = static_cast<std::uint8_t>((ss2 * multiplier) >> 24);
        }
    }

    return out;
}

} // namespace

std::array<int, 3> lanczosMeanPixel(const std::vector<std::uint8_t>& rgb, int width, int height) {
    Plane image{ width, height, rgb };
    if (width <= 1 && height <= 1) {
        return { image.rgb[0], image.rgb[1], image.rgb[2] };
    }

    // thumbnail((1, 1)) always lands on 1x1; resize() then reduces by an integer factor before resampling.
    Box box{ 0, 0, static_cast<float>(width), static_cast<float>(height) };
    const int factorX = std::max(static_cast<int>(width / 2.0), 1);
    const int factorY = std::max(static_cast<int>(height / 2.0), 1);
    if (factorX > 1 || factorY > 1) {
        image = reduce(image, factorX, factorY);
        box = { 0, 0, static_cast<float>(static_cast<double>(width) / factorX),
            static_cast<float>(static_cast<double>(height) / factorY) };
    }

    Plane result;
    if (image.height > image.width * 100) {
        const Plane tall = resample(image, image.width, 1, { 0, box.y0, static_cast<float>(image.width), box.y1 });
        result = resample(tall, 1, 1, { box.x0, 0, box.x1, 1 });
    } else {
        result = resample(image, 1, 1, box);
    }

    return { result.rgb[0], result.rgb[1], result.rgb[2] };
}

} // namespace burl::colour
