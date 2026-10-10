pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell
import Burl
import Burl.Config
import Burl.Sim
import "GraphDrift.js" as GraphDrift
import "GraphActions.js" as GraphActions
import "SearchRanking.js" as SearchRanking
import qs.components
import qs.components.images
import qs.services
import qs.modules.launcher.services

// Spatial replacement for the launcher list. Roam nodes + edges are drawn
// alongside floating anchor nodes for apps / recents / bookmarks /
// wallpapers. As the user types, matched nodes are pulled toward the
// center and scaled up; non-matches dim and shrink.
//
// The force-directed physics live in a C++ ForceSim (see
// files/burl/plugin/src/Burl/Sim/). QML owns the *semantic*
// node list (labels, colours, click callbacks) and reads positions /
// radii back from the sim each tick via Q_INVOKABLE accessors. This
// keeps the JS event loop free for input handling and lets the node
// count scale.
Item {
    id: root

    required property ScreenState visibilities
    property string query: ""
    // Per-segment scope filter. Each element is { kind, q }. Empty list
    // means "no scope" — `query` is used as a single global search.
    // When non-empty, each node is scored against the segment whose
    // kind matches it (max if multiple); kinds with no segment are out.
    property var scopeSegments: []

    // Clipboard entries are only materialised as nodes under an explicit
    // `>clip` scope. Two hundred unlinked text nodes in the idle sky would
    // swamp the structure the graph exists to show, and cost the sim a
    // couple of hundred bodies to relax for nothing.
    readonly property bool clipScoped: (scopeSegments ?? []).some(s => s.kind === "clip") || pivotKind === "clip"

    onClipScopedChanged: {
        if (clipScoped)
            Clipboard.refresh();
        requestRebuild();
    }

    // Same gating as the clipboard, and for a harder reason: the emoji table is
    // ~12k entries, so only the current query's matches ever become nodes.
    readonly property bool emojiScoped: (scopeSegments ?? []).some(s => s.kind === "emoji") || pivotKind === "emoji"

    onEmojiScopedChanged: {
        if (emojiScoped)
            Emoji.search(root.emojiQueries);
        requestRebuild();
    }

    readonly property var emojiQueries: (scopeSegments ?? []).filter(s => s.kind === "emoji").map(s => s.q ?? "")

    onEmojiQueriesChanged: if (emojiScoped)
        Emoji.search(root.emojiQueries)
    // External pause signal — used by Content.qml to halt the sim while
    // the user is in the actions overlay so the search bar stays
    // responsive (we share a single JS event loop with input).
    property bool paused: false
    property bool transitioning: false
    property bool rebuildPending: false
    property bool edgesPending: false
    property bool resizePending: false
    // Keep the first hidden preload warm so opening never starts a cold layout.
    readonly property bool updatesDeferred: transitioning || (paused && layoutReady)
    onUpdatesDeferredChanged: {
        if (updatesDeferred) return;
        if (rebuildPending || edgesPending) rebuildTimer.restart();
        if (resizePending) resizeTimer.restart();
    }

    function requestRebuild(): void {
        rebuildPending = true;
        if (!updatesDeferred) rebuildTimer.restart();
    }

    function requestEdges(): void {
        edgesPending = true;
        if (!updatesDeferred) rebuildTimer.restart();
    }

    function flushSources(): void {
        if (updatesDeferred) return;
        if (rebuildPending) {
            rebuildPending = false;
            rebuild();
        }
        if (edgesPending) {
            edgesPending = false;
            edgeLayer.refresh();
        }
    }
    // View transform driven by mouse wheel zoom + drag-empty pan AND
    // programmatic fits (rescore / cycleMatch). Behavior animates the
    // tween so the camera glides between picks instead of snapping.
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    // Explicit animations (not Behavior) so user wheel/drag inputs hit
    // the property directly without going through the auto-fit ease —
    // wheel is responsive, fitCamera() still glides.
    // All three camera axes share duration + easing so the on-screen
    // projection (pan + zoom) glides on a straight line. Mismatched
    // durations made the camera bow off-axis because pan finished
    // while zoom was still mid-curve.
    NumberAnimation { id: zoomAnim; target: root; property: "zoom"; duration: 420; easing.type: Easing.OutCubic }
    NumberAnimation { id: panXAnim; target: root; property: "panX"; duration: 420; easing.type: Easing.OutCubic }
    NumberAnimation { id: panYAnim; target: root; property: "panY"; duration: 420; easing.type: Easing.OutCubic }

    // Share one reveal value across edge bands and labels.
    GrowIn {
        id: growAnim
    }

    // Called by Content.qml when the launcher opens, so the graph grows in
    // rather than snapping straight into view.
    function growIn(): void {
        growAnim.grow();
    }

    onScopeSegmentsChanged: filterTimer.restart();

    // Coalesce keystrokes before reheating the full graph.
    function _applyFilter(): void {
        rescore();
        sim.reheat(0.65);
        fitCamera();
        edgeLayer.refresh();
    }
    Timer {
        id: filterTimer
        interval: 80
        repeat: false
        onTriggered: root._applyFilter()
    }

    // World <-> screen coordinate helpers.
    function _w2sX(x: real): real { return x * zoom + panX; }
    function _w2sY(y: real): real { return y * zoom + panY; }
    function _s2wX(x: real): real { return (x - panX) / zoom; }
    function _s2wY(y: real): real { return (y - panY) / zoom; }

    // Tunables.
    readonly property int maxApps: 100
    readonly property int maxRecents: 60
    readonly property int maxWallpapers: Math.max(1, Math.min(30, Config.launcher.maxWallpapers))
    onMaxWallpapersChanged: requestRebuild()
    // Cap rendered nodes separately from source fetch limits to bound frame cost.
    readonly property int maxRoam: 600
    readonly property int maxProjects: 80
    readonly property int maxMail: 60
    readonly property int maxEvents: 40
    readonly property int maxWebBookmarks: 160
    readonly property int maxWebHistory: 100
    readonly property int maxWebTabs: 80
    readonly property int maxSpotify: 50
    readonly property real baseRadius: 5
    readonly property real maxRadius: 38
    readonly property real attractMatchK: 0.07  // query-match pull
    readonly property real attractRestK: 0.03   // non-match return
    // The preview pick keeps a disc on the left and grows sideways
    // into a pill that holds the label + description. The sim's
    // "current radius" is the disc; the pill body extension is pure
    // QML chrome with its own opacity-driven fade-in for a smoother
    // morph than the binary visible toggle.
    readonly property real previewRadius: maxRadius * 2.6
    // Width of the pill chrome that extends right from the preview
    // disc (text column + padding). Used for fitCamera so the entire
    // pill stays on-screen.
    readonly property real previewPillWidth: 360
    // Match-ring geometry — shared by retargetMatches() (target seeds)
    // and fitCamera() (zoom fit) so they never drift apart. ringMinR is
    // the gap from the centred pick to the ring; ringPerNode is the
    // arc-length budget per ring node. Generous for breathing room.
    readonly property real ringMinR: previewRadius * 2.8
    readonly property real ringPerNode: maxRadius * 3.8
    // Canopy shape: the compass ring and match ring stretch wider than they
    // are tall (like a tree canopy) instead of sitting on a perfect circle.
    // Applied as a per-axis multiplier on the *offset* from centre, so it
    // reshapes the layout without touching the radii/attract strengths.
    readonly property real canopyX: 1.15
    readonly property real canopyY: 0.72

    // Deterministic per-node pseudo-random value in [-1, 1], keyed on index
    // only (not rebuilt per rescore/tick) so a node's jittered size/tone is
    // stable across the graph's lifetime — the graph reads as grown, not
    // tiled, without ever twitching from rebuild to rebuild. Same magic
    // constant as the existing ring-angle jitter above, for consistency.
    function _jitter(i: int): real {
        return Math.sin(i * 12.9898);
    }

    // i is the node index; every call site passes it (QML typed functions
    // don't support default parameter values). There is deliberately NO
    // "skip the jitter" escape hatch: two call sites returning different
    // radii for the same node is how node sizes start popping between
    // rebuild and retarget.
    function baseRadiusFor(kind: string, i: int): real {
        // Apps and wallpapers read as primary entry points — give them
        // more weight at rest so their image content is legible.
        let r = baseRadius;
        if (kind === "app") r = baseRadius * 1.6;
        else if (kind === "wallpaper") r = baseRadius * 2.0;
        // Hubs read as hubs. Without this every node is the same speck and
        // the graph looks like scattered debris rather than a structure.
        // Logarithmic and capped: one 200-link roam node must not become a
        // planet the sim then has to shove everything else around.
        const deg = root.nodeDegree[i] ?? 0;
        r *= 1 + Math.min(1.4, Math.log2(1 + deg) * 0.28);
        // ±12% identity-keyed jitter so same-kind nodes don't sit at one
        // mechanical size.
        return r * (1.0 + _jitter(i) * 0.12);
    }

    // [{id, kind, label, iconName?, imagePath?, color, onColor, glyph, onClicked}]
    property var nodes: []
    // id -> nodes index (for edge lookup by roam id).
    property var indexById: ({})
    // Indices into nodes[] of kind=app — drives the IconImage overlay.
    property var appIndices: []
    // Indices into nodes[] of kind=wallpaper — drives the thumbnail overlay.
    property var wallpaperIndices: []
    // Indices of Spotify nodes that have a remote cover image URL.
    property var spotifyImageIndices: []
    // Cover URLs that failed to load/decode. Rebuilds recreate the
    // cover delegates, and Qt only caches successful decodes — without
    // this a bad URL is re-fetched and re-logged on every rebuild.
    property var failedImageUrls: ({})
    // Indices of currently-matched nodes (search), in best-first order.
    property var matchIndices: []
    // Top-N match indices for label display — avoids a wall of overlapping
    // labels when many nodes match. matchIndices is best-first so slice(0,N)
    // gives the highest-scoring ones.
    readonly property var topMatchIndices: matchIndices.slice(0, 12)
    // Per-node match score, parallel to nodes[]. Used by node and edge styling.
    property var nodeScores: []
    property int currentNode: -1
    property var navSlots: [-1, -1, -1, -1]
    readonly property var _navSlotDirs: [[0, -1], [1, 0], [0, 1], [-1, 0]]   // N, E, S, W
    // Pivot kind: when the user clicks a node whose kind isn't part
    // of the active scope, that kind becomes transiently "active"
    // (as if `>kind` were appended to the search). Clicking a node
    // of a different kind replaces it; clicking back into the typed
    // scope clears it. Empty string = no pivot.
    property string pivotKind: ""
    onPivotKindChanged: rescore()
    // Per-node BFS depth from the nearest match (0 = match, 1..3 =
    // elevated background, Infinity = unrelated). Drives label
    // visibility and opacity tiering.
    property var depthToMatch: []
    // How far out from a match we treat nodes as "related" (elevated
    // appearance). Beyond this they dim like
    // unrelated background.
    readonly property int elevationDepth: 3
    // Position within matchIndices selected via arrow keys.
    property int currentMatchIndex: 0
    property int hoverIndex: -1
    // One snapshot notification updates all delegates at the render cadence.
    property var snap: []
    property var _curSnap: []    // authoritative post-step positions

    property bool snapshotDirty: true
    function _refresh(): void {
        snapshotDirty = true;
    }

    // Fixed-rate glide of the current preview pick to the viewport
    // centre, run once per physics step. The sim's own target
    // attraction is alpha-scaled, so as the cluster cools the pull on
    // the pick fades and the last stretch to centre crawls (the "takes
    // a long time to centre" feel). This lerp is independent of alpha —
    // it closes a fixed fraction of the remaining gap each step, so the
    // pick reaches centre in ~0.2s regardless of how settled the rest
    // of the graph is. The pick is isolated (no repulsion) so nothing
    // fights it; the alpha-scaled attraction stays as a gentle backstop.
    readonly property real _centerLerp: 0.22
    function _centerPreview(): void {
        const cn = currentNode;
        if (cn < 0 || browsing) return;
        const filtering = (query ?? "").trim() !== "" || scopeSegments.length > 0;
        if (!filtering) return;
        const cx = width / 2;
        const cy = height / 2;
        const px = sim.x(cn);
        const py = sim.y(cn);
        const dx = cx - px;
        const dy = cy - py;
        if (dx * dx + dy * dy <= 1.0) return;   // already centred
        sim.setPosition(cn, px + dx * _centerLerp, py + dy * _centerLerp);
        _refresh();   // re-snapshot so the render below sees the nudge
    }
    // Tiny accessors with a graceful fallback before the first snapshot.
    function _px(i: int): real { return snap[i * 3] ?? sim.x(i); }
    function _py(i: int): real { return snap[i * 3 + 1] ?? sim.y(i); }
    function _nx(i: int): real { return _px(i) + idleOffset(i).x; }
    function _ny(i: int): real { return _py(i) + idleOffset(i).y; }
    function _nr(i: int): real { const v = snap[i * 3 + 2]; return browsing ? (i === currentNode ? selectedRadius : Math.min(v ?? baseRadius, maxRadius)) : (v === undefined ? sim.radius(i) : v); }


    Component.onCompleted: {
        // Reading any WebSources property here forces the QML singleton
        // to instantiate now (otherwise it lazy-loads only when the
        // bookmarksChanged Connections fires, which never triggers if
        // it was never reached) — same gotcha as IdleInhibitor.
        void WebSources.placesDb;
        rebuild();
    }

    onWidthChanged: { resizePending = true; resizeTimer.restart(); }
    onHeightChanged: { resizePending = true; resizeTimer.restart(); }
    onQueryChanged: filterTimer.restart();

    Timer {
        id: resizeTimer
        interval: 150
        onTriggered: {
            if (root.updatesDeferred) return;
            root.resizePending = false;
            if (root.layoutReady && !root.browsing)
                root.retargetMatches();
            else if (!root.layoutReady)
                root.relayout();
        }
    }

    // Source scans emit bursts; rebuild once after they settle.
    Timer {
        id: rebuildTimer
        interval: 120
        repeat: false
        onTriggered: root.flushSources()
    }

    Connections {
        target: EmacsSources
        function onRoamNodesChanged() { root.requestRebuild(); }
        function onRecentsChanged() { root.requestRebuild(); }
        function onBookmarksChanged() { root.requestRebuild(); }
        function onProjectsChanged() { root.requestRebuild(); }
        function onRoamLinksChanged() { root.requestEdges(); }
    }

    Connections {
        target: MailSources
        function onMessagesChanged() { root.requestRebuild(); }
    }

    Connections {
        target: CalendarSources
        function onEventsChanged() { root.requestRebuild(); }
    }

    Connections {
        target: Apps
        function onListChanged() { root.requestRebuild(); }
    }

    Connections {
        target: Clipboard
        function onEntriesChanged() { root.requestRebuild(); }
    }

    Connections {
        target: Emoji
        function onMatchesChanged() { root.requestRebuild(); }
    }

    Connections {
        target: Wallpapers
        function onListChanged() { root.requestRebuild(); }
    }

    Connections {
        target: WebSources
        function onBookmarksChanged() { root.requestRebuild(); }
        function onHistoryChanged() { root.requestRebuild(); }
        function onTabsChanged() { root.requestRebuild(); }
    }

    Connections {
        target: SpotifySources
        function onPlaylistsChanged() { root.requestRebuild(); }
        function onRecentsChanged() { root.requestRebuild(); }
    }

    // Hyprland client + monitor list changes trigger a rebuild so
    // new windows / closed apps / monitor hotplug show up.
    Connections {
        target: Hypr.toplevels
        function onValuesChanged() { root.requestRebuild(); }
    }
    Connections {
        target: Hypr.monitors
        function onValuesChanged() { root.requestRebuild(); }
    }
    Connections {
        target: Hypr.workspaces
        function onValuesChanged() { root.requestRebuild(); }
    }

    // The C++ force-directed sim. Owns positions / velocities / radii;
    // ticks itself on an internal 24ms QTimer. We push graph via
    // setGraph() in relayout() and per-node targets via setTarget() in
    ForceSim {
        id: sim

        width: root.width
        height: root.height
        paused: root.transitioning || (root.paused && !root.preparing)
        // Stronger repulsion + longer springs spread the cluster out as
        // it settles (these are alpha-scaled, so they shape the layout
        // during motion); collidePadding is the hard minimum gap that
        // persists at rest. Together they give nodes more breathing room.
        repulsion: 2000
        springLength: 130
        collidePadding: 12
        // Cool-down rate per step (default 0.035). Lower = the cluster
        // keeps gently organising for longer after each reheat instead
        // of freezing quickly — a longer, calmer background settle.
        // ~0.022 roughly doubles the visible settle time. The preview
        // pick no longer depends on this (see _centerPreview), so a
        // slower cool-down doesn't slow centring.
        alphaDecay: 0.022
        // Drive ticks from QML's FrameAnimation so cadence matches the
        // display refresh rate (60 / 120 / 240 Hz). The internal QTimer
        // path would run at fixed 24ms and drift relative to vsync.
        tickInternally: false

        onPositionsChanged: root._refresh()
        onRunningChanged: if (!running && !root.preparing) root.publishSnapshot()

    }

    // Separate physics and rendering rates keep settling independent of display refresh.
    property double _lastStep: 0     // wall-clock ms of the most recent physics step
    property double _lastRender: 0   // wall-clock ms of the most recent render bump
    readonly property int _stepIntervalMs: 8    // ~125Hz physics
    // Reduce rendering frequency when frame cost exceeds the display budget.
    readonly property var _renderTiers: [12, 24, 33]   // ~83Hz, ~42Hz, ~30Hz
    property int _renderTier: 0
    readonly property int _renderIntervalMs: _renderTiers[_renderTier]
    property double _lastRetune: 0
    // Dead band 15-22ms is "holding 60Hz" — a healthy 60Hz panel sits at
    // ~16.7 and never retunes. Outside it, move one tier per second so the
    // load we just shed doesn't immediately promote us back and oscillate.
    function _retuneRenderGate(now: double): void {
        if (now - _lastRetune < 1000)
            return;
        const ms = frameDriver.smoothFrameTime * 1000;
        if (ms <= 0)
            return;
        const was = _renderTier;
        if (ms > 22)
            _renderTier = Math.min(_renderTier + 1, _renderTiers.length - 1);
        else if (ms < 15)
            _renderTier = Math.max(_renderTier - 1, 0);
        if (_renderTier !== was)
            _lastRetune = now;
    }
    // Bound catch-up work after a stalled frame to avoid a sustained backlog.
    readonly property int _maxCatchUpSteps: 4
    readonly property bool ambientDrift: Ambience.sway && !GameMode.enabled

    property real driftSeconds: 0
    readonly property real driftStrength: ambientDrift ? 1 : 0
    property point selectedOffset: Qt.point(0, 0)
    readonly property int orbitCount: 17
    property int orbitRevision: 0
    function attachOrbits(): void { orbitRevision++; }
    property real selectedRadius: 0
    NumberAnimation { id: selectionGrow; target: root; property: "selectedRadius"; duration: Ambience.grow ? 240 : 0; easing.type: Easing.OutCubic }
    onCurrentNodeChanged: {
        selectedOffset = GraphDrift.offset(driftSeconds, driftStrength, currentNode % orbitCount);
        selectionGrow.stop();
        selectedRadius = snap[currentNode * 3 + 2] ?? baseRadius;
        selectionGrow.to = previewRadius;
        selectionGrow.start();
    }

    function idleOffset(i: int): point {
        return i === currentNode ? selectedOffset : GraphDrift.offset(driftSeconds, driftStrength, i % orbitCount);
    }

    function publishSnapshot(): void {
        if (snapshotDirty) {
            _curSnap = sim.snapshot();
            snapshotDirty = false;
        }
        snap = _curSnap;
        edgeLayer.refresh();
    }

    FrameAnimation {
        id: frameDriver

        running: (sim.running || root.ambientDrift || root.driftStrength > 0.001) && !root.paused && !root.preparing
        onTriggered: {
            const now = Date.now();
            root._retuneRenderGate(now);
            const dt = Math.min(frameTime, 0.05);
            if (root.ambientDrift) root.driftSeconds += dt;
            const due = Math.floor((now - root._lastStep) / root._stepIntervalMs);
            if (due > 0) {
                const steps = Math.min(due, root._maxCatchUpSteps);
                // Advance the clock by what we actually ran so the phase
                // survives; on a capped burst drop the backlog instead.
                root._lastStep = steps < due
                    ? now
                    : root._lastStep + steps * root._stepIntervalMs;
                if (sim.running) {
                    for (let s = 0; s < steps; ++s)
                        sim.step();
                    root._centerPreview();
                }
            }
            // Publishing at display cadence overwhelms the GUI thread.
            if (root.snapshotDirty && now - root._lastRender >= root._renderIntervalMs) {
                root._lastRender = now;
                root.publishSnapshot();
            }
        }
    }

    function colorFor(kind: string): color {
        switch (kind) {
        case "app":         return Colours.palette.m3primary;
        case "recent":      return Colours.palette.m3secondary;
        case "bookmark":    return Colours.palette.m3tertiary;
        case "wallpaper":   return Colours.palette.m3surfaceContainerHighest;
        case "webBookmark": return Colours.palette.sky ?? Colours.palette.m3primaryContainer;
        case "webFolder":   return Colours.palette.lavender ?? Colours.palette.m3tertiaryContainer;
        case "webHistory":  return Colours.palette.teal ?? Colours.palette.m3secondaryContainer;
        case "webTab":      return Colours.palette.green ?? Colours.palette.m3primary;
        case "spotifyPlaylist": return Colours.palette.green ?? Colours.palette.m3primaryContainer;
        case "spotifyTrack":    return Colours.palette.green ?? Colours.palette.m3primaryContainer;
        case "client":      return Colours.palette.peach ?? Colours.palette.m3primaryContainer;
        case "monitor":     return Colours.palette.maroon ?? Colours.palette.m3tertiaryContainer;
        case "workspace":   return Colours.palette.yellow ?? Colours.palette.m3primaryContainer;
        case "category":    return Colours.palette.mauve ?? Colours.palette.m3secondaryContainer;
        case "project":     return Colours.palette.flamingo ?? Colours.palette.m3primaryContainer;
        case "mail":        return Colours.palette.blue ?? Colours.palette.m3secondaryContainer;
        case "event":       return Colours.palette.peach ?? Colours.palette.m3tertiaryContainer;
        case "clip":        return Colours.palette.rosewater ?? Colours.palette.m3surfaceVariant;
        case "emoji":       return Colours.palette.yellow ?? Colours.palette.m3tertiaryContainer;
        default:            return Colours.palette.lavender ?? Colours.palette.m3surfaceTint;
        }
    }

    function glyphFor(kind: string): string {
        switch (kind) {
        case "recent":      return "description";
        case "bookmark":    return "bookmark";
        case "wallpaper":   return "image";
        case "webBookmark": return "language";
        case "webFolder":   return "folder";
        case "webHistory":  return "history";
        case "webTab":      return "tab";
        case "spotifyPlaylist": return "queue_music";
        case "spotifyTrack":    return "music_note";
        case "client":      return "open_in_new";
        case "monitor":     return "monitor";
        case "workspace":   return "grid_view";
        case "category":    return "category";
        case "project":     return "folder_special";
        case "mail":        return "mail";
        case "event":       return "event";
        case "clip":        return "content_paste";
        case "emoji":       return "mood";
        default:            return "hub"; // roam
        }
    }

    function onColorFor(kind: string): color {
        switch (kind) {
        case "app":         return Colours.palette.m3onPrimary;
        case "recent":      return Colours.palette.m3onSecondary;
        case "bookmark":    return Colours.palette.m3onTertiary;
        case "wallpaper":   return Colours.palette.m3onSurface;
        case "webBookmark": return Colours.palette.m3onPrimaryContainer;
        case "webFolder":   return Colours.palette.m3onTertiaryContainer;
        case "webHistory":  return Colours.palette.m3onSecondaryContainer;
        case "webTab":      return Colours.palette.m3onPrimary;
        case "spotifyPlaylist": return Colours.palette.m3onPrimaryContainer;
        case "spotifyTrack":    return Colours.palette.m3onPrimaryContainer;
        case "client":      return Colours.palette.m3onPrimaryContainer;
        case "monitor":     return Colours.palette.m3onTertiaryContainer;
        case "workspace":   return Colours.palette.m3onPrimaryContainer;
        case "category":    return Colours.palette.m3onSecondaryContainer;
        case "project":     return Colours.palette.m3onPrimaryContainer;
        case "mail":        return Colours.palette.m3onSecondaryContainer;
        case "clip":        return Colours.palette.m3onSurfaceVariant;
        case "emoji":       return Colours.palette.m3onTertiaryContainer;
        case "event":       return Colours.palette.m3onTertiaryContainer;
        default:            return Colours.palette.m3surface;
        }
    }

    function actionContext(): var {
        return {
            emacsEnabled: Quickshell.env("BURL_EMACS_INTEGRATION") === "1",
            agendaFile: CalendarSources.agendaFile,
            execute: command => Quickshell.execDetached(command),
            launch: entry => Apps.launch(entry),
            dispatch: command => Hypr.dispatch(command)
        };
    }

    function activateSource(kind: string, source: var, visibility: var): bool {
        const context = actionContext();
        return GraphActions.execute(GraphActions.primary(kind, source, context), context, visibility);
    }

    function kindActions(node: var): var {
        const context = actionContext();
        return GraphActions.secondary(node, context).map(action => ({
            name: action.name,
            icon: action.icon,
            desc: action.desc,
            activate: (search, visibility) => GraphActions.execute(action, context, visibility)
        }));
    }

    function rebuild(): void {
        const selectionId = nodes[currentNode]?.id;
        const historyIds = navigationHistory.map(i => nodes[i]?.id);
        const wasBrowsing = browsing;
        const out = [];
        const idx = {};

        // Apps — Apps.list is sorted by frequency in AppDb.
        const apps = Apps.list ?? [];
        const appIdx = [];
        for (let i = 0; i < Math.min(apps.length, maxApps); ++i) {
            const e = apps[i];
            const entry = e.entry ?? e;
            const id = `app:${entry?.id ?? i}`;
            out.push({
                id,
                kind: "app",
                label: entry?.name ?? `App ${i}`,
                searchMetadata: [e.genericName ?? "", e.keywords ?? "", e.comment ?? ""],
                iconName: entry?.icon ?? "",
                entry: entry,        // payload for kind-actions (new window)
                color: colorFor("app"),
                onColor: onColorFor("app"),
                glyph: glyphFor("app"),
                onClicked: vis => { Apps.launch(entry); vis.launcher = false; }
            });
            idx[id] = out.length - 1;
            appIdx.push(out.length - 1);
        }
        if (appIndices.length !== appIdx.length || appIndices.some((value, i) => value !== appIdx[i]))
            appIndices = appIdx;

        // App categories — one node per distinct primary category
        // (first token of the .desktop Categories field). Apps link to
        // their category in relayout() via the same hub-and-spoke
        // edges that group same-class clients.
        const catColor = colorFor("category");
        const catOnColor = onColorFor("category");
        const catGlyph = glyphFor("category");
        const seenCats = new Set();
        // categories can come back as either a string (the C++ wrapper
        // joins with " ") or a QStringList depending on the Apps
        // backend. Normalise to string.
        function catString(entry) {
            // categories may be a QStringList (renders as "a,b,c" via
            // String coercion) or a plain string. Normalise to a
            // space-separated string we can split.
            return String(entry?.categories ?? "").replace(/,/g, " ").trim();
        }
        for (let i = 0; i < Math.min(apps.length, maxApps); ++i) {
            const e = apps[i];
            const entry = e.entry ?? e;
            const cats = catString(entry);
            if (!cats) continue;
            const primary = cats.split(/[ ;,]+/).find(c => c.length > 0);
            if (!primary || seenCats.has(primary)) continue;
            seenCats.add(primary);
            const id = `category:${primary}`;
            out.push({
                id,
                kind: "category",
                label: primary,
                color: catColor,
                onColor: catOnColor,
                glyph: catGlyph,
                onClicked: vis => { vis.launcher = false; }
            });
            idx[id] = out.length - 1;
        }

        // Wallpapers — render the image itself as the node "icon".
        const walls = Wallpapers.list ?? [];
        const wpIdx = [];
        const wpColor = colorFor("wallpaper");
        const wpOnColor = onColorFor("wallpaper");
        const wpGlyph = glyphFor("wallpaper");
        for (let i = 0; i < Math.min(walls.length, maxWallpapers); ++i) {
            const w = walls[i];
            const id = `wallpaper:${w.path}`;
            out.push({
                id,
                kind: "wallpaper",
                label: w.name,
                tooltip: w.relativePath,
                imagePath: w.path,
                color: wpColor,
                onColor: wpOnColor,
                glyph: wpGlyph,
                onClicked: vis => { Wallpapers.setWallpaper(w.path); vis.launcher = false; }
            });
            idx[id] = out.length - 1;
            wpIdx.push(out.length - 1);
        }
        if (wallpaperIndices.length !== wpIdx.length || wallpaperIndices.some((value, i) => value !== wpIdx[i]))
            wallpaperIndices = wpIdx;

        // Recent files.
        const recents = EmacsSources.recents.slice(0, maxRecents);
        const recentColor = colorFor("recent");
        const recentOnColor = onColorFor("recent");
        const recentGlyph = glyphFor("recent");
        for (let i = 0; i < recents.length; ++i) {
            const r = recents[i];
            const id = `recent:${r.path}`;
            out.push({
                id,
                kind: "recent",
                source: r,
                label: r.name,
                tooltip: r.path,
                path: r.path,
                color: recentColor,
                onColor: recentOnColor,
                glyph: recentGlyph,
                onClicked: vis => root.activateSource("recent", r, vis)
            });
            idx[id] = out.length - 1;
        }

        // Bookmarks.
        const bookmarks = EmacsSources.bookmarks;
        const bmColor = colorFor("bookmark");
        const bmOnColor = onColorFor("bookmark");
        const bmGlyph = glyphFor("bookmark");
        for (const bm of bookmarks) {
            const id = `bookmark:${bm.name}`;
            out.push({
                id,
                kind: "bookmark",
                source: bm,
                label: bm.name,
                color: bmColor,
                onColor: bmOnColor,
                glyph: bmGlyph,
                onClicked: vis => root.activateSource("bookmark", bm, vis)
            });
            idx[id] = out.length - 1;
        }

        // Roam nodes — keyed by the org-roam id so edges resolve.
        const roamColor = colorFor("roam");
        const roamOnColor = onColorFor("roam");
        const roamGlyph = glyphFor("roam");
        for (const n of EmacsSources.roamNodes.slice(0, maxRoam)) {
            out.push({
                id: n.id,
                kind: "roam",
                source: n,
                label: n.title,
                tags: n.tags,
                color: roamColor,
                onColor: roamOnColor,
                glyph: roamGlyph,
                onClicked: vis => root.activateSource("roam", n, vis)
            });
            idx[n.id] = out.length - 1;
        }

        // Projects (project.el, SQLite-backed). Keyed by root so recent
        // files under that root can link to it.
        const projColor = colorFor("project");
        const projOnColor = onColorFor("project");
        const projGlyph = glyphFor("project");
        for (const p of (EmacsSources.projects ?? []).slice(0, maxProjects)) {
            const id = `project:${p.root}`;
            out.push({
                id,
                kind: "project",
                source: p,
                label: p.name,
                tooltip: p.root,
                path: p.root,
                color: projColor,
                onColor: projOnColor,
                glyph: projGlyph,
                onClicked: vis => root.activateSource("project", p, vis)
            });
            idx[id] = out.length - 1;
        }

        // Unread / flagged mail (mu index). Keyed by message-id so
        // same-sender messages can cluster via senderLinks.
        const mailColor = colorFor("mail");
        const mailOnColor = onColorFor("mail");
        const mailGlyph = glyphFor("mail");
        for (const msg of (MailSources.messages ?? []).slice(0, maxMail)) {
            const id = `mail:${msg.id}`;
            const subject = msg.subject || "(no subject)";
            out.push({
                id,
                kind: "mail",
                source: msg,
                label: subject,
                tooltip: `${msg.from} — ${subject}`,
                color: mailColor,
                onColor: mailOnColor,
                glyph: mailGlyph,
                onClicked: vis => root.activateSource("mail", msg, vis)
            });
            idx[id] = out.length - 1;
        }

        // Synthetic event IDs connect events through dayLinks.
        const evColor = colorFor("event");
        const evOnColor = onColorFor("event");
        const evGlyph = glyphFor("event");
        for (const ev of (CalendarSources.events ?? []).slice(0, maxEvents)) {
            const when = ev.allDay ? ev.day : `${ev.day} ${ev.time}`;
            out.push({
                id: ev.id,
                kind: "event",
                source: ev,
                label: ev.title,
                tooltip: when,
                color: evColor,
                onColor: evOnColor,
                glyph: evGlyph,
                onClicked: vis => root.activateSource("event", ev, vis)
            });
            idx[ev.id] = out.length - 1;
        }

        // Hyprland monitors. Each gets a node so clients can link to
        // their host monitor visually.
        const monColor = colorFor("monitor");
        const monOnColor = onColorFor("monitor");
        const monGlyph = glyphFor("monitor");
        for (const m of Hypr.monitors.values) {
            const o = m.lastIpcObject;
            // Prefer the typed property — lastIpcObject can be stale or
            // missing keys (same class as the toplevel staleness gotcha), and
            // an unnamed monitor produced id "monitor:undefined" plus an
            // undefined label. The id matters beyond the warning: the
            // workspace→monitor edges resolve by monitor *name*, so a broken
            // id silently dropped them.
            const name = m.name ?? o?.name;
            if (!name) continue;
            const id = `monitor:${name}`;
            out.push({
                id,
                kind: "monitor",
                label: name,
                tooltip: `${o?.width ?? m.width}x${o?.height ?? m.height}@${Math.round(o?.refreshRate ?? 0)}`,
                color: monColor,
                onColor: monOnColor,
                glyph: monGlyph,
                onClicked: vis => { vis.launcher = false; }
            });
            idx[id] = out.length - 1;
        }

        // Hyprland workspaces. Each becomes a node; clients on a
        // workspace edge to it, and the workspace edges to its monitor.
        const wsColor = colorFor("workspace");
        const wsOnColor = onColorFor("workspace");
        const wsGlyph = glyphFor("workspace");
        for (const w of Hypr.workspaces.values) {
            const o = w.lastIpcObject;
            if (!o) continue;
            const id = `workspace:${o.name ?? o.id}`;
            out.push({
                id,
                kind: "workspace",
                label: o.name ?? String(o.id),
                tooltip: `monitor: ${o.monitor ?? "?"}`,
                color: wsColor,
                onColor: wsOnColor,
                glyph: wsGlyph,
                workspaceMonitor: o.monitor,    // monitor *name*
                onClicked: () => ShellState.selectWorkspace([`workspace name:${o.name}`])
            });
            idx[id] = out.length - 1;
        }

        // Hyprland window clients (open apps). Each top-level window is
        // a node; clients sharing a class become a same-class cluster
        // via hub-and-spoke edges (built in relayout()), and each links
        // to the workspace it lives on (which in turn links to its
        // monitor — two hops cluster the whole layout per screen).
        const clientColor = colorFor("client");
        const clientOnColor = onColorFor("client");
        const clientGlyph = glyphFor("client");
        for (const t of Hypr.toplevels.values) {
            const o = t.lastIpcObject;
            if (!o || !o.address) continue;
            const id = `client:${o.address}`;
            const klass = o.class ?? "";
            const title = o.title ?? klass;
            out.push({
                id,
                kind: "client",
                label: title || klass || "(window)",
                tooltip: `${klass}  •  ws ${o.workspace?.name ?? "?"}`,
                color: clientColor,
                onColor: clientOnColor,
                glyph: clientGlyph,
                clientClass: klass,
                clientAddress: o.address,       // payload for focus-accent
                clientWorkspace: o.workspace?.name,
                clientMonitor: o.monitor,       // monitor *index*
                onClicked: vis => {
                    vis.launcher = false;
                    // Pass Lua directly — Hypr.dispatch passes
                    // 'hl.…' strings straight through to
                    // Hyprland.dispatch. The hyprland-next bindings
                    // expose hl.dsp.focus with a 'window' selector.
                    Hypr.dispatch(`hl.dsp.focus({ window = "address:${o.address}" })`);
                }
            });
            idx[id] = out.length - 1;
        }

        // Web bookmarks (folders + leaves) — folders get their own kind
        // so their colour reads as "container" vs leaf. Click opens URL
        // for leaves; folders are no-op (autocompletion fodder).
        const webBmFolderColor = colorFor("webFolder");
        const webBmFolderOnColor = onColorFor("webFolder");
        const webBmFolderGlyph = glyphFor("webFolder");
        const webBmColor = colorFor("webBookmark");
        const webBmOnColor = onColorFor("webBookmark");
        const webBmGlyph = glyphFor("webBookmark");
        for (const bm of (WebSources.bookmarks ?? []).slice(0, maxWebBookmarks)) {
            const isF = bm.isFolder === true;
            const url = bm.url ?? "";
            const id = `web:${bm.id}`;
            out.push({
                id,
                kind: isF ? "webFolder" : "webBookmark",
                label: bm.title || url || "(untitled)",
                tooltip: url,
                color: isF ? webBmFolderColor : webBmColor,
                onColor: isF ? webBmFolderOnColor : webBmOnColor,
                glyph: isF ? webBmFolderGlyph : webBmGlyph,
                onClicked: vis => {
                    if (isF || !url) return;
                    vis.launcher = false;
                    Quickshell.execDetached(["xdg-open", url]);
                }
            });
            idx[id] = out.length - 1;
        }

        // Web history — flat, no edges. Capped in C++ *and* here.
        const webHistColor = colorFor("webHistory");
        const webHistOnColor = onColorFor("webHistory");
        const webHistGlyph = glyphFor("webHistory");
        for (const h of (WebSources.history ?? []).slice(0, maxWebHistory)) {
            const url = h.url ?? "";
            if (!url) continue;
            const id = `webhist:${url}`;
            out.push({
                id,
                kind: "webHistory",
                label: h.title || url,
                tooltip: url,
                color: webHistColor,
                onColor: webHistOnColor,
                glyph: webHistGlyph,
                onClicked: vis => {
                    vis.launcher = false;
                    Quickshell.execDetached(["xdg-open", url]);
                }
            });
            idx[id] = out.length - 1;
        }

        // Live Zen / Firefox tabs from sessionstore-backups.
        const webTabColor = colorFor("webTab");
        const webTabOnColor = onColorFor("webTab");
        const webTabGlyph = glyphFor("webTab");
        for (const t of (WebSources.tabs ?? []).slice(0, maxWebTabs)) {
            const url = t.url ?? "";
            if (!url) continue;
            const id = `webtab:${url}`;
            const tabIndex = t.tabIndex ?? 0;
            out.push({
                id,
                kind: "webTab",
                label: t.title || url,
                tooltip: url,
                color: webTabColor,
                onColor: webTabOnColor,
                glyph: webTabGlyph,
                onClicked: vis => {
                    vis.launcher = false;
                    // Focus the existing Zen window — opening the
                    // URL via xdg-open would just create a duplicate
                    // tab. Then, if the tab is within Ctrl+1..9 reach
                    // (Firefox/Zen shortcut), send the key to jump
                    // straight to it.
                    Hypr.dispatch(`hl.dsp.focus({ window = "class:app.zen_browser.zen" })`);
                    if (tabIndex >= 1 && tabIndex <= 9) {
                        Quickshell.execDetached(["hyprctl", "dispatch", "sendshortcut",
                                                 `CTRL,${tabIndex},class:app.zen_browser.zen`]);
                    }
                }
            });
            idx[id] = out.length - 1;
        }

        // Spotify playlists. Click → play on active device. URI is
        // the playlist's spotify:playlist:XYZ.
        const spPlColor = colorFor("spotifyPlaylist");
        const spPlOnColor = onColorFor("spotifyPlaylist");
        const spPlGlyph = glyphFor("spotifyPlaylist");
        const spImgIdx = [];
        for (const p of (SpotifySources.playlists ?? []).slice(0, maxSpotify)) {
            const uri = p.uri ?? "";
            if (!uri) continue;
            const id = `spotify:pl:${uri}`;
            const tipBits = [p.owner, p.trackCount ? `${p.trackCount} tracks` : ""].filter(Boolean);
            out.push({
                id,
                kind: "spotifyPlaylist",
                label: p.name ?? "(playlist)",
                tooltip: tipBits.join("  •  "),
                imageUrl: p.image ?? "",
                color: spPlColor,
                onColor: spPlOnColor,
                glyph: spPlGlyph,
                onClicked: vis => {
                    vis.launcher = false;
                    SpotifySources.play(uri);
                }
            });
            idx[id] = out.length - 1;
            if (p.image) spImgIdx.push(out.length - 1);
        }

        // Spotify recently-played tracks. Each track is its own node;
        // grouping by album as edges happens in relayout().
        const spTrColor = colorFor("spotifyTrack");
        const spTrOnColor = onColorFor("spotifyTrack");
        const spTrGlyph = glyphFor("spotifyTrack");
        for (const t of (SpotifySources.recents ?? []).slice(0, maxSpotify)) {
            const uri = t.uri ?? "";
            if (!uri) continue;
            const id = `spotify:tr:${uri}`;
            out.push({
                id,
                kind: "spotifyTrack",
                label: t.name ?? "(track)",
                tooltip: [t.artist, t.album].filter(Boolean).join("  •  "),
                imageUrl: t.image ?? "",
                color: spTrColor,
                onColor: spTrOnColor,
                glyph: spTrGlyph,
                spotifyAlbum: t.album ?? "",
                uri: uri,            // payload for now-playing accent
                onClicked: vis => {
                    vis.launcher = false;
                    SpotifySources.play(uri);
                }
            });
            idx[id] = out.length - 1;
            if (t.image) spImgIdx.push(out.length - 1);
        }
        if (spotifyImageIndices.length !== spImgIdx.length || spotifyImageIndices.some((value, i) => value !== spImgIdx[i]))
            spotifyImageIndices = spImgIdx;

        const emojiColor = colorFor("emoji");
        const emojiOnColor = onColorFor("emoji");
        for (const e of (root.emojiScoped ? Emoji.matches : [])) {
            const id = `emoji:${e.glyph}`;
            if (idx[id] !== undefined)
                continue;
            out.push({
                id,
                kind: "emoji",
                label: e.keywords,
                tooltip: qsTr("Copy to clipboard"),
                color: emojiColor,
                onColor: emojiOnColor,
                glyph: e.glyph,
                onClicked: vis => {
                    vis.launcher = false;
                    Emoji.copy(e.glyph);
                }
            });
            idx[id] = out.length - 1;
        }

        // Clipboard history. Ephemeral by nature and never linked to anything,
        // so these are always isolated nodes — the point is `>clip <text>`,
        // not the topology.
        const clipColor = colorFor("clip");
        const clipOnColor = onColorFor("clip");
        const clipGlyph = glyphFor("clip");
        for (const c of (root.clipScoped ? Clipboard.entries : [])) {
            if (c.binary)
                continue;
            const id = `clip:${c.id}`;
            out.push({
                id,
                kind: "clip",
                label: c.preview,
                tooltip: qsTr("Copy to clipboard"),
                clipId: c.id,
                color: clipColor,
                onColor: clipOnColor,
                glyph: clipGlyph,
                onClicked: vis => {
                    vis.launcher = false;
                    Clipboard.copy(c.id);
                }
            });
            idx[id] = out.length - 1;
        }

        // Skip the reassignment if nothing structural changed — same
        // length and same ids in the same order. Otherwise every burst
        // of source-model signals (WebSources reload, Apps refresh,
        // EmacsSources scan) destroys + recreates every Repeater
        // delegate, which flashes icons + resets label fade timing.
        const sameShape = nodes.length === out.length
            && nodes.every((n, i) => n.id === out[i]?.id);
        if (sameShape) {
            let searchChanged = false;
            // Refresh callbacks / colour references in place but keep
            // the same object identity for indexById and Repeater
            // models — bindings are stable.
            for (let i = 0; i < out.length; ++i) {
                const cur = nodes[i];
                const nxt = out[i];
                cur.color = nxt.color;
                cur.source = nxt.source;
                cur.onColor = nxt.onColor;
                cur.glyph = nxt.glyph;
                cur.onClicked = nxt.onClicked;
                const oldMetadata = cur.searchMetadata ?? [];
                const newMetadata = nxt.searchMetadata ?? [];
                searchChanged = searchChanged || cur.label !== nxt.label
                    || oldMetadata.length !== newMetadata.length
                    || oldMetadata.some((value, j) => value !== newMetadata[j]);
                cur.searchMetadata = nxt.searchMetadata;
                cur.label = nxt.label;
                cur.tooltip = nxt.tooltip;
                cur.imagePath = nxt.imagePath;
                cur.iconName = nxt.iconName;
            }
            if (searchChanged && (!browsing || searchActive)) rescore();
            return;
        }

        const positions = {};
        for (let i = 0; i < nodes.length; ++i)
            positions[nodes[i].id] = Qt.point(snap[i * 3], snap[i * 3 + 1]);
        layoutPositions = positions;
        nodes = out;
        indexById = idx;
        nodeScores = new Array(nodes.length).fill(0);
        relayout();
        rescore();
        if (wasBrowsing && idx[selectionId] !== undefined && isNavigationCandidate(idx[selectionId])) {
            selectNode(idx[selectionId]);
            navigationHistory = historyIds.filter(id => idx[id] !== undefined && isNavigationCandidate(idx[id])).map(id => idx[id]);
        }
        edgeLayer.refresh();
    }

    // Edges resolved once per rebuild for the sim (index pairs).
    property var edgePairs: []
    // index -> edge count, rebuilt with edgePairs. Drives node size.
    property var nodeDegree: ({})
    // { nodeIndex: [neighbourIndex, ...] }, rebuilt in relayout().
    // Shared by cycleLinkedNeighbor (Tab nav) and the neighbour highlight.
    property var nodeAdjacency: ({})

    // Neighbour highlight. The "focus" node is the hovered node
    // (mouse) else the current pick (keyboard). highlightSet = that node +
    // its 1-hop neighbours. Recomputed only when the focus or adjacency
    // changes (NOT per sim tick). When inactive (-1) all nodes render
    // normally. Suppressed while an active search filter is driving its
    // own depth-based emphasis, so the two systems don't fight.
    readonly property int highlightFocus: {
        const filtering = (root.query ?? "").trim() !== "" || root.scopeSegments.length > 0;
        if (filtering) return -1;
        return hoverIndex >= 0 ? hoverIndex : currentNode;
    }
    property var highlightSet: ({})
    onHighlightFocusChanged: {
        if (highlightFocus < 0) { highlightSet = ({}); return; }
        const s = ({});
        s[highlightFocus] = true;
        for (const j of (nodeAdjacency[highlightFocus] ?? [])) s[j] = true;
        highlightSet = s;
        edgeLayer.refresh();   // edges re-evaluate brighten/dim
    }
    // Font cache (size bucket → font string). Setting ctx.font with a fresh
    // string per node is the most expensive op in the paint loop.
    property var _glyphFonts: ({})
    property var _labelFonts: ({})

    property var layoutPositions: ({})
    property bool layoutReady: false
    property int warmupRemaining: 0
    readonly property bool preparing: warmupRemaining > 0
    Timer {
        interval: 16
        repeat: true
        running: root.preparing && !root.transitioning
        onTriggered: {
            const deadline = Date.now() + 4;
            let steps = 0;
            do {
                sim.step();
                ++steps;
            } while (steps < Math.min(4, root.warmupRemaining) && Date.now() < deadline);
            root.warmupRemaining -= steps;
            if (!root.preparing) {
                root.layoutReady = true;
                root.publishSnapshot();
            }
        }
    }

    function relayout(): void {
        if (!width || !height || nodes.length === 0) return;
        const cx = width / 2;
        const cy = height / 2;
        const golden = Math.PI * (3 - Math.sqrt(5));

        // Initial seed radius scales with sqrt(node count) so the
        // starting *density* stays constant — a fixed radius packs 300
        // nodes into the same disc as 100 and opens as tangled soup the
        // sim then has to untangle. 0.45 of the smaller dimension is the
        // baseline for ~120 nodes; more nodes seed proportionally wider.
        const seedR = Math.min(width, height) * 0.45
            * Math.max(1, Math.sqrt(nodes.length / 120));
        const initX = [];
        const initY = [];
        const radii = [];
        for (let i = 0; i < nodes.length; ++i) {
            const k = i + 1;
            const rad = seedR * Math.sqrt(k / nodes.length);
            const ang = k * golden;
            const previous = layoutPositions[nodes[i].id];
            initX.push(previous?.x ?? cx + rad * Math.cos(ang));
            initY.push(previous?.y ?? cy + rad * Math.sin(ang));
        }

        // Materialise edges as index pairs for the sim. Two sources:
        //   - org-roam links (roam node <-> roam node)
        //   - web bookmark folder structure (child <-> parent folder)
        const pairs = [];
        for (const link of EmacsSources.roamLinks) {
            const i = indexById[link.source];
            const j = indexById[link.dest];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        for (const link of (WebSources.bookmarkLinks ?? [])) {
            const i = indexById[`web:${link.source}`];
            const j = indexById[`web:${link.dest}`];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Same-host history clusters: each non-hub history entry on a
        // host edges back to its hub. Pulls visit-the-same-site nodes
        // visibly together.
        for (const link of (WebSources.historyLinks ?? [])) {
            const i = indexById[`webhist:${link.source}`];
            const j = indexById[`webhist:${link.dest}`];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Same-host tab clusters mirror the history hub-and-spoke.
        for (const link of (WebSources.tabLinks ?? [])) {
            const i = indexById[`webtab:${link.source}`];
            const j = indexById[`webtab:${link.dest}`];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Recent files → their project (source = recent path, dest = root).
        for (const link of (EmacsSources.projectLinks ?? [])) {
            const i = indexById[`recent:${link.source}`];
            const j = indexById[`project:${link.dest}`];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Mail clustered by sender (each message → first from same sender).
        for (const link of (MailSources.senderLinks ?? [])) {
            const i = indexById[`mail:${link.source}`];
            const j = indexById[`mail:${link.dest}`];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Calendar events clustered by day (event ids are already full ids).
        for (const link of (CalendarSources.dayLinks ?? [])) {
            const i = indexById[link.source];
            const j = indexById[link.dest];
            if (i !== undefined && j !== undefined && i !== j)
                pairs.push(Qt.point(i, j));
        }
        // Spotify: link tracks that share an album. First-seen track
        // per album becomes the hub.
        {
            const albumHub = ({});
            for (let i = 0; i < nodes.length; ++i) {
                const n = nodes[i];
                if (n.kind !== "spotifyTrack") continue;
                const a = n.spotifyAlbum ?? "";
                if (!a) continue;
                if (albumHub[a] === undefined) { albumHub[a] = i; continue; }
                pairs.push(Qt.point(i, albumHub[a]));
            }
        }

        // Workspaces → their host monitor.
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (n.kind !== "workspace") continue;
            const monName = n.workspaceMonitor;
            if (!monName) continue;
            const monI = indexById[`monitor:${monName}`];
            if (monI !== undefined) pairs.push(Qt.point(i, monI));
        }

        // Hyprland client clusters:
        //   - same-class windows → hub-and-spoke (first of each class)
        //   - each client → its workspace (so the cluster anchors per
        //     workspace, which anchors per monitor via the edge above)
        const clientHubByClass = ({});
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (n.kind !== "client") continue;
            const klass = n.clientClass ?? "";
            if (klass) {
                const hub = clientHubByClass[klass];
                if (hub === undefined) {
                    clientHubByClass[klass] = i;
                } else if (hub !== i) {
                    pairs.push(Qt.point(i, hub));
                }
            }
            // Workspace anchor.
            const wsName = n.clientWorkspace;
            if (wsName) {
                const wsI = indexById[`workspace:${wsName}`];
                if (wsI !== undefined) pairs.push(Qt.point(i, wsI));
            }
        }

        // Apps → primary category hub.
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (n.kind !== "app") continue;
            // appIndices were filled from apps[], but onClicked closes
            // over `entry`. We need the category here — look it up by
            // re-walking Apps.list for this index.
            const e = (Apps.list ?? [])[appIndices.indexOf(i)];
            const entry = e?.entry ?? e;
            const catsRaw = entry?.categories;
            const cats = String(catsRaw ?? "").replace(/,/g, " ").trim();
            if (!cats) continue;
            const primary = cats.split(/[ ;,]+/).find(c => c.length > 0);
            if (!primary) continue;
            const catI = indexById[`category:${primary}`];
            if (catI !== undefined && catI !== i) pairs.push(Qt.point(i, catI));
        }

        edgePairs = pairs;

        // Precompute the undirected adjacency map once per relayout so
        // edge-following nav (Tab) and neighbour-highlight read O(1) instead
        // of re-scanning edgePairs on every call.  adjacency[i] = [j, ...].
        const adj = ({});
        for (const e of pairs) {
            (adj[e.x] || (adj[e.x] = [])).push(e.y);
            (adj[e.y] || (adj[e.y] = [])).push(e.x);
        }
        nodeAdjacency = adj;

        // Degrees before radii: baseRadiusFor scales by connectivity, so the
        // edge list has to exist before any radius is asked for.
        const deg = ({});
        for (const e of pairs) {
            deg[e.x] = (deg[e.x] ?? 0) + 1;
            deg[e.y] = (deg[e.y] ?? 0) + 1;
        }
        nodeDegree = deg;
        for (let i = 0; i < nodes.length; ++i)
            radii.push(baseRadiusFor(nodes[i].kind, i));

        const retained = layoutReady && Object.keys(layoutPositions).length > 0;
        warmupRemaining = retained ? 0 : 320;
        sim.prewarmTicks = 0;
        sim.setGraph(initX, initY, radii, pairs);
        if (retained) sim.reheat(0.18);
        // Seed snap from the initial positions so the edge layer draws
        // immediately — without this, snap stays [] until the first
        // FrameAnimation step and edges are invisible at startup.
        _curSnap = sim.snapshot();
        snap = _curSnap;
    }

    // Update each node's TARGET position + size based on the query —
    // actual motion is done in the C++ sim, so nodes glide into place
    // rather than snap.
    function rescore(): void {
        if (nodes.length === 0) {
            nodeScores = [];
            matchIndices = [];
            depthToMatch = [];
            currentMatchIndex = 0;
            currentNode = -1;
            hoverIndex = -1;
            navigationHistory = [];
            browsing = false;
            _assignNavSlots();
            return;
        }
        const q = (query ?? "").trim().toLowerCase();
        const matches = [];
        const segs = scopeSegments ?? [];
        const hasScope = segs.length > 0 || !!pivotKind;
        const scores = new Array(nodes.length).fill(0);
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            let s = 0;
            if (hasScope) {
                for (const segment of segs) {
                    if (segment.kind !== n.kind) continue;
                    const term = (segment.q ?? "").trim();
                    s = Math.max(s, term ? SearchRanking.score(n.label, term, n.searchMetadata) : 1);
                }
                if (pivotKind === n.kind && !segs.some(segment => segment.kind === n.kind))
                    s = 1;
            } else {
                s = SearchRanking.score(n.label, q, n.searchMetadata);
            }
            scores[i] = s;
            if (s > 0) matches.push(i);
        }
        matches.sort((a, b) => scores[b] - scores[a]);
        matchIndices = matches;
        nodeScores = scores;
        currentMatchIndex = 0;
        browsing = false;
        navigationHistory = [];
        currentNode = matches.length > 0 ? matches[0] : -1;

        // BFS the edge graph outward from the match set, tagging each
        // reachable node with its depth (capped at elevationDepth).
        // Related nodes stay visible without entering keyboard search results.
        const depths = new Array(nodes.length).fill(Infinity);
        const queue = [];
        for (const m of matches) {
            depths[m] = 0;
            queue.push(m);
        }
        const adj = new Array(nodes.length);
        for (let i = 0; i < nodes.length; ++i) adj[i] = [];
        for (const e of edgePairs) {
            adj[e.x].push(e.y);
            adj[e.y].push(e.x);
        }
        let head = 0;
        while (head < queue.length) {
            const i = queue[head++];
            if (depths[i] >= elevationDepth) continue;
            for (const j of adj[i]) {
                if (depths[j] > depths[i] + 1) {
                    depths[j] = depths[i] + 1;
                    queue.push(j);
                }
            }
        }
        depthToMatch = depths;

        const filtering = !!(q || hasScope);
        for (let i = 0; i < nodes.length; ++i) {
            // Whenever a filter is active (typed query OR scope),
            // ghost out non-matching nodes so the matching cluster
            // can move freely without colliding with the rest.
            // Radii are NOT computed here — retargetMatches() owns every
            // sim.setTarget radius, so a second baseRadiusFor() call per
            // node per rescore (i.e. per keystroke) is pure waste.
            sim.setInteractive(i, !filtering || scores[i] > 0);
        }
        retargetMatches();
    }

    // Push targets for the current match set into the sim. The match at
    // currentMatchIndex pulls to center and grows into a preview; the
    // remaining matches arrange on a ring around it. Non-match targets
    // are computed once in rescore() so we don't redo them here.
    // Radius of the match ring for a given off-centre match count. Shared by
    // retargetMatches (which places the ring) and fitCamera (which has to
    // frame exactly that ring) — this was duplicated arithmetic in both,
    // which is how they drift apart.
    function _ringInnerR(otherCount: int): real {
        const fitR = otherCount * ringPerNode / (2 * Math.PI);
        return Math.max(ringMinR, fitR);
    }

    function _assignNavSlots(): void {
        navSlots = _navSlotDirs.map(d => directionalNode(d[0], d[1]));
    }

    function retargetMatches(): void {
        // Clear isolation up-front — only the current preview pick
        // gets it back below, so nodes that previously held the slot
        // lose it cleanly when the highlight moves.
        for (let i = 0; i < nodes.length; ++i) sim.setIsolated(i, false);

        _assignNavSlots();
        const q = (query ?? "").trim().toLowerCase();
        const segs = scopeSegments ?? [];
        const hasScope = segs.length > 0;
        const filtering = !!(q || hasScope);
        const cx = width / 2;
        const cy = height / 2;
        // Match-ring radius: large enough to fit all non-preview
        // matches on the circumference. If the preview pick is a
        // match, drop it from the ring; otherwise the ring holds
        // every match.
        const previewIsMatch = currentNode >= 0 && matchIndices.indexOf(currentNode) >= 0;
        const otherCount = Math.max(0, matchIndices.length - (previewIsMatch ? 1 : 0));
        const innerR = _ringInnerR(otherCount);

        let maxScore = 0;
        let minScore = Infinity;
        for (const mi of matchIndices) {
            const s = nodeScores[mi];
            if (s > maxScore) maxScore = s;
            if (s < minScore) minScore = s;
        }
        if (!isFinite(minScore)) minScore = 0;
        // Rank is mapped relative to the score *range*, not the absolute
        // max — otherwise a match-all scope (>wallpaper: every node = 1)
        // collapses every node onto the same tight inner radius and they
        // cram together. range 0 → no centrality/size variation.
        const scoreRange = maxScore - minScore;

        // Kinds named by any scope segment (plus the pivot) are "active".
        // Off-scope kinds get dimmed harder below.
        const activeKinds = new Set(segs.map(s => s.kind));
        if (pivotKind) activeKinds.add(pivotKind);

        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            const rest = baseRadiusFor(n.kind, i);
            const isMatch = nodeScores[i] > 0;
            const offScope = hasScope && !activeKinds.has(n.kind);

            const isPreview = i === currentNode;
            // Preview pick is isolated from repulsion so the rest of
            // the cluster can't shove it off-center.
            sim.setIsolated(i, isPreview);

            if (isPreview) {
                // Could be a match OR an elevated neighbour the user
                // arrow-keyed into; either way, pull to center and
                // grow into the preview.
                sim.setTarget(i, cx, cy, attractMatchK * 4.0, previewRadius);
            } else if (filtering && isMatch) {
                {
                    // Ring angle is keyed to node *identity* (golden angle
                    // by node index), NOT rank/slot — so a match keeps its
                    // place on the ring as the set grows or shrinks while
                    // you type or cycle. Nodes no longer hop slots, which
                    // was the main source of the restless churn. attractK
                    // is soft so repulsion + springs organicise the ring.
                    const ang = (i * 2.3999632) % (2 * Math.PI);
                    // Small identity-keyed radial jitter so the ring isn't
                    // a mechanical circle; stable across rescores.
                    const jitter = Math.sin(i * 12.9898) * 0.06;
                    // Rank (relative to the score range) drives both axes:
                    // stronger matches ring in a little tighter and grow
                    // bigger; weaker drift to the rim. With no range (all
                    // scores equal) norm = 0 → everyone sits on the full
                    // fitted ring at a moderate size — no cramming.
                    const norm = scoreRange > 1e-6
                        ? (nodeScores[i] - minScore) / scoreRange
                        : 0;
                    const ringScale = 1.1 - norm * 0.35;   // 0.75 best … 1.1 worst / all-equal
                    const r = innerR * ringScale * (1.0 + jitter);
                    const tx = cx + r * canopyX * Math.cos(ang);
                    const ty = cy + r * canopyY * Math.sin(ang);
                    const rad = rest + (maxRadius - rest) * (0.45 + 0.55 * norm);
                    sim.setTarget(i, tx, ty, attractMatchK * 0.5, rad);
                }
            } else if (q && !isMatch) {
                // Depth-tiered radius so promoted neighbours read
                // visibly bigger than truly-unrelated background.
                // Scales between rest and maxRadius:
                //   depth 1 → near match-tier size
                //   depth 2 → noticeably bigger than rest
                //   depth 3 → just above rest
                //   beyond  → 0.35 × rest (a small dot)
                const d = depthToMatch?.[i] ?? Infinity;
                let radius;
                if (d === 1)      radius = rest + (maxRadius - rest) * 0.55;
                else if (d === 2) radius = rest + (maxRadius - rest) * 0.30;
                else if (d === 3) radius = rest + (maxRadius - rest) * 0.10;
                else              radius = rest * 0.65;
                sim.setTarget(i, sim.x(i), sim.y(i), attractRestK, radius);
            } else if (hasScope) {
                const d = depthToMatch?.[i] ?? Infinity;
                let radius;
                if (d === 1)      radius = rest + (maxRadius - rest) * 0.55;
                else if (d === 2) radius = rest + (maxRadius - rest) * 0.30;
                else if (d === 3) radius = rest + (maxRadius - rest) * 0.10;
                else              radius = offScope ? rest * 0.65 : rest;
                sim.setTarget(i, sim.x(i), sim.y(i), 0, radius);
            } else {
                sim.setTarget(i, sim.x(i), sim.y(i), 0, rest);
            }
        }
    }


    function topMatch(): var {
        if (currentNode >= 0 && currentNode < nodes.length)
            return nodes[currentNode];
        if (matchIndices.length === 0) return null;
        const i = Math.max(0, Math.min(matchIndices.length - 1, currentMatchIndex));
        return nodes[matchIndices[i]];
    }

    function currentIsMatch(): bool {
        return currentNode >= 0 && matchIndices.indexOf(currentNode) >= 0;
    }

    function currentPickKind(): string {
        if (currentNode >= 0 && currentNode < nodes.length)
            return nodes[currentNode].kind ?? "";
        return "";
    }

    readonly property bool searchActive: (query ?? "").trim() !== "" || scopeSegments.length > 0

    function flushSearch(): void {
        if (!filterTimer.running) return;
        filterTimer.stop();
        _applyFilter();
    }

    function isNavigationCandidate(index: int): bool {
        return index >= 0 && index < nodes.length
            && (!searchActive || (nodeScores[index] ?? 0) > 0);
    }

    function cycleMatch(delta: int): void {
        flushSearch();
        if (!matchIndices.length) return;
        const here = matchIndices.indexOf(currentNode);
        const next = here < 0 ? (delta < 0 ? matchIndices.length - 1 : 0)
            : (here + delta + matchIndices.length) % matchIndices.length;
        selectNode(matchIndices[next]);
    }

    function cycleLinkedNeighbor(delta: int): void {
        flushSearch();
        if (searchActive) { cycleMatch(delta); return; }
        if (delta < 0) { navigateBack(); return; }
        if (currentNode < 0) { selectNode(matchIndices[0] ?? 0); return; }
        const neighbors = nodeAdjacency[currentNode] ?? [];
        const pick = neighbors.find(i => !navigationHistory.includes(i));
        if (pick !== undefined) selectNode(pick);
        else if (neighbors.length) selectNode(neighbors[0]);
    }

    // Pan (keep current zoom) so node i sits at the viewport centre.
    function _centerOnNode(i: int): void {
        if (i < 0 || !width || !height) return;
        const wx = _nx(i), wy = _ny(i);
        _animateCamera(zoom, width / 2 - wx * zoom, height / 2 - wy * zoom);
    }

    property var navigationHistory: []
    property bool browsing: false

    function selectNode(index: int): void {
        if (index < 0 || index >= nodes.length) return;
        browsing = true;
        if (currentNode >= 0 && currentNode !== index)
            navigationHistory = navigationHistory.concat([currentNode]).slice(-100);
        currentNode = index;
        const mp = matchIndices.indexOf(index);
        if (mp >= 0) currentMatchIndex = mp;
        _assignNavSlots();
        const sx = _w2sX(_nx(index)), sy = _w2sY(_ny(index));
        if (sx < 120 || sx > width-220 || sy < 90 || sy > height-220)
            _centerOnNode(index);
        edgeLayer.refresh();
    }

    function navigateBack(): void {
        flushSearch();
        const history = navigationHistory.slice();
        let previous = -1;
        while (history.length && !isNavigationCandidate(previous)) previous = history.pop();
        navigationHistory = history;
        if (!isNavigationCandidate(previous)) return;
        currentNode = previous;
        _assignNavSlots();
        _centerOnNode(previous);
        edgeLayer.refresh();
    }

    function directionalNode(dirX: real, dirY: real): int {
        const cx = currentNode >= 0 ? _nx(currentNode) : _s2wX(width/2);
        const cy = currentNode >= 0 ? _ny(currentNode) : _s2wY(height/2);
        let best = -1, bestCost = Infinity;
        for (let i = 0; i < nodes.length; ++i) {
            if (i === currentNode || !isNavigationCandidate(i)) continue;
            const dx = _nx(i)-cx, dy = _ny(i)-cy;
            const distance = Math.hypot(dx, dy);
            if (distance < 1) continue;
            const alignment = (dx*dirX+dy*dirY)/distance;
            if (alignment < 0.35) continue;
            const cost = distance/(alignment*alignment);
            if (cost < bestCost) { best = i; bestCost = cost; }
        }
        return best;
    }

    function navDirection(dirX: real, dirY: real): void {
        flushSearch();
        if (searchActive && !isNavigationCandidate(currentNode)) {
            selectNode(matchIndices[0] ?? -1);
            return;
        }
        selectNode(directionalNode(dirX, dirY));
    }

    function _animateCamera(newZoom: real, newPanX: real, newPanY: real): void {
        zoomAnim.stop(); zoomAnim.to = newZoom; zoomAnim.start();
        panXAnim.stop(); panXAnim.to = newPanX; panXAnim.start();
        panYAnim.stop(); panYAnim.to = newPanY; panYAnim.start();
    }

    // Stir the background while the actions overlay is open. There's no
    // query active there (so no match ring / camera fit), so a plain
    // reheat re-fires repulsion + springs from alpha=1 for a gentle
    // re-settle, and a small camera orbit makes the graph visibly react
    // to each selection. `seed` (the action index) spreads successive
    // cycles to different spots instead of jittering in place.
    function stir(seed: int): void {
        sim.reheat(0.5);
        const ang = seed * 2.399963;   // golden angle → even spread
        const r = Math.min(width, height) * 0.05;
        _animateCamera(1.0 + 0.04 * Math.sin(seed * 1.7),
                       Math.cos(ang) * r,
                       Math.sin(ang) * r);
    }

    function fitCamera(): void {
        if (!width || !height) return;
        if (matchIndices.length === 0) {
            // No filter — return to the neutral view so subsequent
            // opens don't start zoomed in on a stale pick.
            _animateCamera(1.0, 0, 0);
            return;
        }
        // Centre on the preview's *target* position (the viewport
        // world-centre), not its current sim position — otherwise we
        // pan to wherever the node hasn't moved away from yet, and the
        // node then drifts off-screen as the sim settles toward target.
        const targetX = width / 2;
        const targetY = height / 2;

        const otherCount = Math.max(0, matchIndices.length - 1);
        const innerR = _ringInnerR(otherCount);

        // Bounding radius around the preview: ring outer edge + a
        // node-radius pad so the outermost match isn't clipped. Plus
        // the pill chrome that extends right from the preview disc —
        // include its half-width so it stays visible. Framed against
        // canopyX (the wider of the two canopy axes) so the flatter
        // vertical squeeze never clips the ring's horizontal extent.
        const target = innerR * canopyX + maxRadius * 1.8 + previewPillWidth * 0.5;

        // 85% of the half-viewport so there's a soft margin instead of
        // a tight crop. Zoom range is clamped tight (0.7–1.2) so the
        // camera doesn't snap between dramatically different scales
        // when cycling through matches — feels more like the view is
        // panning than zooming.
        const viewportR = Math.min(width, height) * 0.5 * 0.85;
        const newZoom = Math.max(0.7, Math.min(1.2, viewportR / Math.max(1, target)));

        const newPanX = width / 2 - targetX * newZoom;
        const newPanY = height / 2 - targetY * newZoom;

        _animateCamera(newZoom, newPanX, newPanY);
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true

        property int dragIndex: -1
        property bool dragMoved: false
        readonly property real dragSlop: 4

        function hitTest(sx: real, sy: real): int {
            const wx = root._s2wX(sx);
            const wy = root._s2wY(sy);
            const slop = 2 / root.zoom;
            let hit = -1, nearest = Infinity;
            for (let i = 0; i < root.nodes.length; ++i) {
                const dx = wx - root._nx(i), dy = wy - root._ny(i);
                const distance = dx * dx + dy * dy;
                const radius = root._nr(i) + slop;
                if (distance <= radius * radius) {
                    if (i === root.currentNode) return i;
                    if (distance < nearest) { hit = i; nearest = distance; }
                }
            }
            return hit;
        }

        property real panStartX
        property real panStartY
        property bool panning: false

        function pressAt(x: real, y: real): void {
            zoomAnim.stop();
            panXAnim.stop();
            panYAnim.stop();
            dragIndex = hitTest(x, y);
            dragMoved = false;
            panning = false;
            if (dragIndex >= 0) {
                sim.pin(dragIndex, sim.x(dragIndex), sim.y(dragIndex));
            } else {
                panStartX = x - root.panX;
                panStartY = y - root.panY;
                panning = true;
                cursorShape = Qt.ClosedHandCursor;
            }
        }

        function moveTo(x: real, y: real): void {
            if (dragIndex >= 0) {
                const wx = root._s2wX(x);
                const wy = root._s2wY(y);
                const dx = wx - root._nx(dragIndex);
                const dy = wy - root._ny(dragIndex);
                if (dragMoved || (dx * dx + dy * dy) > (dragSlop / root.zoom) ** 2) {
                    if (!dragMoved) sim.reheat(0.45);
                    dragMoved = true;
                    const offset = root.idleOffset(dragIndex);
                    sim.setPosition(dragIndex, wx - offset.x, wy - offset.y);
                    root._refresh();
                }
                return;
            }
            if (panning) {
                panXAnim.stop();
                panYAnim.stop();
                root.panX = x - panStartX;
                root.panY = y - panStartY;
                return;
            }
            const i = hitTest(x, y);
            if (i !== root.hoverIndex) {
                root.hoverIndex = i;
                edgeLayer.refresh();
                cursorShape = i >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor;
            }
        }

        onCanceled: {
            if (dragIndex >= 0) sim.unpin(dragIndex);
            dragIndex = -1;
            dragMoved = false;
            panning = false;
            cursorShape = Qt.ArrowCursor;
        }

        function releaseAt(): void {
            const idx = dragIndex;
            const moved = dragMoved;
            if (idx >= 0) sim.unpin(idx);
            dragIndex = -1;
            dragMoved = false;
            panning = false;
            cursorShape = Qt.ArrowCursor;
            if (moved) {
                sim.reheat(0.45);
                return;
            }
            if (idx < 0) return;

            // Two-step click: click an unselected node to make
            // it the preview pick; click the already-selected
            // node to fire its action. Enter on the selection
            // also fires.
            if (idx === root.currentNode) {
                root.nodes[idx].onClicked(root.visibilities);
                return;
            }
            root.selectNode(idx);
        }

        onPressed: event => pressAt(event.x, event.y)
        onPositionChanged: event => moveTo(event.x, event.y)
        onReleased: releaseAt()

        onWheel: w => {
            // Cancel any in-flight auto-camera animation so the
            // user's wheel input wins immediately.
            zoomAnim.stop();
            panXAnim.stop();
            panYAnim.stop();
            const factor = w.angleDelta.y > 0 ? 1.12 : (1 / 1.12);
            const newZoom = Math.max(0.25, Math.min(4, root.zoom * factor));
            const wx = root._s2wX(w.x);
            const wy = root._s2wY(w.y);
            root.zoom = newZoom;
            root.panX = w.x - wx * newZoom;
            root.panY = w.y - wy * newZoom;
        }
    }

    Item {
        id: world
        // The sibling MouseArea handles all graph input; skip per-node hit testing.
        enabled: false
        x: root.panX
        y: root.panY
        width: root.width
        height: root.height
        scale: root.zoom
        transformOrigin: Item.TopLeft
        opacity: root.preparing ? 0 : growAnim.progress

        Item {
            id: selectedMotion
            width: world.width
            height: world.height
            x: root.selectedOffset.x
            y: root.selectedOffset.y
            z: 200
        }
        Repeater {
            id: labelOrbits
            onItemAdded: Qt.callLater(root.attachOrbits)
            model: root.orbitCount
            delegate: Item {
                required property int index
                width: world.width
                height: world.height
                readonly property var offset: GraphDrift.offset(root.driftSeconds, root.driftStrength, index)
                x: offset.x
                y: offset.y
            }
        }
        Repeater {
            id: nodeOrbits
            onItemAdded: Qt.callLater(root.attachOrbits)
            model: root.orbitCount
            delegate: Item {
                required property int index
                width: world.width
                height: world.height
                readonly property var offset: GraphDrift.offset(root.driftSeconds, root.driftStrength, index)
                x: offset.x
                y: offset.y
                z: 1
            }
        }

        GraphEdges {
            id: edgeLayer
            anchors.fill: parent
            graph: root

        }

        // Label layer — declared *before* the disc / icon layers so node
        // labels render UNDERNEATH every node. Labels frequently overlap
        // neighbouring nodes (there's no collision-free placement on a dense
        // force layout), so rather than fight it we let the discs occlude the
        // text: a label crossing another node slides behind it, which reads
        // far cleaner than text painted over discs. Positions mirror the disc
        // delegate (centred under the node) since these are separate items.
        //
        // The grow-in reveal lives HERE, on the layer, as one opacity driven by
        // the shared GrowIn scalar — not inside the delegates. A per-label
        // `opacity: … * growAnim.progress` is intercepted by the delegate's
        // `Behavior on opacity`, and since growAnim.progress changes every frame
        // it runs, that restarts a fresh 180ms animation per label per frame for
        // the whole grow (and the fade then lags 180ms behind, never landing on
        // the intended curve). One animator writing one value the delegates sit
        // under; never a per-element animator.
        Item {
            anchors.fill: parent
            Instantiator {
                asynchronous: true
                model: root.nodes.length

                delegate: Text {
                    id: nodeLabel
                    parent: { void root.orbitRevision; return labelOrbits.itemAt(index % root.orbitCount); }

                    required property int index
                    readonly property var modelData: root.nodes[index] ?? ({ label: "", glyph: "", color: "transparent", onColor: "transparent" })
                    readonly property real nx: { if (!live) return 0; return root._px(index); }
                    readonly property real ny: { if (!live) return 0; return root._py(index); }
                    readonly property real sr: { if (!live) return 0; return root._nr(index); }
                    readonly property real score: root.nodeScores[index] ?? 0
                    readonly property bool isCurrent: {
                        const q = (root.query ?? "").trim();
                        const hasScope = root.scopeSegments.length > 0;
                        return root.currentNode === index;
                    }
                    readonly property bool isMatchHighlighted: {
                        const q = (root.query ?? "").trim();
                        const hasScope = root.scopeSegments.length > 0;
                        return index === root.hoverIndex || ((q || hasScope) && score > 0);
                    }
                    readonly property bool live: !isCurrent && (index === root.hoverIndex
                        || root.topMatchIndices.includes(index))

                    visible: live
                    width: 260
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    text: modelData.label
                    color: Colours.palette.m3onSurface
                    // Outline in the (woodland-warmed) surface colour gives each
                    // glyph a halo so the text stays legible where it crosses
                    // discs, icons and edges behind it (labels render under the
                    // node layer). Matches Content.qml's parchment backdrop.
                    style: Text.Outline
                    styleColor: Colours.palette.m3surface
                    x: { return nx - width / 2; }
                    y: { return ny + sr + 8; }
                    opacity: 1
                    font.pixelSize: index === root.hoverIndex ? 16 : 14
                }
            }
        }

        // Per-node disc + glyph, rendered as GPU-batched QML Items instead of
        // a software Canvas paint. Each delegate owns:
        //   - a coloured circle (Rectangle, radius = width/2)
        //   - a current-pick halo + ring (Rectangle, visible when chosen)
        //   - a source-kind glyph (Text, non-app/wallpaper)
        // The under-node label lives in the separate label layer above; app-
        // icon / wallpaper-thumbnail Repeaters below stack on top of the disc.
        Instantiator {
            asynchronous: true
            model: root.nodes.length

            delegate: Item {
                id: nodeItem
                parent: { void root.orbitRevision; return isCurrent ? selectedMotion : nodeOrbits.itemAt(index % root.orbitCount); }
                required property int index
                readonly property var modelData: root.nodes[index] ?? ({ label: "", glyph: "", color: "transparent", onColor: "transparent" })
                readonly property var node: modelData
                readonly property real nr: { return root._nr(index); }
                readonly property real nx: { return root._px(index); }
                readonly property real ny: { return root._py(index); }
                readonly property real score: root.nodeScores[index] ?? 0
                readonly property bool matched: {
                    const q = (root.query ?? "").trim();
                    return !(q || root.scopeSegments.length) || score > 0;
                }
                readonly property bool isCurrent: {
                    const q = (root.query ?? "").trim();
                    const hasScope = root.scopeSegments.length > 0;
                    return root.currentNode === index;
                }
                readonly property bool isMatchHighlighted: {
                    const q = (root.query ?? "").trim();
                    const hasScope = root.scopeSegments.length > 0;
                    return index === root.hoverIndex || ((q || hasScope) && score > 0);
                }
                readonly property bool slowMotion: sim.alpha < 0.55

                // Distance (in edges) from the nearest match. 0=match,
                // 1..3=elevated background, Infinity=unrelated.
                readonly property real graphDepth: root.depthToMatch?.[index] ?? Infinity

                width: { return nr * 2; }
                height: width
                x: { return nx - width / 2; }
                y: { return ny - height / 2; }
                // Three-tier opacity: matched 1.0, elevated (depth ≤ 3)
                // 0.5–0.8 by depth, unrelated 0.18. Filter-off shows
                // everyone at full opacity.
                opacity: {
                    // The selected pick is always fully lit, even when
                    // it's an elevated (filtered-out) node — selecting
                    // promotes it visually as well as physically.
                    if (isCurrent) return 1.0;
                    const q = (root.query ?? "").trim();
                    const filtering = q !== "" || root.scopeSegments.length > 0;
                    if (!filtering) {
                        // When hovering/selecting a node with no active filter,
                        // dim everything except the focus + its 1-hop
                        // neighbours so the local topology pops.
                        if (root.highlightFocus >= 0)
                            return root.highlightSet[index] ? 1.0 : 0.42;
                        return 1.0;
                    }
                    if (matched) return 1.0;
                    if (graphDepth <= root.elevationDepth)
                        return 0.85 - (graphDepth - 1) * 0.15;
                    return 0.34;
                }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                // Current pick floats above all; elevated neighbours float
                // above unrelated background so they don't get visually
                // buried.
                z: {
                    if (isCurrent) return 100;
                    if (graphDepth <= root.elevationDepth) return 50 - graphDepth * 5;
                    return 0;
                }

                // Lantern glow. One shared greyscale texture, no per-node tint, so
                // every glow batches into a single draw call — a Shape/RadialGradient
                // per node would be one batch each across ~300 nodes. Untinted also
                // keeps the sky reading as one warm light rather than a colour riot.
                Image {
                    anchors.centerIn: parent
                    width: parent.width * 3.4
                    height: width

                    source: Quickshell.shellPath("assets/images/ui/node-glow.png")
                    sourceSize.width: 128
                    sourceSize.height: 128
                    asynchronous: true
                    smooth: true
                    // Scaled by connectivity at rest, so the hubs read as the lit
                    // part of the sky and the unlinked leaves settle into a field
                    // behind them. Uniform glow made the whole graph one texture.
                    opacity: {
                        if (nodeItem.isCurrent)
                            return 0.55;
                        if (nodeItem.isMatchHighlighted)
                            return 0.4;
                        const deg = root.nodeDegree[nodeItem.index] ?? 0;
                        return 0.10 + Math.min(0.22, Math.log2(1 + deg) * 0.05);
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // The disc itself + optional outline / current ring.
                Rectangle {
                    id: disc
                    anchors.fill: parent
                    radius: width / 2
                    color: root.colorFor(nodeItem.node.kind)
                    border.color: nodeItem.isCurrent
                        ? Colours.palette.m3primary
                        : Colours.palette.m3onSurface
                    border.width: nodeItem.isCurrent ? 3
                        : (nodeItem.isMatchHighlighted ? 1.5 : 0)
                }

                // Source-kind glyph (description / bookmark / hub / image /
                // language / folder / history). App + wallpaper get their
                // own image overlay below instead.
                //
                // Items render on the GPU and cost essentially nothing per
                // frame, so this isn't gated on sim alpha.
                Text {
                    visible: nodeItem.node.kind !== "app"
                          && nodeItem.node.kind !== "wallpaper"
                    anchors.centerIn: parent
                    text: nodeItem.node.glyph
                    color: root.onColorFor(nodeItem.node.kind)
                    // Emoji nodes put the character itself on the disc, so they
                    // must fall through to the system emoji font rather than being
                    // forced into the icon family (which has no glyph for it).
                    font.family: nodeItem.node.kind === "emoji" ? "Noto Color Emoji" : "Material Symbols Rounded"
                    font.pixelSize: 128
                    scale: Math.max(6, nodeItem.width * 0.6) / 128
                }

            }
        }

        // Single preview-pill overlay that follows the current pick, instead
        // of a pill + label column embedded in every node delegate (those
        // re-laid-out for all ~300 nodes every frame even though only one is
        // ever current). z=99 sits just under the current disc (z=100) so the
        // disc still draws over the pill's rounded left end.
        Item {
            id: previewPill
            parent: selectedMotion

            readonly property int ci: root.currentNode
            readonly property var cnode: (ci >= 0 && ci < root.nodes.length) ? root.nodes[ci] : null
            readonly property real cnr: { return ci >= 0 ? root._nr(ci) : 0; }
            readonly property real cnx: { return ci >= 0 ? root._px(ci) : 0; }
            readonly property real cny: { return ci >= 0 ? root._py(ci) : 0; }
            readonly property bool showChrome: {
                const q = (root.query ?? "").trim();
                return cnode !== null;
            }

            visible: ci >= 0
            z: 99
            width: { return cnr * 2; }
            height: Math.max(64, width)
            x: { return cnx - width / 2; }
            y: { return cny - height / 2; }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                height: parent.height
                width: parent.width + root.previewPillWidth
                radius: height / 2
                // Parchment-warmed pill fill; the border stays m3primary —
                // it marks the current *selection* (interactive state).
                color: Woodland.velvet
                border.color: Colours.palette.m3primary
                border.width: 2
                opacity: previewPill.showChrome ? 0.92 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.right
                anchors.leftMargin: 16
                width: root.previewPillWidth - 32
                spacing: 4
                opacity: previewPill.showChrome ? 1.0 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }

                Text {
                    width: parent.width
                    text: previewPill.cnode?.label ?? ""
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: previewPill.cnode?.tooltip ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }

        // App icons rendered as real images on top of the disc Repeater.
        // Positions follow the published simulation snapshot (sim.x(i)
        // isn't a notifying property — it's a method).
        Instantiator {
            asynchronous: true
            model: root.appIndices

            delegate: Item {
                id: appDelegate
                parent: { void root.orbitRevision; return root.currentNode === modelData ? selectedMotion : nodeOrbits.itemAt(modelData % root.orbitCount); }
                required property int modelData
                readonly property var node: root.nodes[modelData]
                readonly property bool isPreview: root.currentNode === modelData

                width: { return root._nr(modelData) * 1.5; }
                height: width
                x: { return root._px(modelData) - width / 2; }
                y: { return root._py(modelData) - height / 2; }
                opacity: {
                    if (isPreview) return 1.0;
                    const q = (root.query ?? "").trim();
                    if (!q && !root.scopeSegments.length) return 1.0;
                    return (root.nodeScores[modelData] ?? 0) > 0 ? 1.0 : 0.25;
                }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                // Match the disc Repeater's z bump so the icon stays on top
                // of every other node while it's the preview pick.
                // Sit just above this node's own disc (the disc Repeater
                // uses the same depth-tiered z, 50-d*5 for matches / elevated,
                // 0 for background). Without the +0.5 the matched disc renders
                // on top and hides the icon for every non-selected node.
                z: {
                    if (isPreview) return 101;
                    const d = root.depthToMatch?.[modelData] ?? Infinity;
                    if (d <= root.elevationDepth) return 50 - d * 5 + 0.5;
                    return 0.5;
                }

                // Fixed sourceSize so the icon pixmap is decoded once at
                // the preview-tier size and just scaled to the delegate's
                // current dimensions. Re-binding sourceSize per frame
                // (the default IconImage path) re-rasterises the SVG /
                // PNG on every tick of the grow/shrink animation, which
                // is why the icons flickered as they animated.
                Image {
                    anchors.fill: parent
                    source: Quickshell.iconPath(appDelegate.node?.iconName ?? "", "image-missing")
                    asynchronous: true
                    cache: true
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize: {
                        const dpr = Screen.devicePixelRatio || 1;
                        const max = root.previewRadius * 1.5 * dpr;
                        return Qt.size(max, max);
                    }
                }
            }
        }

        // Wallpaper thumbnails — Image clipped to a circle.
        Instantiator {
            asynchronous: true
            model: root.wallpaperIndices

            delegate: Item {
                id: wpDelegate
                parent: { void root.orbitRevision; return root.currentNode === modelData ? selectedMotion : nodeOrbits.itemAt(modelData % root.orbitCount); }
                required property int modelData
                readonly property var node: root.nodes[modelData]

                width: { return root._nr(modelData) * 2.0; }
                height: width
                x: { return root._px(modelData) - width / 2; }
                y: { return root._py(modelData) - height / 2; }
                opacity: {
                    if (isPreview) return 1.0;
                    const q = (root.query ?? "").trim();
                    if (!q && !root.scopeSegments.length) return 1.0;
                    return (root.nodeScores[modelData] ?? 0) > 0 ? 1.0 : 0.25;
                }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                // Float the preview thumbnail above every other node so
                // ring matches don't render over it.
                // Sit just above this node's own disc (the disc Repeater
                // uses the same depth-tiered z, 50-d*5 for matches / elevated,
                // 0 for background). Without the +0.5 the matched disc renders
                // on top and hides the icon for every non-selected node.
                z: {
                    if (isPreview) return 101;
                    const d = root.depthToMatch?.[modelData] ?? Infinity;
                    if (d <= root.elevationDepth) return 50 - d * 5 + 0.5;
                    return 0.5;
                }

                // Whether this delegate is the centred preview pick.
                readonly property bool isPreview: root.currentNode === modelData

                // Stacked layers: low-res thumbnail (fast, every wallpaper
                // loads at once) + full-res original on top, but only
                // loaded for the current preview pick so we never have N
                // concurrent multi-MB JPEG decodes.
                //
                // Rounded by a stencil clip, not a MultiEffect mask: this item's
                // size tracks the node radius and the zoom, both of which change
                // every simulation update while the sim runs, and resizing a layered item
                // reallocates and re-renders its offscreen buffer every frame —
                // thirty of those land right on the launcher's opening pan.
                StyledClippingRect {
                    anchors.fill: parent
                    radius: width / 2

                    // Keep the small image visible while the preview decodes.
                    Image {
                        anchors.fill: parent
                        source: wpDelegate.node?.imagePath ? "file://" + wpDelegate.node.imagePath : ""
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: {
                            const dpr = Screen.devicePixelRatio || 1;
                            return Qt.size(160 * dpr, 160 * dpr);
                        }
                    }

                    // Crisp full-res, only fetched when this is the
                    // preview. Fades over the thumbnail when decoded.
                    Image {
                        anchors.fill: parent
                        source: wpDelegate.isPreview && wpDelegate.node?.imagePath
                            ? ("file://" + wpDelegate.node.imagePath)
                            : ""
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: {
                            const dpr = Screen.devicePixelRatio || 1;
                            const max = root.previewRadius * 2.0 * dpr;
                            return Qt.size(max, max);
                        }
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }

            }
        }

        // Spotify cover art (playlists + recently-played track albums).
        // Qt fetches the HTTPS image and caches per-source.
        Instantiator {
            asynchronous: true
            model: root.spotifyImageIndices

            delegate: Item {
                id: spDelegate
                parent: { void root.orbitRevision; return root.currentNode === modelData ? selectedMotion : nodeOrbits.itemAt(modelData % root.orbitCount); }
                required property int modelData
                readonly property var node: root.nodes[modelData]
                readonly property bool isPreview: root.currentNode === modelData

                width: { return root._nr(modelData) * 2.0; }
                height: width
                x: { return root._px(modelData) - width / 2; }
                y: { return root._py(modelData) - height / 2; }
                opacity: {
                    if (isPreview) return 1.0;
                    const q = (root.query ?? "").trim();
                    if (!q && !root.scopeSegments.length) return 1.0;
                    return (root.nodeScores[modelData] ?? 0) > 0 ? 1.0 : 0.25;
                }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                // Sit just above this node's own disc (the disc Repeater
                // uses the same depth-tiered z, 50-d*5 for matches / elevated,
                // 0 for background). Without the +0.5 the matched disc renders
                // on top and hides the icon for every non-selected node.
                z: {
                    if (isPreview) return 101;
                    const d = root.depthToMatch?.[modelData] ?? Infinity;
                    if (d <= root.elevationDepth) return 50 - d * 5 + 0.5;
                    return 0.5;
                }

                // See the wallpaper delegate: a stencil clip, not a layered mask.
                StyledClippingRect {
                    anchors.fill: parent
                    radius: width / 2

                    Image {
                        anchors.fill: parent
                        readonly property string coverUrl: spDelegate.node?.imageUrl ?? ""
                        source: root.failedImageUrls[coverUrl] ? "" : coverUrl
                        asynchronous: true
                        cache: true
                        onStatusChanged: {
                            if (status === Image.Error && coverUrl)
                                root.failedImageUrls[coverUrl] = true;
                        }
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: {
                            const dpr = Screen.devicePixelRatio || 1;
                            const max = root.previewRadius * 2.0 * dpr;
                            return Qt.size(max, max);
                        }
                    }
                }

            }
        }
    }
}
