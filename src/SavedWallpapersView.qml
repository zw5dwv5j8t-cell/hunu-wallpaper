import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Dialog {
    id: dialog
    required property var workspace
    property var sets: []
    property var outputs: []
    property var monitorLayout: ({})
    property int selectedIndex: -1
    property var assignments: []
    property string errorText: ""
    readonly property var selectedSet: selectedIndex >= 0 && selectedIndex < sets.length
        ? sets[selectedIndex] : null
    readonly property bool canApply: {
        if (!selectedSet || selectedSet.error !== "" || selectedSet.legacy || assignments.length < 1
                || !workspace.backendReady || workspace.busy || loader.running)
            return false
        let seen = []
        for (let output of assignments) {
            if (outputs.indexOf(output) < 0 || seen.indexOf(output) >= 0)
                return false
            seen.push(output)
        }
        return true
    }

    function selectSet(index) {
        selectedIndex = index
        assignments = selectedSet
            ? selectedSet.monitors.map(function(monitor) { return monitor.output }) : []
    }

    function refresh() {
        if (loader.running || workspace.busy)
            return
        sets = []
        outputs = []
        selectSet(-1)
        errorText = ""
        loader.command = ["python3", workspace.scriptPath("list-wallpaper-sets.py"),
                          workspace.outputDirectory, workspace.configPath]
        loader.running = true
    }

    onOpened: refresh()
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(880, parent.width - 40)
    height: Math.min(620, parent.height - 40)
    modal: true
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        radius: 12
        color: Theme.base
        border.color: Qt.alpha(Theme.subtext, 0.3)
    }
    header: Label {
        text: "Previous wallpapers"
        color: Theme.text
        font.pixelSize: 22
        font.bold: true
        padding: 20
        bottomPadding: 8
    }

    Process {
        id: loader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    dialog.sets = result.sets
                    dialog.outputs = result.outputs
                    dialog.monitorLayout = result.layout || ({})
                    dialog.errorText = result.outputError
                    if (dialog.sets.length > 0)
                        dialog.selectSet(0)
                } catch (error) {
                    dialog.errorText = "Could not read saved wallpaper sets."
                }
            }
        }
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            if (exitCode !== 0)
                dialog.errorText = "Could not read the wallpaper folder."
        }
    }

    contentItem: ColumnLayout {
        spacing: 12
        Label {
            Layout.fillWidth: true
            text: dialog.workspace.outputDirectory
            color: Theme.subtext
            elide: Text.ElideMiddle
        }
        Label {
            Layout.fillWidth: true
            visible: loader.running || dialog.sets.length === 0 || dialog.errorText !== ""
            text: loader.running ? "Reading saved wallpapers…"
                : dialog.errorText !== "" ? dialog.errorText
                : "No saved wallpaper sets found in this folder."
            color: Theme.subtext
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16
            ListView {
                id: setList
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                clip: true
                model: dialog.sets
                spacing: 6
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property int index
                    required property var modelData
                    width: setList.width
                    highlighted: dialog.selectedIndex === index
                    onClicked: dialog.selectSet(index)
                    contentItem: Column {
                        spacing: 4
                        Image {
                            width: parent.width
                            height: 76
                            source: modelData.monitors.length > 0
                                ? modelData.monitors[0].url : ""
                            sourceSize.width: 260
                            sourceSize.height: 100
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Label {
                            width: parent.width
                            text: modelData.name
                            color: Theme.text
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
            ScrollView {
                id: detailScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: detailScroll.availableWidth
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        text: dialog.selectedSet ? dialog.selectedSet.title : "Select a wallpaper set"
                        color: Theme.text
                        font.bold: true
                        wrapMode: Text.WrapAnywhere
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: dialog.selectedSet !== null
                        text: !dialog.selectedSet ? "" : dialog.selectedSet.error !== ""
                            ? dialog.selectedSet.error : dialog.selectedSet.legacy
                            ? "This older set has no saved assignments. Generate a new set to enable reapplying."
                            : dialog.selectedSet.created
                        color: Theme.subtext
                        wrapMode: Text.WordWrap
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: dialog.selectedSet !== null && !dialog.selectedSet.legacy
                        text: {
                            const set = dialog.selectedSet
                            if (!set)
                                return ""
                            const mode = set.mode === "linked" ? "Linked / Seam"
                                : set.mode === "quality" ? "Maximum Quality" : "Unknown mode"
                            const ai = set.aiScale === null || set.aiScale === undefined
                                ? "AI upscaling: not recorded"
                                : set.aiScale === 1 ? "AI upscaling: Off"
                                : "AI upscaling: " + set.aiScale + "×"
                            return mode + " · " + ai
                        }
                        color: Theme.subtext
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: dialog.selectedSet ? dialog.selectedSet.monitors : []
                        delegate: Label {
                            required property var modelData
                            Layout.fillWidth: true
                            text: "Monitor " + modelData.slot + " · " + modelData.output
                                + (modelData.offsetX === null || modelData.offsetX === undefined
                                    || modelData.offsetY === null || modelData.offsetY === undefined
                                    ? " · Offsets: not recorded"
                                    : " · X: " + modelData.offsetX + " · Y: " + modelData.offsetY)
                            color: Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                    }

                    SavedSetPreview {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 210
                        wallpaperSet: dialog.selectedSet
                        monitorLayout: dialog.monitorLayout
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Uses the outputs recorded when this set was generated."
                        color: Theme.muted
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: dialog.workspace.backendStatus
            color: dialog.workspace.backendReady ? Theme.success : Theme.subtext
            wrapMode: Text.WordWrap
        }
    }

    footer: RowLayout {
        Button {
            text: "Refresh"
            enabled: !loader.running && !dialog.workspace.busy
            onClicked: dialog.refresh()
        }
        Item { Layout.fillWidth: true }
        Button {
            text: "Close"
            onClicked: dialog.close()
        }
        Button {
            text: "Apply set"
            enabled: dialog.canApply
            onClicked: {
                let pairs = []
                for (let i = 0; i < dialog.selectedSet.monitors.length; ++i) {
                    pairs.push(dialog.assignments[i])
                    pairs.push(dialog.selectedSet.monitors[i].file)
                }
                dialog.workspace.applySavedSet(dialog.selectedSet, dialog.monitorLayout, pairs)
                dialog.close()
            }
        }
    }
}
