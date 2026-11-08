import QtQuick
import QtQuick.Controls
ScrollBar {
    id: control
    implicitWidth: orientation === Qt.Vertical ? 9 : 64
    implicitHeight: orientation === Qt.Vertical ? 64 : 9
    padding: 2
    contentItem: Rectangle {
        implicitWidth: control.orientation === Qt.Vertical ? 5 : 28
        implicitHeight: control.orientation === Qt.Vertical ? 28 : 5
        radius: 3
        color: control.pressed ? Theme.accent : control.active ? Theme.subtext : Theme.muted
        opacity: control.policy === ScrollBar.AlwaysOff || control.size >= 1 ? 0
            : control.active || control.pressed ? 0.8 : 0.35
    }
}
