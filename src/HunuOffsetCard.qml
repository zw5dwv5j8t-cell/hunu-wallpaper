import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One enabled monitor's controls; linked synchronization stays in the workspace.
Rectangle {
    id: card
    required property var workspace
    required property int slot
    Layout.fillWidth: true
    implicitHeight: 150
    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 13
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            HunuIcon { symbol: "monitor"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
            HunuText { text: "Monitor " + card.slot; font.weight: Font.DemiBold }
            HunuText { text: workspace.outputName[card.slot]; color: Theme.subtext; font.pixelSize: 12 }
            Item { Layout.fillWidth: true }
            HunuText { text: workspace.pixelW[card.slot] + " × " + workspace.pixelH[card.slot]; color: Theme.muted; font.pixelSize: 11 }
        }
        RowLayout {
            Layout.fillWidth: true
            HunuText { text: "X"; color: Theme.text; Layout.preferredWidth: 18 }
            HunuSlider {
                objectName: "offsetSlider-" + card.slot + "-x"
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
            HunuText { text: "Y"; color: Theme.text; Layout.preferredWidth: 18 }
            HunuSlider {
                objectName: "offsetSlider-" + card.slot + "-y"
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

    }
}
