pragma Singleton

import QtQuick
import Quickshell
import Burl.Config

// A single looping phase (radians) that EVERY Sway/Breathe instance reads.
// The performance law forbids N independent animators for N swaying icons:
// one animation ticks, the rest are plain bindings on `phase`.
// Runs only while at least one active subscriber exists and Ambience allows it.
//
// Idle cost: zero — with no subscribers the animation is genuinely stopped
// (not paused), so nothing is registered with Qt's animation timer and no
// binding re-evaluates.
Singleton {
    id: root

    property real phase: 0
    // Incremented/decremented by Sway/Breathe as they become active.
    property int subscribers: 0

    // Where the last run left off, so a restart resumes mid-swing instead of
    // snapping to 0. Not `running: true; paused: ...` — a paused animation
    // stays registered with Qt's timer and keeps ticking the GUI thread
    // with nothing swaying.
    property real _resumePhase: 0

    NumberAnimation {
        target: root
        property: "phase"
        // sin() is 2π-periodic, so a loop running φ₀ → φ₀+2π is continuous at
        // both ends for every subscriber — resuming needs no more than this.
        from: root._resumePhase
        to: root._resumePhase + Math.PI * 2
        duration: Tokens.anim.durations.extraLarge * 4 // 4000ms full cycle
        loops: Animation.Infinite
        running: Ambience.sway && root.subscribers > 0
        onRunningChanged: if (!running)
            root._resumePhase = root.phase % (Math.PI * 2)
    }
}
