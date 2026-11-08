import QtQuick
import QtQuick.Controls
RadioButton {
    id: control
    implicitHeight: 30
    spacing: 8
    font.family: Theme.fontFamily
    font.pixelSize: 13
    indicator: Rectangle {
        implicitWidth: 18; implicitHeight: 18
        x: control.leftPadding; y: (control.height-height)/2
        radius: 9; color: Theme.base
        border.color: control.checked ? Theme.accent : Theme.border
        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.accent; visible: control.checked }
        opacity: control.enabled ? 1 : 0.4
    }
    contentItem: Text {
        text: control.text; font: control.font
        color: control.enabled ? Theme.text : Theme.muted
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}
