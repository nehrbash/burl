#pragma once

#include "hct.hpp"

#include <cstdint>
#include <map>
#include <vector>

// Port of materialyoucolor 3.0.2 (palettes/tonal_palette.py, temperature/temperature_cache.py,
// dislike/dislike_analyzer.py, contrast/contrast.py), itself a port of Google's material-color-utilities (Apache-2.0).
namespace burl::colour {

class TonalPalette {
public:
    static TonalPalette fromHct(const Hct& hct);
    static TonalPalette fromHueAndChroma(double hue, double chroma);

    double hue() const { return this->mHue; }

    double chroma() const { return this->mChroma; }

    const Hct& keyColor() const { return this->mKeyColor; }

    std::uint32_t tone(double tone) const;
    Hct getHct(double tone) const;

private:
    TonalPalette(double hue, double chroma, const Hct& keyColor);

    double mHue;
    double mChroma;
    Hct mKeyColor;
    mutable std::map<double, std::uint32_t> mCache;
};

bool isDisliked(const Hct& hct);
Hct fixIfDisliked(const Hct& hct);

namespace contrast {

double ratioOfTones(double toneA, double toneB);
double lighter(double tone, double ratio);
double darker(double tone, double ratio);
double lighterUnsafe(double tone, double ratio);
double darkerUnsafe(double tone, double ratio);

} // namespace contrast

class TemperatureCache {
public:
    explicit TemperatureCache(const Hct& input);

    std::vector<Hct> analogous(int count, int divisions);

    // Throws std::domain_error for achromatic input (division by zero).
    Hct complement();

private:
    const std::vector<Hct>& hctsByHue();
    const std::vector<double>& temps();
    const std::vector<std::size_t>& hctsByTemp();
    double relativeTemperature(std::size_t index);
    double inputRelativeTemperature();

    // hctsByHue() followed by the input colour; temperatures and the temperature order index into this.
    std::vector<Hct> mAll;
    std::vector<double> mTemps;
    std::vector<std::size_t> mByTemp;
    double mInputRelativeTemperature = -1.0;
    Hct mInput;
};

} // namespace burl::colour
