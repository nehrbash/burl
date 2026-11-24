pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        // The flag outlives the shell, so a restart or crash while locked re-locks at startup
        // (Hyprland's allow_session_lock_restore hands the held lock to the new client).
        onLockedChanged: Quickshell.execDetached(["sh", "-c", locked ? `touch "$XDG_RUNTIME_DIR/burl-lock-on-start"` : `rm -f "$XDG_RUNTIME_DIR/burl-lock-on-start"`])

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    Process {
        // greetd's warm login (systems/oceania.scm) and a lock held when the
        // previous shell exited both leave this flag; rm doubles as an atomic claim.
        id: bootLockCheck

        command: ["sh", "-c", `rm "$XDG_RUNTIME_DIR/burl-lock-on-start" 2> /dev/null && echo locked || true`]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "locked")
                    lock.locked = true;
            }
        }
    }

    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false

        // Warm the screencopy backend before the lock needs it: it appears to
        // load async on first request, and the compositor refuses capture
        // once locked, so the lock's own first request can lose that race.
        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: lock.locked = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    IpcHandler {
        function lock(): void {
            lock.locked = true;
        }

        function unlock(): void {
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
