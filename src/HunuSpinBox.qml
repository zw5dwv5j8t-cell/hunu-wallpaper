import QtQuick
import QtQuick.Controls
SpinBox {
    id: control
    implicitWidth: 160
    implicitHeight: 40
    leftPadding: 35
    rightPadding: 35
    font.family: Theme.fontFamily
    font.pixelSize: 13
    contentItem: TextInput {
        text: control.displayText; font: control.font
        color: control.enabled ? Theme.text : Theme.muted
        horizontalAlignment: Qt.AlignHCenter; verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        selectByMouse: true
    }
    background: Rectangle { radius: Theme.radiusSmall; color: Theme.surface; border.color: control.activeFocus ? Theme.accent : Theme.border }
    up.indicator: Rectangle {
        x: control.width-width; width: 32; height: control.height; color: "transparent"
        Text { anchors.centerIn: parent; text: "+"; color: control.enabled ? Theme.text : Theme.muted; font.pixelSize: 19 }
    }
    down.indicator: Rectangle {
        width: 32; height: control.height; color: "transparent"
        Text { anchors.centerIn: parent; text: "−"; color: control.enabled ? Theme.text : Theme.muted; font.pixelSize: 19 }
    }
}
