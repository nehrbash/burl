import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property bool hibernateSetting: false
    readonly property bool checked: hibernateSetting ? IdleInhibitor.hibernateAfterSleep : IdleInhibitor.enabled
    readonly property bool showActiveSince: !hibernateSetting && IdleInhibitor.enabled

    readonly property real nonAnimHeight: layout.implicitHeight + (showActiveSince ? activeChip.implicitHeight + activeChip.anchors.topMargin : 0) + Tokens.padding.extraLargeIncreased

    Layout.fillWidth: true
    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    WoodPanel {
        anchors.fill: parent
    }

    BarkFrame {
        anchors.fill: parent
        radius: parent.radius
        frameWidth: 3
    }

    RowLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.large

            radius: Tokens.rounding.full
            color: root.checked ? Woodland.brass : Woodland.velvet

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: root.hibernateSetting ? "downloading" : "coffee"
                color: root.checked ? Colours.palette.m3onPrimary : Woodland.ivory
                fontStyle: Tokens.font.icon.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.hibernateSetting ? qsTr("Auto Hibernate") : qsTr("Keep Awake")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.hibernateSetting
                    ? (root.checked ? qsTr("Hibernate after sleeping") : qsTr("Sleep only"))
                    : (root.checked ? qsTr("Prevent lock and sleep") : qsTr("Normal power management"))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }

        StyledSwitch {
            checked: root.checked
            onToggled: {
                if (root.hibernateSetting)
                    IdleInhibitor.hibernateAfterSleep = checked;
                else
                    IdleInhibitor.enabled = checked;
            }
        }
    }

    Loader {
        id: activeChip

        asynchronous: true
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: Tokens.spacing.large
        anchors.bottomMargin: root.showActiveSince ? Tokens.padding.large : -implicitHeight
        anchors.leftMargin: Tokens.padding.large

        opacity: root.showActiveSince ? 1 : 0
        scale: root.showActiveSince ? 1 : 0.5

        Component.onCompleted: active = Qt.binding(() => opacity > 0)

        sourceComponent: StyledRect {
            implicitWidth: activeText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: activeText.implicitHeight + Tokens.padding.small

            radius: Tokens.rounding.full
            color: Woodland.brass

            StyledText {
                id: activeText

                anchors.centerIn: parent
                text: qsTr("Active since %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, GlobalConfig.services.useTwelveHourClock ? "hh:mm a" : "hh:mm"))
                color: Colours.palette.m3onPrimary
                font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.9)).build()
            }
        }

        Behavior on anchors.bottomMargin {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
