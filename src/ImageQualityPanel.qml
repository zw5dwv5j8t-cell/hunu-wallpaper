import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: panel
    required property var workspace

    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: Theme.border
    visible: workspace.sourcePath !== ""

    // Display backend recommendations; AI scaling remains a manual choice.
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 18

        ColumnLayout {
            spacing: 3

            HunuText {
                text: "Image Quality"
                color: Theme.text
                font.bold: true
                font.pixelSize: 15
            }
            HunuText {
                text: "Source  " + panel.workspace.sourceW
                    + " × " + panel.workspace.sourceH
                    + "   ·   Recommended  " + panel.workspace.idealW
                    + " × " + panel.workspace.idealH
                color: Theme.subtext
                font.pixelSize: 12
            }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
            spacing: 5

            HunuText {
                Layout.alignment: Qt.AlignRight
                text: panel.workspace.sourceSufficient
                    ? "Source quality: Excellent"
                    : "Source quality: Below recommended"
                color: panel.workspace.sourceSufficient
                    ? Theme.success : Theme.text
                font.bold: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4

                HunuText {
                    text: "AI Upscaling"
                    color: Theme.subtext
                    font.pixelSize: 12
                }
                HunuRadioButton {
                    text: "Off"
                    checked: panel.workspace.upscaleScale === 1
                    onClicked: panel.workspace.upscaleScale = 1
                }
                HunuRadioButton {
                    text: "2×"
                    enabled: panel.workspace.upscalerAvailable
                    checked: panel.workspace.upscaleScale === 2
                    onClicked: panel.workspace.upscaleScale = 2
                }
                HunuRadioButton {
                    text: "3×"
                    enabled: panel.workspace.upscalerAvailable
                    checked: panel.workspace.upscaleScale === 3
                    onClicked: panel.workspace.upscaleScale = 3
                }
                HunuRadioButton {
                    text: "4×"
                    enabled: panel.workspace.upscalerAvailable
                    checked: panel.workspace.upscaleScale === 4
                    onClicked: panel.workspace.upscaleScale = 4
                }
            }

            HunuText {
                Layout.alignment: Qt.AlignRight
                text: !panel.workspace.upscalerChecked
                    ? "Checking Real-ESRGAN…"
                    : !panel.workspace.upscalerAvailable
                        ? "Real-ESRGAN is not installed — AI upscaling is optional."
                        : panel.workspace.sourceSufficient
                            ? "No upscaling needed."
                            : panel.workspace.recommendedScale > 0
                                ? "Recommended: "
                                    + panel.workspace.recommendedScale + "×"
                                : "4× is the highest available scale and remains below ideal."
                color: Theme.muted
                font.pixelSize: 12
            }
        }
    }
}