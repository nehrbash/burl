pragma Singleton

import QtQuick
import Quickshell
import Burl
import Burl.Config
import Burl.Models
import qs.utils

// Screenshot history: one merged, newest-first list over the two directories
// screenshots can live in, plus every command line that acts on a shot.
//
// Saved-vs-unsaved is a FLAG on the entry, not a section: somebody looking for
// "the shot I just took" does not care which directory it is in, and two
// sections would double the scroll chrome inside a 366px card.
//
// The command lines live here (not in the card) so the card, the preview
// overlay and the `screenshots` IPC handler cannot drift apart. Every path is
// passed to `sh -c` as a POSITIONAL argument — never interpolated into the
// script text, or a filename with a quote in it becomes shell injection.
Singleton {
    id: root

    // scripts/burl-screenshot writes fullscreen grabs here, named by a bare
    // timestamp with NO extension (e.g. 20260721125311).
    readonly property string cachedir: `${Paths.cache}/screenshots`
    // The notification's Save action (and ours) moves them here as <ts>.png.
    readonly property string saveddir: `${Paths.pictures}/Screenshots`

    // Hard cap after the sort, so the delegate pool, the label formatting and
    // the thumbnail cache never see the tail of a directory somebody dumped a
    // thousand grabs into.
    readonly property int maxEntries: 200

    // Newest first. Plain JS objects, NOT FileSystemEntry QObjects, so nothing
    // past the cap is retained:
    //   { path, name, base, parentDir, saved, stamp, label }
    property list<var> entries: []
    readonly property var latest: root.entries.length > 0 ? root.entries[0] : null

    // Card expansion. Persisted — a shell reload should not re-collapse the
    // shelf somebody left open.
    property alias expanded: props.expanded

    // The preview overlay is anchored by PATH, not by index: deleting entry 3
    // shifts every index above it, and an index-anchored lightbox would
    // silently start showing a different picture. Deriving the index means a
    // delete of the previewed file closes the overlay on its own, with no
    // cross-component knowledge anywhere.
    property string previewPath
    readonly property int previewIndex: root.indexOfPath(root.previewPath)
    // save() renames the file out from under previewPath. Until the rebuild
    // debounce lands, neither the old nor the new path is in entries; without
    // this the lightbox would collapse mid-save and look like the button did
    // nothing.
    property string pendingSave
    readonly property var previewEntry: root.previewIndex >= 0 ? root.entries[root.previewIndex] : null

    // Thumbnail warm-up gate.
    //
    // On a cache MISS the caching image provider hands back the ORIGINAL image
    // as the texture (plugin Images/cachingimageprovider.cpp:96) and only
    // schedules the downscale in the background. These grabs are 7680x2160, so
    // one miss is a ~66MB texture and six simultaneous misses (a full expanded
    // grid on first open) would be ~400MB of transient VRAM. So exactly ONE
    // uncached thumbnail is admitted at a time; once a path is through, it is
    // free forever (the on-disk cache makes the next load a 165x93 PNG).
    property var warmDone: ({})
    property string warmSlot
    property var warmQueue: []

    function indexOfPath(path: string): int {
        if (!path)
            return -1;
        for (let i = 0; i < root.entries.length; i++)
            if (root.entries[i].path === path)
                return i;
        return -1;
    }

    function rebuild(): void {
        const out = [];

        const collect = (model, saved) => {
            const list = model.entries;
            for (let i = 0; i < list.length; i++) {
                const e = list[i];
                const base = e.baseName;
                // Explicit field-by-field construction. Do NOT use
                // `new Date(...matches.slice(1))` + setMonth(-1) like
                // cards/RecordingList.qml — wrong across month boundaries.
                const m = base.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/);
                const d = m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) : null;
                out.push({
                    path: e.path,
                    name: e.name,
                    base: base,
                    parentDir: e.parentDir,
                    saved: saved,
                    stamp: d ? d.getTime() : 0,
                    label: d ? Qt.formatDateTime(d, Qt.locale()) : base
                });
            }
        };

        collect(cacheModel, false);
        collect(savedModel, true);

        // Sort on the PARSED stamp, not FileSystemModel.sortReverse, so the two
        // directories interleave correctly. Unparseable names sort to the
        // bottom (stamp 0) instead of jumbling the real history.
        out.sort((a, b) => b.stamp - a.stamp || b.name.localeCompare(a.name));

        root.entries = out.slice(0, root.maxEntries);

        if (root.previewPath && root.indexOfPath(root.previewPath) < 0) {
            if (root.pendingSave && root.indexOfPath(root.pendingSave) >= 0) {
                root.previewPath = root.pendingSave;
                root.pendingSave = "";
                pendingSaveTimeout.stop();
            } else if (!root.pendingSave) {
                root.previewPath = "";
            }
        }
    }

    function requestWarm(path: string): void {
        if (!path || root.warmDone[path] || root.warmSlot === path)
            return;
        if (!root.warmQueue.includes(path)) {
            root.warmQueue.push(path);
            root.warmQueueChanged();
        }
        root.pumpWarm();
    }

    function finishWarm(path: string): void {
        if (!path)
            return;
        // Reassign: mutating a var object in place emits no change signal, so
        // the delegates' `allowed` bindings would never re-evaluate.
        const done = Object.assign({}, root.warmDone);
        done[path] = true;
        root.warmDone = done;
        if (root.warmSlot === path) {
            warmTimeout.stop();
            root.warmSlot = "";
        }
        root.pumpWarm();
    }

    function pumpWarm(): void {
        if (root.warmSlot)
            return;
        while (root.warmQueue.length > 0) {
            const next = root.warmQueue.shift();
            root.warmQueueChanged();
            if (!root.warmDone[next]) {
                root.warmSlot = next;
                warmTimeout.restart();
                return;
            }
        }
    }

    function mayWarm(path: string): bool {
        return root.warmSlot === path || (root.warmDone[path] ?? false);
    }

    function openPreview(path: string): void {
        root.previewPath = path;
    }

    function closePreview(): void {
        root.previewPath = "";
    }

    function stepPreview(delta: int): void {
        const i = root.previewIndex;
        if (i < 0)
            return;
        const next = Math.max(0, Math.min(root.entries.length - 1, i + delta));
        root.previewPath = root.entries[next].path;
    }

    // wl-copy reading stdin neither sniffs content nor sees a filename to guess
    // from, so WITHOUT --type an extensionless grab is advertised as
    // text/plain and pastes as garbage into GIMP/Firefox. Every shot burl
    // produces is PNG (grim's default, and CUtils::saveItem writes PNG), so
    // hardcoding the type is correct — do not consult a mime database.
    function copyImage(path: string): void {
        if (!path)
            return;
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", path]);
        Toaster.toast(qsTr("Copied"), qsTr("Screenshot is on the clipboard"), "content_copy");
    }

    // satty is the same editor the screenshot notification's Open action uses.
    // Passing only `-f`: an "edit" must never overwrite the original, so the
    // destination is left to satty's own `output-filename`, which
    // burl-py/burl/data/templates/satty.toml points at the saved-screenshots
    // directory under this service's timestamp convention — so a Ctrl+S in
    // satty shows up in this very list, flagged saved. No `setsid -f` either;
    // execDetached already reparents.
    function edit(path: string): void {
        if (path)
            Quickshell.execDetached(["satty", "-f", path]);
    }

    // mv, not cp — matching the notification's Save action — so the entry flips
    // unsaved -> saved in a single rebuild instead of appearing twice. `-n`
    // guards an existing target.
    function save(path: string, base: string): void {
        if (!path)
            return;
        const target = base.endsWith(".png") ? base : `${base}.png`;
        if (root.previewPath === path) {
            root.pendingSave = `${root.saveddir}/${target}`;
            pendingSaveTimeout.restart();
        }
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && mv -n "$2" "$1/$3"', "sh", root.saveddir, path, target]);
        Toaster.toast(qsTr("Saved"), qsTr("Kept in %1").arg(Paths.shortenHome(root.saveddir)), "bookmark_add");
    }

    // The DIRECTORY, not the file: most file managers hand a FILE argument to
    // its default handler (i.e. open it) but browse into a DIR argument,
    // which is the "reveal" behaviour we want here.
    function reveal(dir: string): void {
        if (dir)
            Quickshell.execDetached([...GlobalConfig.general.apps.explorer, dir]);
    }

    // printf %s, not echo: no trailing newline on the clipboard.
    function copyPath(path: string): void {
        if (!path)
            return;
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", path]);
        Toaster.toast(qsTr("Copied path"), Paths.shortenHome(path), "link");
    }

    function remove(path: string): void {
        if (path)
            CUtils.deleteFile(Qt.resolvedUrl(path));
    }

    PersistentProperties {
        id: props

        property bool expanded: false

        reloadableId: "screenshots"
    }

    // `filter: Images` is the whole reason extensionless grabs can be listed —
    // but ONLY with an explicit "*" name filter. The scan builds its
    // QDirIterator name filters as `nameFilters + "*.<fmt>"` for every format
    // QImageReader supports (plugin Models/filesystemmodel.cpp:296), so with an
    // EMPTY nameFilters list a file called `20260721125311` is dropped by NAME
    // before the QImageReader::canRead() content sniff ever runs. "*" lets
    // every name through to the sniff, which is what actually decides.
    //
    // The sniff also handles the junk that is really in these directories:
    // ~/Pictures/Screenshots holds an `Original/` subdirectory (excluded, the
    // Images scan is QDir::Files only) and a `.screensht.log` (excluded,
    // showHidden is false — which also hides any `.<ts>.part` partial write).
    FileSystemModel {
        id: cacheModel

        path: root.cachedir
        filter: FileSystemModel.Images
        nameFilters: ["*"]
        watchChanges: true
        showHidden: false
        onEntriesChanged: rebuildTimer.restart()
    }

    FileSystemModel {
        id: savedModel

        path: root.saveddir
        filter: FileSystemModel.Images
        nameFilters: ["*"]
        watchChanges: true
        showHidden: false
        onEntriesChanged: rebuildTimer.restart()
    }

    // QFileSystemWatcher fires per directory mutation; the Save action's `mv`
    // mutates both directories, so coalesce the burst into one rebuild.
    Timer {
        id: rebuildTimer

        interval: 150
        onTriggered: root.rebuild()
    }

    // A file that can never be decoded (truncated, racing a write) would
    // otherwise wedge the warm-up queue forever. One timeout, no retry: a
    // permanently unreadable file must not spin.
    // The mv can fail (existing target, full disk). Do not hold a dead preview
    // anchor forever.
    Timer {
        id: pendingSaveTimeout

        interval: 3000
        onTriggered: {
            root.pendingSave = "";
            if (root.previewPath && root.indexOfPath(root.previewPath) < 0)
                root.previewPath = "";
        }
    }

    Timer {
        id: warmTimeout

        interval: 4000
        onTriggered: root.finishWarm(root.warmSlot)
    }
}
