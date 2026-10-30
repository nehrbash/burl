import QtQuick
import Quickshell
import qs.services
import qs.modules.tasknudge
ShellRoot {
    id: root
    settings.watchFiles: false
    TaskNudge { id: nudge }
    function snapshot(rest) {
        Tasks._parseSnapshot(JSON.stringify({
            generated_at: Date.now()/1000,
            pomodoro: {enabled: true, "clocked-in": true, "on-break": rest,
                       "remaining-seconds": 300, "total-seconds": 300},
            prefs: {"clock-in-reminders": false}
        }));
    }
    function check(value, message) {
        if (!value) throw new Error(message);
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            try {
                root.snapshot(true);
                root.check(nudge.shouldShow, "break opens");
                Tasks.endBreak();
                root.check(!nudge.shouldShow, "end closes without Emacs");
                root.snapshot(true);
                root.check(!nudge.shouldShow, "stale snapshot stays closed");
                root.snapshot(false);
                root.snapshot(true);
                root.check(nudge.shouldShow, "next break opens");
                Tasks.stopPomodoro();
                root.check(!nudge.shouldShow, "stop closes without Emacs");
                root.snapshot(false);
                root.snapshot(true);
                nudge.dismiss();
                root.check(!nudge.shouldShow, "local dismissal closes break");
                console.log("BREAK-DISMISS-PASS");
            } catch (e) {
                console.error("BREAK-DISMISS-FAIL", e);
            }
            Qt.quit();
        }
    }
}
