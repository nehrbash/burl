import QtQuick
import QtQuick.Shapes
import qs.components

// A procedural moss crust for the top edge of a bark card. Replaces
// moss-edge.png, whose bottom contour only varied between rows 26 and 36 of 48
// and repeated on a FIXED 256px tile: a ±5px ripple at a fixed period across a
// 600-1400px card is exactly what reads as a straight line.
//
// Three compounding causes, three fixes:
//   1. fixed tiling period   -> one path across the WHOLE width, seeded per card
//   2. constant crust height -> lobe WIDTH and both apex AND valley depth vary,
//      under a low-frequency envelope, with deliberate bald lobes where the
//      bark shows through
//   3. flush against a straight top edge -> the lobes rise ABOVE that line, so
//      the crust sits ON the card's edge rather than inside it, and a clipper
//      would cut exactly that off (hence MossCrust lives outside BarkCard's).
//      Separate cushion circles were tried for this and read as discrete dark
//      dots stuck on the crust.
//
// Tone layering copies moss-ring.svg: the separation from bark comes from the
// DARK underlay, not from the moss colour.
//
// ONE Shape, three ShapePaths, one PathSvg each — never one path per lobe.
// Rebuilt at most once per 90ms and never on a resize frame; the first build is
// synchronous so a freshly laid card never shows a wrong edge for 90ms.
// Idle cost: zero — the Timer is one-shot and nothing repaints after the build.
Item {
    id: root

    // Crust depth BELOW the card's top line.
    property real depth: 28
    // How far the top swells rise ABOVE it. Keep small: this paints outside the
    // card, over whatever is above it.
    property real crest: 4
    // The card's own radius, so the top contour follows its corners.
    property real cornerRadius: 16
    // Distinct per card or every crust grows identically.
    property int seed: 0

    // Alphas in the same range as Woodland.leafFill/leafFillDeep, which is what
    // the rest of the shell's foliage uses: at 0.92 this read as candy green.
    property color deepFill: Qt.alpha(Woodland.mix(Woodland.oliveDark, Woodland.barkEdge, 0.45), 0.82)
    property color bodyFill: Qt.alpha(Woodland.olive, 0.72)
    property color crownFill: Qt.alpha(Woodland.oliveLight, 0.52)

    property bool _built: false

    implicitHeight: root.depth + root.crest

    onWidthChanged: root._schedule()
    onDepthChanged: root._schedule()
    onSeedChanged: root._schedule()
    onCornerRadiusChanged: root._schedule()
    Component.onCompleted: root._schedule()

    function _schedule(): void {
        if (root.width <= 0)
            return;
        if (root._built)
            rebuildTimer.restart();
        else
            root._rebuild();
    }

    // Deterministic 0..1. Never Math.random(): a crust that reshuffled on every
    // dashboard open would read as noise rather than as a place — the same rule
    // the star motes and the bark-grain phase follow.
    function _r(i: int): real {
        const v = Math.sin(i * 127.1 + root.seed * 311.7) * 43758.5453123;
        return v - Math.floor(v);
    }

    // One closed band, drawn as a crust SITTING ON the card's top line: the big
    // irregular lobes go UPWARD, off the card, and only a shallow skirt runs
    // down its face. That way round on purpose — the upward edge is the one
    // against the parchment, where the contrast is, so it is the silhouette the
    // eye actually reads. Lobing only the downward edge (tried first) put all
    // the variation where it was invisible against dark bark and the crust read
    // as scalloped trim.
    //
    // Inset from the card's corners by `cornerRadius`, so the run stays within
    // the flat span of the top edge and never has to follow a corner arc.
    function _band(rise: real, skirt: real, salt: int, floorK: real, lobeMin: real, lobeMax: real): string {
        const t = root.crest;
        const xL = root.cornerRadius * 0.7;
        const xR = root.width - root.cornerRadius * 0.7;
        if (xR - xL < 12)
            return "";

        const vx = [xL];
        const up = [];
        const dn = [];
        let x = xL;
        let i = 0;
        let bald = false;
        while (x < xR) {
            const u0 = root._r(i * 4 + salt);
            const u1 = root._r(i * 4 + 1 + salt);
            const u2 = root._r(i * 4 + 2 + salt);
            const u3 = root._r(i * 4 + 3 + salt);
            x = Math.min(xR, x + (lobeMin + u0 * (lobeMax - lobeMin)));
            // Low-frequency envelope: the crust thickens and thins over ~w/3,
            // which is the read a fixed-period tile can never have.
            const env = 0.70 + 0.30 * Math.sin((x / root.width) * Math.PI * 3.0 + salt * 0.7);
            // A bald lobe drops to the card line so the bark shows through.
            // Never two in a row, or the crust falls apart instead of breaking.
            bald = !bald && u1 < 0.18;
            up.push(bald ? 0 : rise * (floorK + (1 - floorK) * u2) * env);
            dn.push(skirt * (0.45 + 0.55 * u3));
            vx.push(x);
            i++;
        }

        const n = vx.length - 1;
        // A symmetric quadratic peaks only halfway to its control point, so
        // every control overshoots or the lobes land at half height and the
        // whole crust reads as a flat ribbon.
        let s = `M ${xL} ${t}`;
        for (let k = 0; k < n; k++)
            s += ` Q ${(vx[k] + vx[k + 1]) / 2} ${t + dn[k] * 2} ${vx[k + 1]} ${t}`;
        for (let k = n - 1; k >= 0; k--)
            s += ` Q ${(vx[k] + vx[k + 1]) / 2} ${t - up[k] * 2} ${vx[k]} ${t}`;
        return s + " Z";
    }

    function _rebuild(): void {
        if (root.width <= 0)
            return;
        root._built = true;
        const r = Math.max(4, root.crest);
        const k = Math.max(2, root.depth);
        deepSvg.path = root._band(r * 1.00, k * 1.00, 41, 0.42, 13, 32);
        bodySvg.path = root._band(r * 0.86, k * 0.80, 0, 0.40, 11, 28);
        crownSvg.path = root._band(r * 0.50, k * 0.40, 7, 0.45, 8, 19);
    }

    Timer {
        id: rebuildTimer

        interval: 90
        onTriggered: root._rebuild()
    }

    // Deepest band first: it peeks past the body on both edges, which is the
    // moss-ring separation rule — the dark underlay, not the moss colour, is
    // what lifts the crust off the bark.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        visible: root._built

        ShapePath {
            strokeWidth: -1
            fillColor: root.deepFill

            PathSvg {
                id: deepSvg
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.bodyFill

            PathSvg {
                id: bodySvg
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.crownFill

            PathSvg {
                id: crownSvg
            }
        }
    }
}
