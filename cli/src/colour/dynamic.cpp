// Derived from materialyoucolor 3.0.2 dynamiccolor/dynamic_color.py, dynamic_scheme.py, color_spec.py and
// contrast_curve.py (MIT, Ansh Dadwal), itself a port of Google's material-color-utilities (Apache-2.0).
// Licenses: cli/third_party/material-color-utilities/LICENSE*.

#include "dynamic.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace burl::colour {

namespace {

TonalPalette make(double hue, double chroma) {
    return TonalPalette::fromHueAndChroma(hue, chroma);
}

double piecewiseHue(const Hct& source, const std::vector<double>& hueBreakpoints, const std::vector<double>& hues) {
    const std::size_t size = std::min(hueBreakpoints.size() - 1, hues.size());
    const double sourceHue = source.hue();
    for (std::size_t i = 0; i < size; ++i) {
        if (sourceHue >= hueBreakpoints[i] && sourceHue < hueBreakpoints[i + 1]) {
            return sanitizeDegrees(hues[i]);
        }
    }

    return sourceHue;
}

double rotatedHue(const Hct& source, const std::vector<double>& hueBreakpoints, const std::vector<double>& rotations) {
    double rotation = piecewiseHue(source, hueBreakpoints, rotations);
    if (std::min(hueBreakpoints.size() - 1, rotations.size()) == 0) {
        rotation = 0;
    }

    return sanitizeDegrees(source.hue() + rotation);
}

TonalPalette primaryPalette2021(Variant variant, const Hct& source) {
    switch (variant) {
    case Variant::Content:
    case Variant::Fidelity:
        return make(source.hue(), source.chroma());
    case Variant::FruitSalad:
        return make(sanitizeDegrees(source.hue() - 50.0), 48.0);
    case Variant::Monochrome:
        return make(source.hue(), 0.0);
    case Variant::Neutral:
        return make(source.hue(), 12.0);
    case Variant::Rainbow:
        return make(source.hue(), 48.0);
    case Variant::TonalSpot:
        return make(source.hue(), 36.0);
    case Variant::Expressive:
        return make(sanitizeDegrees(source.hue() + 240), 40);
    case Variant::Vibrant:
        return make(source.hue(), 200.0);
    }

    throw std::invalid_argument("unsupported variant");
}

TonalPalette secondaryPalette2021(Variant variant, const Hct& source) {
    switch (variant) {
    case Variant::Content:
    case Variant::Fidelity:
        return make(source.hue(), std::max(source.chroma() - 32.0, source.chroma() * 0.5));
    case Variant::FruitSalad:
        return make(sanitizeDegrees(source.hue() - 50.0), 36.0);
    case Variant::Monochrome:
        return make(source.hue(), 0.0);
    case Variant::Neutral:
        return make(source.hue(), 8.0);
    case Variant::Rainbow:
    case Variant::TonalSpot:
        return make(source.hue(), 16.0);
    case Variant::Expressive:
        return make(rotatedHue(source, { 0, 21, 51, 121, 151, 191, 271, 321, 360 },
                        { 45, 95, 45, 20, 45, 90, 45, 45, 45 }),
            24.0);
    case Variant::Vibrant:
        return make(rotatedHue(source, { 0, 41, 61, 101, 131, 181, 251, 301, 360 },
                        { 18, 15, 10, 12, 15, 18, 15, 12, 12 }),
            24.0);
    }

    throw std::invalid_argument("unsupported variant");
}

TonalPalette tertiaryPalette2021(Variant variant, const Hct& source) {
    switch (variant) {
    case Variant::Content:
        return TonalPalette::fromHct(fixIfDisliked(TemperatureCache(source).analogous(3, 6)[2]));
    case Variant::Fidelity:
        return TonalPalette::fromHct(fixIfDisliked(TemperatureCache(source).complement()));
    case Variant::FruitSalad:
        return make(source.hue(), 36.0);
    case Variant::Monochrome:
        return make(source.hue(), 0.0);
    case Variant::Neutral:
        return make(source.hue(), 16.0);
    case Variant::Rainbow:
    case Variant::TonalSpot:
        return make(sanitizeDegrees(source.hue() + 60.0), 24.0);
    case Variant::Expressive:
        return make(rotatedHue(source, { 0, 21, 51, 121, 151, 191, 271, 321, 360 },
                        { 120, 120, 20, 45, 20, 15, 20, 120, 120 }),
            32.0);
    case Variant::Vibrant:
        return make(rotatedHue(source, { 0, 41, 61, 101, 131, 181, 251, 301, 360 },
                        { 35, 30, 20, 25, 30, 35, 30, 25, 25 }),
            32.0);
    }

    throw std::invalid_argument("unsupported variant");
}

TonalPalette neutralPalette2021(Variant variant, const Hct& source) {
    switch (variant) {
    case Variant::Content:
    case Variant::Fidelity:
        return make(source.hue(), source.chroma() / 8.0);
    case Variant::FruitSalad:
        return make(source.hue(), 10.0);
    case Variant::Monochrome:
    case Variant::Rainbow:
        return make(source.hue(), 0.0);
    case Variant::Neutral:
        return make(source.hue(), 2.0);
    case Variant::TonalSpot:
        return make(source.hue(), 6.0);
    case Variant::Expressive:
        return make(sanitizeDegrees(source.hue() + 15), 8);
    case Variant::Vibrant:
        return make(source.hue(), 10);
    }

    throw std::invalid_argument("unsupported variant");
}

TonalPalette neutralVariantPalette2021(Variant variant, const Hct& source) {
    switch (variant) {
    case Variant::Content:
    case Variant::Fidelity:
        return make(source.hue(), (source.chroma() / 8.0) + 4.0);
    case Variant::FruitSalad:
        return make(source.hue(), 16.0);
    case Variant::Monochrome:
    case Variant::Rainbow:
        return make(source.hue(), 0.0);
    case Variant::Neutral:
        return make(source.hue(), 2.0);
    case Variant::TonalSpot:
        return make(source.hue(), 8.0);
    case Variant::Expressive:
        return make(sanitizeDegrees(source.hue() + 15), 12);
    case Variant::Vibrant:
        return make(source.hue(), 12);
    }

    throw std::invalid_argument("unsupported variant");
}

double expressiveNeutralHue(const Hct& source) {
    return rotatedHue(source, { 0, 71, 124, 253, 278, 300, 360 }, { 10, 0, 10, 0, 10, 0 });
}

double expressiveNeutralChroma(const Hct& source, bool isDark, Platform platform) {
    const double neutralHue = expressiveNeutralHue(source);
    const bool phone = platform == Platform::Phone;
    if (phone && isDark && Hct::isYellow(neutralHue)) {
        return 6;
    }

    if (phone && isDark) {
        return 14;
    }

    return phone ? 18 : 12;
}

double vibrantNeutralHue(const Hct& source) {
    return rotatedHue(source, { 0, 38, 105, 140, 333, 360 }, { -14, 10, -14, 10, -14 });
}

double vibrantNeutralChroma(const Hct& source, Platform platform) {
    const double neutralHue = vibrantNeutralHue(source);
    if (platform == Platform::Phone) {
        return 28;
    }

    return Hct::isBlue(neutralHue) ? 28 : 20;
}

TonalPalette primaryPalette2025(Variant variant, const Hct& source, bool isDark, Platform platform) {
    const bool phone = platform == Platform::Phone;
    switch (variant) {
    case Variant::Neutral:
        if (phone) {
            return make(source.hue(), Hct::isBlue(source.hue()) ? 12 : 8);
        }

        return make(source.hue(), Hct::isBlue(source.hue()) ? 16 : 12);
    case Variant::TonalSpot:
        return make(source.hue(), phone && isDark ? 26 : 32);
    case Variant::Expressive:
        return make(source.hue(), phone && isDark ? 36 : (phone ? 48 : 40));
    case Variant::Vibrant:
        return make(source.hue(), phone ? 74 : 56);
    default:
        return primaryPalette2021(variant, source);
    }
}

TonalPalette secondaryPalette2025(Variant variant, const Hct& source, bool isDark, Platform platform) {
    const bool phone = platform == Platform::Phone;
    switch (variant) {
    case Variant::Neutral:
        if (phone) {
            return make(source.hue(), Hct::isBlue(source.hue()) ? 6 : 4);
        }

        return make(source.hue(), Hct::isBlue(source.hue()) ? 10 : 6);
    case Variant::TonalSpot:
        return make(source.hue(), 16);
    case Variant::Expressive:
        return make(rotatedHue(source, { 0, 105, 140, 204, 253, 278, 300, 333, 360 },
                        { -160, 155, -100, 96, -96, -156, -165, -160 }),
            phone && isDark ? 16 : 24);
    case Variant::Vibrant:
        return make(rotatedHue(source, { 0, 38, 105, 140, 333, 360 }, { -14, 10, -14, 10, -14 }), phone ? 56 : 36);
    default:
        return secondaryPalette2021(variant, source);
    }
}

TonalPalette tertiaryPalette2025(Variant variant, const Hct& source, Platform platform) {
    const bool phone = platform == Platform::Phone;
    switch (variant) {
    case Variant::Neutral:
        return make(rotatedHue(source, { 0, 38, 105, 161, 204, 278, 333, 360 }, { -32, 26, 10, -39, 24, -15, -32 }),
            phone ? 20 : 36);
    case Variant::TonalSpot:
        return make(rotatedHue(source, { 0, 20, 71, 161, 333, 360 }, { -40, 48, -32, 40, -32 }), phone ? 28 : 32);
    case Variant::Expressive:
        return make(rotatedHue(source, { 0, 105, 140, 204, 253, 278, 300, 333, 360 },
                        { -165, 160, -105, 101, -101, -160, -170, -165 }),
            48);
    case Variant::Vibrant:
        return make(rotatedHue(source, { 0, 38, 71, 105, 140, 161, 253, 333, 360 },
                        { -72, 35, 24, -24, 62, 50, 62, -72 }),
            56);
    default:
        return tertiaryPalette2021(variant, source);
    }
}

TonalPalette neutralPalette2025(Variant variant, const Hct& source, bool isDark, Platform platform) {
    const bool phone = platform == Platform::Phone;
    switch (variant) {
    case Variant::Neutral:
        return make(source.hue(), phone ? 1.4 : 6);
    case Variant::TonalSpot:
        return make(source.hue(), phone ? 5 : 10);
    case Variant::Expressive:
        return make(expressiveNeutralHue(source), expressiveNeutralChroma(source, isDark, platform));
    case Variant::Vibrant:
        return make(vibrantNeutralHue(source), vibrantNeutralChroma(source, platform));
    default:
        return neutralPalette2021(variant, source);
    }
}

TonalPalette neutralVariantPalette2025(Variant variant, const Hct& source, bool isDark, Platform platform) {
    const bool phone = platform == Platform::Phone;
    switch (variant) {
    case Variant::Neutral:
        return make(source.hue(), (phone ? 1.4 : 6) * 2.2);
    case Variant::TonalSpot:
        return make(source.hue(), (phone ? 5 : 10) * 1.7);
    case Variant::Expressive: {
        const double neutralHue = expressiveNeutralHue(source);
        const double neutralChroma = expressiveNeutralChroma(source, isDark, platform);
        return make(neutralHue, neutralChroma * (neutralHue >= 105 && neutralHue < 125 ? 1.6 : 2.3));
    }
    case Variant::Vibrant:
        return make(vibrantNeutralHue(source), vibrantNeutralChroma(source, platform) * 1.29);
    default:
        return neutralVariantPalette2021(variant, source);
    }
}

std::optional<TonalPalette> errorPalette2025(Variant variant, const Hct& source, Platform platform) {
    const bool phone = platform == Platform::Phone;
    const double errorHue =
        piecewiseHue(source, { 0, 3, 13, 23, 33, 43, 153, 273, 360 }, { 12, 22, 32, 12, 22, 32, 22, 12 });
    switch (variant) {
    case Variant::Neutral:
        return make(errorHue, phone ? 50 : 40);
    case Variant::TonalSpot:
        return make(errorHue, phone ? 60 : 48);
    case Variant::Expressive:
        return make(errorHue, phone ? 64 : 48);
    case Variant::Vibrant:
        return make(errorHue, phone ? 80 : 60);
    default:
        return std::nullopt;
    }
}

SpecVersion fallbackSpecVersion(SpecVersion specVersion, Variant variant) {
    switch (variant) {
    case Variant::Expressive:
    case Variant::Vibrant:
    case Variant::TonalSpot:
    case Variant::Neutral:
        return specVersion;
    default:
        return SpecVersion::V2021;
    }
}

bool isFixedDimName(const std::string& name) {
    std::string lowered = name;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    const auto endsWith = [&lowered](const std::string& suffix) {
        return lowered.size() >= suffix.size() &&
            lowered.compare(lowered.size() - suffix.size(), suffix.size(), suffix) == 0;
    };
    return endsWith("_fixed_dim") || endsWith("fixeddim");
}

// The tone shared by the 2021 and 2025 paths once a colour has a background to meet contrast against.
double toneAgainstSecondBackground(
    SchemeRef scheme, const DynamicColor& color, double answer, double desiredRatio) {
    const DynamicColor* bg1 = color.background(scheme);
    const DynamicColor* bg2 = color.secondBackground(scheme);
    const double bgTone1 = bg1->getTone(scheme);
    const double bgTone2 = bg2->getTone(scheme);
    const double upper = std::max(bgTone1, bgTone2);
    const double lower = std::min(bgTone1, bgTone2);

    if (contrast::ratioOfTones(upper, answer) >= desiredRatio &&
        contrast::ratioOfTones(lower, answer) >= desiredRatio) {
        return answer;
    }

    const double lightOption = contrast::lighter(upper, desiredRatio);
    const double darkOption = contrast::darker(lower, desiredRatio);

    int availables = 0;
    double onlyAvailable = 0.0;
    if (lightOption >= 0.0) {
        ++availables;
        onlyAvailable = lightOption;
    }

    if (darkOption >= 0.0) {
        ++availables;
        onlyAvailable = darkOption;
    }

    const bool prefersLight =
        DynamicColor::tonePrefersLightForeground(bgTone1) || DynamicColor::tonePrefersLightForeground(bgTone2);
    if (prefersLight) {
        return lightOption < 0 ? 100 : lightOption;
    }

    if (availables == 1) {
        return onlyAvailable;
    }

    return darkOption < 0 ? 0 : darkOption;
}

bool hasBackgroundAndCurve(SchemeRef scheme, const DynamicColor& color) {
    return color.background && color.background(scheme) && color.contrastCurve && color.contrastCurve(scheme);
}

double tone2021(SchemeRef scheme, const DynamicColor& color) {
    const bool decreasingContrast = scheme.contrastLevel < 0;
    std::optional<ToneDeltaPair> toneDeltaPair;
    if (color.toneDeltaPair) {
        toneDeltaPair = color.toneDeltaPair(scheme);
    }

    if (toneDeltaPair) {
        const DynamicColor& roleA = *toneDeltaPair->roleA;
        const DynamicColor& roleB = *toneDeltaPair->roleB;
        const double delta = toneDeltaPair->delta;
        const TonePolarity polarity = toneDeltaPair->polarity;
        const bool stayTogether = toneDeltaPair->stayTogether;

        const bool aIsNearer = polarity == TonePolarity::Nearer ||
            (polarity == TonePolarity::Lighter && !scheme.isDark) ||
            (polarity == TonePolarity::Darker && scheme.isDark);
        const DynamicColor& nearer = aIsNearer ? roleA : roleB;
        const DynamicColor& farther = aIsNearer ? roleB : roleA;
        const bool amNearer = color.name == nearer.name;
        const double expansionDir = scheme.isDark ? 1 : -1;
        double nTone = nearer.tone(scheme);
        double fTone = farther.tone(scheme);

        if (color.background && nearer.contrastCurve && farther.contrastCurve) {
            const DynamicColor* bg = color.background(scheme);
            const auto nContrastCurve = nearer.contrastCurve(scheme);
            const auto fContrastCurve = farther.contrastCurve(scheme);
            if (bg && nContrastCurve && fContrastCurve) {
                const double bgTone = bg->getTone(scheme);
                const double nContrast = nContrastCurve->get(scheme.contrastLevel);
                const double fContrast = fContrastCurve->get(scheme.contrastLevel);

                if (contrast::ratioOfTones(bgTone, nTone) < nContrast) {
                    nTone = DynamicColor::foregroundTone(bgTone, nContrast);
                }

                if (contrast::ratioOfTones(bgTone, fTone) < fContrast) {
                    fTone = DynamicColor::foregroundTone(bgTone, fContrast);
                }

                if (decreasingContrast) {
                    nTone = DynamicColor::foregroundTone(bgTone, nContrast);
                    fTone = DynamicColor::foregroundTone(bgTone, fContrast);
                }
            }
        }

        if ((fTone - nTone) * expansionDir < delta) {
            fTone = clampDouble(0, 100, nTone + delta * expansionDir);
            if (!((fTone - nTone) * expansionDir >= delta)) {
                nTone = clampDouble(0, 100, fTone - delta * expansionDir);
            }
        }

        if (50 <= nTone && nTone < 60) {
            if (expansionDir > 0) {
                nTone = 60;
                fTone = std::max(fTone, nTone + delta * expansionDir);
            } else {
                nTone = 49;
                fTone = std::min(fTone, nTone + delta * expansionDir);
            }
        } else if (50 <= fTone && fTone < 60) {
            if (stayTogether) {
                if (expansionDir > 0) {
                    nTone = 60;
                    fTone = std::max(fTone, nTone + delta * expansionDir);
                } else {
                    nTone = 49;
                    fTone = std::min(fTone, nTone + delta * expansionDir);
                }
            } else if (expansionDir > 0) {
                fTone = 60;
            } else {
                fTone = 49;
            }
        }

        return amNearer ? nTone : fTone;
    }

    double answer = color.tone(scheme);
    if (!hasBackgroundAndCurve(scheme, color)) {
        return answer;
    }

    const double bgTone = color.background(scheme)->getTone(scheme);
    const double desiredRatio = color.contrastCurve(scheme)->get(scheme.contrastLevel);

    if (!(contrast::ratioOfTones(bgTone, answer) >= desiredRatio)) {
        answer = DynamicColor::foregroundTone(bgTone, desiredRatio);
    }

    if (decreasingContrast) {
        answer = DynamicColor::foregroundTone(bgTone, desiredRatio);
    }

    if (color.isBackground && 50 <= answer && answer < 60) {
        answer = contrast::ratioOfTones(49, bgTone) >= desiredRatio ? 49 : 60;
    }

    if (!color.secondBackground || !color.secondBackground(scheme)) {
        return answer;
    }

    return toneAgainstSecondBackground(scheme, color, answer, desiredRatio);
}

double tone2025(SchemeRef scheme, const DynamicColor& color) {
    std::optional<ToneDeltaPair> toneDeltaPair;
    if (color.toneDeltaPair) {
        toneDeltaPair = color.toneDeltaPair(scheme);
    }

    if (toneDeltaPair) {
        const DynamicColor& roleA = *toneDeltaPair->roleA;
        const DynamicColor& roleB = *toneDeltaPair->roleB;
        const TonePolarity polarity = toneDeltaPair->polarity;
        const DeltaConstraint constraint = toneDeltaPair->constraint;
        const double absoluteDelta = polarity == TonePolarity::Darker ||
                (polarity == TonePolarity::RelativeLighter && scheme.isDark) ||
                (polarity == TonePolarity::RelativeDarker && !scheme.isDark)
            ? -toneDeltaPair->delta
            : toneDeltaPair->delta;

        const bool amRoleA = color.name == roleA.name;
        const DynamicColor& selfRole = amRoleA ? roleA : roleB;
        const DynamicColor& refRole = amRoleA ? roleB : roleA;
        double selfTone = selfRole.tone(scheme);
        const double refTone = refRole.getTone(scheme);
        const double relativeDelta = absoluteDelta * (amRoleA ? 1 : -1);

        if (constraint == DeltaConstraint::Exact) {
            selfTone = clampDouble(0, 100, refTone + relativeDelta);
        } else if (constraint == DeltaConstraint::Nearer) {
            if (relativeDelta > 0) {
                selfTone = clampDouble(0, 100, clampDouble(refTone, refTone + relativeDelta, selfTone));
            } else {
                selfTone = clampDouble(0, 100, clampDouble(refTone + relativeDelta, refTone, selfTone));
            }
        } else if (constraint == DeltaConstraint::Farther) {
            if (relativeDelta > 0) {
                selfTone = clampDouble(refTone + relativeDelta, 100, selfTone);
            } else {
                selfTone = clampDouble(0, refTone + relativeDelta, selfTone);
            }
        }

        if (color.background && color.contrastCurve) {
            const DynamicColor* background = color.background(scheme);
            const auto contrastCurve = color.contrastCurve(scheme);
            if (background && contrastCurve) {
                const double bgTone = background->getTone(scheme);
                const double selfContrast = contrastCurve->get(scheme.contrastLevel);
                selfTone = contrast::ratioOfTones(bgTone, selfTone) >= selfContrast && scheme.contrastLevel >= 0
                    ? selfTone
                    : DynamicColor::foregroundTone(bgTone, selfContrast);
            }
        }

        if (color.isBackground && !isFixedDimName(color.name)) {
            if (selfTone >= 57) {
                selfTone = clampDouble(65, 100, selfTone);
            } else {
                selfTone = clampDouble(0, 49, selfTone);
            }
        }

        return selfTone;
    }

    double answer = color.tone(scheme);
    if (!hasBackgroundAndCurve(scheme, color)) {
        return answer;
    }

    const double bgTone = color.background(scheme)->getTone(scheme);
    const double desiredRatio = color.contrastCurve(scheme)->get(scheme.contrastLevel);

    answer = contrast::ratioOfTones(bgTone, answer) >= desiredRatio && scheme.contrastLevel >= 0
        ? answer
        : DynamicColor::foregroundTone(bgTone, desiredRatio);

    if (color.isBackground && !isFixedDimName(color.name)) {
        if (answer >= 57) {
            answer = clampDouble(65, 100, answer);
        } else {
            answer = clampDouble(0, 49, answer);
        }
    }

    if (!color.secondBackground || !color.secondBackground(scheme)) {
        return answer;
    }

    return toneAgainstSecondBackground(scheme, color, answer, desiredRatio);
}

} // namespace

double ContrastCurve::get(double contrastLevel) const {
    if (contrastLevel <= -1.0) {
        return this->low;
    }

    if (contrastLevel < 0.0) {
        return lerp(this->low, this->normal, (contrastLevel - (-1)) / 1);
    }

    if (contrastLevel < 0.5) {
        return lerp(this->normal, this->medium, (contrastLevel - 0) / 0.5);
    }

    if (contrastLevel < 1.0) {
        return lerp(this->medium, this->high, (contrastLevel - 0.5) / 0.5);
    }

    return this->high;
}

DynamicScheme::DynamicScheme(
    const Hct& source, Variant kind, double contrast, bool dark, Platform target, SpecVersion requestedSpec)
    : sourceColorHct(source)
    , variant(kind)
    , contrastLevel(contrast)
    , isDark(dark)
    , platform(target)
    , specVersion(fallbackSpecVersion(requestedSpec, kind))
    , primaryPalette(this->specVersion == SpecVersion::V2025 ? primaryPalette2025(kind, source, dark, target)
                                                             : primaryPalette2021(kind, source))
    , secondaryPalette(this->specVersion == SpecVersion::V2025 ? secondaryPalette2025(kind, source, dark, target)
                                                               : secondaryPalette2021(kind, source))
    , tertiaryPalette(this->specVersion == SpecVersion::V2025 ? tertiaryPalette2025(kind, source, target)
                                                              : tertiaryPalette2021(kind, source))
    , neutralPalette(this->specVersion == SpecVersion::V2025 ? neutralPalette2025(kind, source, dark, target)
                                                             : neutralPalette2021(kind, source))
    , neutralVariantPalette(this->specVersion == SpecVersion::V2025
              ? neutralVariantPalette2025(kind, source, dark, target)
              : neutralVariantPalette2021(kind, source))
    , errorPalette((this->specVersion == SpecVersion::V2025 ? errorPalette2025(kind, source, target) : std::nullopt)
                       .value_or(make(25.0, 84.0))) {}

DynamicColor DynamicColor::fromPalette(DynamicColor options) {
    if (!options.tone) {
        options.tone = initialToneFromBackground(options.background);
    }

    if (!options.background && options.secondBackground) {
        throw std::invalid_argument(options.name + " has secondBackground defined, but background is not defined");
    }

    if (!options.background && options.contrastCurve) {
        throw std::invalid_argument(options.name + " has contrastCurve defined, but background is not defined");
    }

    if (options.background && !options.contrastCurve) {
        throw std::invalid_argument(options.name + " has background defined, but contrastCurve is not defined");
    }

    return options;
}

DynamicColor::ToneFn DynamicColor::initialToneFromBackground(ColorFn background) {
    if (!background) {
        return [](SchemeRef) {
            return 50.0;
        };
    }

    return [background](SchemeRef scheme) {
        const DynamicColor* bg = background(scheme);
        return bg ? bg->getTone(scheme) : 50.0;
    };
}

Hct DynamicColor::getHct(SchemeRef scheme) const {
    if (scheme.specVersion == SpecVersion::V2025) {
        const TonalPalette& tonalPalette = this->palette(scheme);
        const double toneValue = this->getTone(scheme);
        const double hue = tonalPalette.hue();
        const double chroma = tonalPalette.chroma() * (this->chromaMultiplier ? this->chromaMultiplier(scheme) : 1);
        return Hct::fromHct(hue, chroma, toneValue);
    }

    const double toneValue = this->getTone(scheme);
    return this->palette(scheme).getHct(toneValue);
}

double DynamicColor::getTone(SchemeRef scheme) const {
    return scheme.specVersion == SpecVersion::V2025 ? tone2025(scheme, *this) : tone2021(scheme, *this);
}

double DynamicColor::foregroundTone(double bgTone, double ratio) {
    const double lighterTone = contrast::lighterUnsafe(bgTone, ratio);
    const double darkerTone = contrast::darkerUnsafe(bgTone, ratio);
    const double lighterRatio = contrast::ratioOfTones(lighterTone, bgTone);
    const double darkerRatio = contrast::ratioOfTones(darkerTone, bgTone);
    const bool preferLighter = tonePrefersLightForeground(bgTone);

    if (preferLighter) {
        const bool negligibleDifference =
            std::abs(lighterRatio - darkerRatio) < 0.1 && lighterRatio < ratio && darkerRatio < ratio;
        return lighterRatio >= ratio || lighterRatio >= darkerRatio || negligibleDifference ? lighterTone : darkerTone;
    }

    return darkerRatio >= ratio || darkerRatio >= lighterRatio ? darkerTone : lighterTone;
}

bool DynamicColor::tonePrefersLightForeground(double tone) {
    return pyRound(tone) < 60.0;
}

} // namespace burl::colour
