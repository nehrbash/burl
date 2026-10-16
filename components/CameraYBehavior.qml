import QtQuick

Behavior {
    required property var camera
    enabled: camera !== null && camera.cameraAnimated && camera.cameraMoving
    YAnimator {
        duration: camera?.panMs ?? 0
        easing.type: camera?.panEase ?? Easing.Linear
    }
}
