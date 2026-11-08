import QtQuick
import QtQuick.Controls
CheckBox {
    id: control
    implicitHeight: 32
    spacing: 10
    font.family: Theme.fontFamily
    font.pixelSize: 13
    indicator: Rectangle {
        implicitWidth: 20; implicitHeight: 20
        x: control.leftPadding
        y: (control.height-height)/2
        radius: 5
        color: control.checked ? Theme.accent : Theme.surface
        border.color: control.checked ? Theme.accent : control.activeFocus ? Theme.accent : Theme.border
        HunuIcon { anchors.fill: parent; anchors.margins: 2; symbol: "check"; iconColor: Theme.onAccent; visible: control.checked }
        opacity: control.enabled ? 1 : 0.4
    }
    contentItem: Text {
        text: control.text; font: control.font
        color: control.enabled ? Theme.text : Theme.muted
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}
