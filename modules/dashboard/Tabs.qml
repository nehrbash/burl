import QtQuick
import qs.components
import qs.components.controls

Item {
    id: root

    required property real nonAnimWidth
    required property ScreenState screenState
    required property var tabs
    readonly property alias count: bar.count

    implicitHeight: bar.implicitHeight

    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y)
                root.screenState.selectDashboardTab(root.screenState.dashboardTab + (event.angleDelta.y < 0 ? 1 : -1));
        }
    }

    NavigationTabs {
        id: bar
        anchors.fill: parent
        model: root.tabs
        currentIndex: root.screenState.dashboardTab
        onActivated: index => root.screenState.selectDashboardTab(index)
    }
}
