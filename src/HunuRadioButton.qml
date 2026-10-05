import QtQuick
import QtQuick.Controls

// Keep radio labels legible with the active Hunu palette.
RadioButton {
    contentItem: Text {
        text: parent.text
        font: parent.font
        color: parent.enabled ? Theme.text : Theme.muted
        verticalAlignment: Text.AlignVCenter
        leftPadding: parent.indicator.width + parent.spacing
    }
}
