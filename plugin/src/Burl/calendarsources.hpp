#pragma once

#include <qfilesystemwatcher.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

namespace burl {

// Parses an org-gcal agenda file (~/doc/gcal.org) into upcoming-event
// nodes for the launcher graph. Each top-level `* Heading` with an active
// `<YYYY-MM-DD ...>` timestamp becomes an event; past events are dropped.
//
// dayLinks clusters events by calendar day: every event on a given day
// links to the earliest event that day, so a busy day reads as a cluster.
//
// This is a plain text file (not SQLite), parsed with a regex sweep and
// re-read, debounced, whenever org-gcal rewrites it.
class CalendarSources : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString agendaFile READ agendaFile WRITE setAgendaFile NOTIFY agendaFileChanged)
    // How many days ahead to include (0 = today only).
    Q_PROPERTY(int horizonDays READ horizonDays WRITE setHorizonDays NOTIFY horizonDaysChanged)

    Q_PROPERTY(QVariantList events READ events NOTIFY eventsChanged)
    // Edges: { source: eventId, dest: dayHubEventId }.
    Q_PROPERTY(QVariantList dayLinks READ dayLinks NOTIFY eventsChanged)

public:
    explicit CalendarSources(QObject* parent = nullptr);

    [[nodiscard]] QString agendaFile() const { return m_agendaFile; }
    void setAgendaFile(const QString& path);

    [[nodiscard]] int horizonDays() const { return m_horizonDays; }
    void setHorizonDays(int n);

    [[nodiscard]] QVariantList events() const { return m_events; }
    [[nodiscard]] QVariantList dayLinks() const { return m_dayLinks; }

    Q_INVOKABLE void reload();

signals:
    void agendaFileChanged();
    void horizonDaysChanged();
    void eventsChanged();

private:
    void rewatch();
    void scheduleReload();

    QString m_agendaFile;
    int m_horizonDays = 30;

    QVariantList m_events;
    QVariantList m_dayLinks;

    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace burl
