import QtQuick
import QtQuick.Controls

// Render one crop using geometry supplied by the workspace.
// The same component serves physical and independent previews.
Rectangle {
    id: preview
    required property var workspace
    required property int slot
    required property bool linked
    property real previewScale: 1

    color: Theme.surface
    radius: 7
    clip: true
    border.width: 1
    border.color: Qt.alpha(Theme.subtext, 0.25)

    Image {
        source: workspace.sourceUrl
        asynchronous: true
        smooth: true
        fillMode: Image.Stretch
        width: workspace.previewW * preview.previewScale
        height: workspace.previewH * preview.previewScale
        x: -(workspace.baseX[preview.slot] + workspace.offsetX[preview.slot]) * preview.previewScale
        y: -(workspace.baseY[preview.slot] + workspace.offsetY[preview.slot]) * preview.previewScale
        visible: workspace.sourceUrl !== ""
    }

    Column {
        anchors.centerIn: parent
        spacing: 2
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Monitor " + preview.slot
            color: Theme.text
            font.bold: true
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: workspace.outputName[preview.slot]
                + " · " + workspace.pixelW[preview.slot]
                + "×" + workspace.pixelH[preview.slot]
            color: Theme.subtext
            font.pixelSize: 11
        }
    }
}
