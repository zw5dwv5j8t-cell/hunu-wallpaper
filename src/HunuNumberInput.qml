import QtQuick
import QtQuick.Controls

TextField {
    id: numberBox
    property real numberValue: 0
    property bool syncingFromValue: false

    implicitWidth: 96
    implicitHeight: 36
    leftPadding: 10
    rightPadding: 10
    topPadding: 0
    bottomPadding: 0
    text: String(numberValue)
    color: Theme.text
    selectByMouse: true
    horizontalAlignment: TextInput.AlignRight
    verticalAlignment: TextInput.AlignVCenter
    clip: true
    inputMethodHints: Qt.ImhFormattedNumbersOnly

    validator: DoubleValidator {
        bottom: -9999
        top: 9999
        decimals: 2
        notation: DoubleValidator.StandardNotation
    }

    background: Rectangle {
        radius: 7
        color: Theme.surface
        border.width: 1
        border.color: numberBox.activeFocus
            ? Theme.subtext : Qt.alpha(Theme.subtext, 0.30)
    }

    // External measurement changes update the field without interrupting edits.
    onNumberValueChanged: {
        if (!activeFocus) {
            syncingFromValue = true
            text = String(numberValue)
            syncingFromValue = false
        }
    }

    onTextEdited: {
        if (syncingFromValue)
            return

        const n = Number.fromLocaleString(Qt.locale(), text)
        if (!isNaN(n))
            numberValue = n
    }

    onActiveFocusChanged: {
        if (activeFocus)
            selectAll()
        else
            text = String(numberValue)
    }
}