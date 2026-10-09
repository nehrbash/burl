#include "forcesim.hpp"

#include <cmath>
#include <qloggingcategory.h>

Q_LOGGING_CATEGORY(lcForceSim, "burl.sim.forcesim", QtInfoMsg)

namespace burl::sim {

ForceSim::ForceSim(QObject* parent)
    : QObject(parent) {
    // The internal QTimer is opt-in via tickInternally. Default is
    // off — drive step() from QML's FrameAnimation so the tick rate
    // tracks display refresh.
    m_timer.setInterval(24);
    m_timer.setSingleShot(false);
    connect(&m_timer, &QTimer::timeout, this, &ForceSim::step);
}

void ForceSim::setGraph(const QList<qreal>& initialX, const QList<qreal>& initialY,
                        const QList<qreal>& radii, const QList<QPoint>& edges) {
    const int n = initialX.size();
    if (initialY.size() != n || radii.size() != n) {
        qCWarning(lcForceSim) << "setGraph: parallel array sizes differ"
                              << initialX.size() << initialY.size() << radii.size();
        return;
    }

    m_x.resize(n);
    m_y.resize(n);
    m_vx.assign(n, 0.0f);
    m_vy.assign(n, 0.0f);
    m_r.resize(n);
    m_targetX.assign(n, 0.0f);
    m_targetY.assign(n, 0.0f);
    m_targetR.resize(n);
    m_attractK.assign(n, 0.0f);
    m_pinned.assign(n, false);
    m_interactive.assign(n, true);
    m_isolated.assign(n, false);
    m_fx.assign(n, 0.0f);
    m_fy.assign(n, 0.0f);

    for (int i = 0; i < n; ++i) {
        m_x[i] = static_cast<float>(initialX[i]);
        m_y[i] = static_cast<float>(initialY[i]);
        m_r[i] = static_cast<float>(radii[i]);
        m_targetR[i] = m_r[i];
    }

    m_edges.clear();
    m_edges.reserve(edges.size());
    m_degree.assign(n, 0);
    for (const auto& e : edges) {
        if (e.x() >= 0 && e.x() < n && e.y() >= 0 && e.y() < n && e.x() != e.y()) {
            m_edges.append({ e.x(), e.y() });
            m_degree[e.x()] += 1;
            m_degree[e.y()] += 1;
        }
    }

    m_alpha = 1.0;
    m_simTicksLeft = m_simTicks;

    // A brief prewarm (small enough to be invisible — ~40 ticks at
    // ~10ms total) takes the worst of the initial collision-resolve
    // out of the user's first frame, but leaves enough alpha for the
    // sim to settle visibly afterwards. With the wider relayout seed
    // (45%) this is plenty.
    if (n > 1 && m_prewarmTicks > 0 && m_width > 0.0 && m_height > 0.0) {
        m_silent = true;
        const int budget = std::min(m_prewarmTicks, 110);
        for (int t = 0; t < budget; ++t) {
            m_alpha = 1.0;
            m_simTicksLeft = 2;
            step();
        }
        m_silent = false;
        // Hand off to the visible sim with a full tick budget but a
        // *reduced* alpha — the prewarm has already untangled the bulk
        // of the overlap silently, so the user sees a gentle final
        // settle instead of the full expansion from alpha=1.
        m_simTicksLeft = m_simTicks;
        m_alpha = 0.55;
    }

    emit graphChanged();
    emit positionsChanged();
    updateRunning();
}

void ForceSim::setTarget(int i, qreal targetX, qreal targetY, qreal attractK, qreal radius) {
    if (i < 0 || i >= m_x.size()) return;
    m_targetX[i] = static_cast<float>(targetX);
    m_targetY[i] = static_cast<float>(targetY);
    m_attractK[i] = static_cast<float>(attractK);
    // Don't snap the radius — store as target and ease toward it in
    // step(). Grow / shrink animates over a few hundred ms.
    m_targetR[i] = static_cast<float>(radius);
}

void ForceSim::pin(int i, qreal px, qreal py) {
    if (i < 0 || i >= m_x.size()) return;
    m_pinned[i] = true;
    m_x[i] = static_cast<float>(px);
    m_y[i] = static_cast<float>(py);
    m_vx[i] = 0.0f;
    m_vy[i] = 0.0f;
}

void ForceSim::unpin(int i) {
    if (i < 0 || i >= m_x.size()) return;
    m_pinned[i] = false;
}

void ForceSim::setInteractive(int i, bool on) {
    if (i < 0 || i >= m_interactive.size()) return;
    m_interactive[i] = on;
}

void ForceSim::setIsolated(int i, bool on) {
    if (i < 0 || i >= m_isolated.size()) return;
    m_isolated[i] = on;
}

// Debug helper — returns the current ghost count. Wire from QML to
// verify rescore() is flagging off-kind nodes.
int ForceSim::ghostCount() const {
    int g = 0;
    for (bool b : m_interactive) if (!b) ++g;
    return g;
}

void ForceSim::reheat(qreal alpha) {
    if (m_x.isEmpty()) return;
    m_alpha = std::max(static_cast<qreal>(m_alphaMin), alpha);
    m_simTicksLeft = m_simTicks;
    updateRunning();
}

qreal ForceSim::x(int i) const { return (i >= 0 && i < m_x.size()) ? m_x[i] : 0.0; }
qreal ForceSim::y(int i) const { return (i >= 0 && i < m_y.size()) ? m_y[i] : 0.0; }
qreal ForceSim::radius(int i) const { return (i >= 0 && i < m_r.size()) ? m_r[i] : 0.0; }

QList<qreal> ForceSim::snapshot() const {
    const int n = m_x.size();
    QList<qreal> out;
    out.reserve(n * 3);
    for (int i = 0; i < n; ++i) {
        out.append(m_x[i]);
        out.append(m_y[i]);
        out.append(m_r[i]);
    }
    return out;
}

int ForceSim::hitTest(qreal px, qreal py, qreal slop) const {
    const int n = m_x.size();
    for (int i = n - 1; i >= 0; --i) {
        const float dx = static_cast<float>(px) - m_x[i];
        const float dy = static_cast<float>(py) - m_y[i];
        const float r = m_r[i] + static_cast<float>(slop);
        if (dx * dx + dy * dy <= r * r) return i;
    }
    return -1;
}

void ForceSim::setPosition(int i, qreal px, qreal py) {
    if (i < 0 || i >= m_x.size()) return;
    m_x[i] = static_cast<float>(px);
    m_y[i] = static_cast<float>(py);
}

void ForceSim::setPaused(bool p) {
    if (m_paused == p) return;
    m_paused = p;
    emit pausedChanged();
    updateRunning();
}

void ForceSim::setTickInternally(bool on) {
    if (m_tickInternally == on) return;
    m_tickInternally = on;
    emit tunablesChanged();
    updateRunning();
}

void ForceSim::updateRunning() {
    const bool want = !m_paused
                      && !m_x.isEmpty()
                      && m_simTicksLeft > 0
                      && m_alpha >= m_alphaMin;
    if (want != m_running) {
        m_running = want;
        emit runningChanged();
    }
    if (m_tickInternally) {
        if (m_running && !m_timer.isActive()) m_timer.start();
        else if (!m_running && m_timer.isActive()) m_timer.stop();
    } else if (m_timer.isActive()) {
        m_timer.stop();
    }
}

// One tick of the spatial-grid force-directed step. Mirrors the JS
// simStep in GraphView.qml. Keep the algorithm identical so behaviour
// is preserved during the QML → C++ cutover.
void ForceSim::step() {
    const int n = m_x.size();
    if (n == 0 || m_paused || m_simTicksLeft <= 0 || m_alpha < m_alphaMin) {
        if (m_running) updateRunning();
        return;
    }

    const float a = static_cast<float>(m_alpha);
    const float cell = static_cast<float>(m_cellSize);
    const float cell2 = cell * cell;
    const float cxv = static_cast<float>(m_width) * 0.5f;
    const float cyv = static_cast<float>(m_height) * 0.5f;

    const int cols = std::max(1, static_cast<int>(std::ceil(m_width / cell)));
    const int rows = std::max(1, static_cast<int>(std::ceil(m_height / cell)));
    const int need = cols * rows;
    if (m_grid.size() < need) m_grid.resize(need);
    for (int k = 0; k < need; ++k) m_grid[k].clear();

    auto clampi = [](int v, int lo, int hi) {
        return std::min(hi, std::max(lo, v));
    };

    // Single shared grid; the force loop filters neighbours by group
    // (interactive flag), so each group runs its own physics without
    // seeing the other. Cheaper than maintaining two grids for the
    // node counts we deal with.
    for (int i = 0; i < n; ++i) {
        const int gx = clampi(static_cast<int>(std::floor(m_x[i] / cell)), 0, cols - 1);
        const int gy = clampi(static_cast<int>(std::floor(m_y[i] / cell)), 0, rows - 1);
        m_grid[gy * cols + gx].append(i);
    }

    // Repulsion + soft overlap resolution. Each node interacts only
    // with the 9-cell neighbourhood (its own cell + 8 surrounding) —
    // O(n · k) for small k, regardless of total node count.
    for (int i = 0; i < n; ++i) {
        m_fx[i] = 0.0f;
        m_fy[i] = 0.0f;
        float fx = 0.0f;
        float fy = 0.0f;
        const float xi = m_x[i];
        const float yi = m_y[i];
        const float ri = m_r[i];
        const bool inter_i = m_interactive[i];
        const bool isolated_i = m_isolated[i];

        // Isolated nodes (the preview pick) skip the *repulsion* loop
        // — they don't get shoved by the ring — but still feel target
        // attraction below so they hold at the centre. Skipping the
        // outer loop entirely (the previous version) zeroed their
        // forces and made them drift, then forceCenter rocked them.
        if (!isolated_i) {
            const int gx = clampi(static_cast<int>(std::floor(xi / cell)), 0, cols - 1);
            const int gy = clampi(static_cast<int>(std::floor(yi / cell)), 0, rows - 1);
            for (int dy = -1; dy <= 1; ++dy) {
                const int cy2 = gy + dy;
                if (cy2 < 0 || cy2 >= rows) continue;
                for (int dx = -1; dx <= 1; ++dx) {
                    const int cx2 = gx + dx;
                    if (cx2 < 0 || cx2 >= cols) continue;
                    const auto& bucket = m_grid[cy2 * cols + cx2];
                    for (qint32 j : bucket) {
                        if (i == j) continue;
                        if (m_interactive[j] != inter_i) continue;
                        float ddx = xi - m_x[j];
                        float ddy = yi - m_y[j];
                        float d2 = ddx * ddx + ddy * ddy;
                        if (d2 > cell2) continue;
                        if (d2 < 1.0f) {
                            ddx = static_cast<float>(i - j);
                            ddy = 1.0f;
                            d2 = ddx * ddx + 1.0f;
                        }
                        const float dist = std::sqrt(d2);

                        // Coulomb-ish repulsion, alpha-scaled.
                        const float inv = (static_cast<float>(m_repulsion) / d2) * a;
                        fx += (ddx / dist) * inv;
                        fy += (ddy / dist) * inv;

                        // Hard overlap push (forceCollide). Independent of
                        // alpha so dense clusters stop overlapping at rest.
                        // Isolated nodes (preview pick) get a 1.4x
                        // "personal space" padding so spring-linked
                        // neighbours don't get yanked inside the disc.
                        const float rj_eff = m_isolated[j] ? m_r[j] * 1.7f : m_r[j];
                        const float minDist = ri + rj_eff + static_cast<float>(m_collidePadding);
                        if (dist < minDist) {
                            const float push = (minDist - dist) * 0.5f;
                            fx += (ddx / dist) * push;
                            fy += (ddy / dist) * push;
                        }
                    }
                }
            }
        }

        // Target attraction (only when QML set attractK > 0 — e.g. the
        // match ring or the rest pull during a query).
        if (m_attractK[i] > 0.0f) {
            const float k = m_attractK[i] * a;
            fx += (m_targetX[i] - xi) * k;
            fy += (m_targetY[i] - yi) * k;
        }

        m_fx[i] = fx;
        m_fy[i] = fy;
    }

    // Edge springs (alpha-scaled). Cross-group: relationship springs
    // *do* fire across the interactive boundary so an unselected node
    // tied to a matched one gets pulled along with the cluster. Only
    // repulsion / collide stay group-local.
    const float sk = static_cast<float>(m_springK);
    const float sl = static_cast<float>(m_springLength);
    for (const auto& e : m_edges) {
        const qint32 i = e.first;
        const qint32 j = e.second;
        const float dx = m_x[j] - m_x[i];
        const float dy = m_y[j] - m_y[i];
        const float dist = std::max(0.001f, std::sqrt(dx * dx + dy * dy));
        // Effective rest length is at least the collide distance —
        // otherwise the spring tries to pull spokes inside the hub's
        // radius and fights forceCollide forever, producing the
        // permanent oscillation around a large hub.
        const float ri_eff = m_isolated[i] ? m_r[i] * 1.7f : m_r[i];
        const float rj_eff = m_isolated[j] ? m_r[j] * 1.7f : m_r[j];
        const float sl_eff = std::max(sl, ri_eff + rj_eff + static_cast<float>(m_collidePadding));
        const float force = (dist - sl_eff) * sk * a;
        const float ux = dx / dist;
        const float uy = dy / dist;
        // Degree-normalised spring (d3's bias trick): each endpoint
        // feels force / sqrt(its degree), so a hub with 100 spokes
        // doesn't get summed-yanked while each spoke still feels a
        // proper pull. Without this, large clusters never settle.
        const float ki = 1.0f / std::sqrt(static_cast<float>(std::max<qint32>(1, m_degree[i])));
        const float kj = 1.0f / std::sqrt(static_cast<float>(std::max<qint32>(1, m_degree[j])));
        // Isolated endpoints (the pinned preview pick) only emit
        // pull — spokes get tugged toward the hub, but the hub
        // doesn't get yanked around by N spokes summing unevenly.
        if (!m_isolated[i]) {
            m_fx[i] += ux * force * ki;
            m_fy[i] += uy * force * ki;
        }
        if (!m_isolated[j]) {
            m_fx[j] -= ux * force * kj;
            m_fy[j] -= uy * force * kj;
        }
    }

    // Integrate. Damping = 1 - velocityDecay. Speed clamped.
    const float decay = 1.0f - static_cast<float>(m_damping);
    const float maxS = static_cast<float>(m_maxSpeed);
    for (int i = 0; i < n; ++i) {
        if (m_pinned[i]) {
            m_vx[i] = 0.0f;
            m_vy[i] = 0.0f;
            continue;
        }
        m_vx[i] = (m_vx[i] + m_fx[i]) * decay;
        m_vy[i] = (m_vy[i] + m_fy[i]) * decay;
        const float sp = std::sqrt(m_vx[i] * m_vx[i] + m_vy[i] * m_vy[i]);
        if (sp > maxS) {
            const float s = maxS / sp;
            m_vx[i] *= s;
            m_vy[i] *= s;
        }
        m_x[i] += m_vx[i];
        m_y[i] += m_vy[i];
    }

    // forceCenter: rigid translation that pins the *interactive*
    // cluster's centroid to the viewport center. Translation is
    // applied only to interactive nodes so ghosts (off-kind in scope
    // mode) stay precisely where they were — no wobble from the
    // in-kind cluster's centroid shifting.
    if (m_width > 0.0 && m_height > 0.0) {
        float mx = 0.0f;
        float my = 0.0f;
        int counted = 0;
        for (int i = 0; i < n; ++i) {
            if (!m_interactive[i] || m_isolated[i]) continue;
            mx += m_x[i];
            my += m_y[i];
            ++counted;
        }
        if (counted > 0) {
            mx /= counted;
            my /= counted;
            const float sx = cxv - mx;
            const float sy = cyv - my;
            // Isolated nodes (the pinned preview pick) are excluded
            // from both centroid and translation so the cluster shifts
            // around them without rocking the centre.
            for (int i = 0; i < n; ++i) {
                if (!m_interactive[i] || m_isolated[i]) continue;
                m_x[i] += sx;
                m_y[i] += sy;
            }
        }
    }

    // Ease each node's actual radius toward its target. Same lerp
    // rate everyone, so grow/shrink animations stay in sync across
    // the cluster. Animation continues while the cluster is moving
    // (alpha > min), which is the period the sim is already ticking.
    for (int i = 0; i < n; ++i) {
        m_r[i] += (m_targetR[i] - m_r[i]) * m_radiusLerp;
    }

    // d3 alpha cool-down.
    m_alpha = m_alpha + (m_alphaTarget - m_alpha) * m_alphaDecay;
    m_simTicksLeft -= 1;
    m_tickCount += 1;

    if (!m_silent) emit positionsChanged();

    if (!m_silent && (m_simTicksLeft <= 0 || m_alpha < m_alphaMin)) updateRunning();
}

} // namespace burl::sim
