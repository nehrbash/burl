pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

ColumnLayout {
    id: root

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 0
    property var validator: null
    property string suffix: ""
    property int decimals: 1
    property var formatValueFunction: null
    property var parseValueFunction: null
    // IntValidator is the one validator with no `decimals` property.
    readonly property bool _isIntValidator: !!validator && validator.decimals === undefined

    // Live, every drag/keystroke: for updating a preview.
    signal valueModified(real newValue)

    // The commit edge — drag release, or Enter/focus-out in the field.  Use
    // this for anything expensive or user-visible (applying to hardware).
    signal valueCommitted(real newValue)

    // StyledSlider reports a 0..1 handle position, not a from..to value.
    function _fromPos(pos: real): real {
        const v = root.from + pos * (root.to - root.from);
        return root.stepSize > 0 ? Math.round(v / root.stepSize) * root.stepSize : v;
    }

    function formatValue(val: real): string {
        if (formatValueFunction) {
            return formatValueFunction(val);
        }
        if (root._isIntValidator)
            return Math.round(val).toString();
        return val.toFixed(root.decimals);
    }

    function parseValue(text: string): real {
        if (parseValueFunction)
            return parseValueFunction(text);
        // Only IntValidator lacks `decimals` — matching formatValue().  Do NOT
        // test whether `top` is a whole number: a DoubleValidator bounded at
        // 3.0 would then parseInt("1.5") down to 1 and the field would silently
        // refuse every fractional entry.
        if (root._isIntValidator)
            return parseInt(text);
        return parseFloat(text);
    }

    spacing: Tokens.spacing.small

    // Mirror `value` into the field whenever it moves under us — the owner
    // seeding it after creation, a drag, a revert.  Skipped only while the user
    // is typing, so their caret isn't yanked around.
    onValueChanged: if (!inputField.hasFocus)
        inputField.text = root.formatValue(root.value)

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            visible: root.label !== ""
            text: root.label
            font.pointSize: Tokens.font.body.medium.pointSize
        }

        Item {
            Layout.fillWidth: true
        }

        StyledInputField {
            id: inputField

            Layout.preferredWidth: 70
            validator: root.validator

            // Seeded, not bound: the field is authoritative while focused.
            Component.onCompleted: text = root.formatValue(root.value)

            onTextEdited: text => {
                if (hasFocus) {
                    const val = root.parseValue(text);
                    if (!isNaN(val)) {
                        let isValid = true;
                        if (root.validator) {
                            if (root.validator.bottom !== undefined && val < root.validator.bottom) {
                                isValid = false;
                            }
                            if (root.validator.top !== undefined && val > root.validator.top) {
                                isValid = false;
                            }
                        }

                        if (isValid) {
                            root.valueModified(val);
                        }
                    }
                }
            }

            onEditingFinished: {
                const val = root.parseValue(text);
                let isValid = true;
                if (root.validator) {
                    if (root.validator.bottom !== undefined && val < root.validator.bottom) {
                        isValid = false;
                    }
                    if (root.validator.top !== undefined && val > root.validator.top) {
                        isValid = false;
                    }
                }

                if (isNaN(val) || !isValid)
                    text = root.formatValue(root.value);
                else
                    root.valueCommitted(val);
            }
        }

        StyledText {
            visible: root.suffix !== ""
            text: root.suffix
            color: Woodland.creamSecondary
            font.pointSize: Tokens.font.body.medium.pointSize
        }
    }

    StyledSlider {
        id: slider

        Layout.fillWidth: true
        implicitHeight: Tokens.padding.medium * 3

        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value

        // StyledSlider drives its own MouseArea and never writes `value`, so
        // Slider.onMoved / Slider.pressed are dead here — position arrives via
        // interaction().  It also clears `dragging` before emitting the release
        // interaction, which makes that the commit edge.
        onInteraction: pos => {
            const v = root._fromPos(pos);
            root.valueModified(v);
            if (!dragging)
                root.valueCommitted(v);
        }
    }
}
