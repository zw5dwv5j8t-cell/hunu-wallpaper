import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: results
    required property var workspace

    radius: Theme.radius
    color: Theme.surface
    border.color: Theme.border
    clip: true

    // Keep Cancel usable while the workspace's editing controls are locked.
    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
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

            ScrollBar.vertical: HunuScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Column {
                id: resultContent
                width: resultScroll.width - 12
                spacing: 3

                ProgressBar {
                    palette.highlight: Theme.accent
                    palette.base: Theme.base
                    width: parent.width
                    visible: results.workspace.generating
                    from: 0
                    to: 100
                    value: Math.max(0, results.workspace.jobProgress)
                    indeterminate: results.workspace.jobProgress < 0
                }
                HunuText {
                    width: parent.width
                    visible: results.workspace.generating
                        && results.workspace.jobProgress >= 0
                    text: Math.round(results.workspace.jobProgress) + "%"
                    color: Theme.subtext
                    font.pixelSize: 12
                }
                HunuText {
                    width: parent.width
                    text: results.workspace.backendStatus
                    color: results.workspace.backendReady
                        ? Theme.success : Theme.subtext
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                HunuText {
                    width: parent.width
                    text: results.workspace.appliedSavedSet
                        ? results.workspace.statusMessage + " · " + results.workspace.appliedSavedSet.name
                        : results.workspace.generatedPair !== ""
                        ? results.workspace.statusMessage + "  ·  Set "
                            + results.workspace.generatedPair
                        : results.workspace.statusMessage
                    color: Theme.success
                    font.bold: true
                    elide: Text.ElideRight
                }

                HunuText {
                    width: parent.width
                    visible: !results.workspace.appliedSavedSet && results.workspace.activeSlots.some(function(slot) {
                        return results.workspace.generatedFile[slot] !== ""
                    })
                    text: "Saved for " + results.workspace.activeSlots.filter(function(slot) {
                        return results.workspace.generatedFile[slot] !== ""
                    }).map(function(slot) { return results.workspace.outputName[slot] }).join(" · ")
                    color: Theme.subtext
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    ToolTip.visible: resultFilesHover.containsMouse
                    ToolTip.text: results.workspace.activeSlots.map(function(slot) {
                        return results.workspace.outputName[slot] + ": " + results.workspace.generatedFile[slot]
                    }).join("\n")
                    MouseArea { id: resultFilesHover; anchors.fill: parent; hoverEnabled: true }
                }

                HunuText {
                    visible: results.workspace.processError !== ""
                    width: parent.width
                    text: results.workspace.processError
                    color: Theme.muted
                    wrapMode: Text.Wrap
                }
            }
        }

        HunuActionButton {
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
        HunuActionButton {
            Layout.preferredWidth: 124
            Layout.minimumWidth: 124
            Layout.maximumWidth: 124
            objectName: "generateWallpapers"
            glyph: "play"
            text: results.workspace.generating
                ? results.workspace.jobPhase === "upscale"
                    ? "Upscaling…" : "Generating…"
                : "Generate"
            enabled: !results.workspace.appliedSavedSet && results.workspace.sourcePath !== ""
                && !results.workspace.busy
            onClicked: results.workspace.generate()
            ToolTip.visible: hovered
            ToolTip.text: "Create one correctly sized wallpaper file for every enabled monitor."
        }
        HunuActionButton {
            Layout.preferredWidth: 96
            Layout.minimumWidth: 96
            Layout.maximumWidth: 96
            objectName: "applyWallpapers"
            primary: true
            glyph: "check"
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