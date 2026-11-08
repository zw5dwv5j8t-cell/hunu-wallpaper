import QtQuick
import QtQuick.Controls
Switch {
    id: control
    implicitWidth: 52
    implicitHeight: 32
    padding: 0
    indicator: Rectangle {
        implicitWidth: 48; implicitHeight: 26
        x: (control.width-width)/2; y: (control.height-height)/2
        radius: 13
        color: control.checked ? Theme.accent : Theme.raised
        border.color: control.checked ? Theme.accent : Theme.border
        opacity: control.enabled ? 1 : 0.4
        Rectangle { width: 20; height: 20; radius: 10; y: 3; x: control.checked ? 25 : 3; color: control.checked ? "white" : Theme.subtext }
    }
    contentItem: Item {}
}
