import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool active: false
    property var queries: []
    property string directory: Quickshell.env("BURL_FILE_SEARCH_ROOT") || Quickshell.env("HOME")
    property string executable: "burl-file-search"
    property var entries: []
    property string error: ""
    property bool truncated: false
    property bool loading: false
    property int generation: 0
    property var currentJob: null
    readonly property var eligibleQueries: queries.filter(q => {
        let pattern = q.trim();
        if (pattern.startsWith("re:")) {
            pattern = pattern.slice(3);
            if (pattern.startsWith("/")) pattern = pattern.slice(1).replace(/\/$/, "");
        }
        return pattern.replace(/\s/g, "").length >= 3;
    })
    readonly property string status: !active ? ""
        : !eligibleQueries.length ? qsTr("Type at least 3 characters to search files")
        : error ? error
        : loading ? qsTr("Searching files…")
        : truncated ? qsTr("%1 files · search limit reached").arg(entries.length)
        : qsTr("%1 files").arg(entries.length)

    onActiveChanged: schedule()
    onEligibleQueriesChanged: schedule()
    onDirectoryChanged: schedule()
    onExecutableChanged: schedule()

    function cancel(): void {
        ++generation;
        debounce.stop();
        const job = currentJob;
        currentJob = null;
        if (job && job.running) job.signal(9);
        loading = false;
    }

    function schedule(): void {
        cancel();
        entries = [];
        error = "";
        truncated = false;
        if (active && eligibleQueries.length) {
            loading = true;
            debounce.restart();
        }
    }

    function finish(job: var, code: int, exitStatus: int): void {
        if (job !== currentJob || job.generation !== generation) return;
        currentJob = null;
        loading = false;
        if (code !== 0 || exitStatus !== 0) {
            error = qsTr("File search failed");
            return;
        }
        try {
            const result = JSON.parse(job.output);
            if (!Array.isArray(result.entries)) throw new Error("Invalid search response");
            error = result.error || "";
            truncated = !!result.truncated;
            entries = error ? [] : result.entries.slice(0, 60).filter(entry =>
                typeof entry.path === "string" && entry.path.startsWith("/")
                && typeof entry.label === "string" && Array.isArray(entry.queries));
        } catch (exception) {
            error = qsTr("Cannot read file search results");
        }
    }

    Timer {
        id: debounce
        interval: 220
        onTriggered: {
            const command = [root.executable, "--root", root.directory];
            for (const query of root.eligibleQueries) command.push("--query", query);
            const job = worker.createObject(root, {command, generation: root.generation});
            root.currentJob = job;
            job.running = true;
        }
    }

    Component {
        id: worker
        Process {
            id: process
            property int generation
            property bool didStart: false
            readonly property string output: collector.text
            stdout: StdioCollector { id: collector }
            stderr: StdioCollector {}
            onStarted: didStart = true
            onExited: (code, status) => {
                root.finish(process, code, status);
                destroy();
            }
            onRunningChanged: if (!running && !didStart) {
                root.finish(process, -1, 1);
                destroy();
            }
            property Timer watchdog: Timer {
                interval: 5000
                running: process.running
                onTriggered: {
                    if (root.currentJob === process) {
                        root.currentJob = null;
                        root.loading = false;
                        root.error = qsTr("File search timed out; narrow your query");
                    }
                    process.signal(9);
                }
            }
        }
    }

    Component.onDestruction: cancel()
}
