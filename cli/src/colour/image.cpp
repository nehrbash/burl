// Derived from burl/utils/colourfulness.py, burl/utils/material/score.py, and materialyoucolor 3.0.2 quantize/celebi.cc
// and score/score.py (MIT, Ansh Dadwal), itself a port of Google's material-color-utilities (Apache-2.0).
// Licenses: cli/third_party/material-color-utilities/LICENSE*.

#include "colour.hpp"
#include "dynamic.hpp"
#include "hct.hpp"
#include "palette.hpp"
#include "resample.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
#include <map>
#include <stdexcept>

#include <QtGui/QImage>
#include <QtGui/QImageReader>

#include "wsmeans.h"
#include "wu.h"

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

namespace burl::colour {

namespace {

struct StbPixels {
    unsigned char* data = nullptr;
    int width = 0;
    int height = 0;
    int channels = 0;

    explicit StbPixels(const std::string& path) {
        this->data = stbi_load(path.c_str(), &this->width, &this->height, &this->channels, 4);
    }

    ~StbPixels() { stbi_image_free(this->data); }

    StbPixels(const StbPixels&) = delete;
    StbPixels& operator=(const StbPixels&) = delete;
};

// The pixel list materialyoucolor's ImageQuantizeCelebi(path, 1, n) feeds the quantizer. Alpha is dropped, not
// composited.
std::vector<std::uint32_t> celebiPixels(const StbPixels& image) {
    std::vector<std::uint32_t> pixels;
    pixels.reserve(static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height));
    for (std::ptrdiff_t i = 0; i < static_cast<std::ptrdiff_t>(image.width) * image.height; ++i) {
        const unsigned char* pixel = image.data + i * 4;
        pixels.push_back(static_cast<std::uint32_t>(pixel[0]) << 16 | static_cast<std::uint32_t>(pixel[1]) << 8 |
            static_cast<std::uint32_t>(pixel[2]));
    }

    return pixels;
}

std::map<std::uint32_t, std::uint32_t> quantizeCelebi(const std::vector<std::uint32_t>& pixels, int maxColors) {
    const auto wuResult = material_color_utilities::QuantizeWu(pixels, static_cast<std::uint16_t>(maxColors));
    return material_color_utilities::QuantizeWsmeans(pixels, wuResult, static_cast<std::uint16_t>(maxColors))
        .color_to_count;
}

constexpr double kTargetChroma = 48.0;
constexpr double kWeightProportion = 0.7;
constexpr double kWeightChromaAbove = 0.3;
constexpr double kWeightChromaBelow = 0.1;

// Score.score(colors_to_population, filter_enabled=False): no colour is filtered out; throws when none has chroma.
Hct score(const std::map<std::uint32_t, std::uint32_t>& colorsToPopulation) {
    std::vector<Hct> colorsHct;
    std::array<std::uint64_t, 360> huePopulation{};
    std::uint64_t populationSum = 0;

    for (const auto& [rgb, population] : colorsToPopulation) {
        const Hct hct = Hct::fromInt(rgb);
        colorsHct.push_back(hct);
        huePopulation[static_cast<std::size_t>(static_cast<int>(hct.hue()))] += population;
        populationSum += population;
    }

    if (populationSum == 0) {
        throw std::runtime_error("image has no pixels");
    }

    std::array<double, 360> hueExcitedProportions{};
    for (int hue = 0; hue < 360; ++hue) {
        const double proportion =
            static_cast<double>(huePopulation[static_cast<std::size_t>(hue)]) / static_cast<double>(populationSum);
        for (int i = hue - 14; i < hue + 16; ++i) {
            hueExcitedProportions[static_cast<std::size_t>(sanitizeDegreesInt(i))] += proportion;
        }
    }

    struct Scored {
        const Hct* hct;
        double score;
    };
    std::vector<Scored> scoredHct;
    for (const Hct& hct : colorsHct) {
        const int hue = sanitizeDegreesInt(static_cast<int>(pyRound(hct.hue())));
        const double proportion = hueExcitedProportions[static_cast<std::size_t>(hue)];
        const double proportionScore = proportion * 100.0 * kWeightProportion;
        const double chromaWeight = hct.chroma() < kTargetChroma ? kWeightChromaBelow : kWeightChromaAbove;
        const double chromaScore = (hct.chroma() - kTargetChroma) * chromaWeight;
        scoredHct.push_back({ &hct, proportionScore + chromaScore });
    }

    std::stable_sort(scoredHct.begin(), scoredHct.end(), [](const Scored& a, const Scored& b) {
        return a.score > b.score;
    });

    for (int cutoff = 20; cutoff >= 0; --cutoff) {
        for (const Scored& item : scoredHct) {
            if (item.hct->chroma() > cutoff && item.hct->tone() > cutoff * 3) {
                return fixIfDisliked(*item.hct);
            }
        }
    }

    throw std::runtime_error("image has no colour with chroma");
}

bool isJpeg(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    unsigned char magic[3] = {};
    file.read(reinterpret_cast<char*>(magic), sizeof(magic));
    return file.gcount() == 3 && magic[0] == 0xFF && magic[1] == 0xD8 && magic[2] == 0xFF;
}

// Qt's JPEG decoder is libjpeg like Pillow's; stb's differs in the last bits of the IDCT and chroma upsampling.
Image loadWithQt(const std::string& path) {
    QImageReader reader(QString::fromStdString(path));
    QImage decoded = reader.read();
    if (decoded.isNull()) {
        throw std::runtime_error("cannot decode image " + path + ": " + reader.errorString().toStdString());
    }

    decoded = decoded.convertToFormat(QImage::Format_ARGB32);
    Image image;
    image.width = decoded.width();
    image.height = decoded.height();
    image.argb.reserve(static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height));
    for (int y = 0; y < image.height; ++y) {
        const auto* line = reinterpret_cast<const QRgb*>(decoded.constScanLine(y));
        image.argb.insert(image.argb.end(), line, line + image.width);
    }

    return image;
}

Image loadWithStb(const StbPixels& pixels) {
    Image image;
    image.width = pixels.width;
    image.height = pixels.height;
    image.argb.reserve(static_cast<std::size_t>(pixels.width) * static_cast<std::size_t>(pixels.height));
    for (std::ptrdiff_t i = 0; i < static_cast<std::ptrdiff_t>(pixels.width) * pixels.height; ++i) {
        const unsigned char* pixel = pixels.data + i * 4;
        image.argb.push_back(static_cast<std::uint32_t>(pixel[3]) << 24 | static_cast<std::uint32_t>(pixel[0]) << 16 |
            static_cast<std::uint32_t>(pixel[1]) << 8 | static_cast<std::uint32_t>(pixel[2]));
    }

    return image;
}

} // namespace

Image loadImage(const std::string& path) {
    if (isJpeg(path)) {
        return loadWithQt(path);
    }

    const StbPixels pixels(path);
    if (pixels.data) {
        return loadWithStb(pixels);
    }

    return loadWithQt(path);
}

std::uint32_t scoreImage(const std::string& path) {
    const StbPixels pixels(path);
    if (!pixels.data) {
        throw std::runtime_error("cannot decode image " + path);
    }

    return score(quantizeCelebi(celebiPixels(pixels), 128)).toInt();
}

namespace {

// CPython 3.12's sum() over floats: Neumaier-compensated.
double pySum(const std::vector<double>& values) {
    if (values.empty()) {
        return 0.0;
    }

    double result = values[0];
    double c = 0.0;
    for (std::size_t i = 1; i < values.size(); ++i) {
        const double x = values[i];
        const double t = result + x;
        if (std::abs(result) >= std::abs(x)) {
            c += (result - t) + x;
        } else {
            c += (x - t) + result;
        }

        result = t;
    }

    if (!exactlyEqual(c, 0.0) && std::abs(c) <= std::numeric_limits<double>::max()) {
        result += c;
    }

    return result;
}

// Calls libm through a pointer so the compiler cannot rewrite pow(x, 2) as x * x.
double pyPow(double base, double exponent) {
    static double (*const volatile pow)(double, double) = static_cast<double (*)(double, double)>(&std::pow);
    return pow(base, exponent);
}

double mean(const std::vector<double>& values) {
    return values.empty() ? 0 : pySum(values) / static_cast<double>(values.size());
}

double stddev(const std::vector<double>& values, double meanValue) {
    if (values.empty()) {
        return 0;
    }

    std::vector<double> squares;
    squares.reserve(values.size());
    for (const double x : values) {
        squares.push_back(pyPow(x - meanValue, 2));
    }

    return std::sqrt(pySum(squares) / static_cast<double>(values.size()));
}

} // namespace

double colourfulness(const Image& image) {
    std::vector<double> rgDiffs;
    std::vector<double> ybDiffs;
    rgDiffs.reserve(image.argb.size());
    ybDiffs.reserve(image.argb.size());

    for (const std::uint32_t argb : image.argb) {
        const int r = static_cast<int>((argb >> 16) & 0xFF);
        const int g = static_cast<int>((argb >> 8) & 0xFF);
        const int b = static_cast<int>(argb & 0xFF);
        rgDiffs.push_back(std::abs(r - g));
        ybDiffs.push_back(std::abs(0.5 * (r + g) - b));
    }

    const double meanRg = mean(rgDiffs);
    const double meanYb = mean(ybDiffs);
    const double stdRg = stddev(rgDiffs, meanRg);
    const double stdYb = stddev(ybDiffs, meanYb);

    return std::sqrt(pyPow(stdRg, 2) + pyPow(stdYb, 2)) +
        0.3 * std::sqrt(pyPow(meanRg, 2) + pyPow(meanYb, 2));
}

std::string variantFor(const Image& image) {
    const double value = colourfulness(image);
    if (value < 10) {
        return "neutral";
    }

    if (value < 20) {
        return "content";
    }

    return "tonalspot";
}

std::string modeFor(const Image& image) {
    if (image.width <= 0 || image.height <= 0) {
        throw std::runtime_error("empty image");
    }

    std::vector<std::uint8_t> rgb;
    rgb.reserve(image.argb.size() * 3);
    for (const std::uint32_t argb : image.argb) {
        rgb.push_back(static_cast<std::uint8_t>((argb >> 16) & 0xFF));
        rgb.push_back(static_cast<std::uint8_t>((argb >> 8) & 0xFF));
        rgb.push_back(static_cast<std::uint8_t>(argb & 0xFF));
    }

    const auto pixel = lanczosMeanPixel(rgb, image.width, image.height);
    const Hct hct = Hct::fromInt(argbFromRgb(pixel[0], pixel[1], pixel[2]));
    return hct.tone() > 60 ? "light" : "dark";
}

} // namespace burl::colour
