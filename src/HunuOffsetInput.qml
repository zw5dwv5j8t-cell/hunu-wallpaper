import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Commit exact offsets on Enter or focus loss, within valid crop limits.
TextField {
    id: field
    required property var workspace
    required property int slot
    required property string axis

    readonly property int currentValue: axis === "x"
        ? workspace.offsetX[slot] : workspace.offsetY[slot]
    readonly property int minimum: workspace.offsetMinimum(slot, axis)
    readonly property int maximum: workspace.offsetMaximum(slot, axis)

    Layout.preferredWidth: 80
    text: String(currentValue)
    color: Theme.text
    horizontalAlignment: TextInput.AlignRight
    selectByMouse: true
    validator: IntValidator {}
    background: Rectangle {
        radius: 6
        color: Theme.base
        border.width: 1
        border.color: field.activeFocus
            ? Theme.subtext : Qt.alpha(Theme.subtext, 0.35)
    }

    function commitValue() {
        if (acceptableInput) {
            const value = Math.max(minimum,
                Math.min(maximum, Number(text)))
            if (value !== currentValue)
                workspace.setOffset(slot, axis, value)
        }
        text = String(currentValue)
    }

    onCurrentValueChanged: {
        if (!activeFocus)
            text = String(currentValue)
    }
    onAccepted: commitValue()
    onActiveFocusChanged: {
        if (activeFocus)
            selectAll()
        else
            commitValue()
    }
}
