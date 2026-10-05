import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: preview
    required property var setup

    Layout.fillWidth: true
    implicitHeight: 235
    radius: 12
    color: Theme.surface
    border.width: 1
    border.color: Qt.alpha(Theme.subtext, 0.22)

    // Include enabled monitors when calculating the physical preview bounds.
    property real minX: Math.min(setup.slot1Xcm,
        setup.slot2Index >= 0 ? setup.slot2Xcm : setup.slot1Xcm,
        setup.slot3Index >= 0 ? setup.slot3Xcm : setup.slot1Xcm)

    property real minY: Math.min(setup.slot1Ycm,
        setup.slot2Index >= 0 ? setup.slot2Ycm : setup.slot1Ycm,
        setup.slot3Index >= 0 ? setup.slot3Ycm : setup.slot1Ycm)

    property real maxX: Math.max(setup.slot1Xcm + setup.slot1WidthCm,
        setup.slot2Index >= 0
            ? setup.slot2Xcm + setup.slot2WidthCm
            : setup.slot1Xcm + setup.slot1WidthCm,
        setup.slot3Index >= 0
            ? setup.slot3Xcm + setup.slot3WidthCm
            : setup.slot1Xcm + setup.slot1WidthCm)

    property real maxY: Math.max(setup.slot1Ycm + setup.slot1HeightCm,
        setup.slot2Index >= 0
            ? setup.slot2Ycm + setup.slot2HeightCm
            : setup.slot1Ycm + setup.slot1HeightCm,
        setup.slot3Index >= 0
            ? setup.slot3Ycm + setup.slot3HeightCm
            : setup.slot1Ycm + setup.slot1HeightCm)

    property real spanW: Math.max(1, maxX - minX)
    property real spanH: Math.max(1, maxY - minY)
    property real scaleFactor: Math.min(
        (width - 50) / spanW, (height - 50) / spanH)

    PreviewScreenRect {
        slot: 1
        active: preview.setup.slot1Index >= 0
        layoutMinX: preview.minX
        layoutMinY: preview.minY
        layoutScale: preview.scaleFactor
        cmX: preview.setup.slot1Xcm
        cmY: preview.setup.slot1Ycm
        cmW: preview.setup.slot1WidthCm
        cmH: preview.setup.slot1HeightCm
        outputName: {
            const monitor = preview.setup.monitorAt(preview.setup.slot1Index)
            return monitor ? monitor.name : ""
        }
    }

    PreviewScreenRect {
        slot: 2
        active: preview.setup.slot2Index >= 0
        layoutMinX: preview.minX
        layoutMinY: preview.minY
        layoutScale: preview.scaleFactor
        cmX: preview.setup.slot2Xcm
        cmY: preview.setup.slot2Ycm
        cmW: preview.setup.slot2WidthCm
        cmH: preview.setup.slot2HeightCm
        outputName: {
            const monitor = preview.setup.monitorAt(preview.setup.slot2Index)
            return monitor ? monitor.name : ""
        }
    }

    PreviewScreenRect {
        slot: 3
        active: preview.setup.slot3Index >= 0
        layoutMinX: preview.minX
        layoutMinY: preview.minY
        layoutScale: preview.scaleFactor
        cmX: preview.setup.slot3Xcm
        cmY: preview.setup.slot3Ycm
        cmW: preview.setup.slot3WidthCm
        cmH: preview.setup.slot3HeightCm
        outputName: {
            const monitor = preview.setup.monitorAt(preview.setup.slot3Index)
            return monitor ? monitor.name : ""
        }
    }

    component PreviewScreenRect: Rectangle {
        id: screenRect
        required property int slot
        required property bool active
        required property real cmX
        required property real cmY
        required property real cmW
        required property real cmH
        required property string outputName
        required property real layoutMinX
        required property real layoutMinY
        required property real layoutScale

        visible: active
        x: 25 + (cmX - layoutMinX) * layoutScale
        y: 25 + (cmY - layoutMinY) * layoutScale
        width: Math.max(2, cmW * layoutScale)
        height: Math.max(2, cmH * layoutScale)
        radius: 5
        color: Qt.alpha(Theme.text, 0.08)
        border.width: 2
        border.color: Theme.subtext

        Column {
            anchors.centerIn: parent
            spacing: 2

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Monitor " + screenRect.slot
                color: Theme.text
                font.bold: true
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: screenRect.outputName
                color: Theme.subtext
                font.pixelSize: 11
            }
        }
    }
}