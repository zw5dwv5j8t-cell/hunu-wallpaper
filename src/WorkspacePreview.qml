import QtQuick
import QtQuick.Layouts

Item {
    id: preview
    required property var workspace

    // Geometry remains calculated by the workspace/backend.
    // This component only arranges the preview rectangles.
    Item {
        id: linkedPreview
        anchors.centerIn: parent
        visible: preview.workspace.mode === "linked"
        width: Math.min(parent.width,
            parent.height * preview.workspace.desktopW
                / Math.max(1, preview.workspace.desktopH))
        height: width * preview.workspace.desktopH
            / Math.max(1, preview.workspace.desktopW)

        property real unitScale: width
            / Math.max(1, preview.workspace.desktopW)

        Repeater {
            model: preview.workspace.activeSlots.length

            delegate: HunuMonitorPreview {
                required property int index
                workspace: preview.workspace
                slot: preview.workspace.activeSlots[index]
                linked: true
                x: workspace.physX[slot] * linkedPreview.unitScale
                y: workspace.physY[slot] * linkedPreview.unitScale
                width: workspace.physW[slot] * linkedPreview.unitScale
                height: workspace.physH[slot] * linkedPreview.unitScale
                previewScale: width / Math.max(1, workspace.cropW[slot])
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16
        visible: preview.workspace.mode === "quality"

        Repeater {
            model: preview.workspace.activeSlots.length

            delegate: Item {
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                property int slot: preview.workspace.activeSlots[index]

                HunuMonitorPreview {
                    workspace: preview.workspace
                    anchors.centerIn: parent
                    slot: parent.slot
                    linked: false

                    width: {
                        const aspect = workspace.pixelW[slot]
                            / Math.max(1, workspace.pixelH[slot])
                        return Math.min(parent.width - 8,
                            (parent.height - 8) * aspect)
                    }
                    height: width * workspace.pixelH[slot]
                        / Math.max(1, workspace.pixelW[slot])
                    previewScale: Math.min(
                        width / Math.max(1, workspace.cropW[slot]),
                        height / Math.max(1, workspace.cropH[slot]))
                }
            }
        }
    }
}