import QtQuick
import qs.components

// Wind sway for a hanging/perched item. Use as a transform:
//
//   transform: Sway { origin.x: 0; origin.y: 0; amplitude: 4
//                     phaseOffset: index * 0.8; active: root.visible }
//
// Cost: one binding per instance while SwayClock runs; zero when `active` is
// false (the instance unsubscribes and the clock stops at 0 subscribers).
Rotation {
    id: root

    property real amplitude: 4
    property real phaseOffset: 0
    property bool active: true

    // Refcount bookkeeping. `active` may settle to false *during* creation (a
    // binding's first evaluation emits activeChanged before onCompleted), so
    // the count must never be derived from signal order: `_subscribed` is the
    // single source of truth for "this instance holds one refcount", and
    // _syncClock() is the only place that touches SwayClock.subscribers. It
    // flips at most one count in either direction, so a double-increment or
    // double-decrement is not expressible.
    property bool _alive: false
    property bool _subscribed: false

    function _syncClock(): void {
        const want = root._alive && root.active;
        if (want === root._subscribed)
            return;
        root._subscribed = want;
        SwayClock.subscribers += want ? 1 : -1;
    }

    angle: root.active ? root.amplitude * Math.sin(SwayClock.phase + root.phaseOffset) : 0

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
