pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl

Singleton {
    id: root

    // Normalised: { title, start, end (ms), allDay, calendar, location, link }
    property var events: []
    property bool viaEmacs: false

    readonly property date now: Time.date
    readonly property var dayStart: new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    readonly property var dayEnd: dayStart + 86400000
    readonly property var tomorrowEnd: dayEnd + 86400000

    readonly property var allDayToday: events.filter(e => e.allDay && e.start < dayEnd && e.end > dayStart)
    readonly property var upcoming: events.filter(e => !e.allDay && e.end > now.getTime())
    readonly property var next: upcoming.length ? upcoming[0] : null
    readonly property var laterToday: upcoming.filter(e => e !== next && e.start < dayEnd)
    readonly property var tomorrow: events.filter(e => e.start >= dayEnd && e.start < tomorrowEnd)

    function _norm(e): var {
        // Date-only ISO strings parse as UTC; force local midnight.
        const ms = v => new Date(v.length === 10 ? v + "T00:00:00" : v).getTime();
        const start = ms(e.start);
        let end = e.end ? ms(e.end) : start;
        if (e.allDay)
            end = Math.max(end, start + 86400000);
        return {
            title: e.title ?? "",
            start,
            end: Math.max(end, start),
            allDay: !!e.allDay,
            calendar: e.calendar ?? "personal",
            location: e.location ?? "",
            link: e.link ?? ""
        };
    }

    function _sort(list: var): var {
        return list.filter(e => !isNaN(e.start)).sort((a, b) => a.start - b.start);
    }

    function _fromParser(): void {
        const out = [];
        for (const e of (CalendarSources.events ?? [])) {
            const day = e.date + "T";
            out.push(_norm({
                title: e.title,
                start: e.allDay ? day + "00:00:00" : day + e.time + ":00",
                end: e.allDay ? "" : day + (e.endTime || e.time) + ":00",
                allDay: e.allDay,
                calendar: e.calendar,
                location: e.location,
                link: e.link
            }));
        }
        events = _sort(out);
        viaEmacs = false;
    }

    property bool _again: false

    function refresh(): void {
        if (proc.running)
            _again = true;
        else
            proc.running = true;
    }

    function _unquote(raw: string): string {
        let s = (raw ?? "").trim();
        if (s.startsWith("\"") && s.endsWith("\""))
            s = s.slice(1, -1).replace(/\\"/g, "\"").replace(/\\\\/g, "\\").replace(/\\n/g, "\n");
        return s;
    }

    // Emacs owns the org-gcal files, so its JSON is authoritative; the C++ org
    // parser keeps the card alive when the daemon is down or lacks the function.
    Process {
        id: proc

        command: {
            const fixture = Quickshell.env("BURL_CALENDAR_JSON");
            return fixture ? ["cat", fixture] : ["timeout", "10", "emacsclient", "-e", "(sn-gcal/upcoming 168)"];
        }
        stdout: StdioCollector {
            id: out
        }
        onExited: code => {
            try {
                if (code !== 0)
                    throw new Error("emacsclient failed");
                const list = JSON.parse(root._unquote(out.text));
                root.events = root._sort(list.map(root._norm));
                root.viaEmacs = true;
            } catch (e) {
                root._fromParser();
            }
            if (root._again) {
                root._again = false;
                rerun.start();
            }
        }
    }

    Timer {
        id: rerun

        interval: 100
        onTriggered: root.refresh()
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: CalendarSources

        function onEventsChanged(): void {
            root.refresh();
        }
    }
}
