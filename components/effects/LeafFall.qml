pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl.Config
import qs.components

// Ambient falling leaves for an OPEN surface. Five painted species tumble, slip
// sideways on a gust and settle out near the bottom edge instead of being cut
// off mid-air.
//
//   LeafFall { anchors.fill: parent; active: root.visible && !GameMode.enabled }
//
// WHY A Repeater AND NOT ParticleSystem
// The leaf art is 256x256 and is drawn at 26-42px. ImageParticle exposes
// neither `sourceSize` nor `mipmap`, so it would minify the source ~6x with
// plain linear filtering — on a 240Hz panel that shimmers on every rotating
// sprite. An Image can do both. Two secondary wins: an ImageParticle draws one
// texture, so random species choice would need five particle groups (five
// emitters + five painters), and per-leaf easing curves (Tokens.anim.*) are not
// expressible with affectors at all.
//
// PER-SURFACE BUDGET (hard, not advisory)
//   * live leaves == maxLeaves, always: one delegate owns exactly one leaf and
//     never spawns a second. Keep the cap in the low tens (<= 18). Current
//     callers: sidebar 12.
//   * per leaf: 1 wrapper Item (draws nothing) + 1 Image (one textured quad),
//     and 4 concurrently running NumberAnimations — fall/settle, drift, opacity
//     and rock/flutter; the sequential ones only ever have one leg live. At 18
//     leaves that is <= 90 property writes per frame, all applied by Qt's C++
//     animation driver: no geometry rebuilds, no Canvas, no Shape, no paintTick,
//     and no repaint beyond the moved quads.
//   * JS per frame: none. launch() is the only script, and it runs once per leaf
//     per fall — about two calls a second across a whole surface.
//   * textures: sprites.length (5) for the whole surface, shared by every leaf,
//     because every leaf asks for the SAME sourceSize (`texSize`). A per-leaf
//     sourceSize would key a separate pixmap-cache entry per leaf, so size
//     variance comes from the item box and never from sourceSize.
//   * zero cost when hidden: `running` false collapses the model to 0, which
//     destroys every delegate and with it every animation. No timers survive,
//     nothing ticks, nothing is drawn. Honours Ambience.leaves; callers add
//     `&& !GameMode.enabled`.
Item {
    id: root

    // Bind to the surface's real visibility AND (at the call site) !GameMode.enabled.
    property bool active: false
    // Leaves entering per second. Sets how thinly the leaves are spread in time
    // (the random pre-roll each leaf waits before falling again), so a low rate
    // reads as a sparse sky without touching the cap. Average leaves in the air
    // is maxLeaves * airtime / (airtime + maxLeaves / (2 * rate)) — at rate 2
    // and maxLeaves 12 that measured ~9 of 12, dipping to 3 at the troughs.
    property real rate: 3
    // HARD cap on live leaves — one delegate each.
    property int maxLeaves: 18
    // Sideways gust in px/s. Positive drifts right; one leaf in four slips
    // upwind so the fall never looks like a single conveyor.
    property real wind: 12
    // Base leaf edge in px, before the per-leaf depth scale. This is a BOX edge,
    // not the painted leaf: the art fills 84-98% of its square canvas on the
    // long axis, so the painted silhouette is 0.84..0.98 of the box. 32 puts the
    // mid-depth box at 34.9px and the mid-depth painted leaf at 29-34px tall and
    // 20-28px wide — the width at which the five silhouettes are individually
    // identifiable rather than a row of dark lozenges.
    property real size: 32
    // The painted set. All five are 256x256, each trimmed to its own alpha bbox
    // and re-centred symmetrically (margins match within 1px), so `rotation`
    // spins about the item centre with no offset math AND every species reaches
    // near the canvas edge — the shipped long-axis fill is aspen 84.0%, birch
    // 89.1%, elm 91.4%, maple 96.9%, oak 97.7%, widths 148..203px. The fills are
    // deliberately not all 100%: the spread preserves the species' relative
    // weight (aspen lightest, oak/maple heaviest) while compressing the painted
    // area ratio to 1.35x, so no species is small enough to lose its outline.
    // Willow is gone — a 55x201 blade drew a 4-8px stick at every depth and read
    // as a twig, never as a leaf.
    property list<url> sprites: [
        Quickshell.shellPath("assets/images/leaves/leaf-oak.png"),
        Quickshell.shellPath("assets/images/leaves/leaf-maple.png"),
        Quickshell.shellPath("assets/images/leaves/leaf-elm.png"),
        Quickshell.shellPath("assets/images/leaves/leaf-birch.png"),
        Quickshell.shellPath("assets/images/leaves/leaf-aspen.png")
    ]

    readonly property bool running: root.active && Ambience.leaves
    // Decode size shared by every leaf: one cache entry per species. 64px stays
    // above the largest on-screen box (size * 1.30 = 41.6px), so every leaf is
    // still minified and `mipmap` still has a level to pick — which is what
    // keeps a rotating sprite from shimmering.
    readonly property int texSize: 64
    // Rotates which delegate index gets which species so the same leaf is not
    // always in the same lane. Evaluated once.
    readonly property int speciesOffset: Math.floor(Math.random() * root.sprites.length)

    visible: root.running
    // Decoration: never eat input.
    enabled: false

    Repeater {
        // The gate that makes idling free: no delegates, no animations. The
        // size test is not cosmetic — a delegate draws its whole path from the
        // surface geometry in Component.onCompleted, and anchors have not been
        // applied yet during the surface's own creation, so without it every
        // leaf would fly its first fall against a 0x0 surface. A later resize
        // only restates the path on the leaf's next fall.
        model: root.running && root.width > 0 && root.height > 0 ? root.maxLeaves : 0

        Item {
            id: leaf

            required property int index

            // The one per-cycle value a binding reads. Everything else is
            // assigned straight onto the animation objects by launch(), while
            // the flight is stopped — an animation property that carries a
            // binding re-fires mid-flight and Qt reports it as a binding loop.
            property real leafSize: 0

            // Fixed for the delegate's lifetime: re-picking mid-flight would
            // swap the texture under a visible leaf and churn the pixmap cache.
            readonly property url species: root.sprites[(leaf.index + root.speciesOffset) % root.sprites.length]

            // Draws one fall: size, depth, path, spin and timing, then flies it.
            function launch(): void {
                const rnd = Math.random;
                // The shell's canonical one-second unit; every duration below is
                // a multiple of it.
                const second = Tokens.anim.durations.extraLarge;
                // 0 = far leaf, 1 = near leaf. Depth drives SIZE, SPEED and
                // MOTION AMPLITUDE — never opacity. Coupling opacity to depth
                // made the small leaf also the faint one, and a small faint
                // olive leaf on bark is mud twice over: too little silhouette to
                // read and too little contrast to find. Aerial perspective here
                // is carried by parallax instead (far = slower, gentler, drifts
                // less across the frame), which needs no shader and no alpha.
                const depth = rnd();

                // 0.82..1.30 of base: near/far ratio 1.59, tighter than a
                // literal perspective spread on purpose. The far end is the
                // constraint — 0.82 * 32 = 26.2px box is the smallest box whose
                // narrowest species (aspen, 57.8% wide) still paints a 15px-wide
                // leaf rather than a smudge.
                leaf.leafSize = root.size * (0.82 + depth * 0.48);

                const fallDur = Math.round(second * (7 + (1 - depth) * 6));
                const settleDur = Math.round(second * (1.4 + rnd() * 1.2));
                const airDur = fallDur + settleDur;
                const fadeDur = Math.round(second * 1.2);

                // Stagger: a fresh pre-roll every fall, spread over
                // maxLeaves/rate seconds, so the leaves never re-synchronise.
                preRoll.duration = Math.round(second * (root.maxLeaves / Math.max(root.rate, 0.25)) * rnd());

                // Vertical: in from above the top edge, accelerate down to just
                // shy of the bottom, then creep a little further while fading.
                fallY.from = -leaf.leafSize;
                fallY.to = root.height * 0.88 - leaf.leafSize * 0.5;
                fallY.duration = fallDur;
                settleY.to = fallY.to + leaf.leafSize * 0.45;
                settleY.duration = settleDur;

                // Horizontal: one gust carried across the whole airtime, clamped
                // so a leaf cannot drift out of frame. Scaled by depth as well —
                // the same air moves a near leaf further across the frame than a
                // far one, which is the parallax half of the depth cue.
                const gust = root.wind * (airDur / second) * (0.30 + depth * 0.55 + rnd() * 0.55) * (rnd() < 0.25 ? -1 : 1);
                driftX.from = (root.width - leaf.leafSize) * rnd();
                driftX.to = Math.max(-leaf.leafSize * 0.4, Math.min(root.width - leaf.leafSize * 0.6, driftX.from + gust));
                driftX.duration = airDur;

                // Opacity is independent of depth and floored well clear of mud:
                // 0.78..0.94, mean 0.86. The spread is there only so a clump of
                // leaves is not one flat wash; it is small enough that no leaf is
                // ever the "faint" one. The fade is a lifecycle cue (entering
                // frame, settling out), not a depth cue.
                fadeIn.to = 0.78 + rnd() * 0.16;
                fadeIn.duration = fadeDur;
                hold.duration = Math.max(0, fallDur - fadeDur);
                fadeOut.duration = settleDur;

                // Rock and tumble are one mechanism at two amplitudes: a gentle
                // +-25 deg rock at the low end, most of a full flip at the high
                // end. The start angle is free because the art is centred. Depth
                // biases the amplitude and the clock — a far leaf rocks a little
                // and slowly, a near one flips hard and fast. That, plus the
                // gust scaling above, is what depth buys now that it no longer
                // touches opacity.
                const span = 25 + depth * 80 + rnd() * 95;
                const rockDur = Math.round(second * (1.7 + (1 - depth) * 1.1 + rnd() * 1.6));
                rockOut.from = rnd() * 360 - span;
                rockOut.to = rockOut.from + span * 2;
                rockOut.duration = rockDur;
                rockBack.to = rockOut.from;
                rockBack.duration = rockDur;
                rock.loops = Math.max(1, Math.round(airDur / (rockDur * 2)));

                // Lateral flutter on its own clock, so the sideways slip is not
                // locked to the rocking. The amplitude is already a multiple of
                // leafSize, so depth reaches it for free; only the clock needs
                // the explicit far-is-slower term.
                const swing = leaf.leafSize * (0.35 + rnd() * 0.8);
                const flutterDur = Math.round(second * (1.1 + (1 - depth) * 0.7 + rnd() * 1.5));
                flutterOut.from = -swing;
                flutterOut.to = swing;
                flutterOut.duration = flutterDur;
                flutterBack.to = -swing;
                flutterBack.duration = flutterDur;
                flutter.loops = Math.max(1, Math.round(airDur / (flutterDur * 2)));

                flight.restart();
            }

            width: leaf.leafSize
            height: leaf.leafSize
            opacity: 0

            Component.onCompleted: leaf.launch()

            Image {
                id: sprite

                // No horizontal anchor: `x` is the flutter channel.
                y: 0
                width: parent.width
                height: parent.height
                source: leaf.species
                sourceSize.width: root.texSize
                sourceSize.height: root.texSize
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
                asynchronous: true
            }

            // One fall, then launch() reseeds and restarts it. Re-seeding from
            // `finished` (rather than looping forever) keeps every write to an
            // animation property on a stopped animation.
            SequentialAnimation {
                id: flight

                onFinished: leaf.launch()

                PauseAnimation {
                    id: preRoll
                }

                ParallelAnimation {
                    SequentialAnimation {
                        NumberAnimation {
                            id: fallY

                            target: leaf
                            property: "y"
                            easing: Tokens.anim.standardAccel
                        }

                        NumberAnimation {
                            id: settleY

                            target: leaf
                            property: "y"
                            easing: Tokens.anim.standardDecel
                        }
                    }

                    NumberAnimation {
                        id: driftX

                        target: leaf
                        property: "x"
                        easing: Tokens.anim.standardDecel
                    }

                    SequentialAnimation {
                        NumberAnimation {
                            id: fadeIn

                            target: leaf
                            property: "opacity"
                            from: 0
                            easing: Tokens.anim.standardDecel
                        }

                        PauseAnimation {
                            id: hold
                        }

                        NumberAnimation {
                            id: fadeOut

                            target: leaf
                            property: "opacity"
                            to: 0
                            easing: Tokens.anim.standardAccel
                        }
                    }

                    SequentialAnimation {
                        id: rock

                        NumberAnimation {
                            id: rockOut

                            target: sprite
                            property: "rotation"
                            easing: Tokens.anim.standard
                        }

                        NumberAnimation {
                            id: rockBack

                            target: sprite
                            property: "rotation"
                            easing: Tokens.anim.standard
                        }
                    }

                    SequentialAnimation {
                        id: flutter

                        NumberAnimation {
                            id: flutterOut

                            target: sprite
                            property: "x"
                            easing: Tokens.anim.standard
                        }

                        NumberAnimation {
                            id: flutterBack

                            target: sprite
                            property: "x"
                            easing: Tokens.anim.standard
                        }
                    }
                }
            }
        }
    }
}
