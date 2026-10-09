pragma ComponentBehavior: Bound

// Aliased: dash/Media.qml and this directory's own Media.qml would otherwise
// both resolve as `Media`. performance/ has no such collision.
import "dash" as DashCards
import "performance"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import Burl
import Burl.Config
import Burl.Services
import qs.components
import qs.components.containers
import qs.components.filedialog
import qs.components.widgets
import qs.services

// A FocusScope, not a plain Item: the nav (tab bar today, world tree next) and
// the section panes both want keys, and a scope lets the pane that grabbed
// focus (TasksTab force-focuses itself) keep its own bindings while everything
// it does not consume bubbles up to the nav handlers below.
FocusScope {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    // Every section, ALWAYS unfiltered, each with a stable string id. Selection
    // is by id (screenState.dashboardSection); the enabled subset exists only
    // for layout and for the legacy index-based IPC. Ids are chosen so the
    // config flag derives from them — "media" -> Config.dashboard.showMedia —
    // so nothing needs a second id-to-flag table (see
    // ScreenState.dashboardSectionFlag).
    readonly property var sections: [
        {
            id: "dashboard",
            component: dashComponent,
            iconName: "dashboard",
            text: qsTr("Dashboard"),
            enabled: Config.dashboard.showDashboard
        },
        {
            id: "media",
            component: mediaComponent,
            iconName: "queue_music",
            text: qsTr("Media"),
            enabled: Config.dashboard.showMedia
        },
        {
            id: "performance",
            component: performanceComponent,
            iconName: "speed",
            text: qsTr("Performance"),
            enabled: Config.dashboard.showPerformance
        },
        {
            id: "weather",
            component: weatherComponent,
            iconName: "cloud",
            text: qsTr("Weather"),
            enabled: Config.dashboard.showWeather
        },
        {
            id: "tasks",
            component: tasksComponent,
            iconName: "checklist",
            text: qsTr("Tasks"),
            enabled: true
        }
    ]
    readonly property var enabledSections: sections.filter(s => s.enabled)
    readonly property string activeSectionId: screenState.dashboardSection
    readonly property string focusedSectionId: screenState.dashboardFocusSection
    // Index of the showing section within enabledSections, i.e. within the
    // Repeater's model. -1 only in the instant before reconcile runs.
    readonly property int activeIndex: enabledSections.findIndex(s => s.id === root.activeSectionId)

    // `repeaterRef` (below, forwarded off the loaded ClippingRectangle) is null
    // for the living-mode instant where the carousel is not instantiated —
    // living mode's own TasksTab hosting (out of this file's scope) is
    // responsible for its own needsKeyboard plumbing.
    readonly property bool needsKeyboard: {
        const rep = viewLoader.item?.repeaterRef;
        if (!rep)
            return false;
        const count = rep.count;
        for (let i = 0; i < count; i++) {
            const item = rep.itemAt(i) as Loader;
            if (item?.sourceComponent === tasksComponent && (item?.item as TasksTab)?.needsKeyboard)
                return true;
        }
        return false;
    }
    // Set by a nav component when a pointer actually lands on it, so a click
    // counts as "the user is working in here" for keyboard focus.
    property bool interacted

    // ---- guest hosting ----------------------------------------------------
    // The launcher mounts this same component at the bottom of its camera pan,
    // so the world tree you fly down to IS the dashboard rather than a painting
    // of it. A GUEST does not own the shell-global dashboard state: its reveal
    // comes from the host's camera instead of `screenState.dashboard`, it must
    // not publish the drawers window's input mask or claim that window's
    // keyboard focus, and "dismiss" means "tell the host" (fly back up), not
    // "close the drawer". Read off `nav` by LivingTree.qml.
    // Dormant-sprout mode: paint the seed and the hover-to-grow strip at the
    // bottom edge and nothing else, because the tree this instance would grow
    // is being grown somewhere else (see Wrapper.qml).
    property bool sproutOnly

    property bool guest
    property bool guestOnScreen: true
    property real guestOpenP: 1
    // How far the tree host has been pushed down the frame by the host's
    // camera, and how present the tree's own brown room should be. The room is
    // full-SURFACE and this item is the surface, so without the offset it
    // would ride down with the tree and cut a hard band across the host's top
    // edge instead of covering the screen.
    property real guestRoomOffset
    property real guestRoomP: 1
    // The launcher hangs its tree in a midnight sky, so it hands in the
    // pre-baked night variant of the painting rather than the daylight one.
    property url guestArtSource

    signal guestDismissRequested
    // Escape's own way out, distinct from guestDismissRequested: the pointer
    // paths mean "leave this room" (the host flies back up), Escape means
    // "close", full stop.
    signal guestCloseRequested
    signal guestSearchRequested(string text)
    signal guestFocusRequested

    // navStyle: "living" (default) | "tabs". "living" mode has no tab bar and
    // no band, because the growing tree (a separate URL-loaded nav) is both
    // nav AND content host. treeUnavailable is the belt-and-braces half: the
    // tree is loaded by URL, and if that file is missing or broken we fall
    // back to Tabs.qml rather than shipping a dashboard with no navigation.
    property bool treeUnavailable
    // qmllint disable missing-property
    // treeUnavailable HAS to gate this, not just the loader: without it a
    // failed LivingTree.qml left useLiving true, so navTabs stayed inactive and
    // the dashboard came up with no navigation at all — the exact failure the
    // fallback exists to prevent.
    readonly property bool useLiving: Config.dashboard.navStyle === "living" && !root.treeUnavailable

    // Wrapper.qml reads `content.item?.growProgress` to drive its reveal: in
    // living mode the tree's own growth IS the reveal, so forward the host's
    // scalar. Zero in tabs/tree mode, where Wrapper slides the panel instead.
    readonly property real growProgress: root.useLiving ? (livingTree.item?.growProgress ?? 0) : 0
    // qmllint enable missing-property

    readonly property bool keyboardNavEnabled: Config.dashboard.keyboardNav

    // Claiming layershell keyboard focus for the whole time the dashboard is
    // merely open would eat keystrokes from the app underneath, and with
    // showOnHover the panel opens without anyone asking. So: claim it when the
    // panel was opened deliberately (keybind/IPC), when hover-open is off (every
    // open is deliberate), when a pointer has landed on the nav, or when a pane
    // asks for keys (TasksTab).
    readonly property bool wantsKeyboard: screenState.dashboard && root.keyboardNavEnabled && (root.needsKeyboard || root.interacted || screenState.dashboardOpenedByKey || !Config.dashboard.showOnHover)
    // `viewLoader.item` is null for the living-mode instant where the
    // carousel is not instantiated at all. The nav is always the tab bar
    // here: living mode is full-bleed and sizes nothing through this path.
    readonly property real nonAnimWidth: (viewLoader.item?.implicitWidth ?? 0) + viewLoader.anchors.margins * 2
    readonly property real nonAnimHeight: navTabs.implicitHeight + navTabs.anchors.topMargin + (viewLoader.item?.implicitHeight ?? 0) + viewLoader.anchors.margins * 2

    function selectSection(id: string): bool {
        return root.screenState.selectDashboardSection(id);
    }

    function focusSection(id: string): bool {
        return root.screenState.focusDashboardSection(id);
    }

    function toggleSection(id: string): string {
        return root.screenState.toggleDashboardSection(id);
    }

    // Left/Right and the wheel. Neither surviving nav draws a focus ring — the
    // living tree emphasises-and-grows, the tab bar slides its underline — so
    // this always moves the selection rather than a ring.
    function navigate(delta: int): void {
        // The living tree hangs one node per CARD, so stepping whole sections
        // would jump over most of the canopy. Falls back to sections for the
        // tab bar, which really does show one section at a time.
        // qmllint disable missing-property
        const tree = root.useLiving ? livingTree.item : null;
        if (tree && typeof tree.stepCard === "function") {
            tree.stepCard(delta);
            return;
        }
        // qmllint enable missing-property
        root.screenState.stepDashboardSection(delta);
    }

    function activateFocused(): void {
        root.selectSection(root.focusedSectionId || root.activeSectionId);
    }

    // Escape closes outright, wherever this instance is mounted — it never
    // steps back through an intermediate room on the way out. A guest's
    // dismissSurface() only flies up to the host's other room, which is a
    // "back", not a close.
    // NOT `escape` — QML rejects that as an illegal method name (it collides with
    // the JS global) and the whole shell fails to load with "Illegal method name".
    function escapeNav(): void {
        if (root.guest)
            root.guestCloseRequested();
        else
            root.screenState.dashboard = false;
    }

    function dismissSurface(): void {
        if (root.guest)
            root.guestDismissRequested();
        else
            root.screenState.dashboard = false;
    }

    function grabKeyboard(): void {
        // Not while the launcher is up: the showall keybind opens both, and the
        // launcher's search field is the one that should hold focus. Nor for a
        // sprout, whose whole tree is in that same launcher surface.
        if (root.sproutOnly || root.guest)
            return;
        if (root.screenState.dashboard && root.keyboardNavEnabled && !root.screenState.launcher)
            root.forceActiveFocus();
    }

    function publishSections(): void {
        root.screenState.dashboardSectionIds = root.sections.map(s => s.id);
        root.screenState.dashboardEnabledIds = root.enabledSections.map(s => s.id);
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    onSectionsChanged: root.publishSections()
    // Guests never touch it: two instances writing one shell-global property
    // means the guest's `false` can land on top of the drawer's `true`.
    onWantsKeyboardChanged: if (!root.guest)
        root.screenState.dashboardWantsKeyboard = root.wantsKeyboard

    Keys.onLeftPressed: root.navigate(-1)
    Keys.onRightPressed: root.navigate(1)
    Keys.onReturnPressed: root.activateFocused()
    Keys.onEnterPressed: root.activateFocused()
    Keys.onSpacePressed: root.activateFocused()
    Keys.onEscapePressed: root.escapeNav()
    // No surviving nav draws a focus ring, and swallowing Tab without one would
    // break ordinary focus navigation inside a pane for no visible benefit.
    Keys.onPressed: event => {
        if (root.guest && root.screenState.dashboardOpenSections.length === 0
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                && event.text.length > 0 && event.text.charCodeAt(0) >= 0x20) {
            root.guestSearchRequested(event.text);
            event.accepted = true;
            return;
        }
        // Digits select by position in the enabled set, left to right — the
        // same numbering the setTab IPC uses.
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            const i = event.key - Qt.Key_1;
            if (i < root.enabledSections.length) {
                root.selectSection(root.enabledSections[i].id);
                event.accepted = true;
            }
            return;
        }
        switch (event.key) {
        case Qt.Key_Home:
            root.screenState.selectDashboardEdge(false);
            event.accepted = true;
            break;
        case Qt.Key_End:
            root.screenState.selectDashboardEdge(true);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            // Hand focus into the showing pane. Only reached if the pane did
            // not already own the key (TasksTab consumes Up/Down itself).
            (viewLoader.item?.currentItem as Loader)?.item?.forceActiveFocus();
            event.accepted = true;
            break;
        case Qt.Key_Down:
            root.grabKeyboard();
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (event.modifiers & Qt.ControlModifier) {
                root.toggleSection(root.focusedSectionId);
                event.accepted = true;
            }
            break;
        default:
            break;
        }
    }

    Component.onCompleted: {
        root.publishSections();
        if (!root.guest)
            root.screenState.dashboardWantsKeyboard = root.wantsKeyboard;
        root.grabKeyboard();
    }
    Component.onDestruction: if (!root.guest)
        root.screenState.dashboardWantsKeyboard = false

    // Section Components, hoisted to root scope (not nested inside the
    // Flickable below) so they stay resolvable by id from `sections` above no
    // matter which chrome is gated off by a Loader. This is the load-bearing
    // half of "no solid background container": once the tab-bar/tree carousel
    // moves behind `Loader.active` it becomes its own Component boundary, and
    // ids declared inside a Loader.sourceComponent are invisible outside it. A
    // `living` prop threads through to every section but TasksTab — it owns
    // its own 900+ line layout and keyboard model and is hosted as-is.
    Component {
        id: dashComponent

        Dash {
            screenState: root.screenState
            facePicker: root.facePicker
            living: root.useLiving
        }
    }

    Component {
        id: mediaComponent

        Media {
            screenState: root.screenState
            living: root.useLiving
        }
    }

    Component {
        id: performanceComponent

        Performance {
            living: root.useLiving
        }
    }

    Component {
        id: weatherComponent

        WeatherTab {
            living: root.useLiving
        }
    }

    Component {
        id: tasksComponent

        TasksTab {
            living: root.useLiving
        }
    }

    // ---- living-tree card manifest ---------------------------------------
    // The tree hangs INDIVIDUAL cards on their own twigs instead of one pane
    // per section. Sections remain the GROUPING (a card's sectionId picks
    // which bough it forks off) but are not the unit of display — one pane
    // per section left four of five branches bare while a single pane hogged
    // the middle.
    //
    // `alwaysOn` cards instantiate whenever the tree is open — this is what
    // makes the crown look inhabited. The three monolithic panes (weather
    // ~840x500, media ~1000x340, tasks ~1100x560) are deliberately NOT
    // alwaysOn: together they are ~1.4M px^2 against ~720k for all eleven
    // small cards, so they would swamp the canopy. They stay emphasis-gated
    // and hang a labelled bud until picked.
    //
    // Ordering matters: cards are laid along their bough in this order, so
    // keep each section's run contiguous.
    readonly property var treeCards: [
        {
            id: "user",
            sectionId: "dashboard",
            iconName: "person",
            text: qsTr("User"),
            component: cardUser,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "datetime",
            sectionId: "dashboard",
            iconName: "schedule",
            text: qsTr("Time"),
            component: cardDateTime,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "calendar",
            sectionId: "dashboard",
            iconName: "calendar_month",
            text: qsTr("Calendar"),
            component: cardCalendar,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "smallweather",
            sectionId: "dashboard",
            iconName: "cloud",
            text: qsTr("Weather"),
            component: cardSmallWeather,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "resources",
            sectionId: "dashboard",
            iconName: "donut_small",
            text: qsTr("Resources"),
            component: cardResources,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "nowplaying",
            sectionId: "dashboard",
            iconName: "queue_music",
            text: qsTr("Now Playing"),
            component: cardNowPlaying,
            alwaysOn: true,
            enabled: true
        },
        {
            id: "cpu",
            sectionId: "performance",
            iconName: "memory",
            text: qsTr("CPU"),
            component: cardCpu,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showCpu
        },
        {
            id: "gpu",
            sectionId: "performance",
            iconName: "desktop_windows",
            text: qsTr("GPU"),
            component: cardGpu,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showGpu && Gpu.type !== Gpu.None
        },
        {
            id: "memory",
            sectionId: "performance",
            iconName: "memory_alt",
            text: qsTr("Memory"),
            component: cardMemory,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showMemory
        },
        {
            id: "storage",
            sectionId: "performance",
            iconName: "hard_drive",
            text: qsTr("Storage"),
            component: cardStorage,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showStorage
        },
        {
            id: "network",
            sectionId: "performance",
            iconName: "swap_vert",
            text: qsTr("Network"),
            component: cardNetwork,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showNetwork
        },
        {
            id: "battery",
            sectionId: "performance",
            iconName: "battery_full",
            text: qsTr("Battery"),
            component: cardBattery,
            alwaysOn: true,
            enabled: Config.dashboard.performance.showBattery && UPower.displayDevice.isLaptopBattery
        },
        {
            id: "weather",
            sectionId: "weather",
            iconName: "cloud",
            text: qsTr("Forecast"),
            component: weatherComponent,
            alwaysOn: false,
            enabled: true
        },
        {
            id: "media",
            sectionId: "media",
            iconName: "queue_music",
            text: qsTr("Media"),
            component: mediaComponent,
            alwaysOn: false,
            enabled: true
        },
        {
            id: "tasks",
            sectionId: "tasks",
            iconName: "checklist",
            text: qsTr("Tasks"),
            component: tasksComponent,
            alwaysOn: false,
            enabled: true
        }
    ]

    // Each small card is its own plate on the tree. BarkCard is a pure SKIN —
    // it adds no padding and changes no implicit size (see its header) — so
    // TreeCard supplies both, sizing itself off the one widget it wraps.
    component TreeCard: BarkCard {
        id: treeCard

        default property alias body: cardBody.data
        property real pad: Tokens.padding.large
        // Explicit, because half of these widgets have NO meaningful implicit
        // size: Dash.qml hands them Layout.fillHeight / a preferredWidth token
        // and lets the grid size them. Standalone on a twig there is no grid,
        // so childrenRect came back 0, the plate collapsed, and the card's
        // contents drew bare on the canopy.
        property real preferW: 0
        property real preferH: 0

        readonly property Item cardChild: cardBody.children.length > 0 ? cardBody.children[0] : null

        opaque: true
        radius: Tokens.rounding.extraLarge
        implicitWidth: (treeCard.preferW > 0 ? treeCard.preferW : (treeCard.cardChild?.implicitWidth ?? 0)) + treeCard.pad * 2
        implicitHeight: (treeCard.preferH > 0 ? treeCard.preferH : (treeCard.cardChild?.implicitHeight ?? 0)) + treeCard.pad * 2

        Item {
            id: cardBody

            x: treeCard.pad
            y: treeCard.pad
            width: treeCard.width - treeCard.pad * 2
            height: treeCard.height - treeCard.pad * 2

            // Assigned, not bound: binding the child's size to this while this
            // sizes off the child is the loop the explicit prefers exist to
            // avoid. One assignment per resize is enough.
            onWidthChanged: if (treeCard.cardChild) treeCard.cardChild.width = cardBody.width
            onHeightChanged: if (treeCard.cardChild) treeCard.cardChild.height = cardBody.height
            Component.onCompleted: if (treeCard.cardChild) {
                treeCard.cardChild.width = cardBody.width;
                treeCard.cardChild.height = cardBody.height;
            }
        }
    }

    Component {
        id: cardUser

        TreeCard {
            preferW: 340
            preferH: 300
            grainSeed: 1
            moss: true

            DashCards.User {
                screenState: root.screenState
                facePicker: root.facePicker
            }
        }
    }

    Component {
        id: cardSmallWeather

        TreeCard {
            preferW: 275
            preferH: 96
            grainSeed: 2
            grainHorizontal: true

            DashCards.SmallWeather {}
        }
    }

    Component {
        id: cardDateTime

        TreeCard {
            preferW: 190
            preferH: 130
            grainSeed: 3

            DashCards.DateTime {}
        }
    }

    Component {
        id: cardCalendar

        TreeCard {
            preferW: 400
            preferH: 300
            grainSeed: 4

            DashCards.Calendar {
                screenState: root.screenState
            }
        }
    }

    Component {
        id: cardResources

        TreeCard {
            preferW: 180
            preferH: 260
            grainSeed: 5

            DashCards.Resources {}
        }
    }

    Component {
        id: cardNowPlaying

        TreeCard {
            preferW: 270
            preferH: 360
            grainSeed: 6

            DashCards.Media {}
        }
    }

    Component {
        id: cardCpu

        TreeCard {
            preferW: 380
            preferH: 150
            grainSeed: 11

            HeroCard {
                icon: "memory"
                label: qsTr("CPU")
                subLabel: Cpu.name
                usage: Cpu.percentage
                temperature: Cpu.temperature
                accent: Colours.palette.m3primary
                moss: true
                opaque: true
                // The HeroCard's own bark covers the TreeCard's, so the seed
                // has to be repeated here or both heroes open on tile origin 0
                // and the pair reads as one striped slab.
                grainSeed: 11

                ServiceRef {
                    service: Cpu
                }
            }
        }
    }

    Component {
        id: cardGpu

        TreeCard {
            preferW: 380
            preferH: 150
            grainSeed: 12

            HeroCard {
                icon: "desktop_windows"
                label: qsTr("GPU")
                subLabel: Gpu.name
                usage: Gpu.percentage
                temperature: Gpu.temperature
                accent: Colours.palette.m3secondary
                opaque: true
                grainSeed: 12

                ServiceRef {
                    service: Gpu
                }
            }
        }
    }

    Component {
        id: cardMemory

        TreeCard {
            preferW: 260
            preferH: 190
            grainSeed: 13

            MemoryCard {
                opaque: true
            }
        }
    }

    Component {
        id: cardStorage

        TreeCard {
            preferW: 300
            preferH: 190
            grainSeed: 14

            StorageCard {
                opaque: true
            }
        }
    }

    Component {
        id: cardNetwork

        TreeCard {
            preferW: 390
            preferH: 210
            grainSeed: 15

            NetworkCard {
                opaque: true
            }
        }
    }

    Component {
        id: cardBattery

        TreeCard {
            preferW: 160
            preferH: 170
            grainSeed: 16

            BatteryTank {
                opaque: true
            }
        }
    }

    // navStyle "living" draws no panel at all: the tree is ink on wallpaper,
    // and every section root is responsible for its own plate(s) instead (see
    // Dash/Media/Performance/WeatherTab's `living` branches). Gated behind a
    // Loader rather than `visible: false` so the WoodPanel's clip node and its
    // unscaled texture are never even instantiated in living mode.
    Loader {
        anchors.fill: parent
        active: !root.useLiving

        sourceComponent: WoodPanel {
            anchors.fill: parent
            radius: Tokens.rounding.extraLarge
            fill: Qt.alpha(Colours.palette.m3primaryContainer, 0.05)
        }
    }

    // No corner accent here on purpose. A single small leaf tucked into the
    // top-left read as a sticker, and anything with real presence in that corner
    // collides with the tab row that starts one padding step away. The woodland
    // character now lives where there is room for it: the bark cards inside.

    Loader {
        id: navTabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        active: !root.useLiving

        sourceComponent: Tabs {
            nonAnimWidth: root.nonAnimWidth - navTabs.anchors.margins * 2
            screenState: root.screenState
            tabs: root.enabledSections
        }
    }

    // The living tree: full-bleed, no panel behind it, grown from the bottom
    // edge. Deliberately loaded by URL rather than by a typed
    // `import qs.modules.dashboard.tree`, so a missing or broken LivingTree.qml
    // degrades to the tab bar instead of taking the entire dashboard down with
    // it. `nav` is the whole contract: the tree reads sections /
    // activeSectionId / focusedSectionId off it and calls selectSection /
    // focusSection / toggleSection / navigate on it. One initial property,
    // everything else reactive through it.
    Loader {
        id: livingTree

        anchors.fill: parent

        active: root.useLiving

        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn(lc, "living tree nav failed to load; falling back to the tab bar");
                root.treeUnavailable = true;
            }
        }
        Component.onCompleted: setSource(Qt.resolvedUrl("tree/LivingTree.qml"), {
            nav: root
        })
    }

    // navStyle "living" hosts each section at its own bough tip instead of in
    // this horizontal carousel, so the whole clip/flick/repeater apparatus is
    // gated behind a Loader — same demolition technique as the WoodPanel
    // above. `viewLoader.item` is guarded with `?.` in the width/height maths
    // below for the living-mode instant where nothing is loaded.
    Loader {
        id: viewLoader

        anchors.top: navTabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        active: !root.useLiving

        sourceComponent: ClippingRectangle {
            id: viewWrapper

            // Forwarded so `Keys.onUpPressed` and `needsKeyboard` (outside
            // this Loader's sourceComponent boundary) can still reach the
            // showing pane / walk the repeater.
            readonly property Item currentItem: view.currentItem
            readonly property var repeaterRef: repeater

            anchors.fill: parent

            radius: Tokens.rounding.large
            color: "transparent"

            implicitWidth: view.implicitWidth
            implicitHeight: view.implicitHeight

            Flickable {
                id: view

                // Index into the enabled subset. Derived from the section id,
                // not stored, so a disabled section can never leave this
                // pointing at the wrong pane.
                readonly property int currentIndex: Math.max(0, root.activeIndex)
                readonly property Item currentItem: {
                    repeater.count; // Trigger update on count change
                    return repeater.itemAt(currentIndex);
                }

                anchors.fill: parent

                flickableDirection: Flickable.HorizontalFlick

                implicitWidth: currentItem?.implicitWidth ?? 0
                implicitHeight: currentItem?.implicitHeight ?? 0

                contentX: currentItem?.x ?? 0
                contentWidth: row.implicitWidth
                contentHeight: row.implicitHeight

                onContentXChanged: {
                    if (!moving || !currentItem)
                        return;

                    const x = contentX - currentItem.x;
                    if (x > currentItem.implicitWidth / 2)
                        root.screenState.stepDashboardSection(1);
                    else if (x < -currentItem.implicitWidth / 2)
                        root.screenState.stepDashboardSection(-1);
                }

                onDragEnded: {
                    if (!currentItem)
                        return;

                    const x = contentX - currentItem.x;
                    if (x > currentItem.implicitWidth / 10)
                        root.screenState.stepDashboardSection(1);
                    else if (x < -currentItem.implicitWidth / 10)
                        root.screenState.stepDashboardSection(-1);
                    else
                        contentX = Qt.binding(() => currentItem?.x ?? 0);
                }

                RowLayout {
                    id: row

                    Repeater {
                        id: repeater

                        model: ScriptModel {
                            values: root.enabledSections
                        }

                        delegate: Loader {
                            id: paneLoader

                            required property int index
                            required property var modelData

                            Layout.alignment: Qt.AlignTop

                            sourceComponent: modelData.component

                            Component.onCompleted: active = Qt.binding(() => {
                                if (index === view.currentIndex)
                                    return true;
                                const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
                                const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
                                return (vx >= x && vx <= x + implicitWidth) || (vex >= x && vex <= x + implicitWidth);
                            })
                        }
                    }
                }

                Behavior on contentX {
                    Anim {}
                }
            }
        }
    }

    Connections {
        function onDashboardChanged(): void {
            if (root.screenState.dashboard)
                root.grabKeyboard();
            else
                root.interacted = false;
        }

        function onDashboardOpenSectionsChanged(): void {
            if (root.guest && root.screenState.dashboard
                    && root.screenState.dashboardOpenSections.length === 0)
                root.guestFocusRequested();
        }

        target: root.screenState
    }

    LoggingCategory {
        id: lc

        name: "burl.qml.dashboard"
        defaultLogLevel: LoggingCategory.Info
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
