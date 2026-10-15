// Derived from materialyoucolor 3.0.2 palettes/tonal_palette.py, temperature/temperature_cache.py,
// dislike/dislike_analyzer.py and contrast/contrast.py (MIT, Ansh Dadwal), itself a port of Google's material-color-utilities (Apache-2.0).
// Licenses: cli/third_party/material-color-utilities/LICENSE*.

#include "palette.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <stdexcept>

namespace burl::colour {

namespace {

class KeyColor {
public:
    KeyColor(double hue, double requestedChroma)
        : mHue(hue)
        , mRequestedChroma(requestedChroma) {}

    Hct create() {
        constexpr int pivotTone = 50;
        constexpr int toneStepSize = 1;
        constexpr double epsilon = 0.01;
        int lowerTone = 0;
        int upperTone = 100;
        while (lowerTone < upperTone) {
            const int midTone = (lowerTone + upperTone) / 2;
            const bool isAscending = this->maxChroma(midTone) < this->maxChroma(midTone + toneStepSize);
            const bool sufficientChroma = this->maxChroma(midTone) >= this->mRequestedChroma - epsilon;

            if (sufficientChroma) {
                if (std::abs(lowerTone - pivotTone) < std::abs(upperTone - pivotTone)) {
                    upperTone = midTone;
                } else {
                    if (lowerTone == midTone) {
                        return Hct::fromHct(this->mHue, this->mRequestedChroma, static_cast<double>(lowerTone));
                    }

                    lowerTone = midTone;
                }
            } else if (isAscending) {
                lowerTone = midTone + toneStepSize;
            } else {
                upperTone = midTone;
            }
        }

        return Hct::fromHct(this->mHue, this->mRequestedChroma, static_cast<double>(lowerTone));
    }

private:
    double maxChroma(int tone) {
        const auto it = this->mChromaCache.find(tone);
        if (it != this->mChromaCache.end()) {
            return it->second;
        }

        const double chroma = Hct::fromHct(this->mHue, 200.0, static_cast<double>(tone)).chroma();
        this->mChromaCache.emplace(tone, chroma);
        return chroma;
    }

    double mHue;
    double mRequestedChroma;
    std::map<int, double> mChromaCache;
};

std::uint32_t averageArgb(std::uint32_t argb1, std::uint32_t argb2) {
    const auto average = [](std::uint32_t a, std::uint32_t b) {
        return static_cast<int>(pyRound(static_cast<double>(a + b) / 2));
    };
    const int red = average((argb1 >> 16) & 0xFF, (argb2 >> 16) & 0xFF);
    const int green = average((argb1 >> 8) & 0xFF, (argb2 >> 8) & 0xFF);
    const int blue = average(argb1 & 0xFF, argb2 & 0xFF);
    return argbFromRgb(red, green, blue);
}

bool isBetween(double angle, double a, double b) {
    if (a < b) {
        return a <= angle && angle <= b;
    }

    return a <= angle || angle <= b;
}

double rawTemperature(const Hct& color) {
    const Vec3 lab = labFromArgb(color.toInt());
    const double hue = sanitizeDegrees(std::atan2(lab[2], lab[1]) * 180.0 / std::numbers::pi);
    const double chroma = std::sqrt((lab[1] * lab[1]) + (lab[2] * lab[2]));
    return -0.5 + 0.02 * std::pow(chroma, 1.07) * std::cos(sanitizeDegrees(hue - 50.0) * std::numbers::pi / 180.0);
}

} // namespace

TonalPalette::TonalPalette(double hue, double chroma, const Hct& keyColor)
    : mHue(hue)
    , mChroma(chroma)
    , mKeyColor(keyColor) {}

TonalPalette TonalPalette::fromHct(const Hct& hct) {
    return TonalPalette(hct.hue(), hct.chroma(), hct);
}

TonalPalette TonalPalette::fromHueAndChroma(double hue, double chroma) {
    return TonalPalette(hue, chroma, KeyColor(hue, chroma).create());
}

std::uint32_t TonalPalette::tone(double tone) const {
    const auto it = this->mCache.find(tone);
    if (it != this->mCache.end()) {
        return it->second;
    }

    std::uint32_t argb = 0;
    if (exactlyEqual(tone, 99) && Hct::isYellow(this->mHue)) {
        argb = averageArgb(this->tone(98), this->tone(100));
    } else {
        argb = Hct::fromHct(this->mHue, this->mChroma, tone).toInt();
    }

    this->mCache.emplace(tone, argb);
    return argb;
}

Hct TonalPalette::getHct(double tone) const {
    return Hct::fromInt(this->tone(tone));
}

bool isDisliked(const Hct& hct) {
    const bool huePasses = pyRound(hct.hue()) >= 90.0 && pyRound(hct.hue()) <= 111.0;
    const bool chromaPasses = pyRound(hct.chroma()) > 16.0;
    const bool tonePasses = pyRound(hct.tone()) < 65.0;
    return huePasses && chromaPasses && tonePasses;
}

Hct fixIfDisliked(const Hct& hct) {
    if (isDisliked(hct)) {
        return Hct::fromHct(hct.hue(), hct.chroma(), 70.0);
    }

    return hct;
}

namespace contrast {

namespace {

double ratioOfYs(double y1, double y2) {
    const double lighterY = std::max(y1, y2);
    const double darkerY = exactlyEqual(lighterY, y2) ? y1 : y2;
    return (lighterY + 5.0) / (darkerY + 5.0);
}

} // namespace

double ratioOfTones(double toneA, double toneB) {
    toneA = clampDouble(0.0, 100.0, toneA);
    toneB = clampDouble(0.0, 100.0, toneB);
    return ratioOfYs(yFromLstar(toneA), yFromLstar(toneB));
}

double lighter(double tone, double ratio) {
    if (tone < 0.0 || tone > 100.0) {
        return -1.0;
    }

    const double darkY = yFromLstar(tone);
    const double lightY = ratio * (darkY + 5.0) - 5.0;
    const double realContrast = ratioOfYs(lightY, darkY);
    const double delta = std::abs(realContrast - ratio);
    if (realContrast < ratio && delta > 0.04) {
        return -1.0;
    }

    const double returnValue = lstarFromY(lightY) + 0.4;
    if (returnValue < 0 || returnValue > 100) {
        return -1.0;
    }

    return returnValue;
}

double darker(double tone, double ratio) {
    if (tone < 0.0 || tone > 100.0) {
        return -1.0;
    }

    const double lightY = yFromLstar(tone);
    const double darkY = ((lightY + 5.0) / ratio) - 5.0;
    const double realContrast = ratioOfYs(lightY, darkY);

    const double delta = std::abs(realContrast - ratio);
    if (realContrast < ratio && delta > 0.04) {
        return -1.0;
    }

    const double returnValue = lstarFromY(darkY) - 0.4;
    if (returnValue < 0.0 || returnValue > 100.0) {
        return -1.0;
    }

    return returnValue;
}

double lighterUnsafe(double tone, double ratio) {
    const double lighterSafe = lighter(tone, ratio);
    return lighterSafe < 0.0 ? 100.0 : lighterSafe;
}

double darkerUnsafe(double tone, double ratio) {
    const double darkerSafe = darker(tone, ratio);
    return darkerSafe < 0.0 ? 0.0 : darkerSafe;
}

} // namespace contrast

TemperatureCache::TemperatureCache(const Hct& input)
    : mInput(input) {}

const std::vector<Hct>& TemperatureCache::hctsByHue() {
    if (this->mAll.empty()) {
        this->mAll.reserve(362);
        for (int hue = 0; hue <= 360; ++hue) {
            this->mAll.push_back(Hct::fromHct(static_cast<double>(hue), this->mInput.chroma(), this->mInput.tone()));
        }

        this->mAll.push_back(this->mInput);
    }

    return this->mAll;
}

const std::vector<double>& TemperatureCache::temps() {
    if (this->mTemps.empty()) {
        for (const Hct& hct : this->hctsByHue()) {
            this->mTemps.push_back(rawTemperature(hct));
        }
    }

    return this->mTemps;
}

const std::vector<std::size_t>& TemperatureCache::hctsByTemp() {
    if (this->mByTemp.empty()) {
        const auto& temperatures = this->temps();
        this->mByTemp.resize(temperatures.size());
        for (std::size_t i = 0; i < this->mByTemp.size(); ++i) {
            this->mByTemp[i] = i;
        }

        std::stable_sort(this->mByTemp.begin(), this->mByTemp.end(), [&temperatures](std::size_t a, std::size_t b) {
            return temperatures[a] < temperatures[b];
        });
    }

    return this->mByTemp;
}

double TemperatureCache::relativeTemperature(std::size_t index) {
    const auto& temperatures = this->temps();
    const auto& order = this->hctsByTemp();
    const double coldest = temperatures[order.front()];
    const double rangeTemp = temperatures[order.back()] - coldest;
    const double differenceFromColdest = temperatures[index] - coldest;
    if (exactlyEqual(rangeTemp, 0.0)) {
        return 0.5;
    }

    return differenceFromColdest / rangeTemp;
}

double TemperatureCache::inputRelativeTemperature() {
    if (this->mInputRelativeTemperature >= 0.0) {
        return this->mInputRelativeTemperature;
    }

    this->mInputRelativeTemperature = this->relativeTemperature(this->hctsByHue().size() - 1);
    return this->mInputRelativeTemperature;
}

std::vector<Hct> TemperatureCache::analogous(int count, int divisions) {
    const auto& byHue = this->hctsByHue();
    const int startHue = static_cast<int>(pyRound(this->mInput.hue()));
    const std::size_t startIndex = static_cast<std::size_t>(startHue);
    double lastTemp = this->relativeTemperature(startIndex);
    std::vector<std::size_t> allColors = { startIndex };

    double absoluteTotalTempDelta = 0.0;
    for (int i = 0; i < 360; ++i) {
        const std::size_t index = static_cast<std::size_t>(sanitizeDegreesInt(startHue + i));
        const double temp = this->relativeTemperature(index);
        const double tempDelta = std::abs(temp - lastTemp);
        lastTemp = temp;
        absoluteTotalTempDelta += tempDelta;
    }

    int hueAddend = 1;
    const double tempStep = absoluteTotalTempDelta / divisions;
    double totalTempDelta = 0.0;
    lastTemp = this->relativeTemperature(startIndex);

    while (static_cast<int>(allColors.size()) < divisions) {
        const std::size_t index = static_cast<std::size_t>(sanitizeDegreesInt(startHue + hueAddend));
        const double temp = this->relativeTemperature(index);
        const double tempDelta = std::abs(temp - lastTemp);
        totalTempDelta += tempDelta;

        double desiredTotalTempDeltaForIndex = static_cast<double>(allColors.size()) * tempStep;
        bool indexSatisfied = totalTempDelta >= desiredTotalTempDeltaForIndex;
        int indexAddend = 1;

        while (indexSatisfied && static_cast<int>(allColors.size()) < divisions) {
            allColors.push_back(index);
            desiredTotalTempDeltaForIndex =
                static_cast<double>(static_cast<int>(allColors.size()) + indexAddend) * tempStep;
            indexSatisfied = totalTempDelta >= desiredTotalTempDeltaForIndex;
            ++indexAddend;
        }

        lastTemp = temp;
        ++hueAddend;

        if (hueAddend > 360) {
            while (static_cast<int>(allColors.size()) < divisions) {
                allColors.push_back(index);
            }

            break;
        }
    }

    std::vector<Hct> answers = { this->mInput };
    const int size = static_cast<int>(allColors.size());

    const int increaseHueCount = static_cast<int>(std::floor((count - 1) / 2.0));
    for (int i = 1; i <= increaseHueCount; ++i) {
        int index = 0 - i;
        while (index < 0) {
            index = size + index;
        }

        if (index >= size) {
            index = index % size;
        }

        answers.insert(answers.begin(), byHue[allColors[static_cast<std::size_t>(index)]]);
    }

    const int decreaseHueCount = count - increaseHueCount - 1;
    for (int i = 1; i <= decreaseHueCount; ++i) {
        int index = i;
        while (index < 0) {
            index = size + index;
        }

        if (index >= size) {
            index = index % size;
        }

        answers.push_back(byHue[allColors[static_cast<std::size_t>(index)]]);
    }

    return answers;
}

Hct TemperatureCache::complement() {
    const auto& byHue = this->hctsByHue();
    const auto& temperatures = this->temps();
    const auto& order = this->hctsByTemp();

    const std::size_t coldest = order.front();
    const std::size_t warmest = order.back();
    const double coldestHue = byHue[coldest].hue();
    const double coldestTemp = temperatures[coldest];
    const double warmestHue = byHue[warmest].hue();
    const double warmestTemp = temperatures[warmest];
    const double rangeTemp = warmestTemp - coldestTemp;
    const bool startHueIsColdestToWarmest = isBetween(this->mInput.hue(), coldestHue, warmestHue);
    const double startHue = startHueIsColdestToWarmest ? warmestHue : coldestHue;
    const double endHue = startHueIsColdestToWarmest ? coldestHue : warmestHue;
    const double directionOfRotation = 1.0;
    double smallestError = 1000.0;
    std::size_t answer = static_cast<std::size_t>(pyRound(this->mInput.hue()));

    const double complementRelativeTemp = 1.0 - this->inputRelativeTemperature();
    for (int hueAddend = 0; hueAddend <= 360; ++hueAddend) {
        const double hue = sanitizeDegrees(startHue + directionOfRotation * hueAddend);
        if (!isBetween(hue, startHue, endHue)) {
            continue;
        }

        const std::size_t possibleAnswer = static_cast<std::size_t>(pyRound(hue));
        if (exactlyEqual(rangeTemp, 0.0)) {
            throw std::domain_error("temperature range is zero");
        }

        const double relativeTemp = (temperatures[possibleAnswer] - coldestTemp) / rangeTemp;
        const double error = std::abs(complementRelativeTemp - relativeTemp);
        if (error < smallestError) {
            smallestError = error;
            answer = possibleAnswer;
        }
    }

    return byHue[answer];
}

} // namespace burl::colour
