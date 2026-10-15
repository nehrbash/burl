// Derived from materialyoucolor 3.0.2 dynamiccolor/color_spec_2021.py, color_spec_2025.py and
// material_dynamic_colors.py (MIT, Ansh Dadwal), itself a port of Google's material-color-utilities (Apache-2.0).
// Licenses: cli/third_party/material-color-utilities/LICENSE*.

#include "dynamic.hpp"

#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <stdexcept>
#include <string_view>

// Colour definitions are written as designated initializers that name only the attributes a colour has.
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"

namespace burl::colour {

namespace {

using Color = DynamicColor;
using ToneFn = DynamicColor::ToneFn;
using ColorFn = DynamicColor::ColorFn;
using CurveFn = DynamicColor::CurveFn;
using PairFn = DynamicColor::PairFn;

constexpr std::string_view kColorNames[] = {
    "background",
    "onBackground",
    "surface",
    "surfaceDim",
    "surfaceBright",
    "surfaceContainerLowest",
    "surfaceContainerLow",
    "surfaceContainer",
    "surfaceContainerHigh",
    "surfaceContainerHighest",
    "onSurface",
    "surfaceVariant",
    "onSurfaceVariant",
    "outline",
    "outlineVariant",
    "inverseSurface",
    "inverseOnSurface",
    "shadow",
    "scrim",
    "surfaceTint",
    "primary",
    "primaryDim",
    "onPrimary",
    "primaryContainer",
    "onPrimaryContainer",
    "inversePrimary",
    "primaryFixed",
    "primaryFixedDim",
    "onPrimaryFixed",
    "onPrimaryFixedVariant",
    "secondary",
    "secondaryDim",
    "onSecondary",
    "secondaryContainer",
    "onSecondaryContainer",
    "secondaryFixed",
    "secondaryFixedDim",
    "onSecondaryFixed",
    "onSecondaryFixedVariant",
    "tertiary",
    "tertiaryDim",
    "onTertiary",
    "tertiaryContainer",
    "onTertiaryContainer",
    "tertiaryFixed",
    "tertiaryFixedDim",
    "onTertiaryFixed",
    "onTertiaryFixedVariant",
    "error",
    "errorDim",
    "onError",
    "errorContainer",
    "onErrorContainer",
    "primaryPaletteKeyColor",
    "secondaryPaletteKeyColor",
    "tertiaryPaletteKeyColor",
    "neutralPaletteKeyColor",
    "neutralVariantPaletteKeyColor",
    "errorPaletteKeyColor",
};

class Spec;

const TonalPalette& primaryOf(SchemeRef s) {
    return s.primaryPalette;
}

const TonalPalette& secondaryOf(SchemeRef s) {
    return s.secondaryPalette;
}

const TonalPalette& tertiaryOf(SchemeRef s) {
    return s.tertiaryPalette;
}

const TonalPalette& neutralOf(SchemeRef s) {
    return s.neutralPalette;
}

const TonalPalette& neutralVariantOf(SchemeRef s) {
    return s.neutralVariantPalette;
}

const TonalPalette& errorOf(SchemeRef s) {
    return s.errorPalette;
}

bool isFidelity(SchemeRef s) {
    return s.variant == Variant::Fidelity || s.variant == Variant::Content;
}

bool isMonochrome(SchemeRef s) {
    return s.variant == Variant::Monochrome;
}

bool isPhone(SchemeRef s) {
    return s.platform == Platform::Phone;
}

ToneFn constant(double tone) {
    return [tone](SchemeRef) {
        return tone;
    };
}

ToneFn darkLight(double dark, double light) {
    return [dark, light](SchemeRef s) {
        return s.isDark ? dark : light;
    };
}

ToneFn monochromeOr(double monochrome, double otherwise) {
    return [monochrome, otherwise](SchemeRef s) {
        return isMonochrome(s) ? monochrome : otherwise;
    };
}

ToneFn darkLightByContrast(ContrastCurve dark, ContrastCurve light) {
    return [dark, light](SchemeRef s) {
        return s.isDark ? dark.get(s.contrastLevel) : light.get(s.contrastLevel);
    };
}

CurveFn curve(double low, double normal, double medium, double high) {
    return [=](SchemeRef) -> std::optional<ContrastCurve> {
        return ContrastCurve{ low, normal, medium, high };
    };
}

ContrastCurve getCurve(double defaultContrast) {
    if (exactlyEqual(defaultContrast, 1.5)) {
        return { 1.5, 1.5, 3, 5.5 };
    }

    if (exactlyEqual(defaultContrast, 3)) {
        return { 3, 3, 4.5, 7 };
    }

    if (exactlyEqual(defaultContrast, 4.5)) {
        return { 4.5, 4.5, 7, 11 };
    }

    if (exactlyEqual(defaultContrast, 6)) {
        return { 6, 6, 7, 11 };
    }

    if (exactlyEqual(defaultContrast, 7)) {
        return { 7, 7, 11, 21 };
    }

    if (exactlyEqual(defaultContrast, 9)) {
        return { 9, 9, 11, 21 };
    }

    if (exactlyEqual(defaultContrast, 11)) {
        return { 11, 11, 21, 21 };
    }

    if (exactlyEqual(defaultContrast, 21)) {
        return { 21, 21, 21, 21 };
    }

    return { defaultContrast, defaultContrast, 7, 21 };
}

CurveFn getCurveFn(double defaultContrast) {
    return [defaultContrast](SchemeRef) -> std::optional<ContrastCurve> {
        return getCurve(defaultContrast);
    };
}

double findDesiredChromaByTone(double hue, double chroma, double tone, bool byDecreasingTone) {
    double answer = tone;
    Hct closestToChroma = Hct::fromHct(hue, chroma, tone);
    if (closestToChroma.chroma() < chroma) {
        double chromaPeak = closestToChroma.chroma();
        while (closestToChroma.chroma() < chroma) {
            answer += byDecreasingTone ? -1.0 : 1.0;
            const Hct potentialSolution = Hct::fromHct(hue, chroma, answer);
            if (chromaPeak > potentialSolution.chroma()) {
                break;
            }

            if (std::abs(potentialSolution.chroma() - chroma) < 0.4) {
                break;
            }

            if (std::abs(potentialSolution.chroma() - chroma) < std::abs(closestToChroma.chroma() - chroma)) {
                closestToChroma = potentialSolution;
            }

            chromaPeak = std::max(chromaPeak, potentialSolution.chroma());
        }
    }

    return answer;
}

double findBestToneForChroma(double hue, double chroma, double tone, bool byDecreasingTone) {
    double answer = tone;
    Hct bestCandidate = Hct::fromHct(hue, chroma, answer);
    while (bestCandidate.chroma() < chroma) {
        if (tone < 0 || tone > 100) {
            break;
        }

        tone += byDecreasingTone ? -1.0 : 1.0;
        const Hct newCandidate = Hct::fromHct(hue, chroma, tone);
        if (bestCandidate.chroma() < newCandidate.chroma()) {
            bestCandidate = newCandidate;
            answer = tone;
        }
    }

    return answer;
}

double tMaxC(const TonalPalette& palette, double lowerBound = 0, double upperBound = 100, double chromaMultiplier = 1) {
    const double answer = findBestToneForChroma(palette.hue(), palette.chroma() * chromaMultiplier, 100, true);
    return clampDouble(lowerBound, upperBound, answer);
}

double tMinC(const TonalPalette& palette, double lowerBound = 0, double upperBound = 100) {
    const double answer = findBestToneForChroma(palette.hue(), palette.chroma(), 0, false);
    return clampDouble(lowerBound, upperBound, answer);
}

// Chroma boost the 2025 spec gives onSurface, onSurfaceVariant, outline and outlineVariant.
double neutralChromaMultiplier2025(SchemeRef s) {
    if (isPhone(s)) {
        const bool yellow = Hct::isYellow(s.neutralPalette.hue());
        switch (s.variant) {
        case Variant::Neutral:
            return 2.2;
        case Variant::TonalSpot:
            return 1.7;
        case Variant::Expressive:
            return yellow && s.isDark ? 3.0 : (yellow ? 2.3 : 1.6);
        default:
            break;
        }
    }

    return 1.0;
}

class Spec {
public:
    Spec();

    const Color& color(std::string_view name) const;

    const Color* highestSurface(SchemeRef s) const {
        return &this->color(s.isDark ? "surfaceBright" : "surfaceDim");
    }

    ColorFn ref(std::string_view name) const {
        return [this, key = std::string(name)](SchemeRef) -> const Color* {
            return &this->color(key);
        };
    }

    ColorFn highestSurfaceFn() const {
        return [this](SchemeRef s) -> const Color* {
            return this->highestSurface(s);
        };
    }

    // highestSurface on phones, surfaceContainerHigh on watches.
    ColorFn highestSurfaceOrContainerFn() const {
        return [this](SchemeRef s) -> const Color* {
            return isPhone(s) ? this->highestSurface(s) : &this->color("surfaceContainerHigh");
        };
    }

    // highestSurface on phones, nothing on watches.
    ColorFn phoneHighestSurfaceFn() const {
        return [this](SchemeRef s) -> const Color* {
            return isPhone(s) ? this->highestSurface(s) : nullptr;
        };
    }

    // `phone` on phones and `watch` on watches.
    ColorFn byPlatformFn(std::string_view phone, std::string_view watch) const {
        return [this, phone = std::string(phone), watch = std::string(watch)](SchemeRef s) -> const Color* {
            return &this->color(isPhone(s) ? phone : watch);
        };
    }

    PairFn pairFn(std::string_view roleA, std::string_view roleB, double delta, TonePolarity polarity,
        bool stayTogether, DeltaConstraint constraint = DeltaConstraint::Exact) const {
        return [this, a = std::string(roleA), b = std::string(roleB), delta, polarity, stayTogether, constraint](
                   SchemeRef) -> std::optional<ToneDeltaPair> {
            return ToneDeltaPair{ &this->color(a), &this->color(b), delta, polarity, stayTogether, constraint };
        };
    }

    // A pair that only phones have.
    PairFn phonePairFn(std::string_view roleA, std::string_view roleB) const {
        const PairFn pair =
            this->pairFn(roleA, roleB, 5, TonePolarity::RelativeLighter, true, DeltaConstraint::Farther);
        return [pair](SchemeRef s) -> std::optional<ToneDeltaPair> {
            if (isPhone(s)) {
                return pair(s);
            }

            return std::nullopt;
        };
    }

    // A pair that only watches have.
    PairFn watchPairFn(std::string_view container, std::string_view dim) const {
        const PairFn pair = this->pairFn(container, dim, 10, TonePolarity::Darker, true, DeltaConstraint::Farther);
        return [pair](SchemeRef s) -> std::optional<ToneDeltaPair> {
            if (s.platform == Platform::Watch) {
                return pair(s);
            }

            return std::nullopt;
        };
    }

    // The tone of `container` as it would be in a light scheme at standard contrast.
    ToneFn fixedToneFn(std::string_view container) const {
        return [this, key = std::string(container)](SchemeRef s) {
            DynamicScheme light = s;
            light.contrastLevel = 0;
            light.isDark = false;
            return this->color(key).getTone(light);
        };
    }

    std::vector<const Color*> all() const;

private:
    using Colors = std::map<std::string, Color, std::less<>>;

    Colors colors2021() const;
    Colors colors2025() const;
    Color extend(const Color& original, const Color& extended) const;
    Color clone(std::string_view source, std::string_view name) const;

    std::map<std::string, std::unique_ptr<Color>, std::less<>> mColors;
};

Spec::Colors Spec::colors2021() const {
    Colors colors;
    const auto add = [&colors](Color options) {
        Color color = Color::fromPalette(std::move(options));
        const std::string name = color.name;
        colors.emplace(name, std::move(color));
    };
    const auto keyTone = [](const TonalPalette& (*palette)(SchemeRef)) -> ToneFn {
        return [palette](SchemeRef s) {
            return palette(s).keyColor().tone();
        };
    };

    add({ .name = "primaryPaletteKeyColor", .palette = primaryOf, .tone = keyTone(primaryOf) });
    add({ .name = "secondaryPaletteKeyColor", .palette = secondaryOf, .tone = keyTone(secondaryOf) });
    add({ .name = "tertiaryPaletteKeyColor", .palette = tertiaryOf, .tone = keyTone(tertiaryOf) });
    add({ .name = "neutralPaletteKeyColor", .palette = neutralOf, .tone = keyTone(neutralOf) });
    add({ .name = "neutralVariantPaletteKeyColor", .palette = neutralVariantOf, .tone = keyTone(neutralVariantOf) });
    add({ .name = "errorPaletteKeyColor", .palette = errorOf, .tone = keyTone(errorOf) });

    add({ .name = "background", .palette = neutralOf, .tone = darkLight(6, 98), .isBackground = true });
    add({
        .name = "onBackground",
        .palette = neutralOf,
        .tone = darkLight(90, 10),
        .background = this->ref("background"),
        .contrastCurve = curve(3, 3, 4.5, 7),
    });
    add({ .name = "surface", .palette = neutralOf, .tone = darkLight(6, 98), .isBackground = true });
    add({
        .name = "surfaceDim",
        .palette = neutralOf,
        .tone = [](SchemeRef s) {
            return s.isDark ? 6.0 : ContrastCurve{ 87, 87, 80, 75 }.get(s.contrastLevel);
        },
        .isBackground = true,
    });
    add({
        .name = "surfaceBright",
        .palette = neutralOf,
        .tone = [](SchemeRef s) {
            return s.isDark ? ContrastCurve{ 24, 24, 29, 34 }.get(s.contrastLevel) : 98.0;
        },
        .isBackground = true,
    });
    add({
        .name = "surfaceContainerLowest",
        .palette = neutralOf,
        .tone = [](SchemeRef s) {
            return s.isDark ? ContrastCurve{ 4, 4, 2, 0 }.get(s.contrastLevel) : 100.0;
        },
        .isBackground = true,
    });
    add({
        .name = "surfaceContainerLow",
        .palette = neutralOf,
        .tone = darkLightByContrast({ 10, 10, 11, 12 }, { 96, 96, 96, 95 }),
        .isBackground = true,
    });
    add({
        .name = "surfaceContainer",
        .palette = neutralOf,
        .tone = darkLightByContrast({ 12, 12, 16, 20 }, { 94, 94, 92, 90 }),
        .isBackground = true,
    });
    add({
        .name = "surfaceContainerHigh",
        .palette = neutralOf,
        .tone = darkLightByContrast({ 17, 17, 21, 25 }, { 92, 92, 88, 85 }),
        .isBackground = true,
    });
    add({
        .name = "surfaceContainerHighest",
        .palette = neutralOf,
        .tone = darkLightByContrast({ 22, 22, 26, 30 }, { 90, 90, 84, 80 }),
        .isBackground = true,
    });
    add({
        .name = "onSurface",
        .palette = neutralOf,
        .tone = darkLight(90, 10),
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({ .name = "surfaceVariant", .palette = neutralVariantOf, .tone = darkLight(30, 90), .isBackground = true });
    add({
        .name = "onSurfaceVariant",
        .palette = neutralVariantOf,
        .tone = darkLight(80, 30),
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(3, 4.5, 7, 11),
    });
    add({ .name = "inverseSurface", .palette = neutralOf, .tone = darkLight(90, 20), .isBackground = true });
    add({
        .name = "inverseOnSurface",
        .palette = neutralOf,
        .tone = darkLight(20, 95),
        .background = this->ref("inverseSurface"),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({
        .name = "outline",
        .palette = neutralVariantOf,
        .tone = darkLight(60, 50),
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1.5, 3, 4.5, 7),
    });
    add({
        .name = "outlineVariant",
        .palette = neutralVariantOf,
        .tone = darkLight(30, 80),
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1, 1, 3, 4.5),
    });
    add({ .name = "shadow", .palette = neutralOf, .tone = constant(0) });
    add({ .name = "scrim", .palette = neutralOf, .tone = constant(0) });
    add({ .name = "surfaceTint", .palette = primaryOf, .tone = darkLight(80, 40), .isBackground = true });

    add({
        .name = "primary",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 100.0 : 0.0) : (s.isDark ? 80.0 : 40.0);
        },
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(3, 4.5, 7, 7),
        .toneDeltaPair = this->pairFn("primaryContainer", "primary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onPrimary",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 10.0 : 90.0) : (s.isDark ? 20.0 : 100.0);
        },
        .background = this->ref("primary"),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({
        .name = "primaryContainer",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            if (isFidelity(s)) {
                return s.sourceColorHct.tone();
            }

            return isMonochrome(s) ? (s.isDark ? 85.0 : 25.0) : (s.isDark ? 30.0 : 90.0);
        },
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1, 1, 3, 4.5),
        .toneDeltaPair = this->pairFn("primaryContainer", "primary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onPrimaryContainer",
        .palette = primaryOf,
        .tone = [this](SchemeRef s) {
            if (isFidelity(s)) {
                return Color::foregroundTone(this->color("primaryContainer").tone(s), 4.5);
            }

            return isMonochrome(s) ? (s.isDark ? 0.0 : 100.0) : (s.isDark ? 90.0 : 30.0);
        },
        .background = this->ref("primaryContainer"),
        .contrastCurve = curve(3, 4.5, 7, 11),
    });
    add({
        .name = "inversePrimary",
        .palette = primaryOf,
        .tone = darkLight(40, 80),
        .background = this->ref("inverseSurface"),
        .contrastCurve = curve(3, 4.5, 7, 7),
    });

    add({
        .name = "secondary",
        .palette = secondaryOf,
        .tone = darkLight(80, 40),
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(3, 4.5, 7, 7),
        .toneDeltaPair = this->pairFn("secondaryContainer", "secondary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onSecondary",
        .palette = secondaryOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 10.0 : 100.0) : (s.isDark ? 20.0 : 100.0);
        },
        .background = this->ref("secondary"),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({
        .name = "secondaryContainer",
        .palette = secondaryOf,
        .tone = [](SchemeRef s) {
            if (isMonochrome(s)) {
                return s.isDark ? 30.0 : 85.0;
            }

            if (isFidelity(s)) {
                return findDesiredChromaByTone(
                    s.secondaryPalette.hue(), s.secondaryPalette.chroma(), s.isDark ? 30.0 : 90.0, !s.isDark);
            }

            return s.isDark ? 30.0 : 90.0;
        },
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1, 1, 3, 4.5),
        .toneDeltaPair = this->pairFn("secondaryContainer", "secondary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onSecondaryContainer",
        .palette = secondaryOf,
        .tone = [this](SchemeRef s) {
            if (isMonochrome(s)) {
                return s.isDark ? 90.0 : 10.0;
            }

            if (isFidelity(s)) {
                return Color::foregroundTone(this->color("secondaryContainer").tone(s), 4.5);
            }

            return s.isDark ? 90.0 : 30.0;
        },
        .background = this->ref("secondaryContainer"),
        .contrastCurve = curve(3, 4.5, 7, 11),
    });

    add({
        .name = "tertiary",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 90.0 : 25.0) : (s.isDark ? 80.0 : 40.0);
        },
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(3, 4.5, 7, 7),
        .toneDeltaPair = this->pairFn("tertiaryContainer", "tertiary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onTertiary",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 10.0 : 90.0) : (s.isDark ? 20.0 : 100.0);
        },
        .background = this->ref("tertiary"),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({
        .name = "tertiaryContainer",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            if (isMonochrome(s)) {
                return s.isDark ? 60.0 : 49.0;
            }

            if (isFidelity(s)) {
                return fixIfDisliked(s.tertiaryPalette.getHct(s.sourceColorHct.tone())).tone();
            }

            return s.isDark ? 30.0 : 90.0;
        },
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1, 1, 3, 4.5),
        .toneDeltaPair = this->pairFn("tertiaryContainer", "tertiary", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onTertiaryContainer",
        .palette = tertiaryOf,
        .tone = [this](SchemeRef s) {
            if (isMonochrome(s)) {
                return s.isDark ? 0.0 : 100.0;
            }

            if (isFidelity(s)) {
                return Color::foregroundTone(this->color("tertiaryContainer").tone(s), 4.5);
            }

            return s.isDark ? 90.0 : 30.0;
        },
        .background = this->ref("tertiaryContainer"),
        .contrastCurve = curve(3, 4.5, 7, 11),
    });

    add({
        .name = "error",
        .palette = errorOf,
        .tone = darkLight(80, 40),
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(3, 4.5, 7, 7),
        .toneDeltaPair = this->pairFn("errorContainer", "error", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onError",
        .palette = errorOf,
        .tone = darkLight(20, 100),
        .background = this->ref("error"),
        .contrastCurve = curve(4.5, 7, 11, 21),
    });
    add({
        .name = "errorContainer",
        .palette = errorOf,
        .tone = darkLight(30, 90),
        .isBackground = true,
        .background = this->highestSurfaceFn(),
        .contrastCurve = curve(1, 1, 3, 4.5),
        .toneDeltaPair = this->pairFn("errorContainer", "error", 10, TonePolarity::Nearer, false),
    });
    add({
        .name = "onErrorContainer",
        .palette = errorOf,
        .tone = [](SchemeRef s) {
            return isMonochrome(s) ? (s.isDark ? 90.0 : 10.0) : (s.isDark ? 90.0 : 30.0);
        },
        .background = this->ref("errorContainer"),
        .contrastCurve = curve(3, 4.5, 7, 11),
    });

    struct Family {
        const char* prefix;
        const char* onFixed;
        const char* onFixedVariant;
        const TonalPalette& (*palette)(SchemeRef);
        double fixedMonochrome;
        double dimMonochrome;
        double onFixedMonochrome;
        double onFixedDefault;
        double onVariantMonochrome;
        double onVariantDefault;
    };
    const Family families[] = {
        { "primary", "onPrimaryFixed", "onPrimaryFixedVariant", primaryOf, 40.0, 30.0, 100.0, 10.0, 90.0, 30.0 },
        { "secondary", "onSecondaryFixed", "onSecondaryFixedVariant", secondaryOf, 80.0, 70.0, 10.0, 10.0, 25.0,
            30.0 },
        { "tertiary", "onTertiaryFixed", "onTertiaryFixedVariant", tertiaryOf, 40.0, 30.0, 100.0, 10.0, 90.0, 30.0 },
    };
    for (const Family& family : families) {
        const std::string fixed = std::string(family.prefix) + "Fixed";
        const std::string dim = fixed + "Dim";
        add({
            .name = fixed,
            .palette = family.palette,
            .tone = monochromeOr(family.fixedMonochrome, 90.0),
            .isBackground = true,
            .background = this->highestSurfaceFn(),
            .contrastCurve = curve(1, 1, 3, 4.5),
            .toneDeltaPair = this->pairFn(fixed, dim, 10, TonePolarity::Lighter, true),
        });
        add({
            .name = dim,
            .palette = family.palette,
            .tone = monochromeOr(family.dimMonochrome, 80.0),
            .isBackground = true,
            .background = this->highestSurfaceFn(),
            .contrastCurve = curve(1, 1, 3, 4.5),
            .toneDeltaPair = this->pairFn(fixed, dim, 10, TonePolarity::Lighter, true),
        });
        add({
            .name = family.onFixed,
            .palette = family.palette,
            .tone = monochromeOr(family.onFixedMonochrome, family.onFixedDefault),
            .background = this->ref(dim),
            .secondBackground = this->ref(fixed),
            .contrastCurve = curve(4.5, 7, 11, 21),
        });
        add({
            .name = family.onFixedVariant,
            .palette = family.palette,
            .tone = monochromeOr(family.onVariantMonochrome, family.onVariantDefault),
            .background = this->ref(dim),
            .secondBackground = this->ref(fixed),
            .contrastCurve = curve(3, 4.5, 7, 11),
        });
    }

    return colors;
}

Spec::Colors Spec::colors2025() const {
    Colors colors;
    const auto add = [&colors](Color options) {
        Color color = Color::fromPalette(std::move(options));
        const std::string name = color.name;
        colors.emplace(name, std::move(color));
    };
    const auto neutralYellow = [](SchemeRef s) {
        return Hct::isYellow(s.neutralPalette.hue());
    };
    const auto surfaceBoost = [neutralYellow](double neutral, double tonalSpot, double expressiveYellow,
                                  double expressive, double vibrant) -> ToneFn {
        return [=](SchemeRef s) {
            switch (s.variant) {
            case Variant::Neutral:
                return neutral;
            case Variant::TonalSpot:
                return tonalSpot;
            case Variant::Expressive:
                return neutralYellow(s) ? expressiveYellow : expressive;
            case Variant::Vibrant:
                return vibrant;
            default:
                return 1.0;
            }
        };
    };
    const auto phoneOnly = [](ToneFn boost) -> ToneFn {
        return [boost](SchemeRef s) {
            return isPhone(s) ? boost(s) : 1.0;
        };
    };

    add({
        .name = "surface",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (!isPhone(s)) {
                return 0.0;
            }

            if (s.isDark) {
                return 4.0;
            }

            if (neutralYellow(s)) {
                return 99.0;
            }

            return s.variant == Variant::Vibrant ? 97.0 : 98.0;
        },
        .isBackground = true,
    });
    add({
        .name = "surfaceDim",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (s.isDark) {
                return 4.0;
            }

            if (neutralYellow(s)) {
                return 90.0;
            }

            return s.variant == Variant::Vibrant ? 85.0 : 87.0;
        },
        .isBackground = true,
        .chromaMultiplier = [boost = surfaceBoost(2.5, 1.7, 2.7, 1.75, 1.36)](SchemeRef s) {
            return s.isDark ? 1.0 : boost(s);
        },
    });
    add({
        .name = "surfaceBright",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (s.isDark) {
                return 18.0;
            }

            if (neutralYellow(s)) {
                return 99.0;
            }

            return s.variant == Variant::Vibrant ? 97.0 : 98.0;
        },
        .isBackground = true,
        .chromaMultiplier = [boost = surfaceBoost(2.5, 1.7, 2.7, 1.75, 1.36)](SchemeRef s) {
            return s.isDark ? boost(s) : 1.0;
        },
    });
    add({ .name = "surfaceContainerLowest", .palette = neutralOf, .tone = darkLight(0, 100), .isBackground = true });
    add({
        .name = "surfaceContainerLow",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (!isPhone(s)) {
                return 15.0;
            }

            if (s.isDark) {
                return 6.0;
            }

            if (neutralYellow(s)) {
                return 98.0;
            }

            return s.variant == Variant::Vibrant ? 95.0 : 96.0;
        },
        .isBackground = true,
        .chromaMultiplier = phoneOnly(surfaceBoost(1.3, 1.25, 1.3, 1.15, 1.08)),
    });
    add({
        .name = "surfaceContainer",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (!isPhone(s)) {
                return 20.0;
            }

            if (s.isDark) {
                return 9.0;
            }

            if (neutralYellow(s)) {
                return 96.0;
            }

            return s.variant == Variant::Vibrant ? 92.0 : 94.0;
        },
        .isBackground = true,
        .chromaMultiplier = phoneOnly(surfaceBoost(1.6, 1.4, 1.6, 1.3, 1.15)),
    });
    add({
        .name = "surfaceContainerHigh",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (!isPhone(s)) {
                return 25.0;
            }

            if (s.isDark) {
                return 12.0;
            }

            if (neutralYellow(s)) {
                return 94.0;
            }

            return s.variant == Variant::Vibrant ? 90.0 : 92.0;
        },
        .isBackground = true,
        .chromaMultiplier = phoneOnly(surfaceBoost(1.9, 1.5, 1.95, 1.45, 1.22)),
    });
    add({
        .name = "surfaceContainerHighest",
        .palette = neutralOf,
        .tone = [neutralYellow](SchemeRef s) {
            if (s.isDark) {
                return 15.0;
            }

            if (neutralYellow(s)) {
                return 92.0;
            }

            return s.variant == Variant::Vibrant ? 88.0 : 90.0;
        },
        .isBackground = true,
        .chromaMultiplier = surfaceBoost(2.2, 1.7, 2.3, 1.6, 1.29),
    });
    add({
        .name = "onSurface",
        .palette = neutralOf,
        .tone = [this](SchemeRef s) {
            if (s.variant == Variant::Vibrant) {
                return tMaxC(s.neutralPalette, 0, 100, 1.1);
            }

            return Color::initialToneFromBackground(this->highestSurfaceOrContainerFn())(s);
        },
        .chromaMultiplier = neutralChromaMultiplier2025,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return s.isDark && isPhone(s) ? getCurve(11) : getCurve(9);
        },
    });
    add({
        .name = "onSurfaceVariant",
        .palette = neutralOf,
        .chromaMultiplier = neutralChromaMultiplier2025,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            if (isPhone(s) && s.isDark) {
                return getCurve(6);
            }

            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
    });
    add({
        .name = "outline",
        .palette = neutralOf,
        .chromaMultiplier = neutralChromaMultiplier2025,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(3) : getCurve(4.5);
        },
    });
    add({
        .name = "outlineVariant",
        .palette = neutralOf,
        .chromaMultiplier = neutralChromaMultiplier2025,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(1.5) : getCurve(3);
        },
    });
    add({ .name = "inverseSurface", .palette = neutralOf, .tone = darkLight(98, 4), .isBackground = true });
    add({
        .name = "inverseOnSurface",
        .palette = neutralOf,
        .background = this->ref("inverseSurface"),
        .contrastCurve = getCurveFn(7),
    });

    add({
        .name = "primary",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.primaryPalette;
            const bool phone = isPhone(s);
            switch (s.variant) {
            case Variant::Neutral:
                return s.isDark && phone ? 80.0 : (phone ? 40.0 : 90.0);
            case Variant::TonalSpot:
                if (s.isDark && phone) {
                    return 80.0;
                }

                return phone ? tMaxC(p) : tMaxC(p, 0, 90);
            case Variant::Expressive:
                if (!phone) {
                    return tMaxC(p);
                }

                if (Hct::isYellow(p.hue())) {
                    return tMaxC(p, 0, 25);
                }

                return Hct::isCyan(p.hue()) ? tMaxC(p, 0, 88) : tMaxC(p, 0, 98);
            case Variant::Vibrant:
                if (!phone) {
                    return tMaxC(p);
                }

                return Hct::isCyan(p.hue()) ? tMaxC(p, 0, 88) : tMaxC(p, 0, 98);
            default:
                return 0.0;
            }
        },
        .isBackground = true,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
        .toneDeltaPair = this->phonePairFn("primaryContainer", "primary"),
    });
    add({
        .name = "primaryDim",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            if (s.variant == Variant::Neutral) {
                return 85.0;
            }

            return s.variant == Variant::TonalSpot ? tMaxC(s.primaryPalette, 0, 90) : tMaxC(s.primaryPalette);
        },
        .isBackground = true,
        .background = this->ref("surfaceContainerHigh"),
        .contrastCurve = getCurveFn(4.5),
        .toneDeltaPair = this->pairFn("primaryDim", "primary", 5, TonePolarity::Darker, true, DeltaConstraint::Farther),
    });
    add({
        .name = "onPrimary",
        .palette = primaryOf,
        .background = this->byPlatformFn("primary", "primaryDim"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });
    add({
        .name = "primaryContainer",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.primaryPalette;
            if (s.platform == Platform::Watch) {
                return 30.0;
            }

            switch (s.variant) {
            case Variant::Neutral:
                return s.isDark ? 30.0 : 90.0;
            case Variant::TonalSpot:
                return s.isDark ? tMinC(p, 35, 93) : tMaxC(p, 0, 90);
            case Variant::Expressive:
                if (s.isDark) {
                    return tMaxC(p, 30, 93);
                }

                return Hct::isCyan(p.hue()) ? tMaxC(p, 78, 88) : tMaxC(p, 78, 90);
            case Variant::Vibrant:
                if (s.isDark) {
                    return tMinC(p, 66, 93);
                }

                return Hct::isCyan(p.hue()) ? tMaxC(p, 66, 88) : tMaxC(p, 66, 93);
            default:
                return 0.0;
            }
        },
        .isBackground = true,
        .background = this->phoneHighestSurfaceFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            if (isPhone(s) && s.contrastLevel > 0) {
                return getCurve(1.5);
            }

            return std::nullopt;
        },
        .toneDeltaPair = this->watchPairFn("primaryContainer", "primaryDim"),
    });
    add({
        .name = "onPrimaryContainer",
        .palette = primaryOf,
        .background = this->ref("primaryContainer"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });
    add({
        .name = "inversePrimary",
        .palette = primaryOf,
        .tone = [](SchemeRef s) {
            return tMaxC(s.primaryPalette);
        },
        .background = this->ref("inverseSurface"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });

    add({
        .name = "secondary",
        .palette = secondaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.secondaryPalette;
            if (s.platform == Platform::Watch) {
                return s.variant == Variant::Neutral ? 90.0 : tMaxC(p, 0, 90);
            }

            switch (s.variant) {
            case Variant::Neutral:
                return s.isDark ? tMinC(p, 0, 98) : tMaxC(p);
            case Variant::Vibrant:
                return s.isDark ? tMaxC(p, 0, 90) : tMaxC(p, 0, 98);
            default:
                return s.isDark ? 80.0 : tMaxC(p);
            }
        },
        .isBackground = true,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
        .toneDeltaPair = this->phonePairFn("secondaryContainer", "secondary"),
    });
    add({
        .name = "secondaryDim",
        .palette = secondaryOf,
        .tone = [](SchemeRef s) {
            return s.variant == Variant::Neutral ? 85.0 : tMaxC(s.secondaryPalette, 0, 90);
        },
        .isBackground = true,
        .background = this->ref("surfaceContainerHigh"),
        .contrastCurve = getCurveFn(4.5),
        .toneDeltaPair =
            this->pairFn("secondaryDim", "secondary", 5, TonePolarity::Darker, true, DeltaConstraint::Farther),
    });
    add({
        .name = "onSecondary",
        .palette = secondaryOf,
        .background = this->byPlatformFn("secondary", "secondaryDim"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });
    add({
        .name = "secondaryContainer",
        .palette = secondaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.secondaryPalette;
            if (s.platform == Platform::Watch) {
                return 30.0;
            }

            if (s.variant == Variant::Vibrant) {
                return s.isDark ? tMinC(p, 30, 40) : tMaxC(p, 84, 90);
            }

            if (s.variant == Variant::Expressive) {
                return s.isDark ? 15.0 : tMaxC(p, 90, 95);
            }

            return s.isDark ? 25.0 : 90.0;
        },
        .isBackground = true,
        .background = this->phoneHighestSurfaceFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            if (isPhone(s) && s.contrastLevel > 0) {
                return getCurve(1.5);
            }

            return std::nullopt;
        },
        .toneDeltaPair = this->watchPairFn("secondaryContainer", "secondaryDim"),
    });
    add({
        .name = "onSecondaryContainer",
        .palette = secondaryOf,
        .background = this->ref("secondaryContainer"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });

    add({
        .name = "tertiary",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.tertiaryPalette;
            if (s.platform == Platform::Watch) {
                return s.variant == Variant::TonalSpot ? tMaxC(p, 0, 90) : tMaxC(p);
            }

            if (s.variant == Variant::Expressive || s.variant == Variant::Vibrant) {
                if (Hct::isCyan(p.hue())) {
                    return tMaxC(p, 0, 88);
                }

                return s.isDark ? tMaxC(p, 0, 98) : tMaxC(p, 0, 100);
            }

            return s.isDark ? tMaxC(p, 0, 98) : tMaxC(p);
        },
        .isBackground = true,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
        .toneDeltaPair = this->phonePairFn("tertiaryContainer", "tertiary"),
    });
    add({
        .name = "tertiaryDim",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            return s.variant == Variant::TonalSpot ? tMaxC(s.tertiaryPalette, 0, 90) : tMaxC(s.tertiaryPalette);
        },
        .isBackground = true,
        .background = this->ref("surfaceContainerHigh"),
        .contrastCurve = getCurveFn(4.5),
        .toneDeltaPair =
            this->pairFn("tertiaryDim", "tertiary", 5, TonePolarity::Darker, true, DeltaConstraint::Farther),
    });
    add({
        .name = "onTertiary",
        .palette = tertiaryOf,
        .background = this->byPlatformFn("tertiary", "tertiaryDim"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });
    add({
        .name = "tertiaryContainer",
        .palette = tertiaryOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.tertiaryPalette;
            if (s.platform == Platform::Watch) {
                return s.variant == Variant::TonalSpot ? tMaxC(p, 0, 90) : tMaxC(p);
            }

            switch (s.variant) {
            case Variant::Neutral:
                return s.isDark ? tMaxC(p, 0, 93) : tMaxC(p, 0, 96);
            case Variant::TonalSpot:
                return s.isDark ? tMaxC(p, 0, 93) : tMaxC(p, 0, 100);
            case Variant::Expressive:
                if (Hct::isCyan(p.hue())) {
                    return tMaxC(p, 75, 88);
                }

                return s.isDark ? tMaxC(p, 75, 93) : tMaxC(p, 75, 100);
            case Variant::Vibrant:
                return s.isDark ? tMaxC(p, 0, 93) : tMaxC(p, 72, 100);
            default:
                return 0.0;
            }
        },
        .isBackground = true,
        .background = this->phoneHighestSurfaceFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            if (isPhone(s) && s.contrastLevel > 0) {
                return getCurve(1.5);
            }

            return std::nullopt;
        },
        .toneDeltaPair = this->watchPairFn("tertiaryContainer", "tertiaryDim"),
    });
    add({
        .name = "onTertiaryContainer",
        .palette = tertiaryOf,
        .background = this->ref("tertiaryContainer"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });

    add({
        .name = "error",
        .palette = errorOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.errorPalette;
            if (!isPhone(s)) {
                return tMinC(p);
            }

            return s.isDark ? tMinC(p, 0, 98) : tMaxC(p);
        },
        .isBackground = true,
        .background = this->highestSurfaceOrContainerFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
        .toneDeltaPair = this->phonePairFn("errorContainer", "error"),
    });
    add({
        .name = "errorDim",
        .palette = errorOf,
        .tone = [](SchemeRef s) {
            return tMinC(s.errorPalette);
        },
        .isBackground = true,
        .background = this->ref("surfaceContainerHigh"),
        .contrastCurve = getCurveFn(4.5),
        .toneDeltaPair = this->pairFn("errorDim", "error", 5, TonePolarity::Darker, true, DeltaConstraint::Farther),
    });
    add({
        .name = "onError",
        .palette = errorOf,
        .background = this->byPlatformFn("error", "errorDim"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(6) : getCurve(7);
        },
    });
    add({
        .name = "errorContainer",
        .palette = errorOf,
        .tone = [](SchemeRef s) {
            const TonalPalette& p = s.errorPalette;
            if (s.platform == Platform::Watch) {
                return 30.0;
            }

            return s.isDark ? tMinC(p, 30, 93) : tMaxC(p, 0, 90);
        },
        .isBackground = true,
        .background = this->phoneHighestSurfaceFn(),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            if (isPhone(s) && s.contrastLevel > 0) {
                return getCurve(1.5);
            }

            return std::nullopt;
        },
        .toneDeltaPair = this->watchPairFn("errorContainer", "errorDim"),
    });
    add({
        .name = "onErrorContainer",
        .palette = errorOf,
        .background = this->ref("errorContainer"),
        .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
            return isPhone(s) ? getCurve(4.5) : getCurve(7);
        },
    });

    struct Family {
        const char* prefix;
        const char* onFixed;
        const char* onFixedVariant;
        const TonalPalette& (*palette)(SchemeRef);
    };
    const Family families[] = {
        { "primary", "onPrimaryFixed", "onPrimaryFixedVariant", primaryOf },
        { "secondary", "onSecondaryFixed", "onSecondaryFixedVariant", secondaryOf },
        { "tertiary", "onTertiaryFixed", "onTertiaryFixedVariant", tertiaryOf },
    };
    for (const Family& family : families) {
        const std::string container = std::string(family.prefix) + "Container";
        const std::string fixed = std::string(family.prefix) + "Fixed";
        const std::string dim = fixed + "Dim";
        add({
            .name = fixed,
            .palette = family.palette,
            .tone = this->fixedToneFn(container),
            .isBackground = true,
            .background = this->phoneHighestSurfaceFn(),
            .contrastCurve = [](SchemeRef s) -> std::optional<ContrastCurve> {
                if (isPhone(s) && s.contrastLevel > 0) {
                    return getCurve(1.5);
                }

                return std::nullopt;
            },
        });
        add({
            .name = dim,
            .palette = family.palette,
            .tone = [this, fixed](SchemeRef s) {
                return this->color(fixed).getTone(s);
            },
            .isBackground = true,
            .toneDeltaPair = this->pairFn(dim, fixed, 5, TonePolarity::Darker, true, DeltaConstraint::Exact),
        });
        add({
            .name = family.onFixed,
            .palette = family.palette,
            .background = this->ref(dim),
            .contrastCurve = getCurveFn(7),
        });
        add({
            .name = family.onFixedVariant,
            .palette = family.palette,
            .background = this->ref(dim),
            .contrastCurve = getCurveFn(4.5),
        });
    }

    return colors;
}

Color Spec::extend(const Color& original, const Color& extended) const {
    if (original.name != extended.name) {
        throw std::invalid_argument("extending " + original.name + " with " + extended.name);
    }

    if (original.isBackground != extended.isBackground) {
        throw std::invalid_argument("extending " + original.name + " across background and foreground");
    }

    const auto orig = std::make_shared<const Color>(original);
    const auto ext = std::make_shared<const Color>(extended);
    const auto choose = [orig, ext](SchemeRef s) -> const Color& {
        return s.specVersion == SpecVersion::V2025 ? *ext : *orig;
    };

    Color result;
    result.name = original.name;
    result.isBackground = original.isBackground;
    result.palette = [choose](SchemeRef s) -> const TonalPalette& {
        return choose(s).palette(s);
    };
    result.tone = [choose, orig](SchemeRef s) {
        const Color& chosen = choose(s);
        return chosen.tone ? chosen.tone(s) : orig->tone(s);
    };
    result.chromaMultiplier = [choose](SchemeRef s) {
        const Color& chosen = choose(s);
        return chosen.chromaMultiplier ? chosen.chromaMultiplier(s) : 1.0;
    };
    result.background = [choose](SchemeRef s) -> const Color* {
        const Color& chosen = choose(s);
        return chosen.background ? chosen.background(s) : nullptr;
    };
    result.secondBackground = [choose](SchemeRef s) -> const Color* {
        const Color& chosen = choose(s);
        return chosen.secondBackground ? chosen.secondBackground(s) : nullptr;
    };
    result.contrastCurve = [choose](SchemeRef s) -> std::optional<ContrastCurve> {
        const Color& chosen = choose(s);
        return chosen.contrastCurve ? chosen.contrastCurve(s) : std::nullopt;
    };
    result.toneDeltaPair = [choose](SchemeRef s) -> std::optional<ToneDeltaPair> {
        const Color& chosen = choose(s);
        return chosen.toneDeltaPair ? chosen.toneDeltaPair(s) : std::nullopt;
    };
    return result;
}

Color Spec::clone(std::string_view source, std::string_view name) const {
    Color copy = this->color(source);
    copy.name = std::string(name);
    return copy;
}

Spec::Spec() {
    Colors originals = this->colors2021();
    Colors extensions = this->colors2025();

    const auto store = [this](Color color) {
        const std::string name = color.name;
        this->mColors.emplace(name, std::make_unique<Color>(std::move(color)));
    };

    // Colours whose 2025 definition replaces the 2021 one by variant of the scheme, then the 2025-only colours,
    // then those only the 2021 spec defines.
    for (const std::string_view name : kColorNames) {
        const auto original = originals.find(name);
        const auto extension = extensions.find(name);
        if (original != originals.end() && extension != extensions.end()) {
            store(this->extend(original->second, extension->second));
        } else if (extension != extensions.end()) {
            store(extension->second);
        } else if (original != originals.end()) {
            store(original->second);
        }
    }

    // These start from another colour's final definition.
    const auto replace = [this, &originals, &store](std::string_view name, Color extended) {
        this->mColors.erase(this->mColors.find(name));
        store(this->extend(originals.find(name)->second, extended));
    };
    replace("surfaceVariant", this->clone("surfaceContainerHighest", "surfaceVariant"));
    replace("surfaceTint", this->clone("primary", "surfaceTint"));
    replace("background", this->clone("surface", "background"));

    Color onBackground = this->clone("onSurface", "onBackground");
    onBackground.tone = [this](SchemeRef s) {
        return s.platform == Platform::Watch ? 100.0 : this->color("onSurface").getTone(s);
    };
    replace("onBackground", onBackground);
}

const Color& Spec::color(std::string_view name) const {
    const auto it = this->mColors.find(name);
    if (it == this->mColors.end()) {
        throw std::out_of_range("unknown dynamic colour " + std::string(name));
    }

    return *it->second;
}

std::vector<const Color*> Spec::all() const {
    std::vector<const Color*> colors;
    for (const std::string_view name : kColorNames) {
        colors.push_back(&this->color(name));
    }

    return colors;
}

const Spec& spec() {
    static const Spec instance;
    return instance;
}

} // namespace

const std::vector<const DynamicColor*>& allDynamicColors() {
    static const std::vector<const DynamicColor*> colors = spec().all();
    return colors;
}

} // namespace burl::colour
