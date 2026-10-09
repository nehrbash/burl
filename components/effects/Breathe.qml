import QtQuick
import qs.components

// Slow ambient "breathing" for a resting item. Use as a transform:
//   transform: Breathe { origin.x: width / 2; origin.y: height; amount: 0.035 }
// For HOVER growth do NOT use this — use `Behavior on scale { Anim {} }`,
// which costs nothing at idle (see spec §5).
//
// Cost: one binding per instance while SwayClock runs; zero when `active` is
// false (the instance unsubscribes and the clock stops at 0 subscribers).
Scale {
    id: root

    property real amount: 0.03
    property real rate: 0.5
    property real phaseOffset: 0
    property bool active: true
    readonly property real breath: root.active ? 1 + root.amount * (0.5 + 0.5 * Math.sin(SwayClock.phase * root.rate + root.phaseOffset)) : 1

    // See Sway.qml: refcount state, never signal order. `_subscribed` is the
    // single source of truth and _syncClock() the only mutator, so the count
    // cannot double-increment or double-decrement whatever the signal order.
    property bool _alive: false
    property bool _subscribed: false

    function _syncClock(): void {
        const want = root._alive && root.active;
        if (want === root._subscribed)
            return;
        root._subscribed = want;
        SwayClock.subscribers += want ? 1 : -1;
    }

    xScale: root.breath
    yScale: root.breath

    onActiveChanged: root._syncClock()
    Component.onCompleted: {
        root._alive = true;
        root._syncClock();
    }
    Component.onDestruction: {
        root._alive = false;
        root._syncClock();
    }
}
