import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: results
    required property var workspace

    radius: 10
    color: Theme.surface
    clip: true

    // Keep Cancel usable while the workspace's editing controls are locked.
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Flickable {
            id: resultScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: resultContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Column {
                id: resultContent
                width: resultScroll.width - 12
                spacing: 3

                ProgressBar {
                    width: parent.width
                    visible: results.workspace.generating
                    from: 0
                    to: 100
                    value: Math.max(0, results.workspace.jobProgress)
                    indeterminate: results.workspace.jobProgress < 0
                }
                Label {
                    width: parent.width
                    visible: results.workspace.generating
                        && results.workspace.jobProgress >= 0
                    text: Math.round(results.workspace.jobProgress) + "%"
                    color: Theme.subtext
                    font.pixelSize: 12
                }
                Label {
                    width: parent.width
                    text: results.workspace.backendStatus
                    color: results.workspace.backendReady
                        ? Theme.success : Theme.subtext
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width
                    text: results.workspace.generatedPair !== ""
                        ? results.workspace.statusMessage + "  ·  Set "
                            + results.workspace.generatedPair
                        : results.workspace.statusMessage
                    color: Theme.success
                    font.bold: true
                    elide: Text.ElideRight
                }

                Repeater {
                    model: results.workspace.activeSlots.length

                    delegate: Label {
                        required property int index
                        property int slot: results.workspace.activeSlots[index]
                        width: resultContent.width
                        visible: results.workspace.generatedFile[slot] !== ""
                        text: "Monitor " + slot + " · "
                            + results.workspace.outputName[slot] + " · "
                            + results.workspace.generatedFile[slot].split("/").pop()
                        color: Theme.subtext
                        elide: Text.ElideRight
                    }
                }

                Label {
                    visible: results.workspace.processError !== ""
                    width: parent.width
                    text: results.workspace.processError
                    color: Theme.muted
                    wrapMode: Text.Wrap
                }
            }
        }

        Button {
            Layout.preferredWidth: 96
            Layout.minimumWidth: 96
            Layout.maximumWidth: 96
            visible: results.workspace.generating
            text: results.workspace.cancelRequested ? "Cancelling…" : "Cancel"
            enabled: results.workspace.generating
                && !results.workspace.cancelRequested
            onClicked: results.workspace.cancelGeneration()
            ToolTip.visible: hovered
            ToolTip.text: "Stop generation and clean up unfinished files."
        }
        Button {
            Layout.preferredWidth: 112
            Layout.minimumWidth: 112
            Layout.maximumWidth: 112
            text: results.workspace.generating
                ? results.workspace.jobPhase === "upscale"
                    ? "Upscaling…" : "Generating…"
                : "Generate"
            enabled: results.workspace.sourcePath !== ""
                && !results.workspace.busy
            onClicked: results.workspace.generate()
            ToolTip.visible: hovered
            ToolTip.text: "Create one correctly sized wallpaper file for every enabled monitor."
        }
        Button {
            Layout.preferredWidth: 96
            Layout.minimumWidth: 96
            Layout.maximumWidth: 96
            text: results.workspace.applying ? "Applying…" : "Apply"
            enabled: results.workspace.generatedReady()
                && results.workspace.backendReady
                && !results.workspace.busy
            onClicked: results.workspace.applyGenerated()
            ToolTip.visible: hovered
            ToolTip.text: "Apply generated wallpapers through the selected backend."
        }
    }
}