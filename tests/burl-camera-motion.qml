import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import qs.components

ShellRoot {
    id: root
    settings.watchFiles: false
    property bool cameraAnimated: true
    property bool cameraMoving: true
    property int panMs: 8000
    property int panEase: Easing.Linear
    property string output: Quickshell.env("CAMERA_TEST_OUTPUT")

    function shot(name, next) {
        console.log("CAMERA-SHOT", name, Date.now());
        CUtils.saveItem(canvas, Qt.resolvedUrl("file://" + output + "/" + name + ".png"), () => {
            console.log("CAMERA-SAVED", name, Date.now());
            next();
        },
            () => { console.error("CAMERA-FAIL", "capture", name); Qt.quit(); });
    }
    FloatingWindow {
        implicitWidth: 240
        implicitHeight: 260
        visible: true
        Rectangle {
            id: canvas
            anchors.fill: parent
            color: "black"
            Rectangle {
                id: marker
                x: 40; y: 20; width: 24; height: 24; color: "#00ff00"
                CameraYBehavior on y { camera: root }
            }
            Rectangle {
                id: fade
                x: 160; y: 20; width: 24; height: 24; color: "#ff0000"
                opacity: 0.25
                CameraOpacityBehavior on opacity { camera: root }
            }
        }
    }
    IpcHandler {
        target: "cameraMotion"
        function move(): void { marker.y = 200; fade.opacity = 1; }
        function reverse(): void { marker.y = 20; fade.opacity = 0.25; }
        function blockGui(): void {
            console.log("CAMERA-BLOCK-BEGIN");
            const end = Date.now() + 250;
            while (Date.now() < end) {}
            console.log("CAMERA-BLOCK-END", "qmlY", marker.y);
        }
        function reduce(): void { root.cameraAnimated = false; }
        function snapReduced(): void { marker.y = 180; fade.opacity = 0.75; }
        function capture(name: string): void { root.shot(name, () => console.log("CAMERA-CAPTURED", name)); }
        function finish(): void { console.log("CAMERA-PASS"); Qt.quit(); }
    }
    Timer { interval: 30000; running: true; onTriggered: { console.error("CAMERA-FAIL timeout"); Qt.quit(); } }
    Component.onCompleted: console.log("CAMERA-READY")
}
