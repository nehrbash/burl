#pragma once

#include "hct.hpp"
#include "palette.hpp"

#include <functional>
#include <optional>
#include <string>

// Port of materialyoucolor 3.0.2 (dynamiccolor/dynamic_color.py, dynamic_scheme.py, color_spec.py, contrast_curve.py,
// tone_delta_pair.py, variant.py), itself a port of Google's material-color-utilities (Apache-2.0).
namespace burl::colour {

enum class Variant {
    Monochrome = 1,
    Neutral,
    TonalSpot,
    Vibrant,
    Expressive,
    Fidelity,
    Content,
    Rainbow,
    FruitSalad,
};

enum class Platform {
    Phone,
    Watch,
};

enum class SpecVersion {
    V2021,
    V2025,
};

struct ContrastCurve {
    double low;
    double normal;
    double medium;
    double high;

    double get(double contrastLevel) const;
};

struct DynamicScheme {
    // Falls back to the 2021 spec for variants the 2025 spec does not cover.
    DynamicScheme(const Hct& sourceColorHct, Variant variant, double contrastLevel, bool isDark,
        Platform platform = Platform::Phone, SpecVersion specVersion = SpecVersion::V2025);

    Hct sourceColorHct;
    Variant variant;
    double contrastLevel;
    bool isDark;
    Platform platform;
    SpecVersion specVersion;
    TonalPalette primaryPalette;
    TonalPalette secondaryPalette;
    TonalPalette tertiaryPalette;
    TonalPalette neutralPalette;
    TonalPalette neutralVariantPalette;
    TonalPalette errorPalette;
};

struct DynamicColor;

enum class TonePolarity {
    Darker,
    Lighter,
    Nearer,
    Farther,
    RelativeDarker,
    RelativeLighter,
};

enum class DeltaConstraint {
    Exact,
    Nearer,
    Farther,
};

struct ToneDeltaPair {
    const DynamicColor* roleA;
    const DynamicColor* roleB;
    double delta;
    TonePolarity polarity;
    bool stayTogether;
    DeltaConstraint constraint = DeltaConstraint::Exact;
};

using SchemeRef = const DynamicScheme&;

// An empty function member stands for an absent attribute; a function that returns null/nullopt is a defined
// attribute with no value for that scheme. The calculation delegates distinguish the two.
struct DynamicColor {
    using PaletteFn = std::function<const TonalPalette&(SchemeRef)>;
    using ToneFn = std::function<double(SchemeRef)>;
    using ColorFn = std::function<const DynamicColor*(SchemeRef)>;
    using CurveFn = std::function<std::optional<ContrastCurve>(SchemeRef)>;
    using PairFn = std::function<std::optional<ToneDeltaPair>(SchemeRef)>;

    std::string name;
    PaletteFn palette;
    ToneFn tone;
    bool isBackground = false;
    ToneFn chromaMultiplier;
    ColorFn background;
    ColorFn secondBackground;
    CurveFn contrastCurve;
    PairFn toneDeltaPair;

    // Throws std::invalid_argument on invalid attribute combinations.
    static DynamicColor fromPalette(DynamicColor options);
    static ToneFn initialToneFromBackground(ColorFn background);

    Hct getHct(SchemeRef scheme) const;
    double getTone(SchemeRef scheme) const;

    static double foregroundTone(double bgTone, double ratio);
    static bool tonePrefersLightForeground(double tone);
};

// MaterialDynamicColors().all_colors: every colour of the default (2025) spec, in definition order.
const std::vector<const DynamicColor*>& allDynamicColors();

} // namespace burl::colour
