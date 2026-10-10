import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Temperature units (index 0 = Celsius, 1 = Fahrenheit — matches Weather.formatTemp)
    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: "°C"
        },
        MenuItem {
            text: "°F"
        }
    ]

    // Clock format (index 0 = 24-hour, 1 = 12-hour — matches Time.useTwelveHourClock)
    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: qsTr("24-hour")
        },
        MenuItem {
            text: qsTr("12-hour")
        }
    ]

    function applyLocation(): void {
        const location = locationField.text.trim();
        if (location === GlobalConfig.services.weatherLocation)
            Weather.reload(true);
        else
            GlobalConfig.services.weatherLocation = location;
    }

    title: qsTr("Language & region")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Language")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: localeLayout.implicitHeight + localeLayout.anchors.margins * 2

            RowLayout {
                id: localeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("System language")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("System locale (%1); configured outside Burl").arg(Qt.locale().name)
                        color: Woodland.creamSecondary
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    text: Qt.locale().nativeLanguageName || Qt.locale().name
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        SectionHeader {
            text: qsTr("Weather")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: locationLayout.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: locationLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledTextField {
                    id: locationField

                    Layout.fillWidth: true
                    text: GlobalConfig.services.weatherLocation
                    placeholderText: qsTr("City or latitude, longitude")
                    supportingText: qsTr("Leave empty to detect your location from your IP address")
                    onAccepted: root.applyLocation()
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Weather.locating ? qsTr("Looking up location…") : Weather.locationError || Weather.city || Weather.loc
                    visible: text.length > 0
                    color: Weather.locationError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignRight
                    icon: "location_on"
                    text: Weather.locationError ? qsTr("Retry") : qsTr("Apply")
                    onClicked: root.applyLocation()
                }
            }
        }

        SectionHeader {
            text: qsTr("Units")
        }

        SelectRow {
            first: true
            label: qsTr("Temperature")
            subtext: qsTr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheit ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheit = root.tempItems.indexOf(item) === 1
        }

        SelectRow {
            last: true
            label: qsTr("System temperatures")
            subtext: qsTr("Units for CPU and GPU temperatures")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheitPerformance ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheitPerformance = root.tempItems.indexOf(item) === 1
        }

        SectionHeader {
            text: qsTr("Time & date")
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Clock format")
            subtext: qsTr("How times are shown across the shell")
            menuItems: root.clockItems
            active: root.clockItems[GlobalConfig.services.useTwelveHourClock ? 1 : 0]
            onSelected: item => GlobalConfig.services.useTwelveHourClock = root.clockItems.indexOf(item) === 1
        }
    }
}
