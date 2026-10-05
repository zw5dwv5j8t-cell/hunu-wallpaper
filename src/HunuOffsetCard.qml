import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One enabled monitor's controls; linked synchronization stays in the workspace.
Rectangle {
    id: card
    required property var workspace
    required property int slot
    Layout.fillWidth: true
    implicitHeight: 188
    radius: 10
    color: Theme.surface
    border.width: 1
    border.color: Qt.alpha(Theme.subtext, 0.22)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 13
        spacing: 7

        Label {
            text: "Monitor " + card.slot + " — " + workspace.outputName[card.slot]
            color: Theme.text
            font.bold: true
            font.pixelSize: 15
        }
        Label {
            text: workspace.pixelW[card.slot] + " × " + workspace.pixelH[card.slot]
            color: Theme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "X"; color: Theme.text; Layout.preferredWidth: 18 }
            Slider {
                Layout.fillWidth: true
                from: workspace.offsetMinimum(card.slot, "x")
                to: workspace.offsetMaximum(card.slot, "x")
                value: workspace.offsetX[card.slot]
                stepSize: 1
                enabled: from !== to
                onMoved: workspace.setOffset(card.slot, "x", value)
            }
            HunuOffsetInput {
                workspace: card.workspace
                slot: card.slot
                axis: "x"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Y"; color: Theme.text; Layout.preferredWidth: 18 }
            Slider {
                Layout.fillWidth: true
                from: workspace.offsetMinimum(card.slot, "y")
                to: workspace.offsetMaximum(card.slot, "y")
                value: workspace.offsetY[card.slot]
                stepSize: 1
                enabled: from !== to
                onMoved: workspace.setOffset(card.slot, "y", value)
            }
            HunuOffsetInput {
                workspace: card.workspace
                slot: card.slot
                axis: "y"
            }
        }

        Label {
            Layout.fillWidth: true
            text: workspace.mode === "linked"
                ? workspace.linkedOffsets
                    ? "Move the shared composition across all enabled monitors."
                    : "Move this monitor's crop independently; seams may no longer align."
                : "Move this monitor's independent crop within the original image."
            color: Theme.muted
            wrapMode: Text.WordWrap
            font.pixelSize: 12
        }
    }
}
