import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property int rootHeight

    spacing: Tokens.spacing.extraSmall

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        animate: true
        text: Weather.description
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.large
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacing.medium

        StyledText {
            id: temp

            animate: true
            text: Weather.temp
            color: Woodland.brass
            font: Tokens.font.headline.builders.large.scale(1.5).weight(Font.DemiBold).width(80).build()
        }

        MaterialIcon {
            animate: true
            text: Weather.icon
            color: Woodland.brass
            fontStyle: Tokens.font.headline.builders.large.scale(1.5).build()
        }
    }

    StyledText {
        visible: root.rootHeight > Tokens.sizes.lock.showWeatherDetailsHeight
        Layout.alignment: Qt.AlignHCenter
        animate: true
        text: qsTr("Feels like %1").arg(Weather.feelsLike)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.large
    }

    StyledText {
        visible: root.rootHeight > Tokens.sizes.lock.showWeatherDetailsHeight
        Layout.alignment: Qt.AlignHCenter
        animate: true
        text: {
            const today = Weather.forecast[0];
            return qsTr("High %1 • Low %2").arg(Weather.formatTemp(today?.maxTempC)).arg(Weather.formatTemp(today?.minTempC));
        }
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.medium
    }
}
