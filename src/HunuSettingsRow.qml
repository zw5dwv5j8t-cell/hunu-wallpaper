import QtQuick
import QtQuick.Layouts
Item {
    id: row
    property string heading: ""
    property string detail: ""
    property bool divider: true
    default property alias controls: slot.data
    implicitHeight: Math.max(labels.implicitHeight, slot.implicitHeight) + 32
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border; visible: row.divider }
    RowLayout {
        anchors.fill: parent; anchors.topMargin: 16; anchors.bottomMargin: 16; spacing: 24
        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 5
            HunuText { Layout.fillWidth: true; text: row.heading; font.pixelSize: 14; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
            HunuText { Layout.fillWidth: true; text: row.detail; visible: text !== ""; color: Theme.subtext; font.pixelSize: 12; wrapMode: Text.WordWrap }
        }
        RowLayout { id: slot; spacing: 8 }
    }
}
