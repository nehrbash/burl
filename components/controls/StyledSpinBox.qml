import QtQuick
import Burl.Config
import qs.components
import qs.services

// Qt 6.9-compatible stand-in for QtQuick.Templates' DoubleSpinBox, which
// arrived only in Qt 6.10 (not yet shipped by Guix). Implements the subset
// StepperRow uses: real-valued from/to/stepSize/value, valueModified,
// editable, press-and-hold repeat.
Item {
    id: root

    property real from: 0
    property real to: 99
    property real stepSize: 1
    property real value
    property bool editable: true
    property int repeatRate: 400
    property int repeatDecay: 50
    property int cLayer: 1

    readonly property int decimals: stepSize < 1 ? Math.max(1, Math.ceil(-Math.log10(stepSize))) : 0
    property int spacing: Tokens.spacing.small

    signal valueModified

    function clampRound(v: real): real {
        const p = Math.pow(10, decimals);
        return Math.min(to, Math.max(from, Math.round(v * p) / p));
    }

    function increase(): void {
        value = clampRound(value + stepSize);
        valueModified();
    }

    function decrease(): void {
        value = clampRound(value - stepSize);
        valueModified();
    }

    implicitWidth: downButton.implicitWidth + field.implicitWidth + upButton.implicitWidth + Tokens.spacing.extraSmall
    implicitHeight: Math.max(downButton.implicitHeight, upButton.implicitHeight, field.implicitHeight)

    IconButton {
        id: downButton

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        topRightRadius: pressed ? Tokens.rounding.small : Tokens.rounding.extraSmall
        bottomRightRadius: pressed ? Tokens.rounding.small : Tokens.rounding.extraSmall

        icon: "remove"
        disabledColour: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.4)
        color: disabled ? disabledColour : Colours.layer(Colours.palette.m3surfaceContainerHighest, root.cLayer)
        type: IconButton.Text
        padding: Tokens.padding.extraSmall
        isRound: true
        disabled: !root.enabled || root.value <= root.from
    }

    TextFieldBase {
        id: field

        anchors.left: downButton.right
        anchors.right: upButton.left
        anchors.leftMargin: Tokens.spacing.extraSmall / 2
        anchors.rightMargin: Tokens.spacing.extraSmall / 2
        anchors.verticalCenter: parent.verticalCenter

        text: root.value.toFixed(root.decimals)

        readOnly: !root.editable
        validator: DoubleValidator {
            bottom: root.from
            top: root.to
            decimals: root.decimals
            locale: "C"
        }
        inputMethodHints: Qt.ImhFormattedNumbersOnly

        leftPadding: Tokens.padding.medium
        rightPadding: Tokens.padding.medium

        implicitWidth: 65
        horizontalAlignment: TextInput.AlignHCenter

        onEditingFinished: {
            const v = parseFloat(text.replace(",", "."));
            if (!isNaN(v)) {
                root.value = root.clampRound(v);
                root.valueModified();
            }
            text = Qt.binding(() => root.value.toFixed(root.decimals));
        }

        background: StyledRect {
            radius: Tokens.rounding.extraSmall
            color: Colours.layer(Colours.palette.m3surfaceContainerHighest, root.cLayer)
        }
    }

    IconButton {
        id: upButton

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        topLeftRadius: pressed ? Tokens.rounding.small : Tokens.rounding.extraSmall
        bottomLeftRadius: pressed ? Tokens.rounding.small : Tokens.rounding.extraSmall

        icon: "add"
        disabledColour: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.4)
        color: disabled ? disabledColour : Colours.layer(Colours.palette.m3surfaceContainerHighest, root.cLayer)
        type: IconButton.Text
        padding: Tokens.padding.extraSmall
        isRound: true
        disabled: !root.enabled || root.value >= root.to
    }

    Timer {
        id: timer

        running: upButton.pressed || downButton.pressed
        onRunningChanged: {
            if (!running)
                interval = root.repeatRate;
        }

        interval: root.repeatRate
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (upButton.pressed)
                root.increase();
            else if (downButton.pressed)
                root.decrease();
            if (interval > root.repeatDecay)
                interval -= root.repeatDecay;
        }
    }
}
