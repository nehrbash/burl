pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme: "nocturne"
    property string flavour: "default"
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    property bool cooldownPending
    property real lastBaseTransparency

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        // scheme.json is written by burl-py while this FileView watches it, so
        // a read can land mid-write. Throwing here would leave the palette
        // half-applied until the next write.
        let scheme;
        try {
            scheme = JSON.parse(data);
        } catch (e) {
            return;
        }
        if (!scheme?.colours)
            return;

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }

    function reloadScheme(): void {
        schemeFile.reload();
    }

    function setMode(mode: string): void {
        Schemes.setMode(mode);
    }

    // Always `eval hl.layer_rule(...)`, never `hyprctl keyword` — hyprland's
    // non-legacy parser refuses keyword outright, and Hypr.usingLua reads
    // FALSE here despite lua being the actual parser, so the keyword branch
    // silently never applied these rules.
    function reloadHyprRules(): void {
        const match = `match = { namespace = "qs-drawers" }`;
        const ignoreAlpha = Math.max(0, transparency.base - 0.03);
        Hypr.extras.batchMessage([`eval hl.layer_rule({ ${match}, blur = ${transparency.enabled} })`, `eval hl.layer_rule({ ${match}, ignore_alpha = ${ignoreAlpha} })`]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: root.requestReloadHyprRules()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    FileView {
        id: schemeFile
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#5a77ab"
        property color m3secondary_paletteKeyColor: "#6d778e"
        property color m3tertiary_paletteKeyColor: "#966699"
        property color m3neutral_paletteKeyColor: "#76777b"
        property color m3neutral_variant_paletteKeyColor: "#747780"
        property color m3background: "#111319"
        property color m3onBackground: "#efe3ca"
        property color m3surface: "#111319"
        property color m3surfaceDim: "#111319"
        property color m3surfaceBright: "#38393d"
        property color m3surfaceContainerLowest: "#0c0e13"
        property color m3surfaceContainerLow: "#161920"
        property color m3surfaceContainer: "#1b1e26"
        property color m3surfaceContainerHigh: "#252933"
        property color m3surfaceContainerHighest: "#303540"
        property color m3onSurface: "#efe3ca"
        property color m3surfaceVariant: "#43474f"
        property color m3onSurfaceVariant: "#c8c3b9"
        property color m3inverseSurface: "#e3e2e7"
        property color m3inverseOnSurface: "#2f3034"
        property color m3outline: "#96928b"
        property color m3outlineVariant: "#484a51"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#c7ae7b"
        property color m3primary: "#c7ae7b"
        property color m3onPrimary: "#251e10"
        property color m3primaryContainer: "#514329"
        property color m3onPrimaryContainer: "#f3dfb4"
        property color m3inversePrimary: "#415e91"
        property color m3secondary: "#aebdcb"
        property color m3onSecondary: "#19232e"
        property color m3secondaryContainer: "#3d475b"
        property color m3onSecondaryContainer: "#abb5ce"
        property color m3tertiary: "#baa4d0"
        property color m3onTertiary: "#2c203a"
        property color m3tertiaryContainer: "#b280b4"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#d7e3ff"
        property color m3primaryFixedDim: "#aac7ff"
        property color m3onPrimaryFixed: "#001b3e"
        property color m3onPrimaryFixedVariant: "#284777"
        property color m3secondaryFixed: "#d8e2fc"
        property color m3secondaryFixedDim: "#bcc7df"
        property color m3onSecondaryFixed: "#111c2e"
        property color m3onSecondaryFixedVariant: "#3d475b"
        property color m3tertiaryFixed: "#ffd6fd"
        property color m3tertiaryFixedDim: "#ecb4ed"
        property color m3onTertiaryFixed: "#310938"
        property color m3onTertiaryFixedVariant: "#623766"
        property color term0: "#353434"
        property color term1: "#8881ff"
        property color term2: "#44def5"
        property color term3: "#ffdcf2"
        property color term4: "#8badd4"
        property color term5: "#9ea5ef"
        property color term6: "#95d0fb"
        property color term7: "#e8d3de"
        property color term8: "#ac9fa9"
        property color term9: "#a39eff"
        property color term10: "#89ecff"
        property color term11: "#c9fff3"
        property color term12: "#aec3da"
        property color term13: "#b7baf8"
        property color term14: "#b7e0ff"
        property color term15: "#ffffff"
    }
}
