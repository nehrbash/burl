#pragma once

#include <array>
#include <cstdint>

// Port of materialyoucolor 3.0.2 (hct/, utils/color_utils.py, utils/math_utils.py, blend/blend.py), itself a port of
// Google's material-color-utilities (Apache-2.0). Operation order follows materialyoucolor so results are identical.
namespace burl::colour {

using Vec3 = std::array<double, 3>;

// Exact comparison, spelled out because the project builds with -Wfloat-equal.
bool exactlyEqual(double a, double b);

// Float modulo whose result takes the sign of the divisor.
double pyMod(double a, double b);

// Rounds half to even.
double pyRound(double x);

double sanitizeDegrees(double degrees);
int sanitizeDegreesInt(int degrees);
double lerp(double start, double stop, double amount);
double clampDouble(double low, double high, double value);
double signum(double value);
double differenceDegrees(double a, double b);
double rotationDirection(double from, double to);

std::uint32_t argbFromRgb(int red, int green, int blue);
std::uint32_t argbFromLinrgb(const Vec3& linrgb);
std::uint32_t argbFromXyz(double x, double y, double z);
std::uint32_t argbFromLstar(double lstar);
double linearized(int component);
int delinearized(double component);
double lstarFromArgb(std::uint32_t argb);
double lstarFromY(double y);
double yFromLstar(double lstar);
Vec3 labFromArgb(std::uint32_t argb);

struct Cam16 {
    double hue = 0.0;
    double chroma = 0.0;
    double j = 0.0;
    double q = 0.0;
    double m = 0.0;
    double s = 0.0;
    double jstar = 0.0;
    double astar = 0.0;
    double bstar = 0.0;

    static Cam16 fromInt(std::uint32_t argb);
    static Cam16 fromUcs(double jstar, double astar, double bstar);
    std::uint32_t toInt() const;
};

class Hct {
public:
    static Hct fromInt(std::uint32_t argb);
    static Hct fromHct(double hue, double chroma, double tone);

    static bool isBlue(double hue);
    static bool isYellow(double hue);
    static bool isCyan(double hue);

    std::uint32_t toInt() const { return this->mArgb; }

    double hue() const { return this->mHue; }

    double chroma() const { return this->mChroma; }

    double tone() const { return this->mTone; }

    // Re-solves the colour, so hue and tone may shift to the nearest displayable values.
    void setChroma(double chroma);

private:
    explicit Hct(std::uint32_t argb);
    void setInternalState(std::uint32_t argb);

    double mHue = 0.0;
    double mChroma = 0.0;
    double mTone = 0.0;
    std::uint32_t mArgb = 0;
};

std::uint32_t blendCam16Ucs(std::uint32_t from, std::uint32_t to, double amount);

} // namespace burl::colour
