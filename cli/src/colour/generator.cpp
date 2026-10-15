// Derived from burl/utils/material/generator.py (gen_scheme).

#include "colour.hpp"
#include "dynamic.hpp"

#include <algorithm>
#include <array>
#include <cstdio>
#include <map>
#include <memory>
#include <string_view>

namespace burl::colour {

namespace {

using HctPtr = std::shared_ptr<Hct>;

// Insertion-ordered: reassigning a key keeps its position. Values are shared because some entries alias others and
// are mutated in place.
class OrderedColours {
public:
    void set(const std::string& name, HctPtr value) {
        const auto it = this->mIndex.find(name);
        if (it != this->mIndex.end()) {
            this->mItems[it->second].second = std::move(value);
            return;
        }

        this->mIndex.emplace(name, this->mItems.size());
        this->mItems.emplace_back(name, std::move(value));
    }

    void set(const std::string& name, const Hct& value) { this->set(name, std::make_shared<Hct>(value)); }

    const HctPtr& get(const std::string& name) const { return this->mItems.at(this->mIndex.at(name)).second; }

    const std::vector<std::pair<std::string, HctPtr>>& items() const { return this->mItems; }

private:
    std::vector<std::pair<std::string, HctPtr>> mItems;
    std::map<std::string, std::size_t> mIndex;
};

Hct hexToHct(std::uint32_t rgb) {
    return Hct::fromInt(0xFF000000U | rgb);
}

const std::array<std::uint32_t, 16> kLightGruvbox = {
    0xFDF9F3, 0xFF6188, 0xA9DC76, 0xFC9867, 0xFFD866, 0xF47FD4, 0x78DCE8, 0x333034,
    0x121212, 0xFF6188, 0xA9DC76, 0xFC9867, 0xFFD866, 0xF47FD4, 0x78DCE8, 0x333034,
};

const std::array<std::uint32_t, 16> kDarkGruvbox = {
    0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
    0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
};

const std::array<std::uint32_t, 14> kLightCatppuccin = {
    0xdc8a78, 0xdd7878, 0xea76cb, 0x8839ef, 0xd20f39, 0xe64553, 0xfe640b,
    0xdf8e1d, 0x40a02b, 0x179299, 0x04a5e5, 0x209fb5, 0x1e66f5, 0x7287fd,
};

const std::array<std::uint32_t, 14> kDarkCatppuccin = {
    0xf5e0dc, 0xf2cdcd, 0xf5c2e7, 0xcba6f7, 0xf38ba8, 0xeba0ac, 0xfab387,
    0xf9e2af, 0xa6e3a1, 0x94e2d5, 0x89dceb, 0x74c7ec, 0x89b4fa, 0xb4befe,
};

const std::array<std::pair<std::string_view, std::uint32_t>, 5> kKColours = { {
    { "klink", 0x2980b9 },
    { "kvisited", 0x9b59b6 },
    { "knegative", 0xda4453 },
    { "kneutral", 0xf67400 },
    { "kpositive", 0x27ae60 },
} };

const std::array<std::string_view, 14> kColourNames = {
    "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
    "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender",
};

Hct lighten(const Hct& colour, double amount) {
    const double diff = (100 - colour.tone()) * amount;
    return Hct::fromHct(colour.hue(), colour.chroma() + diff / 5, colour.tone() + diff);
}

Hct darken(const Hct& colour, double amount) {
    const double diff = colour.tone() * amount;
    return Hct::fromHct(colour.hue(), colour.chroma() - diff / 5, colour.tone() - diff);
}

Hct grayscale(const Hct& colour, bool light) {
    Hct result = light ? darken(colour, 0.35) : lighten(colour, 0.65);
    result.setChroma(0);
    return result;
}

Hct mix(const Hct& a, const Hct& b, double weight) {
    return Hct::fromInt(blendCam16Ucs(a.toInt(), b.toInt(), weight));
}

Hct harmonize(const Hct& from, const Hct& to, double toneBoost) {
    const double difference = differenceDegrees(from.hue(), to.hue());
    const double rotationDegrees = std::min(difference * 0.8, 100.0);
    const double outputHue = sanitizeDegrees(from.hue() + rotationDegrees * rotationDirection(from.hue(), to.hue()));
    return Hct::fromHct(outputHue, from.chroma(), from.tone() * (1 + toneBoost));
}

Variant variantFromName(const std::string& name) {
    if (name == "content") {
        return Variant::Content;
    }

    if (name == "expressive") {
        return Variant::Expressive;
    }

    if (name == "fidelity") {
        return Variant::Fidelity;
    }

    if (name == "fruitsalad") {
        return Variant::FruitSalad;
    }

    if (name == "monochrome") {
        return Variant::Monochrome;
    }

    if (name == "neutral") {
        return Variant::Neutral;
    }

    if (name == "rainbow") {
        return Variant::Rainbow;
    }

    if (name == "tonalspot") {
        return Variant::TonalSpot;
    }

    return Variant::Vibrant;
}

std::string hexOf(const Hct& colour) {
    char buffer[7];
    std::snprintf(buffer, sizeof(buffer), "%06x", colour.toInt() & 0xFFFFFFU);
    return buffer;
}

bool startsWith(const std::string& text, std::string_view prefix) {
    return text.compare(0, prefix.size(), prefix) == 0;
}

} // namespace

Colours generate(const Selection& selection, std::uint32_t sourceArgb) {
    const bool light = selection.mode == "light";
    const bool monochrome = selection.variant == "monochrome";
    const bool hard = selection.flavour == "hard";

    const Hct primary = Hct::fromInt(sourceArgb);
    OrderedColours colours;

    const DynamicScheme scheme(primary, variantFromName(selection.variant), 0, !light);
    for (const DynamicColor* colour : allDynamicColors()) {
        colours.set(colour->name, colour->getHct(scheme));
    }

    for (const char* name : { "primary", "secondary", "tertiary", "neutral" }) {
        colours.set(std::string(name) + "_paletteKeyColor", colours.get(std::string(name) + "PaletteKeyColor"));
    }

    colours.set("neutral_variant_paletteKeyColor", colours.get("neutralVariantPaletteKeyColor"));

    const Hct keyColour = *colours.get("primary_paletteKeyColor");
    const auto& gruvbox = light ? kLightGruvbox : kDarkGruvbox;
    for (std::size_t i = 0; i < gruvbox.size(); ++i) {
        const Hct hct = hexToHct(gruvbox[i]);
        const std::string name = "term" + std::to_string(i);
        if (monochrome) {
            colours.set(name, grayscale(hct, light));
        } else {
            colours.set(name, harmonize(hct, keyColour, (i < 8 ? 0.35 : 0.2) * (light ? -1 : 1)));
        }
    }

    const auto& catppuccin = light ? kLightCatppuccin : kDarkCatppuccin;
    for (std::size_t i = 0; i < catppuccin.size(); ++i) {
        const Hct hct = hexToHct(catppuccin[i]);
        const std::string name(kColourNames[i]);
        if (monochrome) {
            colours.set(name, grayscale(hct, light));
        } else {
            colours.set(name, harmonize(hct, keyColour, light ? -0.2 : 0.05));
        }
    }

    for (const auto& [name, rgb] : kKColours) {
        const Hct hct = hexToHct(rgb);
        const std::string key(name);
        const std::string highlight = key + "Selection";
        colours.set(key, harmonize(hct, *colours.get("primary"), 0.1));
        colours.set(highlight, harmonize(hct, *colours.get("onPrimaryFixedVariant"), 0.1));
        if (monochrome) {
            colours.set(key, grayscale(*colours.get(key), light));
            colours.set(highlight, grayscale(*colours.get(highlight), light));
        }
    }

    if (selection.variant == "neutral") {
        for (const auto& item : colours.items()) {
            item.second->setChroma(item.second->chroma() - 15);
        }
    }

    const auto shade = [light](const Hct& colour, double lightAmount, double darkAmount) {
        return light ? lighten(colour, lightAmount) : darken(colour, darkAmount);
    };

    if (hard) {
        std::vector<std::string> names = { "background" };
        for (const auto& item : colours.items()) {
            if (startsWith(item.first, "surface")) {
                names.push_back(item.first);
            }
        }

        for (const std::string& name : names) {
            colours.set(name, shade(*colours.get(name), 0.4, 0.8));
        }

        colours.set("term0", shade(*colours.get("term0"), 0.4, 0.9));
    }

    colours.set("text", colours.get("onBackground"));
    colours.set("subtext1", colours.get("onSurfaceVariant"));
    colours.set("subtext0", colours.get("outline"));
    colours.set("overlay2", mix(*colours.get("surface"), *colours.get("outline"), 0.86));
    colours.set("overlay1", mix(*colours.get("surface"), *colours.get("outline"), 0.71));
    colours.set("overlay0", mix(*colours.get("surface"), *colours.get("outline"), 0.57));
    colours.set("surface2", mix(*colours.get("surface"), *colours.get("outline"), 0.43));
    colours.set("surface1", mix(*colours.get("surface"), *colours.get("outline"), 0.29));
    colours.set("surface0", mix(*colours.get("surface"), *colours.get("outline"), 0.14));
    colours.set("base", colours.get("surface"));
    colours.set("mantle", darken(*colours.get("surface"), 0.03));
    colours.set("crust", darken(*colours.get("surface"), 0.05));

    if (hard) {
        for (const char* name : { "base", "mantle", "crust" }) {
            colours.set(name, shade(*colours.get(name), 0.4, 0.9));
        }

        for (int i = 0; i < 3; ++i) {
            const std::string overlay = "overlay" + std::to_string(i);
            const std::string surface = "surface" + std::to_string(i);
            colours.set(overlay, shade(*colours.get(overlay), 0.4, 0.8));
            colours.set(surface, shade(*colours.get(surface), 0.4, 0.8));
        }
    }

    Colours result;
    result.reserve(colours.items().size() + 4);
    for (const auto& item : colours.items()) {
        result.emplace_back(item.first, hexOf(*item.second));
    }

    if (light) {
        result.emplace_back("success", "4F6354");
        result.emplace_back("onSuccess", "FFFFFF");
        result.emplace_back("successContainer", "D1E8D5");
        result.emplace_back("onSuccessContainer", "0C1F13");
    } else {
        result.emplace_back("success", "B5CCBA");
        result.emplace_back("onSuccess", "213528");
        result.emplace_back("successContainer", "374B3E");
        result.emplace_back("onSuccessContainer", "D1E9D6");
    }

    return result;
}

} // namespace burl::colour
