import QtQuick

Behavior {
    required property var camera
    enabled: camera !== null && camera.cameraAnimated && camera.cameraMoving
    OpacityAnimator {
        duration: camera?.panMs ?? 0
        easing.type: camera?.panEase ?? Easing.Linear
    }
}
