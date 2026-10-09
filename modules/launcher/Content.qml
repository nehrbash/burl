pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.dashboard as Dashboard
import qs.modules.launcher
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState visibilities
    required property var panels
    readonly property var sidebar: ShellState.componentsFor(visibilities.modelData)?.bar
    readonly property real sidebarClearance: sidebar?.shouldBeVisible
        ? Math.max(0, sidebar.mapToItem(root, sidebar.trunkX + sidebar.trunkWidth, 0).x) : 0

    anchors.fill: parent

    // Both rooms share one camera so an interrupted pan reverses coherently.
    property real panP: 0

    // Read by the Behavior when it starts, so `flyTo` sets them first. Each
    // trip has its own pace: arriving is a shot, leaving is a dismissal.
    property int panMs: 1000
    property int panEase: Easing.InOutQuart

    function flyTo(target: real, ms: int, ease: int): void {
        dwell.stop();
        root.panMs = ms;
        root.panEase = ease;
        root.panP = target;
    }

    // ---- one surface, two rooms -------------------------------------------
    // `visibilities.launcher` means "show me the sky and its graph";
    // `visibilities.dashboard` means "show me the world tree on the ground".
    // Either one keeps this surface mounted (see Wrapper), and which one is set
    // decides where the camera points — so flying by hand is a matter of moving
    // the flags, not of nudging panP behind their back.
    readonly property bool surfaceOpen: root.visibilities.launcher || root.visibilities.dashboard

    // Tracks the PREVIOUS surfaceOpen so the camera can tell "the surface just
    // opened, play the arrival" from "we are already up and moving between
    // rooms". A binding cannot: it would already read the new value.
    property bool wasOpen

    function ascend(): void {
        root.visibilities.openWorldRoom("launcher");
    }

    function descend(): void {
        root.visibilities.openWorldRoom("dashboard");
    }

    function dismiss(): void {
        root.visibilities.launcher = false;
        root.visibilities.dashboard = false;
    }

    // Window shortcuts remain reachable when a book's editor consumes arrow keys.
    Shortcut {
        sequence: "Ctrl+Up"
        context: Qt.WindowShortcut
        enabled: root.surfaceOpen
        onActivated: root.ascend()
    }

    Shortcut {
        sequence: "Ctrl+Down"
        context: Qt.WindowShortcut
        enabled: root.surfaceOpen
        onActivated: root.descend()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.surfaceOpen
        onActivated: root.dismiss()
    }

    function syncCamera(): void {
        const open = root.visibilities.launcher || root.visibilities.dashboard;
        const interruptedClose = !root.wasOpen && root.revealP > 0;
        root.revealP = open ? 1 : 0;
        if (!open) {
            root.flyTo(0, 300, Easing.InCubic);
        } else if (root.visibilities.launcher) {
            if (root.wasOpen || interruptedClose)
                root.flyTo(1, 620, Easing.InOutQuart);
            else {
                // The opening shot: hold on the tree, then climb.
                root.panMs = 1000;
                root.panEase = Easing.InOutQuart;
                dwell.restart();
            }
        } else if (root.wasOpen) {
            root.flyTo(0, 760, Easing.InOutQuart);
        } else {
            // Asked straight for the tree from closed — there is no camera move
            // to play, the tree just grows in where the camera already is.
            dwell.stop();
            root.panP = 0;
        }
        root.wasOpen = open;
    }

    // The opening shot holds on the tree before it moves. Without the hold the
    // pan starts the instant the surface appears and the tree is gone before
    // the eye has found it — and a fast-start ease like OutQuint makes that
    // worse, since two thirds of the distance is covered in the first fifth
    // of the time. Hold, then InOutQuart.
    Timer {
        id: dwell

        interval: 340
        repeat: false
        onTriggered: root.panP = 1
    }

    // Any keystroke skips the shot, and typing while down at the tree means
    // "take me to the search" — someone who opened this to type a query should
    // not wait out a second of scenery, and someone who wanted the scenery is,
    // by definition, not typing.
    function skipToSky(): void {
        if (root.visibilities.dashboard) {
            root.ascend();
            return;
        }
        if (root.panP < 1)
            root.flyTo(1, 380, Easing.OutCubic);
    }

    Behavior on panP {
        enabled: Ambience.grow && !GameMode.enabled

        NumberAnimation {
            duration: root.panMs
            easing.type: root.panEase
        }
    }

    // Flag signals precede dependent bindings; defer until the room swap settles.
    Connections {
        function onLauncherChanged(): void {
            Qt.callLater(root.syncCamera);
        }

        function onDashboardChanged(): void {
            Qt.callLater(root.syncCamera);
        }

        target: root.visibilities
    }

    // Opening the launcher within the preload window mounts Content
    // asynchronously with `launcher` ALREADY true, so onLauncherChanged never
    // fires — and a Behavior does not run on initial evaluation, so a plain
    // `panP: launcher ? 1 : 0` binding would land in the sky with no pan.
    // This is the first open after every shell restart, exactly when someone
    // is looking for the animation.
    Component.onCompleted: root.syncCamera()

    // Keep search focused at the tree while its invisible hit targets sit below it.
    readonly property int chromeZ: root.arrivalP > 0.6 ? 5 : 1

    // The graph is up in the sky, so it arrives with the camera: lifted in
    // from below by the last stretch of the pan and faded up over the back
    // half of it, rather than being present the whole way and dragging the
    // eye off the tree.
    readonly property real arrivalP: CUtils.clamp((root.panP - 0.45) / 0.55, 0, 1)

    // Presence is independent of camera position: descending keeps the room open.
    property real revealP: 0

    Behavior on revealP {
        enabled: Ambience.grow && !GameMode.enabled
        NumberAnimation {
            duration: root.surfaceOpen ? 640 : 260
            easing.type: root.surfaceOpen ? Easing.InOutCubic : Easing.InCubic
        }
    }

    Sky {
        id: sky

        anchors.fill: parent
        panP: root.panP
        viewZoom: graph.zoom
        viewPanX: graph.panX
        viewPanY: graph.panY
        onScreen: root.revealP > 0.001
        opacity: root.revealP
    }

    // The world tree at the bottom of the pan is the DASHBOARD's living tree,
    // mounted here as a guest (see Dashboard.Content's `guest` block) rather
    // than a second painting of the same art. Sky owns the camera, so the
    // host just rides `sky.hostY` — flush with the
    // frame at panP 0, which is the layout the tree measures its orbs against.
    //
    // z, not declaration order: the search chrome below fades to opacity 0 down
    // here but stays hit-testable, and the graph fills the surface. Lifting the
    // host above both is what lets a click reach an orb. Both of them are
    // `enabled: false` at this end of the pan anyway; the scenery bands (z 2)
    // are not, so they stay under the tree and catch only what it does not cover.
    Item {
        id: treeHost

        x: 0
        y: sky.hostY
        width: root.width
        height: root.height
        z: 3
        enabled: root.panP < 0.5
        visible: root.revealP > 0.001
        opacity: root.revealP

        Loader {
            anchors.fill: parent
            // Retain the tree geometry between opens; section loaders gate their services.
            active: true
            asynchronous: true

            sourceComponent: Dashboard.Content {
                screenState: root.visibilities
                facePicker: launcherFacePicker
                guest: true
                guestOnScreen: root.revealP > 0.001 && sky.hostY < root.height
                // Grown for as long as the surface is up, whichever room the
                // camera is in — the unveil is the surface arriving, not the
                // camera reaching the ground, or the two reveals fight.
                guestOpenP: root.surfaceOpen ? 1 : 0
                // The tree's own brown, leafy room, lifted back out of the
                // host's camera offset so it covers the frame, and faded out as
                // the camera climbs into the sky that replaces it.
                guestRoomOffset: sky.hostY
                guestRoomP: CUtils.clamp(1 - root.panP / 0.55, 0, 1)
                guestArtSource: Quickshell.shellPath("assets/images/tree/worldtree-night.png")
                onGuestDismissRequested: root.ascend()
                onGuestCloseRequested: root.dismiss()
                onGuestFocusRequested: search.forceActiveFocus()
                onGuestSearchRequested: text => {
                    root.ascend();
                    search.forceActiveFocus();
                    search.insert(search.cursorPosition, text);
                }
            }
        }
    }

    Dashboard.FacePicker {
        id: launcherFacePicker
    }

    readonly property string prefix: GlobalConfig.launcher.actionPrefix
    // Web-search prefix. `?weather today` runs the configured search
    // engine query immediately on Enter, regardless of any matches in
    // the graph. Ctrl+Enter does the same thing from any non-prefix
    // search ("I have a match but I want to web-search anyway").
    readonly property string webSearchPrefix: "?"
    // Configurable in shell.json some day; xdg-open hands off to the
    // user's default browser so this just needs a query-string template.
    readonly property string webSearchUrl: "https://duckduckgo.com/?q=%1"

    function isWebSearch(t: string): bool {
        return t.startsWith(webSearchPrefix);
    }

    function webSearchQuery(t: string): string {
        return t.startsWith(webSearchPrefix)
            ? t.slice(webSearchPrefix.length).trim()
            : t.trim();
    }

    // Tab-complete a partial scope keyword. Matches `>partial` at the end
    // of the search text against the known keyword list, extends to the
    // longest common prefix, and appends a trailing space on a unique hit.
    // Returns true if the text was changed (consume the Tab event).
    function tryTabComplete(): bool {
        const t = search.text;
        const lastPfx = t.lastIndexOf(prefix);
        if (lastPfx < 0) return false;
        const afterPfx = t.slice(lastPfx + prefix.length);
        // Already has a space → keyword is complete, we're in the query portion.
        if (afterPfx.includes(" ")) return false;
        const partial = afterPfx.toLowerCase();
        if (partial.length === 0) return false;
        const keywords = ["apps","roam","recents","bookmarks","wallpaper",
                          "web","webbm","webfolder","webhist","tabs",
                          "spotify","playlists","tracks","clients","monitors",
                          "workspaces","category","projects","mail","cal","clip","emoji"];
        const hits = keywords.filter(k => k.startsWith(partial));
        if (hits.length === 0) return false;
        // Exact match → just append the trailing space.
        if (hits.length === 1 && hits[0] === partial) {
            search.text = t + " ";
            search.cursorPosition = search.text.length;
            return true;
        }
        let lcp = hits[0];
        for (let i = 1; i < hits.length; i++) {
            let j = 0;
            while (j < lcp.length && j < hits[i].length && lcp[j] === hits[i][j]) j++;
            lcp = lcp.slice(0, j);
        }
        if (lcp.length <= partial.length) return false;
        const suffix = hits.length === 1 ? " " : "";
        search.text = t.slice(0, lastPfx + prefix.length) + lcp + suffix;
        search.cursorPosition = search.text.length;
        return true;
    }

    function runWebSearch(q: string): void {
        if (!q) return;
        const url = webSearchUrl.replace("%1", encodeURIComponent(q));
        visibilities.launcher = false;
        Quickshell.execDetached(["xdg-open", url]);
    }
    // Scope grammar: `>kind <q> [>kind <q> …]` builds a union of per-kind
    // subsearches. Each `>kind ` opens a segment that runs until the next
    // `>kind ` or end of text — the chars between are that segment's
    // typed query.
    //
    // Examples:
    //   >wallpaper           → wallpapers (no query)
    //   >apps p              → apps matching 'p'
    //   >wallpaper >apps     → wallpapers ∪ apps
    //   >apps p >recent meet → apps matching 'p' ∪ recents matching 'meet'
    readonly property var scope: parseScopeSegments(search.text)

    // Inverse of the scope→kind map below: kind id → the scope
    // keyword the user would type. Used to "pivot" onto an elevated
    // non-match node (Enter promotes the node's source into the
    // active scope set instead of firing its onClicked action).
    readonly property var kindToScopeKw: ({
        app: "apps",
        roam: "roam",
        recent: "recents",
        bookmark: "bookmarks",
        wallpaper: "wallpaper",
        webBookmark: "webbm",
        webFolder: "webfolder",
        webHistory: "webhist",
        webTab: "tabs",
        spotifyPlaylist: "playlists",
        spotifyTrack: "tracks",
        client: "clients",
        monitor: "monitors",
        workspace: "workspaces",
        category: "category",
        project: "projects",
        mail: "mail",
        event: "cal",
        clip: "clip",
        emoji: "emoji",
    })

    function parseScopeSegments(t: string): var {
        // `web` covers all three webish kinds in one shot: leaves,
        // folders, and history. Individual sub-scopes (`webbm`,
        // `webhist`, `webfolder`) target a single kind for power users.
        const map = ({
            apps: "app",
            roam: "roam",
            recents: "recent",
            bookmarks: "bookmark",
            wallpaper: "wallpaper",
            web: ["webBookmark", "webFolder", "webHistory", "webTab"],
            webbm: "webBookmark",
            webfolder: "webFolder",
            webhist: "webHistory",
            tabs: "webTab",
            spotify: ["spotifyPlaylist", "spotifyTrack"],
            playlists: "spotifyPlaylist",
            tracks: "spotifyTrack",
            clients: "client",
            monitors: "monitor",
            workspaces: "workspace",
            category: "category",
            projects: "project",
            mail: "mail",
            cal: "event",
            clip: "clip",
            emoji: "emoji",
        });
        function matchAt(pos) {
            for (const key in map) {
                const base = `${prefix}${key}`;
                if (!t.startsWith(base, pos)) continue;
                // A scope keyword is delimited by a following space OR the
                // end of input — so a trailing `>apps` (still being typed,
                // no space yet) opens its scope immediately instead of
                // being folded into the previous segment's query text.
                const after = pos + base.length;
                const ch = t[after];
                if (ch === undefined) return { kind: map[key], next: after };
                if (ch === " ") return { kind: map[key], next: after + 1 };
            }
            return null;
        }
        if (!matchAt(0)) return null;
        const segs = [];
        let pos = 0;
        while (pos < t.length) {
            const m = matchAt(pos);
            if (!m) {
                // Trailing chars that aren't a scope marker — fold them into
                // the previous segment's query (e.g. user typed text after).
                if (segs.length > 0)
                    segs[segs.length - 1].q = (segs[segs.length - 1].q + " " + t.slice(pos)).trim();
                break;
            }
            // Scan forward to the next scope marker (or end).
            let end = t.length;
            for (let scan = m.next; scan < t.length; ++scan) {
                if (matchAt(scan)) { end = scan; break; }
            }
            const q = t.slice(m.next, end).trim();
            // A scope key can map to a string (one kind) or an array
            // (the kinds it bundles — e.g. `web` -> webBookmark|Folder|
            // History). Fan-out arrays into one segment per kind so the
            // GraphView's per-segment matcher treats each independently.
            if (Array.isArray(m.kind)) {
                for (const k of m.kind) segs.push({ kind: k, q });
            } else {
                segs.push({ kind: m.kind, q });
            }
            pos = end;
        }
        return segs.length > 0 ? segs : null;
    }

    // Actions / calc overlay shows for `>` alone or `>action…` — but not
    // when in a scoped graph filter (those route through the graph itself).
    readonly property bool inActions: search.text.startsWith(prefix) && !scope
    // Entering the actions overlay kicks the background graph into
    // motion so it doesn't sit dead behind the popup.
    onInActionsChanged: if (inActions) graph.stir(0);

    // Per-kind action menu (Shift+Enter on a node). When open,
    // the ActionsOverlay lists kindActions(node) instead of the global
    // action query. Closed on Escape (before the launcher), on activate,
    // or when the selection goes away.
    property bool kindMenuOpen: false
    function openKindMenu(): void {
        const node = graph.topMatch();
        if (!node) return;
        const acts = graph.kindActions(node);
        if (!acts || acts.length === 0) return;
        actions.kindActions = acts;
        actions.inKindMode = true;
        kindMenuOpen = true;
        graph.stir(0);
    }
    function closeKindMenu(): void {
        kindMenuOpen = false;
        actions.inKindMode = false;
        actions.kindActions = [];
    }

    GraphView {
        id: graph

        objectName: "skyGraph"
        width: root.width
        height: root.height
        y: -sky.travel
        opacity: Math.min(1, root.panP * 3) * root.revealP
        enabled: root.arrivalP > 0.99
        visibilities: root.visibilities
        // When scope is active, GraphView does per-segment scoring and
        // ignores `query`. Otherwise the whole search text drives matching.
        // The `?` web-search prefix is stripped so the graph still scores
        // useful preview matches while the user types.
        query: root.scope
            ? ""
            : (root.inActions
               ? ""
               : (root.isWebSearch(search.text)
                  ? root.webSearchQuery(search.text)
                  : search.text))
        scopeSegments: root.scope ?? []
        // Camera motion and graph settling share the GUI thread.
        paused: !root.surfaceOpen || root.arrivalP < 0.999
        transitioning: root.surfaceOpen && root.panP > 0.001 && root.panP < 0.999
    }

    MouseArea {
        id: descend
        objectName: "skyDescend"

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.spacing.large
        anchors.leftMargin: root.sidebarClearance + Tokens.spacing.large
        width: descendLabel.implicitWidth + 58
        height: 44
        z: root.chromeZ
        enabled: root.atSky
        visible: root.arrivalP > 0.01
        opacity: root.arrivalP * root.revealP
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.descend()

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: descend.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(descend.containsMouse ? Colours.palette.m3primary : Colours.palette.m3outline, 0.3)
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        MaterialIcon {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "keyboard_double_arrow_down"
            color: descend.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        Text {
            id: descendLabel
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            text: "World tree  ·  Ctrl+↓"
            color: Woodland.creamSecondary
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: closeSky
        objectName: "skyClose"
        anchors.left: descend.right
        anchors.leftMargin: Tokens.spacing.small
        anchors.bottom: descend.bottom
        width: closeLabel.implicitWidth + 30
        height: descend.height
        z: root.chromeZ
        enabled: root.atSky
        visible: descend.visible
        opacity: descend.opacity
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: closeSky.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(closeSky.containsMouse ? Colours.palette.m3primary : Colours.palette.m3outline, 0.3)
        }
        Text {
            id: closeLabel
            anchors.centerIn: parent
            text: qsTr("Close · Esc")
            color: Woodland.creamSecondary
            font.pixelSize: 12
        }
    }

    Item {
        id: quickGrid
        z: root.chromeZ
        property int page: 0
        readonly property int curIdx: graph.currentNode
        readonly property var neighbors: {
            const linked = graph.nodeAdjacency[curIdx] ?? [];
            const nearby = graph.navSlots.filter(i => i >= 0 && !linked.includes(i));
            return linked.concat(nearby);
        }
        readonly property int count: neighbors.length
        readonly property int pages: Math.max(1, Math.ceil(count/8))
        readonly property var choices: neighbors.slice(page*8, page*8+8)
        readonly property string letters: "arstgmne"
        onCurIdxChanged: page = 0
        onPagesChanged: page = Math.min(page, pages-1)
        function nodeIndexForKey(k: int): int { return choices[k] ?? -1; }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: 12
        width: Math.min(root.width-80, 900)
        height: 194
        visible: count > 0 && !root.inActions && !root.kindMenuOpen && root.arrivalP > 0.01
        opacity: root.arrivalP * root.revealP
        enabled: root.atSky

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -28
            width: Math.min(500, parent.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: graph.nodes[quickGrid.curIdx]?.label ?? ""
            color: Woodland.parchment
            font.family: "serif"
            font.pixelSize: 18
        }

        Canvas {
            id: previewBranches
            anchors.fill: parent
            antialiasing: true
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: quickGrid
                function onChoicesChanged(): void { previewBranches.requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                for (let i = 0; i < quickGrid.choices.length; ++i) {
                    const left = i%2 === 0, row = Math.floor(i/2);
                    const reach = 0.18 + row*0.055;
                    const x = width*(left ? 0.5-reach : 0.5+reach);
                    const y = 22+row*43;
                    ctx.beginPath();
                    ctx.moveTo(width/2, height-14);
                    ctx.bezierCurveTo(width/2, y+28, x, y+35, x,y);
                    ctx.strokeStyle = Woodland.barkShaded;
                    ctx.lineWidth = 5-row*0.7;
                    ctx.stroke();
                    ctx.strokeStyle = Qt.alpha(Woodland.parchmentEdge, 0.45);
                    ctx.lineWidth = 0.8;
                    ctx.stroke();
                }
            }
        }

        Repeater {
            model: quickGrid.choices
            delegate: Item {
                id: twig
                required property int index
                required property int modelData
                readonly property var node: graph.nodes[modelData]
                width: quickGrid.width*0.30
                height: 34
                x: quickGrid.width*(0.5 + (index%2 === 0 ? -1 : 1)*(0.18+Math.floor(index/2)*0.055))-width/2
                y: 5+Math.floor(index/2)*43
                Rectangle {
                    anchors.fill: parent
                    radius: height/2
                    color: twigMouse.containsMouse
                        ? Colours.palette.m3surfaceContainerHighest
                        : Colours.palette.m3surfaceContainer
                    border.color: twigMouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3outline
                    opacity: 0.96
                }
                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⌃" + quickGrid.letters[twig.index].toUpperCase()
                    color: Colours.palette.m3primary
                    font.pixelSize: 11
                }
                Text {
                    x: 43
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width-55
                    text: twig.node?.label ?? ""
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 12
                }
                MouseArea {
                    id: twigMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: graph.selectNode(twig.modelData)
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: quickGrid.count + " connections   ·   " + (quickGrid.page+1) + "/" + quickGrid.pages
                + "   ·   Alt+[ ] browse   ·   Alt+← back"
            color: Woodland.parchment
            font.pixelSize: 11
        }
        MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 240; height: 24
            onWheel: event => {
                quickGrid.page = (quickGrid.page + (event.angleDelta.y < 0 ? 1 : -1) + quickGrid.pages) % quickGrid.pages;
                event.accepted = true;
            }
        }
    }

    // Floating action/calc list shown above the search bar when prefix typed.
    ActionsOverlay {
        id: actions

        z: root.chromeZ
        visible: root.inActions || root.kindMenuOpen
        opacity: root.arrivalP * root.revealP
        search: search
        visibilities: root.visibilities

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: Tokens.spacing.medium
    }

    StyledRect {
        id: searchWrapper

        z: root.chromeZ
        opacity: root.arrivalP * root.revealP

        // Parchment pill in a carved bark ring so the search bar reads
        // as wood chrome pinned over the graph, not a floating glass bar.
        // Opaque parchment (not Colours.layer — elevation alpha lets the
        // graph bleed through and kills input legibility) with a whisper
        // of the wallpaper scheme.
        color: Woodland.mix(Woodland.parchmentMid, Colours.palette.m3primaryContainer, 0.08)
        border.color: Woodland.barkShaded
        border.width: 2
        radius: height / 2   // true pill — radius tracks height.
        // Generous fixed height so the icon-in-circle has room AND
        // the search text sits comfortably. Matches drawer-style
        // launchers (krunner, anyrun).
        implicitHeight: 64
        implicitWidth: 880

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.08

        // Subtle paper grain inside the pill (clipped to the pill radius).
        WoodPanel {
            anchors.fill: parent
            radius: height / 2
            grainOpacity: 0.1
        }

        // Circular olive surround for the magnifier glyph so it
        // visually anchors the left of the pill (affirmative accent).
        Rectangle {
            id: searchIconBg
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.medium
            width: parent.height - Tokens.padding.small * 2
            height: width
            radius: height / 2
            color: Woodland.olive

            MaterialIcon {
                id: searchIcon
                anchors.centerIn: parent
                text: "search"
                color: Woodland.parchment
                // New MaterialIcon binds its whole `font` from `fontStyle`,
                // so a plain `font.pixelSize` gets clobbered. Size via the
                // icon builder instead (pointSize ≈ 0.45·px to match the
                // old 0.6·height pixel size).
                fontStyle: Tokens.font.icon.size(Math.round(parent.height * 0.45)).build()
            }
        }

        StyledTextField {
            id: search

            // searchWrapper already draws the pill + accent ring; suppress
            // the new StyledTextField's own Material outline background so
            // it doesn't render a second bar inside ours.
            background: null
            // Base onPressed pokes a background StateLayer that doesn't exist
            // here; the field is force-focused on open regardless.
            onPressed: {}

            anchors.left: searchIconBg.right
            anchors.right: clearIcon.left
            anchors.leftMargin: Tokens.spacing.medium
            anchors.rightMargin: Tokens.spacing.small
            anchors.verticalCenter: parent.verticalCenter

            // Bigger typed text. TextField's placeholderText shares
            // font with the input, so a smaller-font placeholder is
            // rendered separately below (so the long hint string still
            // fits without growing the input glyph size).
            font.pointSize: Tokens.font.body.large.pointSize ?? 18
            verticalAlignment: TextInput.AlignVCenter
            topPadding: 0
            bottomPadding: 0

            // Ink on the parchment pill — the scheme-driven default is
            // cream-ish on light wallpapers and vanishes against parchment
            color: Woodland.inkPrimary

            placeholderText: ""

            // Custom placeholder — smaller font so the full hint
            // string fits, only visible when the field is empty.
            StyledText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text.length === 0
                // Elided and kept short: at full length the hint text ran
                // past the pill and clipped mid-word.
                text: qsTr("Search apps, recents, roam, bookmarks, clipboard, emoji…    > actions    ? web search")
                color: Woodland.inkSecondary
                font.pointSize: Tokens.font.body.small.pointSize
                elide: Text.ElideRight
            }

            onAccepted: {
                if (root.isWebSearch(search.text)) {
                    root.runWebSearch(root.webSearchQuery(search.text));
                    return;
                }
                if (root.inActions || root.kindMenuOpen) {
                    actions.activateTop();
                    if (root.kindMenuOpen) root.closeKindMenu();
                    return;
                }
                const node = graph.topMatch();
                if (!node) return;
                // Pressed Enter on an elevated (filtered-out) neighbour:
                // promote its source into the active scope instead of
                // firing the node's onClicked. The node was already
                // selected via arrow-keys; this turns it into a match.
                if (root.scope && !graph.currentIsMatch()) {
                    const kw = root.kindToScopeKw[graph.currentPickKind()];
                    if (kw) {
                        const t = search.text;
                        const marker = `${root.prefix}${kw} `;
                        if (t.indexOf(marker) < 0) {
                            search.text = (t.endsWith(" ") ? t : (t + " ")) + marker;
                        }
                        return;
                    }
                }
                node.onClicked(root.visibilities);
            }

            // Ctrl+Enter: web-search the current query regardless of
            // matches / scope / actions overlay state. Matches the URL
            // bar convention so it's instantly familiar.
            Keys.onPressed: ev => {
                if ((ev.modifiers & Qt.AltModifier) && ev.key === Qt.Key_Left) {
                    graph.navigateBack();
                    ev.accepted = true;
                    return;
                }
                if (root.atSky && !root.inActions && !root.kindMenuOpen
                        && (ev.key === Qt.Key_BracketLeft || ev.key === Qt.Key_BracketRight)
                        && (search.text.length === 0 || (ev.modifiers & Qt.AltModifier))) {
                    quickGrid.page = (quickGrid.page + (ev.key === Qt.Key_BracketRight ? 1 : -1) + quickGrid.pages) % quickGrid.pages;
                    ev.accepted = true;
                    return;
                }

                // Ctrl+Up / Ctrl+Down fly the camera between the sky and the
                // tree. Checked before everything else because bare Up/Down
                // are graph navigation and Keys.onUpPressed does not see
                // modifiers — without accepting here it would nav as well.
                if (ev.modifiers & Qt.ControlModifier) {
                    if (ev.key === Qt.Key_Down) {
                        root.descend();
                        ev.accepted = true;
                        return;
                    }
                    if (ev.key === Qt.Key_Up) {
                        root.ascend();
                        ev.accepted = true;
                        return;
                    }
                }
                const directions = ({});
                directions[Qt.Key_Left] = [-1, 0];
                directions[Qt.Key_Right] = [1, 0];
                directions[Qt.Key_Up] = [0, -1];
                directions[Qt.Key_Down] = [0, 1];
                const arrow = directions[ev.key];
                if (arrow && root.atSky && !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))) {
                    if (root.inActions || root.kindMenuOpen) {
                        if (ev.key === Qt.Key_Up) actions.list?.decrementCurrentIndex?.();
                        else if (ev.key === Qt.Key_Down) actions.list?.incrementCurrentIndex?.();
                        else return;
                    } else graph.navDirection(arrow[0], arrow[1]);
                    ev.accepted = true;
                    return;
                }
                // Vim navigation, opt-in. Ctrl-prefixed because the field is a
                // text input, and h/j/k/l are free — the compass grid claims
                // Ctrl+[arstgmne] and nothing else.
                if (GlobalConfig.launcher.vimKeybinds && (ev.modifiers & Qt.ControlModifier)
                        && !root.inActions && !root.kindMenuOpen && root.panP > 0.5) {
                    const vim = ({});
                    vim[Qt.Key_H] = [-1, 0];
                    vim[Qt.Key_L] = [1, 0];
                    vim[Qt.Key_K] = [0, -1];
                    vim[Qt.Key_J] = [0, 1];
                    const dir = vim[ev.key];
                    if (dir) {
                        graph.navDirection(dir[0], dir[1]);
                        ev.accepted = true;
                        return;
                    }
                }
                // Typing means the user came here to search, not to watch the
                // opening shot. Printable text only: a bare Ctrl press (on the
                // way to Ctrl+Down) must not count as "get me to the sky".
                if (ev.text.length > 0 && ev.text.charCodeAt(0) >= 0x20)
                    root.skipToSky();
                if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)
                    && (ev.modifiers & Qt.ControlModifier)) {
                    root.runWebSearch(root.webSearchQuery(search.text));
                    ev.accepted = true;
                    return;
                }
                // Tab completion runs before inActions check: a partial `>key`
                // sets inActions=true until the keyword resolves, so we must
                // intercept Tab unconditionally here.
                if (ev.key === Qt.Key_Tab && !(ev.modifiers & Qt.ShiftModifier)
                        && !root.kindMenuOpen && root.tryTabComplete()) {
                    ev.accepted = true;
                    return;
                }
                // Tab / Shift+Tab: edge-following graph nav (not in overlays).
                if ((ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab)
                        && !root.inActions && !root.kindMenuOpen && root.atSky && graph.currentNode >= 0) {
                    const back = ev.key === Qt.Key_Backtab
                        || (ev.modifiers & Qt.ShiftModifier);
                    graph.cycleLinkedNeighbor(back ? -1 : 1);
                    ev.accepted = true;
                    return;
                }
                // Shift+Enter opens the per-kind action menu for the current pick.
                if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)
                    && (ev.modifiers & Qt.ShiftModifier)
                    && !root.inActions && graph.currentNode >= 0) {
                    root.openKindMenu();
                    ev.accepted = true;
                    return;
                }
                // Ctrl+[arstgmne] fires one of the eight surrounding compass
                // cells, in reading order — resolved through quickGrid, not
                // match order, so the letter always fires the cell the letter
                // is drawn on. Only intercepts while the grid is showing, so
                // standard Ctrl+A (select-all) etc. still work with no matches.
                if ((ev.modifiers & Qt.ControlModifier) && quickGrid.count > 0
                        && !root.inActions && !root.kindMenuOpen) {
                    const qkeys = [Qt.Key_A, Qt.Key_R, Qt.Key_S, Qt.Key_T,
                                   Qt.Key_G, Qt.Key_M, Qt.Key_N, Qt.Key_E];
                    const ni = quickGrid.nodeIndexForKey(qkeys.indexOf(ev.key));
                    if (ni >= 0 && ni < graph.nodes.length) {
                        graph.selectNode(ni);
                        ev.accepted = true;
                        return;
                    }
                }
            }

            // Escape closes, always — no stepping back through the kind menu or
            // out of the tree into the sky first. One key, one meaning.
            Keys.onEscapePressed: root.dismiss()

            // Wrapper keeps Content mounted across opens, so
            // Component.onCompleted only fires once. Re-grab focus on every
            // open or the field is silently unfocused after the first close.
            // The reveal belongs to an OPEN, not to a camera move: ascend() and
            // descend() flip both visibility flags, so an unguarded growIn()
            // restarts the whole reveal — and keeps the frame animation alive
            // for another ~900ms — on every fly between the sky and the tree.
            property bool grewThisOpen

            function syncOpen(): void {
                if (!(root.visibilities.launcher || root.visibilities.dashboard)) {
                    search.text = "";
                    graph.pivotKind = "";
                    search.grewThisOpen = false;
                    return;
                }
                search.consumePending();
                search.forceActiveFocus();
                if (!search.grewThisOpen) {
                    search.grewThisOpen = true;
                    graph.growIn();
                }
            }

            function consumePending(): void {
                const q = ShellState.pendingLauncherQuery;
                if (!q)
                    return;
                ShellState.pendingLauncherQuery = "";
                search.text = q;
                search.cursorPosition = search.text.length;
            }

            Component.onCompleted: forceActiveFocus()

            Connections {
                // Both flags, because either one opens this surface: entering at
                // the tree (dashboard) still has to hand the field focus, or
                // Ctrl+Up and type-to-search are dead down there.
                function onLauncherChanged(): void {
                    Qt.callLater(search.syncOpen);
                }

                function onDashboardChanged(): void {
                    Qt.callLater(search.syncOpen);
                }

                target: root.visibilities
            }

            Connections {
                // The IPC can land while the launcher is already up, in which
                // case no visibility flag changes and syncOpen never runs.
                function onPendingLauncherQueryChanged(): void {
                    if (root.surfaceOpen)
                        search.consumePending();
                }

                target: ShellState
            }
        }

        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.large

            width: search.text ? implicitWidth : implicitWidth / 2
            opacity: search.text ? (mouse.pressed ? 0.7 : (mouse.containsMouse ? 0.8 : 1)) : 0

            text: "close"
            color: Colours.palette.m3onSurfaceVariant

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: search.text ? Qt.PointingHandCursor : undefined

                onClicked: search.text = ""
            }

            Behavior on width {
                Anim {
                    type: Anim.StandardSmall
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardSmall
                }
            }
        }
    }

    // Down at the tree, a click on bare scenery moves the camera — but WHERE
    // depends on where you clicked, because the two things you might want are
    // opposites: the sky above the canopy takes you up to the graph, the ground
    // below the roots closes the surface.
    //
    // The bands deliberately do not meet. The middle of the frame is the tree,
    // and a click on bare room there should do nothing rather than guess.
    //
    // Both hit targets sit UNDER the tree host (z 3) so orbs and root limbs get
    // their own clicks first; the glow and the chevrons sit OVER it (z 4) or the
    // tree's own room paints across them. Without the affordances the only way
    // up was an undiscoverable Ctrl+Up, since the chrome that would hint at it
    // is invisible down here.
    // PARKED at an end of the pan, not merely pointing somewhere near it. Both
    // bands and their affordances key off this rather than a `panP < 0.5`
    // half-plane: during the opening shot's 340ms hold panP is ALREADY 0, so a
    // pointer that happened to be sitting in a band lit it for a third of a
    // second and then lost it to the climb — a flash, immediately before the
    // pan. Nothing under the camera is interactive while the camera is moving.
    readonly property bool atTree: root.surfaceOpen && root.panP < 0.02 && !dwell.running
    readonly property bool atSky: root.surfaceOpen && root.panP > 0.98

    MouseArea {
        id: ascendBand

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.round(parent.height * 0.42)
        z: 2
        enabled: root.atTree
        visible: enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.ascend()
    }

    MouseArea {
        id: groundBand

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(parent.height * 0.16)
        z: 2
        enabled: root.atTree
        visible: enabled
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()
    }

    Item {
        anchors.fill: parent
        z: 4
        visible: root.atTree

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: ascendBand.height
            opacity: ascendBand.containsMouse ? 1 : 0

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(Woodland.parchment, 0.10)
                }

                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.spacing.large

            text: "keyboard_double_arrow_up"
            color: Woodland.parchment
            opacity: ascendBand.containsMouse ? 0.85 : 0
            fontStyle: Tokens.font.icon.small

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: groundBand.height
            opacity: closeTree.containsMouse ? 1 : 0

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    position: 0.0
                    color: "transparent"
                }

                GradientStop {
                    position: 1.0
                    color: Qt.alpha(Woodland.parchment, 0.10)
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }

        MouseArea {
            id: closeTree
            objectName: "treeClose"

            // Compact surfaces leave too little space between the inner root actions.
            readonly property bool compact: root.width < 800 || root.height < 500
            x: compact ? parent.width - width - Tokens.spacing.large : (parent.width - width) / 2
            y: compact ? Tokens.spacing.large : parent.height - height - Tokens.spacing.large
            width: 44
            height: 44
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismiss()

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(Woodland.barkEdge, closeTree.containsMouse ? 0.85 : 0.4)
                border.width: 1
                border.color: Qt.alpha(Woodland.parchment, closeTree.containsMouse ? 0.3 : 0.12)
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                color: Woodland.parchment
                opacity: closeTree.containsMouse ? 0.85 : 0.5
                fontStyle: Tokens.font.icon.small

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }
        }
    }
}
