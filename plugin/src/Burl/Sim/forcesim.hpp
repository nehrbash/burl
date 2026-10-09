#pragma once

#include <qlist.h>
#include <qobject.h>
#include <qpoint.h>
#include <qqmlintegration.h>
#include <qtimer.h>
#include <qvariant.h>
#include <qvector.h>

namespace burl::sim {

// d3-force-style force-directed simulation, ported from
// modules/launcher/GraphView.qml's JS simStep(). Holds node positions /
// velocities / radii in parallel float arrays so the per-tick math is
// cache-friendly and free of JS interpreter overhead.
//
// QML owns the *semantic* node list (labels, click callbacks, indices
// into source models) and pushes geometry + tunables into this object
// via setGraph() / setTarget(). The simulation emits positionsChanged
// after each tick; QML re-reads positions on that signal.
//
// Phase 1 of porting: single-thread, ticked from an internal QTimer,
// same algorithm as the QML predecessor.
class ForceSim : public QObject {
    Q_OBJECT
    QML_ELEMENT

    // --- Tunables (defaults mirror the previous QML constants). ---
    Q_PROPERTY(qreal repulsion MEMBER m_repulsion NOTIFY tunablesChanged)
    Q_PROPERTY(qreal cellSize MEMBER m_cellSize NOTIFY tunablesChanged)
    Q_PROPERTY(qreal springLength MEMBER m_springLength NOTIFY tunablesChanged)
    // Extra gap (px) added on top of ri + rj in the hard overlap push.
    // Independent of alpha, so it sets the minimum node spacing at rest.
    Q_PROPERTY(qreal collidePadding MEMBER m_collidePadding NOTIFY tunablesChanged)
    Q_PROPERTY(qreal springK MEMBER m_springK NOTIFY tunablesChanged)
    Q_PROPERTY(qreal damping MEMBER m_damping NOTIFY tunablesChanged)
    Q_PROPERTY(qreal maxSpeed MEMBER m_maxSpeed NOTIFY tunablesChanged)
    Q_PROPERTY(qreal alphaDecay MEMBER m_alphaDecay NOTIFY tunablesChanged)
    Q_PROPERTY(qreal alphaMin MEMBER m_alphaMin NOTIFY tunablesChanged)
    Q_PROPERTY(qreal alphaTarget MEMBER m_alphaTarget NOTIFY tunablesChanged)
    Q_PROPERTY(int simTicks MEMBER m_simTicks NOTIFY tunablesChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY tunablesChanged)
    // When true (default false), the sim self-ticks on an internal
    // QTimer. Leave off and drive from QML's FrameAnimation to match
    // display refresh.
    Q_PROPERTY(bool tickInternally READ tickInternally WRITE setTickInternally NOTIFY tunablesChanged)
    // Number of silent (no-emit) ticks setGraph() runs before exposing
    // positions. Lets the layout converge to near-steady-state so the
    // launcher's first open isn't a tight blob expanding — subsequent
    // reheats still get a full settle from alpha=1.
    Q_PROPERTY(int prewarmTicks MEMBER m_prewarmTicks NOTIFY tunablesChanged)

    // --- Viewport (drives forceCenter translation). ---
    Q_PROPERTY(qreal width MEMBER m_width NOTIFY tunablesChanged)
    Q_PROPERTY(qreal height MEMBER m_height NOTIFY tunablesChanged)

    // --- Lifecycle. ---
    Q_PROPERTY(bool paused MEMBER m_paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(int nodeCount READ nodeCount NOTIFY graphChanged)
    Q_PROPERTY(qreal alpha READ alpha NOTIFY positionsChanged)
    Q_PROPERTY(int tickCount READ tickCount NOTIFY positionsChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    explicit ForceSim(QObject* parent = nullptr);

    // Replace the entire graph in one shot. All arrays must be the same
    // length (nodeCount). Edges hold {sourceIndex, destIndex} into the
    // node arrays.
    Q_INVOKABLE void setGraph(const QList<qreal>& initialX, const QList<qreal>& initialY,
                              const QList<qreal>& radii, const QList<QPoint>& edges);

    // Per-frame target updates from QML's rescore(). attractK <= 0
    // disables attraction (node drifts under repulsion + springs only).
    Q_INVOKABLE void setTarget(int i, qreal targetX, qreal targetY, qreal attractK, qreal radius);

    // When `on` is false, the node is excluded from all force
    // interactions: it doesn't push/pull others, and forces don't act
    // on it. Use this to ghost out off-kind nodes during scope-filter
    // mode (>wallpaper, >apps, etc.) so they don't collide with the
    // filtered cluster ringing up.
    Q_INVOKABLE void setInteractive(int i, bool on);

    // Isolated nodes ignore all repulsion + collide (both directions).
    // Edge springs and target attraction still apply. Used for the
    // "preview at center" pick so other matches don't shove it around.
    Q_INVOKABLE void setIsolated(int i, bool on);

    // Drag interaction. While pinned, forces don't apply and velocity
    // is held at zero.
    Q_INVOKABLE void pin(int i, qreal x, qreal y);
    Q_INVOKABLE void unpin(int i);

    // Reset alpha and start ticking — call after a query / model change
    // to "restart" the sim (d3's restart()). alpha controls how much
    // energy is injected: 1.0 for a full relayout (initial open), lower
    // (~0.4) for incremental nudges (typing, selection) so the cluster
    // makes a small, quick adjustment instead of churning for seconds.
    Q_INVOKABLE void reheat(qreal alpha = 1.0);

    // One simulation step. Normally driven from QML's FrameAnimation
    // (so tick rate matches display refresh — 60/120/240 Hz — and no
    // QTimer drift). Also called by the internal QTimer when tickInternally
    // is true.
    Q_INVOKABLE void step();

    // Read positions back from QML. Cheap; positions are floats in a
    // QVector — Q_INVOKABLE has negligible overhead per call.
    Q_INVOKABLE qreal x(int i) const;
    Q_INVOKABLE qreal y(int i) const;
    Q_INVOKABLE qreal radius(int i) const;

    // Batched per-tick snapshot — interleaved [x, y, r] for every node.
    // QML reads this once on positionsChanged instead of issuing 3
    // Q_INVOKABLE calls per node (× hundreds of nodes) every frame,
    // which is the dominant per-frame cost at high node counts.
    Q_INVOKABLE QList<qreal> snapshot() const;

    // Hit-test in world coords. Returns -1 if no node within
    // (node.r + slop) of (px, py). Iterates back-to-front so visually
    // top nodes win on overlap (matches the QML predecessor).
    Q_INVOKABLE int hitTest(qreal px, qreal py, qreal slop) const;

    // Set a node's position directly (used by drag handler).
    Q_INVOKABLE void setPosition(int i, qreal x, qreal y);

    [[nodiscard]] int nodeCount() const { return m_x.size(); }
    Q_INVOKABLE int ghostCount() const;
    [[nodiscard]] qreal alpha() const { return m_alpha; }
    [[nodiscard]] int tickCount() const { return m_tickCount; }
    // "running" semantically means: there is still work for the sim to
    // do (alpha above min, ticks left, not paused, has nodes). Whether
    // a timer or FrameAnimation is currently driving it is separate.
    [[nodiscard]] bool running() const { return m_running; }
    [[nodiscard]] int interval() const { return m_timer.interval(); }
    [[nodiscard]] bool tickInternally() const { return m_tickInternally; }
    void setInterval(int ms) {
        m_timer.setInterval(ms);
        emit tunablesChanged();
    }
    void setTickInternally(bool on);
    void setPaused(bool p);

signals:
    void positionsChanged();
    void graphChanged();
    void pausedChanged();
    void runningChanged();
    void tunablesChanged();

private:
    void updateRunning();

    QTimer m_timer;
    bool m_tickInternally = false;
    bool m_running = false;

    // Parallel arrays — one per node.
    QVector<float> m_x, m_y, m_vx, m_vy, m_r;
    QVector<float> m_targetX, m_targetY, m_targetR, m_attractK;
    // 0..1 per tick — bigger = snappier radius animation, smaller =
    // gentler. 0.09 gives ~350ms ease-in at 60fps, roughly aligned
    // with the camera Behavior (320ms) + pill fade (260ms) so the
    // preview's grow/shrink synchronises with the camera glide.
    float m_radiusLerp = 0.09f;
    QVector<bool> m_pinned;
    QVector<bool> m_interactive;
    QVector<bool> m_isolated;
    // Scratch per-tick force accumulators (reused across ticks).
    QVector<float> m_fx, m_fy;
    // Spatial grid scratch — bin index -> node indices.
    QVector<QVector<qint32>> m_grid;

    QVector<QPair<qint32, qint32>> m_edges;
    // Per-node edge degree — used to scale spring force by 1/sqrt(deg)
    // on each endpoint so high-degree hubs don't get yanked by the
    // sum of N spoke springs.
    QVector<qint32> m_degree;

    qreal m_alpha = 1.0;
    int m_simTicksLeft = 0;
    qint64 m_tickCount = 0;

    // Tunables — defaults match GraphView.qml constants.
    qreal m_repulsion = 1400.0;
    qreal m_cellSize = 220.0;
    qreal m_springLength = 90.0;
    qreal m_collidePadding = 2.0;
    qreal m_springK = 0.20;
    qreal m_damping = 0.40;
    qreal m_maxSpeed = 30.0;
    // Decay slower than d3's 0.0228 because we soften match attract
    // (rescore() halves attractMatchK) — forces are weaker so the sim
    // needs more ticks to reach equilibrium before alpha stops it.
    qreal m_alphaDecay = 0.035;
    qreal m_alphaMin = 0.001;
    qreal m_alphaTarget = 0.0;
    int m_simTicks = 600;
    int m_prewarmTicks = 280;   // ~ enough for alpha to decay below alphaMin
    qreal m_width = 0.0;
    qreal m_height = 0.0;

    bool m_paused = false;
    // When set, step() skips the positionsChanged emit + running
    // checks so we can iterate the sim silently in setGraph() for the
    // prewarm pass.
    bool m_silent = false;
};

} // namespace burl::sim
