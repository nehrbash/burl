pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import Burl.Services
import qs.components
import qs.components.containers
import qs.components.effects
import qs.components.widgets
import qs.services

Item {
    id: root

    required property Item nav

    LoggingCategory {
        id: lcLiving

        name: "burl.qml.livingtree"
        defaultLogLevel: LoggingCategory.Info
    }

    // qmllint disable missing-property
    readonly property var sections: root.nav.sections ?? []
    readonly property string activeId: root.nav.activeSectionId ?? ""
    readonly property string focusedId: root.nav.focusedSectionId ?? ""
    // Plain var, no `as ScreenState` cast: ScreenState is a plain QML component
    // and the cast resolves to null in this URL-mounted file, which pinned openP
    // at 0 and made the whole tree invisible while the dashboard was open.
    readonly property var screenState: root.nav.screenState

    readonly property var openIds: {
        const arr = root.screenState?.dashboardOpenSections;
        return Array.isArray(arr) ? arr : [];
    }
    readonly property string emphasisId: root.openIds.length > 0 ? root.openIds[root.openIds.length - 1] : root.activeId
    // qmllint enable missing-property

    readonly property int na: root.sections.length

    property real geomW: Math.max(1, root.width)
    property real geomH: Math.max(1, root.height)

    // ---- guest hosting ----------------------------------------------------
    // See Content.qml's own `guest` block: when this tree is mounted by the
    // launcher rather than by the dashboard drawer, the host's camera owns the
    // reveal, the drawers window's input mask is none of our business, and
    // dismissing means flying back up rather than closing the drawer.
    readonly property bool guest: root.nav.guest ?? false

    function dismiss(): void {
        root.nav.dismissSurface();
    }

    // Dormant sprout: this instance's tree is grown somewhere else, so only the
    // seed and the hover strip at the bottom edge are live here.
    readonly property bool sproutOnly: root.nav.sproutOnly ?? false

    // The room the tree stands in — the night gradient, the warm
    // trunk bloom and the vignette. It is full-SURFACE, and a guest's surface
    // is pushed down the frame by its host's camera, so the room has to be
    // lifted back by that offset and sized to the screen: left riding with the
    // tree it cut a hard-edged band across the host's top edge instead of
    // covering the frame. `roomP` fades it against the host's own background
    // (the launcher's night sky) as the camera leaves.
    readonly property real roomOffset: root.guest ? (root.nav.guestRoomOffset ?? 0) : 0
    readonly property real roomP: root.guest ? (root.nav.guestRoomP ?? 1) : root.openP

    // ---- whole-tree reveal ------------------------------------------------
    // Bound straight off screenState.dashboard rather than an imperative
    // grow()/ungrow() pair: a plain Behavior handles both directions.
    // NOT readonly: a Behavior intercepts writes, and a binding update is a
    // write — QML rejects "Behavior on <readonly property>" outright.
    property real openP: root.sproutOnly ? 0 : (root.guest ? (root.nav.guestOpenP ?? 1) : (root.screenState?.dashboard ? 1 : 0))

    // Published for Content.qml to forward as its own `growProgress` (read
    // by Wrapper.qml as `content.item?.growProgress`).
    readonly property real growProgress: root.openP

    // ---- hover-to-grow -----------------------------------------------------
    // 0..1, how close the pointer is to the bottom-centre trigger while the
    // tree is closed. Drives ONLY the dormant seed's fade-in (below) — never
    // opens anything by itself. Opening happens exclusively via
    // hoverOpenTimer's dwell (see edgeTrigger); every close path (trunk
    // click, Esc, focus-grab onCleared, SUPER+D) is untouched.
    property real hoverProximity: 0

    Behavior on hoverProximity {
        enabled: Ambience.grow && !GameMode.enabled

        Anim {
            type: Anim.DefaultEffects
        }
    }

    readonly property real trunkX: root.artX + root.artWidth / 2
    readonly property real trunkXHome: root.artXCentred + root.artWidth / 2
    readonly property real trunkRun: 0.30 * root.geomH
    readonly property real trunkTopY: root.geomH - root.trunkRun
    readonly property real trunkWBase: CUtils.clamp(Math.round(root.geomH * 0.05), 40, 88)

    // Lit bark tone, used only by the dormant seed mark below.
    readonly property color barkTone: Woodland.mix(Woodland.barkLit, Woodland.parchment, 0.22)

    readonly property var emberHues: ["#8de8d5", "#b4b2ff", "#8bceff", "#f4a6ca", "#e8d596"]

    function sectionAccent(i: int): color {
        const n = root.emberHues.length;
        return root.emberHues[((i % n) + n) % n];
    }

    // Deterministic (Knuth multiplicative hash) placement for the star motes
    // and falling leaves below — the one piece of the old procedural engine
    // kept, because those two ambient layers need stable, non-reshuffling
    // positions and carry no other dependency on the deleted bough/canopy
    // maths. Never Math.random(): a mote field that reshuffled itself on
    // every open would read as noise rather than as a place.
    function _h(a: int, b: int): real {
        return Math.floor(((a + 1) * 2654435761 + (b + 1) * 40503) % 4294967296);
    }

    readonly property var cards: {
        const live = new Set((root.nav.sections ?? []).filter(s => s?.enabled).map(s => s.id));
        return (root.nav.treeCards ?? []).filter(c => c?.enabled && live.has(c.sectionId));
    }
    readonly property int nc: root.cards.length

    property string selectedCardId: ""

    function reconcileSelection(): void {
        const cur = root.cards.findIndex(c => c.id === root.selectedCardId);
        if (cur >= 0 && root.cards[cur].sectionId === root.emphasisId)
            return;
        const first = root.cards.findIndex(c => c.sectionId === root.emphasisId);
        root.selectedCardId = first >= 0 ? root.cards[first].id : "";
    }

    onEmphasisIdChanged: root.reconcileSelection()

    function stepCard(delta: int): void {
        if (root.nc <= 0)
            return;
        const cur = root.cards.findIndex(c => c.id === root.selectedCardId);
        const next = cur < 0 ? 0 : (cur + delta + root.nc) % root.nc;
        root.selectedCardId = root.cards[next].id;
        root.growSection(root.cards[next].sectionId);
    }

    // ---- section grow/fold (ScreenState's own multi-open algebra, called
    // directly since this file is URL-mounted and Content.qml's `nav` only
    // wraps a subset of ScreenState's dashboard* functions) -----------------
    function growSection(id: string): void {
        if (typeof root.screenState?.growDashboardSection === "function")
            root.screenState.growDashboardSection(id);
        else
            root.nav.selectSection(id);
    }

    function foldSection(id: string): void {
        if (typeof root.screenState?.foldDashboardSection === "function")
            root.screenState.foldDashboardSection(id);
    }

    readonly property real artAspect: 1.12
    readonly property real artHeight: root.geomH * 0.97
    readonly property real artWidth: Math.min(root.geomW * 0.88, root.artHeight * root.artAspect)
    readonly property real artMargin: root.geomW * 0.035
    readonly property real artXCentred: (root.geomW - root.artWidth) / 2
    readonly property real artX: root.artXCentred
    readonly property real artY: root.geomH - root.artHeight
    readonly property real stageZoneW: Math.min(1240, root.geomW * 0.78)
    readonly property real stageZoneX: root.geomW / 2

    readonly property var orbAnchors: [
        {
            u: 0.2545,
            v: 0.2072,
            r: 0.0195
        },
        {
            u: 0.6460,
            v: 0.2132,
            r: 0.0340
        },
        {
            u: 0.6860,
            v: 0.3894,
            r: 0.0360
        },
        {
            u: 0.1648,
            v: 0.4070,
            r: 0.0398
        },
        {
            u: 0.8200,
            v: 0.5273,
            r: 0.0400
        },
        {
            u: 0.2115,
            v: 0.5926,
            r: 0.0365
        }
    ]

    function orbGeom(i: int): var {
        const a = root.orbAnchors[i];
        if (!a)
            return null;
        return {
            x: root.artX + a.u * root.artWidth,
            y: root.artY + a.v * root.artHeight,
            r: a.r * root.artWidth
        };
    }

    readonly property var rootAnchors: [
        { u:0.17,v:0.87 }, { u:0.285,v:0.925 }, { u:0.41,v:0.947 },
        { u:0.59,v:0.938 }, { u:0.73,v:0.91 }, { u:0.855,v:0.865 }
    ]
    property int hoveredRoot: -1

    // Smaller than a section orb (those run 0.034-0.040 of the art width) so
    // the roots read as secondary to the canopy.
    readonly property real rootNodeR: 0.026

    readonly property var sessionActions: [
        {
            id: "lock",
            label: qsTr("Lock"),
            icon: Config.session.icons.lock,
            command: Config.session.commands.lock,
            destructive: false
        },
        {
            id: "logout",
            label: qsTr("Log out"),
            icon: Config.session.icons.logout,
            command: Config.session.commands.logout,
            destructive: false
        },
        {
            id: "reboot",
            label: qsTr("Restart"),
            icon: Config.session.icons.reboot,
            command: Config.session.commands.reboot,
            destructive: false
        },
        {
            id: "windows",
            label: qsTr("Windows"),
            icon: Config.session.icons.windows,
            command: Config.session.commands.windows,
            destructive: false
        },
        {
            id: "hibernate",
            label: qsTr("Hibernate"),
            icon: Config.session.icons.hibernate,
            command: Config.session.commands.hibernate,
            destructive: false
        },
        {
            id: "shutdown",
            label: qsTr("Shut down"),
            icon: Config.session.icons.shutdown,
            command: Config.session.commands.shutdown,
            destructive: true
        }
    ].filter(action => action.command.length > 0)

    function rootNodeGeom(i: int): var {
        const a = root.rootAnchors[i];
        if (!a)
            return null;
        return {
            x: root.artX + a.u * root.artWidth,
            y: root.artY + a.v * root.artHeight,
            r: root.rootNodeR * root.artWidth
        };
    }

    function runSessionAction(action: var): void {
        root.dismiss();
        // Windows is two steps: the helper only flips the firmware's BootNext,
        // so the reboot is ours to do, and only if it actually succeeded.
        if (action.id === "windows") {
            bootToWindows.running = true;
            return;
        }
        if (!IdleInhibitor.execSessionAction(action.command))
            Quickshell.execDetached(action.command);
    }

    Process {
        id: bootToWindows

        command: Config.session.commands.windows
        onExited: code => {
            if (code === 0)
                SessionManager.reboot();
        }
    }

    // ---- multi-open bookkeeping --------------------------------------------
    // A section leaving the open set still needs to be RENDERED for the
    // length of its retreat flight (flightP -> 0) before it disappears.
    // `retiring` holds ids that just left openIds, cleared en masse by one
    // timer sized to the flight duration — simpler than tracking each id's
    // own animation-finished signal, and correct because re-opening an id
    // mid-retreat is harmless (it just re-enters openIds and the timer still
    // clears its (now stale) retiring entry later, a no-op).
    property var retiring: []
    property var _prevOpenIds: []

    function _trackRetiring(): void {
        const prev = root._prevOpenIds;
        const cur = root.openIds;
        const removed = prev.filter(id => cur.indexOf(id) < 0);
        if (removed.length > 0) {
            const merged = root.retiring.slice();
            for (const id of removed)
                if (merged.indexOf(id) < 0)
                    merged.push(id);
            root.retiring = merged;
            retiringCleanup.restart();
        }
        root._prevOpenIds = cur.slice();
    }

    Timer {
        id: retiringCleanup

        interval: 1120
        repeat: false
        onTriggered: root.retiring = []
    }

    readonly property var visibleSectionIds: {
        const out = root.openIds.slice();
        for (const id of root.retiring)
            if (out.indexOf(id) < 0)
                out.push(id);
        return out;
    }

    // ---- mask / trunk publication -----------------------------------------
    // Committed from: openIds changes, resize, and the moment the dashboard
    // opens. Never from anything bound to openP/flightP — those tick
    // every frame and would violate the region-churn discipline Regions.qml's
    // header comment documents.
    function commitMask(): void {
        // The rects describe where the DRAWERS window takes clicks; a guest
        // lives in someone else's window and would be publishing lies.
        if (!root.screenState || root.guest)
            return;
        root.screenState.dashboardMaskRects = [
            {
                x: 0,
                y: 0,
                width: root.geomW,
                height: root.geomH
            }
        ];
        root.screenState.dashboardTrunkRect = {
            x: root.trunkXHome - root.trunkWBase * 1.5,
            y: root.trunkTopY,
            width: root.trunkWBase * 3,
            height: root.geomH - root.trunkTopY
        };
    }

    anchors.fill: parent

    onOpenIdsChanged: {
        root._trackRetiring();
        root.commitMask();
    }
    onWidthChanged: geomSettle.restart()
    onHeightChanged: geomSettle.restart()
    onSectionsChanged: root.commitMask()
    Component.onCompleted: {
        console.info(lcLiving, "mounted: screenState=" + (root.screenState ? "ok" : "NULL") + " dashboard=" + root.screenState?.dashboard + " sections=" + root.na + " size=" + root.width + "x" + root.height);
        root._prevOpenIds = root.openIds.slice();
        root.commitMask();
    }

    Behavior on openP {
        enabled: Ambience.grow && !GameMode.enabled

        Anim {
            type: Anim.SlowSpatial
        }
    }

    Connections {
        function onDashboardChanged(): void {
            // Committed exactly once per open, not per frame.
            if (!root.guest && !root.sproutOnly && root.screenState?.dashboard) {
                root.commitMask();
                root.screenState.dashboardTreeGrown = true;
            }
        }

        target: root.screenState
    }

    // Geometry latch (see geomW/geomH above): a Behavior-animated resize
    // settles once instead of recomputing every anchor on every frame.
    Timer {
        id: geomSettle

        interval: 64
        repeat: false
        onTriggered: {
            root.geomW = Math.max(1, root.width);
            root.geomH = Math.max(1, root.height);
            console.info(lcLiving, "layout " + root.geomW + "x" + root.geomH + " openP=" + root.openP.toFixed(2) + " dash=" + root.screenState?.dashboard);
            root.commitMask();
        }
    }

    Rectangle {
        x: 0
        y: -root.roomOffset
        width: root.geomW
        height: root.geomH
        visible: root.roomP > 0.004
        opacity: root.roomP

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "#11121b"
            }
            GradientStop {
                position: 0.45
                color: "#25212d"
            }
            GradientStop {
                position: 1.0
                color: "#11121b"
            }
        }
    }

    AstralScene {
        x: 0
        y: 0
        width: root.geomW
        height: root.geomH
        scene: "tree"
        camera: 0
        active: root.onScreen && root.roomP > 0.001
        opacity: root.roomP * 0.72
    }

    // 0b — a warm bloom behind the trunk. RadialGradient on a Shape, NOT a
    // rounded Rectangle — a Rectangle has no falloff and draws a hard-edged
    // disc across the screen.
    Shape {
        x: 0
        y: -root.roomOffset
        width: root.geomW
        height: root.geomH
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        visible: root.roomP > 0.01
        opacity: root.roomP

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"

            fillGradient: RadialGradient {
                centerX: root.trunkX
                centerY: root.trunkTopY * 0.82
                centerRadius: Math.max(root.geomW, root.geomH) * 0.62
                focalX: root.trunkX
                focalY: root.trunkTopY * 0.82

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(Woodland.mix(Woodland.parchment, Woodland.oliveLight, 0.25), 0.16)
                }

                GradientStop {
                    position: 0.42
                    color: Qt.alpha(Woodland.barkLit, 0.09)
                }

                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }

            PathSvg {
                path: `M 0 0 L ${root.geomW} 0 L ${root.geomW} ${root.geomH} L 0 ${root.geomH} Z`
            }
        }
    }

    // Clicking bare canvas dismisses the whole surface — the long-standing
    // "click empty canopy to close". Folding a grown section back into its orb
    // is the orb's own click and the trunk column; only one section is ever
    // grown, so there is no "retreat to the section underneath" case here.
    //
    // Not for a guest: the launcher's own ascend catcher already owns "click the
    // empty sky to fly back up", and it is the one carrying the hover glow and
    // the chevron that make it discoverable. Two full-surface catchers means the
    // top one wins and the affordance never lights.
    MouseArea {
        anchors.fill: parent
        enabled: !root.guest && root.openP > 0.5
        onClicked: root.dismiss()
    }

    Bloom {
        x: root.trunkX - root.artWidth*0.38
        y: root.artY + root.artHeight*0.02
        width: root.artWidth*0.76
        height: width
        tone: Woodland.brass
        intensity: 0.32
        opacity: root.roomP
    }

    property int hoveredOrb: -1
    onRoomPChanged: if (root.roomP < 0.01) root.hoveredOrb = -1

    EldritchTree {
        id: branchTree

        x: root.artX
        y: root.artY
        width: root.artWidth
        height: root.artHeight
        anchorsData: root.orbAnchors.slice(0, root.na)
        rootAnchorsData: root.rootAnchors.map(a => ({ u:a.u,v:a.v,ru:root.rootNodeR,rv:root.rootNodeR*root.artWidth/root.artHeight }))
        hoveredRoot: root.hoveredRoot
        growth: root.openP
        selected: root.openIds.length ? root.sections.findIndex(s => s.id === root.emphasisId) : -1
        hovered: root.hoveredOrb
        visible: root.onScreen
        animated: root.roomP > 0.01
    }

    Connections {
        target: branchTree
        function onPulseArrived(index: int): void { orbNodes.itemAt(index)?.ignite(); }
        function onRootPulseArrived(index: int): void { rootNodes.itemAt(index)?.ignite(); }
    }

    SpectralClouds {
        x: 0
        y: 0
        width: root.geomW
        height: root.geomH
        scene: "dream"
        spilling: true
        density: 1.35
        period: 22000
        opacity: root.roomP * 0.95
        active: root.onScreen && root.roomP > 0.001
        enabled: false
    }

    // 2 — motes. Deterministic placement off the Knuth hash above, so they
    // never reshuffle; the twinkle is a per-mote phase on one shared
    // animation rather than a timer each.
    Repeater {
        // onScreen too: 64 motes were drifting over the desktop with the dashboard shut.
        model: root.onScreen && Ambience.leaves && !GameMode.enabled ? 64 : 0

        delegate: Item {
            id: mote

            required property int index

            readonly property real h1: root._h(mote.index, 11)
            readonly property real h2: root._h(mote.index, 23)
            readonly property real fy: Math.pow((mote.h2 % 1000) / 1000, 1.45)
            readonly property bool big: (mote.h1 % 9) === 0
            readonly property real sz: (mote.big ? 5 : 2) + (mote.h1 % 4)

            x: ((mote.h1 % 1009) / 1009) * root.geomW
            y: mote.fy * root.trunkTopY
            width: mote.sz
            height: mote.sz
            opacity: root.openP * (0.30 + (mote.h2 % 55) / 100)
            visible: root.openP > 0.02

            Rectangle {
                anchors.centerIn: parent
                width: mote.sz
                height: 1
                radius: 0.5
                color: Woodland.parchment
            }

            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: mote.sz
                radius: 0.5
                color: Woodland.parchment
            }

            Rectangle {
                anchors.centerIn: parent
                width: mote.sz * 0.34
                height: mote.sz * 0.34
                radius: width / 2
                color: Woodland.parchment
            }

            SequentialAnimation on opacity {
                running: mote.visible && Ambience.sway && !GameMode.enabled
                loops: Animation.Infinite

                PauseAnimation {
                    duration: (mote.h1 % 2600)
                }

                NumberAnimation {
                    to: 0.12
                    duration: 900 + (mote.h2 % 700)
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    to: 0.30 + (mote.h2 % 55) / 100
                    duration: 900 + (mote.h1 % 900)
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    Bloom {
        id: seed

        readonly property real glowRadius: root.trunkWBase * 4

        tone: Woodland.mix(root.barkTone, Woodland.parchment, 0.35)
        intensity: 0.7

        x: root.trunkXHome - seed.glowRadius
        y: root.geomH - seed.glowRadius
        width: seed.glowRadius * 2
        height: seed.glowRadius * 2
        visible: root.openP < 0.05 && seed.opacity > 0.002
        opacity: root.openP < 0.05 ? ((!root.sproutOnly && (root.screenState?.dashboard ?? false)) ? 1 : root.hoverProximity) : 0
    }

    // Hover-to-grow trigger. Lives BELOW root's own bottom edge — Regions.qml
    // commits `window XOR innerRect` unconditionally, i.e. the border strip
    // is ALWAYS part of the input mask, unlike the interior (which the mask
    // excludes entirely while the tree is closed), so this strip is the only
    // place a hover-OPEN trigger can physically work. Widening it never
    // fights closing: it only ever WRITES `dashboard = true`, and only when
    // the dashboard is not already open.
    MouseArea {
        id: edgeTrigger

        readonly property real haloHalfWidth: Math.max(root.trunkWBase * 5, root.geomW * 0.05)
        readonly property real coreHalfWidth: root.trunkWBase * 1.6

        x: root.trunkXHome - edgeTrigger.haloHalfWidth
        y: root.geomH - Tokens.spacing.extraSmall
        width: edgeTrigger.haloHalfWidth * 2
        height: Config.border.thickness + Tokens.spacing.small
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: !root.guest && Config.dashboard.livingHoverGrow !== false && !(root.screenState?.dashboard ?? false)
        cursorShape: Qt.PointingHandCursor

        onPositionChanged: mouse => {
            const dx = Math.abs(mouse.x - edgeTrigger.width / 2);
            root.hoverProximity = CUtils.clamp(1 - dx / edgeTrigger.haloHalfWidth, 0, 1);
            if (dx <= edgeTrigger.coreHalfWidth) {
                if (!hoverOpenTimer.running)
                    hoverOpenTimer.restart();
            } else {
                hoverOpenTimer.stop();
            }
        }
        onEntered: root.hoverProximity = Math.max(root.hoverProximity, 0.12)
        onExited: {
            root.hoverProximity = 0;
            hoverOpenTimer.stop();
        }
    }

    Timer {
        id: hoverOpenTimer

        interval: Tokens.anim.durations.small
        repeat: false
        onTriggered: {
            if (!root.screenState || root.screenState.dashboard)
                return;
            root.nav.interacted = true;
            root.screenState.dashboard = true;
        }
    }

    readonly property bool onScreen: root.openP > 0.001 && (!root.guest || root.nav.guestOnScreen)

    Repeater {
        id: orbNodes

        model: Math.min(root.na, 6)

        // orbIndex, NOT index, as the Orb's own API: a delegate property named
        // `index` collides with the Repeater's own context property and the
        // delegate silently never instantiates — no error, just no orbs.
        // The `required property int index` is how the Repeater's index reaches an
        // INLINE component delegate at all: context-property injection does not
        // cross into `component Orb`, so a bare `orbIndex: index` threw
        // "ReferenceError: index is not defined" on every orb and none appeared.
        delegate: Orb {
            required property int index

            orbIndex: index
        }
    }

    MouseArea {
        x: root.trunkXHome - root.trunkWBase * 1.5
        y: root.trunkTopY
        width: root.trunkWBase * 3
        height: root.geomH - root.trunkTopY
        // Gated: with the dashboard shut this strip still showed a pointing-hand
        // cursor and swallowed clicks at bottom-centre.
        enabled: root.onScreen
        hoverEnabled: root.onScreen
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()
    }

    Repeater {
        model: ScriptModel {
            values: root.visibleSectionIds
        }

        delegate: BookStage {
            required property string modelData

            sectionId: modelData
        }
    }

    // 5b — session nodes on the root limbs. Declared AFTER the trunk dismiss
    // strip on purpose: that column is trunkWBase * 3 wide and swallows the
    // two inner root anchors, so these have to sit above it in the stack.
    Repeater {
        id: rootNodes
        model: root.sessionActions

        delegate: RootNode {
            required property int index
            required property var modelData

            nodeIndex: index
            action: modelData
        }
    }

    Shape {
        x: 0
        y: -root.roomOffset
        width: root.geomW
        height: root.geomH
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        visible: root.roomP > 0.02
        opacity: root.roomP

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"

            fillGradient: RadialGradient {
                centerX: root.trunkX
                centerY: root.geomH * 0.46
                centerRadius: Math.max(root.geomW, root.geomH) * 0.58
                focalX: root.trunkX
                focalY: root.geomH * 0.46

                GradientStop {
                    position: 0.0
                    color: "transparent"
                }

                GradientStop {
                    position: 0.58
                    color: "transparent"
                }

                GradientStop {
                    position: 1.0
                    color: Qt.alpha(Woodland.barkEdge, 0.58)
                }
            }

            PathSvg {
                path: `M 0 0 L ${root.geomW} 0 L ${root.geomW} ${root.geomH} L 0 ${root.geomH} Z`
            }
        }
    }

    // ---- inline components, ALL LAST in the object body -------------------

    component Bloom: Item {
        id: bloom

        required property color tone
        // Peak alpha at the centre of the falloff.
        property real intensity: 0.3

        Behavior on intensity {
            enabled: Ambience.grow && !GameMode.enabled

            Anim {
                type: Anim.DefaultEffects
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"

                // Four stops on a roughly quadratic ramp: the eye reads a
                // linear alpha ramp as a visible disc with a soft edge rather
                // than as light, because most of the falloff happens too late.
                fillGradient: RadialGradient {
                    centerX: bloom.width / 2
                    centerY: bloom.height / 2
                    centerRadius: bloom.width / 2
                    focalX: bloom.width / 2
                    focalY: bloom.height / 2

                    GradientStop {
                        position: 0.0
                        color: Qt.alpha(bloom.tone, bloom.intensity)
                    }

                    GradientStop {
                        position: 0.18
                        color: Qt.alpha(bloom.tone, bloom.intensity * 0.62)
                    }

                    GradientStop {
                        position: 0.42
                        color: Qt.alpha(bloom.tone, bloom.intensity * 0.22)
                    }

                    GradientStop {
                        position: 0.72
                        color: Qt.alpha(bloom.tone, bloom.intensity * 0.05)
                    }

                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }

                PathSvg {
                    path: `M 0 0 L ${bloom.width} 0 L ${bloom.width} ${bloom.height} L 0 ${bloom.height} Z`
                }
            }
        }
    }

    component BarkSocket: Item {
        id: sock

        required property color accent
        required property bool active
        required property bool hovered
        required property string glyph
        // Distinct per socket, or the ten pockets are one carving repeated.
        required property int phase
        property real haloIntensity: 0.3

        readonly property real d: Math.max(8, sock.width)
        readonly property real ringW: Math.max(1.4, sock.d * 0.045) * (sock.active ? 1.55 : 1)
        readonly property real wallW: Math.max(1.2, sock.d * 0.055)
        readonly property real ringR: sock.d / 2 - sock.ringW / 2 - 1
        readonly property real wallR: sock.d / 2 - sock.wallW / 2 - 0.5

        function h(i: int): real {
            const v = Math.sin(i * 127.1 + sock.phase * 311.7) * 43758.5453123;
            return v - Math.floor(v);
        }

        // A fissure on the floor: a short bowed chord near the rim, at r = 0.88.
        // Drawn LIT, not dark — the floor is the darkest tone in the shell, so a
        // barkEdge crack on it is invisible and a faint barkLit ridge is what
        // reads as grain catching light. Kept short and very low alpha: at a
        // longer sweep and 0.22 they cut clean across the bore and read as
        // scratches stamped on rather than as grain in it.
        function crack(k: int): string {
            const c = sock.d / 2;
            const R = c * 0.88;
            const a = sock.h(k * 7) * Math.PI * 2;
            const b = a + Math.PI * (0.34 + 0.30 * sock.h(k * 7 + 1));
            const x0 = c + R * Math.cos(a);
            const y0 = c + R * Math.sin(a);
            const x1 = c + R * Math.cos(b);
            const y1 = c + R * Math.sin(b);
            const bow = c * (0.18 + 0.30 * sock.h(k * 7 + 2)) * (sock.h(k * 7 + 3) < 0.5 ? -1 : 1);
            const mx = (x0 + x1) / 2 - bow * Math.sin(a);
            const my = (y0 + y1) / 2 + bow * Math.cos(a);
            return `M ${x0} ${y0} Q ${mx} ${my} ${x1} ${y1}`;
        }

        // 1 — light in the wood.
        Bloom {
            anchors.centerIn: parent

            width: sock.d * 3
            height: width
            tone: sock.accent
            intensity: sock.haloIntensity
        }

        // 2 — the hole. One static Shape: floor, two wall crescents, two
        // fissures. Separate from the rim Shape below, so a hover never
        // retessellates this geometry.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                strokeWidth: -1

                fillGradient: RadialGradient {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    centerRadius: sock.d / 2
                    focalX: sock.d / 2
                    focalY: sock.d / 2

                    GradientStop {
                        position: 0.00
                        color: Qt.alpha(Woodland.barkEdge, 0.97)
                    }

                    GradientStop {
                        position: 0.72
                        color: Qt.alpha(Woodland.barkEdge, 0.95)
                    }

                    GradientStop {
                        position: 0.90
                        color: Qt.alpha(Woodland.mix(Woodland.barkShaded, Woodland.barkEdge, 0.45), 0.90)
                    }

                    GradientStop {
                        position: 0.97
                        color: Qt.alpha(Woodland.barkShaded, 0.40)
                    }

                    GradientStop {
                        position: 1.00
                        color: "transparent"
                    }
                }

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.d / 2
                    radiusY: sock.d / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            // Lit far wall, lower-right: light crosses the bore and lands on the
            // opposite side. This, not the 1px bevel, is what carries the concave
            // read at a 36px disc.
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkLit, sock.active || sock.hovered ? 0.60 : 0.45)
                strokeWidth: sock.wallW
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.wallR
                    radiusY: sock.wallR
                    startAngle: 25
                    sweepAngle: 120
                }
            }

            // Overhanging lip, upper-left.
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkEdge, 0.75)
                strokeWidth: sock.wallW
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.wallR
                    radiusY: sock.wallR
                    startAngle: 195
                    sweepAngle: 130
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkLit, 0.11)
                strokeWidth: Math.max(1, sock.d * 0.030)
                capStyle: ShapePath.RoundCap

                PathSvg {
                    path: sock.crack(1)
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkLit, 0.08)
                strokeWidth: Math.max(1, sock.d * 0.026)
                capStyle: ShapePath.RoundCap

                PathSvg {
                    path: sock.crack(2)
                }
            }
        }

        // 3 — light pooling INSIDE the well when this pocket is live. The same
        // Bloom a size down: a tinted seat would read as a different disc, pooled
        // light reads as the same pocket, lit.
        Bloom {
            anchors.centerIn: parent

            width: sock.d * 1.15
            height: width
            tone: sock.accent
            intensity: sock.active ? 0.34 : (sock.hovered ? 0.24 : 0.0)
        }

        // 4 — the shared bevel. Same object, same 1px, same tones as every card
        // and utilities socket in the shell; documented usage. Dark cap at the
        // top, light cap at the bottom, both dying out where the two offset
        // circles cross.
        BarkFrame {
            anchors.fill: parent

            socket: true
            radius: width / 2
        }

        // 5 — the accent rim: never a full circle. Two round-capped arcs with a
        // gap near 3 and near 8 o'clock, each over a 1.9x barkEdge halo pass —
        // the separation from bark comes from the dark stroke, not from the
        // accent. Its own Shape because `ringW` steps on open, and a strokeWidth
        // change retessellates whatever Shape it lives in.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: true

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkEdge, 0.85)
                strokeWidth: sock.ringW * 1.9
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.ringR
                    radiusY: sock.ringR
                    startAngle: 192
                    sweepAngle: 172
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Woodland.barkEdge, 0.85)
                strokeWidth: sock.ringW * 1.9
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.ringR
                    radiusY: sock.ringR
                    startAngle: 22
                    sweepAngle: 112
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(sock.accent, sock.active ? 1.0 : (sock.hovered ? 0.95 : 0.72))
                strokeWidth: sock.ringW
                capStyle: ShapePath.RoundCap

                Behavior on strokeColor {
                    CAnim {}
                }

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.ringR
                    radiusY: sock.ringR
                    startAngle: 192
                    sweepAngle: 172
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(sock.accent, sock.active ? 0.70 : (sock.hovered ? 0.62 : 0.48))
                strokeWidth: sock.ringW
                capStyle: ShapePath.RoundCap

                Behavior on strokeColor {
                    CAnim {}
                }

                PathAngleArc {
                    centerX: sock.d / 2
                    centerY: sock.d / 2
                    radiusX: sock.ringR
                    radiusY: sock.ringR
                    startAngle: 22
                    sweepAngle: 112
                }
            }
        }

        // 6 — the glyph. MaterialIcon derives from StyledText, so Text.Outline
        // gives the dark contour that separates it from the accent pooling in the
        // well; no second icon item. Tinted toward the section's own ember, so
        // more than position sets the pockets apart.
        MaterialIcon {
            anchors.centerIn: parent

            text: sock.glyph
            color: sock.active ? Woodland.mix(Woodland.parchment, sock.accent, 0.35) : Qt.alpha(Woodland.mix(Woodland.parchment, sock.accent, 0.20), 0.90)
            style: Text.Outline
            styleColor: Qt.alpha(Woodland.barkEdge, 0.90)
            fontStyle: Tokens.font.icon.small
        }
    }

    component Orb: Item {
        id: orb

        property int orbIndex: 0

        readonly property var section: root.sections[orb.orbIndex] ?? null
        readonly property var anchor: root.orbGeom(orb.orbIndex)
        readonly property color accent: root.sectionAccent(orb.orbIndex)
        readonly property bool isOpen: orb.section ? root.openIds.includes(orb.section.id) : false
        readonly property bool isEmphasis: orb.isOpen && orb.section?.id === root.emphasisId
        readonly property bool withered: orb.section ? !(orb.section.enabled ?? true) : false
        readonly property real revealP: { void branchTree.reveal; return branchTree.orbProgress(orb.orbIndex); }
        readonly property var tip: { void branchTree.reveal; return branchTree.orbEndpoint(orb.orbIndex); }

        function ignite(): void { spirit.ignite(); }

        readonly property real disc: orb.anchor ? orb.anchor.r * 2 : 40

        x: root.artX + (orb.tip?.x ?? 0.5)*root.artWidth - orb.disc/2
        y: root.artY + (orb.tip?.y ?? 0.5)*root.artHeight - orb.disc/2
        width: orb.disc
        height: orb.disc
        // Only the hover bump is smoothed. A Behavior on the product would be
        // restarted every frame while revealP animates, so the grow would
        // never land on its own curve — it would read as lag.
        property real hoverBump: hoverArea.containsMouse || orb.isOpen ? 1.18 : 1

        scale: (0.18 + 0.82*orb.revealP) * orb.hoverBump
        opacity: orb.section ? orb.revealP*(orb.withered ? 0.42 : 1) : 0
        visible: root.onScreen && orb.section != null && orb.revealP > 0.01

        Behavior on hoverBump {
            enabled: Ambience.grow && !GameMode.enabled

            Anim {
                type: Anim.DefaultEffects
            }
        }

        SpiritMedallion {
            id: spirit
            prominent: true

            anchors.fill: parent
            accent: orb.accent
            selected: orb.isOpen
            hovered: hoverArea.containsMouse
            glyph: orb.section?.iconName ?? "circle"
            phase: orb.orbIndex+1
            animate: root.roomP > 0.01
        }

        StyledText {
            id: orbLabel

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: (orb.anchor?.x ?? 0) < root.trunkX ? parent.right : undefined
            anchors.right: (orb.anchor?.x ?? 0) < root.trunkX ? undefined : parent.left
            anchors.leftMargin: Tokens.spacing.extraSmall
            anchors.rightMargin: Tokens.spacing.extraSmall

            text: orb.section?.text ?? ""
            color: Woodland.parchment
            style: Text.Outline
            styleColor: Woodland.barkEdge
            font: Tokens.font.label.small
            horizontalAlignment: (orb.anchor?.x ?? 0) < root.trunkX ? Text.AlignLeft : Text.AlignRight
            opacity: root.openIds.length ? 0 : hoverArea.containsMouse ? 1 : 0.82
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        MouseArea {
            id: hoverArea

            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: orb.revealP > 0.7
            onEntered: { root.hoveredOrb = orb.orbIndex; orb.ignite(); }
            onExited: if (root.hoveredOrb === orb.orbIndex) root.hoveredOrb = -1

            onClicked: mouse => {
                if (!orb.section)
                    return;
                root.nav.interacted = true;
                if (!root.guest) root.nav.forceActiveFocus();
                if (mouse.button === Qt.RightButton) {
                    root.nav.toggleSection(orb.section.id);
                    return;
                }
                if (orb.withered) {
                    root.nav.toggleSection(orb.section.id);
                    return;
                }
                if (orb.isEmphasis) {
                    root.foldSection(orb.section.id);
                    return;
                }
                root.growSection(orb.section.id);
            }
        }
    }

    component RootNode: Item {
        id: node

        property int nodeIndex: 0
        property var action: null
        readonly property bool requiresHold: node.action?.id !== "lock"
        readonly property bool canActivate: node.visible && node.enabled && root.roomP > 0.95 && root.openP > 0.99 && node.revealP > 0.98
        readonly property int holdDuration: 1200
        property real holdProgress: 0
        property double holdStartedAt: 0
        property string heldActionId: ""

        function cancelHold(): void {
            holdDelay.stop();
            holdFill.stop();
            node.holdProgress = 0;
            node.heldActionId = "";
            node.holdStartedAt = 0;
        }

        function beginHold(): void {
            node.cancelHold();
            if (!node.requiresHold || !node.canActivate || !node.action || !nodeHover.pressed || !nodeHover.containsMouse)
                return;
            node.heldActionId = node.action.id;
            node.holdStartedAt = Date.now();
            holdFill.start();
            holdDelay.interval = node.holdDuration;
            holdDelay.start();
        }

        function completeHold(): void {
            const ready = node.canActivate && node.requiresHold && node.action
                && node.heldActionId === node.action.id && nodeHover.pressed && nodeHover.containsMouse;
            const remaining = node.holdDuration-(Date.now()-node.holdStartedAt);
            if (ready && remaining > 0) {
                holdDelay.interval = Math.max(1,Math.min(node.holdDuration,remaining));
                holdDelay.restart();
                return;
            }
            const action = node.action;
            node.cancelHold();
            if (ready) root.runSessionAction(action);
        }

        function activateClick(): void {
            if (node.canActivate && node.action && !node.requiresHold)
                root.runSessionAction(node.action);
        }

        onCanActivateChanged: if (!canActivate) cancelHold()
        onActionChanged: cancelHold()

        Timer {
            id: holdDelay
            interval: node.holdDuration
            onTriggered: node.completeHold()
        }

        NumberAnimation {
            id: holdFill
            target: node
            property: "holdProgress"
            from: 0
            to: 1
            duration: node.holdDuration
        }

        readonly property var anchor: root.rootNodeGeom(node.nodeIndex)
        readonly property color accent: node.action?.destructive ? Colours.palette.m3error : Colours.palette.m3primary
        readonly property real routeP: { void branchTree.reveal; return branchTree.rootProgress(node.nodeIndex); }
        readonly property real revealP: CUtils.clamp((node.routeP-0.65)/0.35,0,1)
        readonly property var tip: { void branchTree.reveal; return branchTree.rootEndpoint(node.nodeIndex); }
        function ignite(): void { rootSpirit.ignite(); }
        readonly property real disc: node.anchor ? node.anchor.r * 2 : 32

        x: root.artX + (node.tip?.x ?? 0.5)*root.artWidth - node.disc/2
        y: root.artY + (node.tip?.y ?? 0.88)*root.artHeight - node.disc/2
        width: node.disc
        height: node.disc
        // See the Orb above: the Behavior belongs on the hover factor alone.
        property real hoverBump: nodeHover.containsMouse ? 1.18 : 1

        scale: (0.25+0.75*node.revealP) * node.hoverBump
        opacity: node.revealP
        visible: root.onScreen && node.action != null && node.revealP > 0.01

        Behavior on hoverBump {
            enabled: Ambience.grow && !GameMode.enabled

            Anim {
                type: Anim.DefaultEffects
            }
        }

        SpiritMedallion {
            id: rootSpirit
            anchors.fill: parent
            accent: node.accent
            hovered: nodeHover.containsMouse
            glyph: node.action?.icon ?? "circle"
            phase: 40+node.nodeIndex
            animate: root.roomP > 0.01
        }

        Shape {
            anchors.fill: parent
            anchors.margins: -7
            visible: node.heldActionId.length > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: node.accent
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: node.width/2+7
                    centerY: node.height/2+7
                    radiusX: node.width/2+7
                    radiusY: node.height/2+7
                    startAngle: -90
                    sweepAngle: 360*node.holdProgress
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: Tokens.spacing.extraSmall

            text: !node.requiresHold ? (node.action?.label ?? "")
                : node.action?.id === "windows" ? qsTr("Hold to boot Windows")
                : qsTr("Hold to %1").arg((node.action?.label ?? "").toLocaleLowerCase())
            color: Woodland.parchment
            style: Text.Outline
            styleColor: Woodland.barkEdge
            font: Tokens.font.label.small
            opacity: nodeHover.containsMouse || node.heldActionId.length > 0 ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        MouseArea {
            id: nodeHover

            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoveredRoot = node.nodeIndex
            onExited: {
                node.cancelHold();
                if (root.hoveredRoot === node.nodeIndex) root.hoveredRoot = -1;
            }
            onPressed: node.beginHold()
            onReleased: node.cancelHold()
            onCanceled: node.cancelHold()
            onClicked: node.activateClick()
        }
    }

    component BookStage: Item {
        id: stage

        required property string sectionId

        readonly property var sectionObj: root.sections.find(s => s?.id === stage.sectionId) ?? null
        readonly property int orbIdx: root.sections.findIndex(s => s?.id === stage.sectionId)
        readonly property var anchor: root.orbGeom(stage.orbIdx)
        readonly property bool isOpenNow: root.openIds.includes(stage.sectionId)
        readonly property bool isEmphasisNow: stage.isOpenNow && stage.sectionId === root.emphasisId

        property real flightP: 0
        property bool ready: false
        Component.onCompleted: { ready = true; flightP = isEmphasisNow ? 1 : 0; }
        onIsEmphasisNowChanged: if (ready) flightP = isEmphasisNow ? 1 : 0

        Behavior on flightP {
            enabled: Ambience.grow && !GameMode.enabled
            NumberAnimation { duration: 1000; easing.type: Easing.InOutCubic }
        }

        readonly property real travelP: CUtils.clamp(stage.flightP / 0.35, 0, 1)
        readonly property real unfurlP: CUtils.clamp((stage.flightP - 0.38) / 0.62, 0, 1)
        property real natW: 640
        property real natH: 420
        readonly property real openW: Math.min(root.stageZoneW, Math.max(560, (stage.natW + 56)/0.82))
        readonly property real openH: Math.min(root.geomH * 0.70, Math.max(430, stage.natH + 94))

        // 48ms + 2px hysteresis, the cardSettle recipe: re-latch only once the
        // pane has stopped changing its mind, and ignore sub-pixel churn.
        Timer {
            id: natSettle

            interval: 48
            onTriggered: {
                const it = sectionContent.item;
                if (!it)
                    return;
                const w = it.implicitWidth;
                const h = it.implicitHeight;
                if (w > 0 && Math.abs(w - stage.natW) > 2)
                    stage.natW = w;
                if (h > 0 && Math.abs(h - stage.natH) > 2)
                    stage.natH = h;
            }
        }

        Connections {
            function onImplicitWidthChanged(): void {
                natSettle.restart();
            }

            function onImplicitHeightChanged(): void {
                natSettle.restart();
            }

            target: sectionContent.item
        }

        width: stage.openW
        height: stage.openH
        x: (stage.anchor?.x ?? root.geomW/2) * (1-stage.travelP)
            + root.stageZoneX*stage.travelP - width/2
        y: (stage.anchor?.y ?? root.geomH/2) * (1-stage.travelP)
            + (root.geomH/2 + height*0.10)*stage.travelP - height/2
        scale: 0.08 + 0.92*stage.travelP
        opacity: CUtils.clamp(stage.flightP*5, 0, 1)
        rotation: -8*(1-stage.travelP)
        z: stage.isEmphasisNow ? 5 : 4
        visible: root.onScreen && stage.sectionObj != null && (stage.isOpenNow || stage.flightP > 0.01)

        // Absorb page clicks before they reach the tree.
        MouseArea { anchors.fill: parent }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -42
            spacing: 8
            opacity: stage.unfurlP
            enabled: stage.unfurlP > 0.9
            Repeater {
                model: root.sections.filter(s => s.enabled)
                delegate: Rectangle {
                    id: folioTab
                    required property var modelData
                    readonly property bool selected: modelData.id === stage.sectionId
                    width: sectionName.implicitWidth+26
                    height: 34
                    radius: 3
                    gradient: Gradient {
                        GradientStop { position: 0; color: Woodland.mix(Woodland.barkEdge, Colours.palette.m3primary, folioTab.selected ? 0.38 : 0.12) }
                        GradientStop { position: 1; color: Woodland.barkEdge }
                    }
                    border.color: Qt.alpha(Woodland.parchmentEdge, folioTab.selected ? 0.75 : 0.35)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        height: 1
                        color: Qt.alpha(Woodland.parchmentEdge, folioTab.selected ? 0.7 : 0.2)
                    }
                    Text {
                        id: sectionName
                        anchors.centerIn: parent
                        text: modelData.text
                        color: Woodland.parchment
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.growSection(parent.modelData.id)
                    }
                }
            }
        }

        Grimoire {
            anchors.fill: parent
            opening: stage.unfurlP
            preparing: stage.isOpenNow || stage.flightP > 0
            title: stage.sectionObj?.text ?? ""
                        coverId: stage.sectionObj?.id ?? "dashboard"
            accent: root.sectionAccent(stage.orbIdx)
            onCloseRequested: root.foldSection(stage.sectionId)

            Loader {
                id: sectionContent

                readonly property real fitScale: Math.max(0.01, Math.min(1,
                    parent.width/Math.max(1, stage.natW), parent.height/Math.max(1, stage.natH)))
                width: parent.width/fitScale
                height: parent.height/fitScale
                scale: fitScale
                transformOrigin: Item.TopLeft
                active: root.onScreen && (stage.isOpenNow || stage.flightP > 0.01)
                asynchronous: true
                sourceComponent: stage.sectionObj?.component ?? null
                onLoaded: natSettle.restart()
            }
        }
    }
}
