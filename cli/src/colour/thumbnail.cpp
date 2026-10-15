// Derived from Pillow 12.2.0 (MIT-CMU, cli/third_party/pillow/LICENSE): Image.thumbnail/resize in Image.py, the nearest
// neighbour ImagingScaleAffine in src/libImaging/Geometry.c, and the JPEG save path (JpegImagePlugin.py, JpegEncode.c).

#include "colour.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <stdexcept>

#include <QtGui/QImage>
#include <QtGui/QImageReader>

#include <jpeglib.h>

namespace burl::colour {

namespace {

constexpr int kBox = 128;

struct Rgb {
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> data; // packed R, G, B
};

// Image.thumbnail's aspect-preserving rounding.
std::pair<int, int> thumbnailSize(int width, int height) {
    if (kBox >= width && kBox >= height) {
        return { width, height };
    }

    const double aspect = static_cast<double>(width) / height;
    const auto pick = [](double number, const auto& key) {
        const double floor = std::floor(number);
        const double ceil = std::ceil(number);
        return std::max(static_cast<int>(key(ceil) < key(floor) ? ceil : floor), 1);
    };

    int x = kBox;
    int y = kBox;
    if (x / static_cast<double>(y) >= aspect) {
        x = pick(y * aspect, [&](double n) { return std::abs(aspect - n / y); });
    } else {
        y = pick(x / aspect, [&](double n) { return n < 0.5 ? 0.0 : std::abs(aspect - x / n); });
    }

    return { x, y };
}

int coord(double value) {
    return value < 0.0 ? -1 : static_cast<int>(value);
}

// ImagingScaleAffine for the box (x0, y0, x1, y1) of `in`, with Pillow's accumulated double positions.
Rgb nearest(const Rgb& in, int xsize, int ysize, float x0, float y0, float x1, float y1) {
    const double scaleX = static_cast<double>(x1 - x0) / xsize;
    const double scaleY = static_cast<double>(y1 - y0) / ysize;

    std::vector<int> columns(static_cast<std::size_t>(xsize), -1);
    double xo = static_cast<double>(x0) + scaleX * 0.5;
    for (int x = 0; x < xsize; ++x) {
        const int xin = coord(xo);
        if (xin >= 0 && xin < in.width) {
            columns[static_cast<std::size_t>(x)] = xin;
        }

        xo += scaleX;
    }

    Rgb out{ xsize, ysize, std::vector<std::uint8_t>(static_cast<std::size_t>(xsize) * static_cast<std::size_t>(ysize) * 3) };
    double yo = static_cast<double>(y0) + scaleY * 0.5;
    for (int y = 0; y < ysize; ++y) {
        const int yin = coord(yo);
        if (yin >= 0 && yin < in.height) {
            const std::uint8_t* source = in.data.data() + static_cast<std::size_t>(yin) * static_cast<std::size_t>(in.width) * 3;
            std::uint8_t* target = out.data.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(xsize) * 3;
            for (int x = 0; x < xsize; ++x) {
                const int column = columns[static_cast<std::size_t>(x)];
                if (column >= 0) {
                    std::copy_n(source + static_cast<std::size_t>(column) * 3, 3, target + static_cast<std::size_t>(x) * 3);
                }
            }
        }

        yo += scaleY;
    }

    return out;
}

// Image.resize(size, NEAREST): very tall images are resized in two passes.
Rgb resizeNearest(const Rgb& in, int xsize, int ysize) {
    const auto w = static_cast<float>(in.width);
    const auto h = static_cast<float>(in.height);
    if (in.height > in.width * 100 && ysize < in.height) {
        const Rgb tall = nearest(in, in.width, ysize, 0, 0, w, h);
        return nearest(tall, xsize, ysize, 0, 0, w, static_cast<float>(ysize));
    }

    return nearest(in, xsize, ysize, 0, 0, w, h);
}

// Pillow's RGB conversion keeps the colour channels of an alpha image and takes the high byte of 16-bit samples.
Rgb decode(const std::string& path) {
    QImageReader reader(QString::fromStdString(path));
    reader.setAutoTransform(false);
    QImage decoded = reader.read();
    if (decoded.isNull()) {
        throw std::runtime_error("cannot decode image " + path + ": " + reader.errorString().toStdString());
    }

    Rgb image;
    image.width = decoded.width();
    image.height = decoded.height();
    image.data.resize(static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height) * 3);

    const bool wide = decoded.format() == QImage::Format_RGBA64 || decoded.format() == QImage::Format_RGBX64;
    if (!wide) {
        decoded = decoded.convertToFormat(QImage::Format_RGBA8888);
    }

    const std::size_t channels = wide ? 8 : 4;
    for (int y = 0; y < image.height; ++y) {
        const uchar* line = decoded.constScanLine(y);
        std::uint8_t* target = image.data.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) * 3;
        for (int x = 0; x < image.width; ++x) {
            const uchar* pixel = line + static_cast<std::size_t>(x) * channels;
            for (std::size_t c = 0; c < 3; ++c) {
                // quint16 samples are in host byte order; the high byte is the second on little endian.
                target[static_cast<std::size_t>(x) * 3 + c] = wide
                    ? static_cast<std::uint8_t>(reinterpret_cast<const quint16*>(pixel)[c] >> 8)
                    : pixel[c];
            }
        }
    }

    return image;
}

// info["comment"] as Pillow's JPEG plugin reads it: the last COM segment before the first scan.
std::vector<std::uint8_t> jpegComment(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    const std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (bytes.size() < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        return {};
    }

    std::vector<std::uint8_t> comment;
    std::size_t at = 2;
    while (at + 4 <= bytes.size()) {
        if (bytes[at] != 0xFF) {
            ++at;
            continue;
        }

        const std::uint8_t marker = bytes[at + 1];
        if (marker == 0xFF) {
            ++at;
            continue;
        }

        if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
            at += 2;
            continue;
        }

        const std::size_t length = static_cast<std::size_t>(bytes[at + 2]) << 8 | bytes[at + 3];
        if (marker == 0xDA || length < 2 || at + 2 + length > bytes.size()) {
            break;
        }

        if (marker == 0xFE) {
            comment.assign(bytes.begin() + static_cast<std::ptrdiff_t>(at + 4),
                bytes.begin() + static_cast<std::ptrdiff_t>(at + 2 + length));
        }

        at += 2 + length;
    }

    return comment;
}

struct Compressor {
    jpeg_compress_struct cinfo{};
    jpeg_error_mgr error{};
    unsigned char* buffer = nullptr;
    unsigned long size = 0;

    Compressor() {
        this->cinfo.err = jpeg_std_error(&this->error);
        jpeg_create_compress(&this->cinfo);
    }

    ~Compressor() {
        jpeg_destroy_compress(&this->cinfo);
        std::free(this->buffer);
    }

    Compressor(const Compressor&) = delete;
    Compressor& operator=(const Compressor&) = delete;
};

// Image.save(path, "JPEG") with no options: libjpeg defaults (quality 75, 4:2:0, JFIF), no optimisation.
std::vector<std::uint8_t> encode(const Rgb& image, const std::vector<std::uint8_t>& comment) {
    Compressor compressor;
    jpeg_compress_struct& cinfo = compressor.cinfo;
    jpeg_mem_dest(&cinfo, &compressor.buffer, &compressor.size);
    cinfo.image_width = static_cast<JDIMENSION>(image.width);
    cinfo.image_height = static_cast<JDIMENSION>(image.height);
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    jpeg_start_compress(&cinfo, TRUE);
    if (!comment.empty()) {
        jpeg_write_marker(&cinfo, JPEG_COM, comment.data(), static_cast<unsigned int>(comment.size()));
    }

    for (int y = 0; y < image.height; ++y) {
        const std::uint8_t* row = image.data.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) * 3;
        JSAMPROW rows[1] = { const_cast<JSAMPROW>(row) };
        jpeg_write_scanlines(&cinfo, rows, 1);
    }

    jpeg_finish_compress(&cinfo);
    return { compressor.buffer, compressor.buffer + compressor.size };
}

bool isJpegFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    char magic[3] = {};
    file.read(magic, 3);
    return file.gcount() == 3 && static_cast<unsigned char>(magic[0]) == 0xFF &&
        static_cast<unsigned char>(magic[1]) == 0xD8 && static_cast<unsigned char>(magic[2]) == 0xFF;
}

} // namespace

std::vector<std::uint8_t> thumbnailJpeg(const std::string& path) {
    Rgb image = decode(path);
    const auto [width, height] = thumbnailSize(image.width, image.height);
    if (width != image.width || height != image.height) {
        image = resizeNearest(image, width, height);
    }

    return encode(image, isJpegFile(path) ? jpegComment(path) : std::vector<std::uint8_t>{});
}

} // namespace burl::colour
