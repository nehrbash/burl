pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import Burl.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/images/ui/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    // burl does not decode video; mpvpaper does, as a child process of the
    // shell. mpvpaper is a wlr-layer-shell client that hands a libmpv render
    // context straight to the compositor, so the video is a real background
    // surface rather than a texture burl has to own -- but its lifetime has to
    // be burl's, because burl's own background window must be transparent for
    // exactly as long as mpvpaper is painting. Owning the process makes that
    // invariant one binding (videoActive) rather than a liveness marker file
    // handed between two supervisors.
    //
    // The selection lives in shell.json (background.video.path/output/speed),
    // so it survives `herd restart quickshell' and comes back on its own --
    // though the video does go down and up across such a restart, which an
    // external supervisor would have avoided.
    //
    // A video has no still for the scheme pipeline to sample, so ffmpeg pulls
    // a representative frame out of it and that is what `burl wallpaper' gets;
    // the palette, templates and thumbnail then follow a video exactly as they
    // follow an image. Extraction needs ffmpeg, which is why
    // burl-video-wallpaper -T survives as the one thing burl shells out for.

    readonly property string videoPath: GlobalConfig.background.video.path
    readonly property string videoOutput: GlobalConfig.background.video.output
    readonly property real videoSpeed: GlobalConfig.background.video.speed
    readonly property bool videoActive: videoDaemon.running
    readonly property list<FileSystemEntry> videoList: videoWallpapers.entries

    readonly property string mpvSocket: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/burl-video-wallpaper.sock`

    // A video already in shell.json when the shell starts: nothing has changed
    // yet, so no onVideoPathChanged fires to bring it up.
    Component.onCompleted: restartVideoDaemon()

    onVideoPathChanged: restartVideoDaemon()
    onVideoOutputChanged: restartVideoDaemon()
    onVideoSpeedChanged: {
        if (!videoActive)
            return;
        if (mpvIpc.connected)
            mpvIpc.pushSpeed();
        else
            mpvIpc.connected = true; // pushes once connected
    }

    onVideoActiveChanged: {
        if (!videoActive)
            mpvIpc.connected = false;
    }

    // An empty `output' means every screen (mpvpaper's own "*"); otherwise it
    // is a space-separated list of connector names.
    function videoActiveFor(screenName: string): bool {
        return videoActive && (videoOutput === "" || videoOutput.split(" ").includes(screenName));
    }

    function setVideoWallpaper(path: string): void {
        // What clearVideoWallpaper() restores. Capture it only when entering
        // video mode: re-picking mid-video would otherwise record the outgoing
        // video's palette frame as if it were a still.
        if (videoPath === "")
            GlobalConfig.background.video.previousStill = actualCurrent;
        GlobalConfig.background.video.path = path;
        videoFrameProc.running = true;
    }

    function clearVideoWallpaper(): void {
        const still = GlobalConfig.background.video.previousStill;
        GlobalConfig.background.video.path = "";
        GlobalConfig.background.video.previousStill = "";
        // Nothing on record (the file was removed, or video mode predates
        // this): leave the palette on the extracted frame rather than guess.
        if (still)
            applyStill(still);
    }

    // mpvpaper cannot survive its outputs changing shape (mode, scale,
    // position, enable): it sizes its EGL window from the wl_output scale seen
    // at the first layer-surface configure and only wl_egl_window_resize()s
    // afterwards, while glViewport keeps the old dimensions -- so the video
    // lands in a sub-rectangle of the output, lower-left, since the GL origin
    // is bottom-left (seen on DP-2, 3840x2160 @ scale 1.5). Rebuilding the
    // surfaces means restarting it. Idempotent, and a no-op with no video set,
    // so callers (Monitors) need no guard.
    function restartVideoDaemon(): void {
        videoDaemon.running = false;
        if (videoPath !== "")
            videoRestartTimer.restart();
    }

    function videoCommand(): list<string> {
        const opts = [
            `speed=${videoSpeed}`,
            `input-ipc-server=${mpvSocket}`,
            "no-config", // a stray ~/.config/mpv/mpv.conf must not break the wallpaper
            "no-audio", // these files do carry an audio track
            "loop-file=inf",
            // Always software decode in practice: mpvpaper forces vo=libmpv
            // with an OpenGL render context, and no Vulkan/VAAPI/VDPAU hwdec
            // frame can attach to that, whatever `mpv --hwdec=help' lists.
            // ~0.73 CPU-s per second of 4K30 H.264, which -p/-a FULL below
            // drops to near zero under a fullscreen window.
            "hwdec=auto-safe",
            "video-sync=display-resample",
            "panscan=1.0", // fill the output, crop rather than letterbox
            "msg-level=all=warn"
        ].join(" ");

        // -p/-a FULL, not -s/-a MAX: Hyprland reports ordinary TILED toplevels
        // as maximised, so MAX auto-stopped the instant any window existed and
        // left a black desktop -- burl had already gone transparent. -p over -s
        // because -s costs a GL context and a first-frame reload per resume.
        // Never -f/--fork: the shell has to keep the child.
        return ["mpvpaper", "-p", "-a", "FULL", "-l", "background", "-o", opts, videoOutput || "*", videoPath];
    }

    Process {
        id: videoDaemon

        stdout: SplitParser {
            onRead: line => console.warn(`mpvpaper: ${line}`)
        }
        stderr: SplitParser {
            onRead: line => console.warn(`mpvpaper: ${line}`)
        }
    }

    Timer {
        id: videoRestartTimer

        // Long enough for the outgoing mpvpaper to release its layer surface;
        // two clients on the background layer at once is undefined stacking.
        interval: 150
        onTriggered: {
            videoDaemon.command = root.videoCommand();
            videoDaemon.running = true;
        }
    }

    Process {
        id: videoFrameProc

        command: ["burl-video-wallpaper", "-T", root.videoPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const frame = text.trim();
                if (frame)
                    root.applyStill(frame);
            }
        }
    }

    // Push a speed change into the running mpv instead of restarting it:
    // mpvpaper forwards input-ipc-server through to libmpv, so this is one
    // JSON line on a unix socket. Held open for as long as the daemon runs --
    // mpv answers every command, and closing straight after the write made it
    // log a broken pipe.
    Socket {
        id: mpvIpc

        function pushSpeed(): void {
            write(`${JSON.stringify({
                command: ["set_property", "speed", root.videoSpeed]
            })}\n`);
            flush();
        }

        path: root.mpvSocket
        onConnectionStateChanged: {
            if (connected)
                pushSpeed();
        }
        parser: SplitParser {
            // mpv replies to every command; nothing here needs the answers,
            // but an unread stream is never drained.
            onRead: () => {}
        }
    }

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["burl", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        // Picking a still is also how you leave video mode.
        if (videoPath !== "")
            clearVideoWallpaper();
        applyStill(path);
    }

    function applyStill(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["burl", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        // Not `list`: Searcher already puts a `list` property on this scope,
        // and a colliding IpcHandler member is silently dropped.
        function listWallpapers(): string {
            return root.list.map(w => w.path).join("\n");
        }

        function setVideo(path: string): void {
            root.setVideoWallpaper(path);
        }

        function clearVideo(): void {
            root.clearVideoWallpaper();
        }

        function setVideoSpeed(speed: real): void {
            GlobalConfig.background.video.speed = speed;
        }

        function getVideo(): string {
            return root.videoPath;
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["burl", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["burl", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: videoWallpapers

        path: Paths.videowallsdir
        filter: FileSystemModel.Files
        // FileSystemModel has no video filter; mpv reads far more than this,
        // but a wallpaper directory holding anything else is not a real case.
        nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi"]
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    Process {
        id: getPreviewColoursProc

        command: ["burl", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
