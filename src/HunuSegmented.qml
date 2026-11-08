import QtQuick
import QtQuick.Layouts
Item {
    id: group
    property var options: []
    property int currentIndex: 0
    signal selected(int index)
    implicitWidth: options.length * 82
    implicitHeight: 40
    Rectangle { anchors.fill: parent; radius: Theme.radiusSmall; color: Theme.surface; border.color: Theme.border }
    RowLayout {
        anchors.fill: parent; anchors.margins: 3; spacing: 2
        Repeater {
            model: group.options
            delegate: HunuActionButton {
                required property int index
                required property string modelData
                Layout.fillWidth: true
                compact: true
                flat: true
                text: modelData
                checked: index === group.currentIndex
                onClicked: group.selected(index)
            }
        }
    }
}
