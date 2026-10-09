import QtQuick

// One animated scalar any surface can interpolate against, so a panel/vine/
// graph "grows" instead of appearing. Never animate per-element objects —
// bind them all to this single `progress`.
//
//   GrowIn { id: grow }
//   transform: Scale { origin.x: 0; xScale: grow.progress }
//   ...  onVisibleChanged: if (visible) grow.grow()
//
// Element stagger is derived arithmetic off `progress`, never a second
// animator. The per-index delay MUST be capped, or elements past
// spread/step never reach 1 and simply never appear:
//   Math.max(0, Math.min(1, grow.progress * (1 + spread) - Math.min(spread, index * step)))
// with spread the total lead-in (0.5) and step the per-index delay. At
// progress 1 every index lands on 1 no matter how long the list is.
//
// Respects Ambience.grow: when off, `progress` snaps to 1 and nothing ticks.
// Idle cost: one stopped animation.
Anim {
    id: root

    property real progress: 1
    property bool enabled: Ambience.grow

    function grow(): void {
        root.stop();
        if (!root.enabled) {
            root.progress = 1;
            return;
        }
        root.progress = 0;
        root.start();
    }

    function snap(): void {
        root.stop();
        root.progress = 1;
    }

    target: root
    properties: "progress"
    from: 0
    to: 1
    type: Anim.SlowSpatial
    running: false
}
