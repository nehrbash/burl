import assert from "node:assert/strict";
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("notification images survive deletion of temporary icon files", { skip: process.env.RUN_QML_NOTIFICATIONS !== "1" }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-notification-images-"));
    try {
        const root = join(dir, "quickshell", "qs");
        mkdirSync(join(root, "services"), { recursive: true });
        mkdirSync(join(root, "utils"));
        mkdirSync(join(dir, "cache"));
        const source = join(dir, "temporary.png");
        const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
        writeFileSync(source, png);
        copyFileSync(new URL("../services/NotifData.qml", import.meta.url), join(root, "services", "NotifData.qml"));
        writeFileSync(join(root, "services", "Hypr.qml"), "pragma Singleton\nimport QtQuick\nQtObject { property bool focusedVisibleFullscreen: false }\n");
        writeFileSync(join(root, "services", "Notifs.qml"), "pragma Singleton\nimport QtQuick\nQtObject { property var list: [] }\n");
        writeFileSync(join(root, "utils", "Paths.qml"), `pragma Singleton
import QtQuick
QtObject { readonly property string notifimagecache: ${JSON.stringify(join(dir, "cache"))} }
`);
        writeFileSync(join(root, "test.qml"), `import QtQuick
import Quickshell
import Burl
import qs.services
ShellRoot {
    id: root
    settings.watchFiles: false
    property NotifData shot: NotifData {
        image: "image://icon/" + ${JSON.stringify(source)}
        appName: "satty"
        summary: "Satty"
        notificationId: "1"
    }
    property NotifData missing: NotifData { image: "image://icon//missing-notification.png" }
    property NotifData themed: NotifData { image: "image://icon/satty" }
    Image {
        id: preview
        onStatusChanged: {
            if (status === Image.Ready) { console.log("NOTIFICATION-IMAGE-PASS"); Qt.quit(); }
            else if (status === Image.Error) { console.log("NOTIFICATION-IMAGE-FAIL"); Qt.quit(); }
        }
    }
    Timer {
        interval: 1; running: true
        onTriggered: {
            if (!root.shot.image.startsWith(${JSON.stringify(join(dir, "cache"))})
                || root.missing.image !== "" || root.themed.image !== "image://icon/satty"
                || !CUtils.deleteFile(Qt.resolvedUrl(${JSON.stringify(source)}))) {
                console.log("NOTIFICATION-IMAGE-FAIL"); Qt.quit(); return;
            }
            preview.source = Qt.resolvedUrl(root.shot.image);
        }
    }
}
`);
        const qml = join(process.env.HOME, ".guix-home/profile/lib/qt6/qml");
        const run = spawnSync("qs", ["-p", join(root, "test.qml")], {
            encoding: "utf8", timeout: 10000,
            env: { ...process.env, QT_QPA_PLATFORM: "wayland", QML_IMPORT_PATH: qml, QML2_IMPORT_PATH: qml }
        });
        const output = run.stdout + run.stderr;
        assert.equal(run.status, 0, output);
        assert.match(output, /NOTIFICATION-IMAGE-PASS/);
        assert.doesNotMatch(output, /NOTIFICATION-IMAGE-FAIL|TypeError|ReferenceError/);
        assert.equal(existsSync(source), false);
        const cached = readdirSync(join(dir, "cache"));
        assert.equal(cached.length, 1);
        assert.deepEqual(readFileSync(join(dir, "cache", cached[0])), png);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
