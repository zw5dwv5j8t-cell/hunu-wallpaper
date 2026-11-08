import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: picker
    // A modal layer surface, not a compositor-managed application window.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hunu-wallpaper-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: Qt.rgba(0, 0, 0, 0.35)
    visible: false
    property var sets: []
    property var monitorLayout: ({})
    property int selectedIndex: 0
    property int hiddenCount: 0
    property string backend: ""
    property string errorText: ""
    readonly property var selectedSet: sets.length ? sets[selectedIndex] : null
    readonly property bool busy: loader.running || applyProcess.running

    function helper(name) {
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace("file://", ""))
    }
    function move(step) {
        if (!busy && sets.length)
            selectedIndex = (selectedIndex + step + sets.length) % sets.length
    }
    function confirm() {
        if (busy || !selectedSet)
            return
        errorText = ""
        applyProcess.command = ["python3", helper("switcher-controller.py"), "apply", selectedSet.name]
        applyProcess.running = true
    }
    onClosed: Qt.quit()
    Component.onCompleted: {
        loader.command = ["python3", helper("switcher-controller.py"), "list"]
        loader.running = true
        controls.forceActiveFocus()
    }

    IpcHandler {
        target: "picker"
        function next(): void { picker.move(1) }
    }
    Process {
        id: loader
        property string errorOutput: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    picker.sets = result.sets
                    picker.monitorLayout = result.layout
                    picker.hiddenCount = result.hidden
                    picker.backend = result.backend
                    const focusedScreen = Quickshell.screens.find(function(s) {
                        return s.name === result.focusedOutput
                    })
                    if (focusedScreen)
                        picker.screen = focusedScreen
                    const index = picker.sets.findIndex(function(s) { return s.name === result.current })
                    picker.selectedIndex = Math.max(0, index)
                } catch (error) {
                    picker.errorText = "Could not load saved wallpapers."
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: loader.errorOutput = text.trim() }
        onExited: function(code) {
            if (code !== 0)
                picker.errorText = errorOutput || "Could not load saved wallpapers."
            picker.visible = true
            controls.forceActiveFocus()
        }
    }
    Process {
        id: applyProcess
        property string errorOutput: ""
        stdout: StdioCollector {}
        stderr: StdioCollector { onStreamFinished: applyProcess.errorOutput = text.trim() }
        onExited: function(code) {
            if (code === 0)
                Qt.quit()
            else
                picker.errorText = errorOutput || "Apply failed. Reopen the switcher to refresh the layout."
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !applyProcess.running
        onClicked: Qt.quit()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(570, parent.height - 48)
        radius: 16
        color: Theme.base
        border.color: Qt.alpha(Theme.subtext, 0.3)
        // Consume clicks inside the card; only the backdrop dismisses it.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        FocusScope {
            id: controls
            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                    picker.move(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
                    picker.move(-1)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    picker.confirm()
                } else if (event.key === Qt.Key_Escape && !applyProcess.running) {
                    Qt.quit()
                } else {
                    return
                }
                event.accepted = true
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 14
                RowLayout {
                    Label {
                        text: "Choose a wallpaper"
                        font.pixelSize: 24
                        font.bold: true
                        color: Theme.text
                        Layout.fillWidth: true
                    }
                    Label {
                        text: picker.sets.length ? (picker.selectedIndex + 1) + " / " + picker.sets.length : ""
                        color: Theme.subtext
                    }
                }
                SavedSetPreview {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    wallpaperSet: picker.selectedSet
                    monitorLayout: picker.monitorLayout
                    visible: picker.sets.length > 0
                }
                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: !picker.sets.length
                    visible: !picker.sets.length
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: loader.running ? "Loading saved wallpapers…" : "No saved wallpaper sets match this monitor layout."
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: picker.selectedSet ? picker.selectedSet.title : ""
                    color: Theme.text
                    font.pixelSize: 18
                    elide: Text.ElideMiddle
                }
                ListView {
                    id: filmstrip
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    orientation: ListView.Horizontal
                    spacing: 10
                    clip: true
                    model: picker.sets
                    currentIndex: picker.selectedIndex
                    highlightRangeMode: ListView.ApplyRange
                    highlightMoveDuration: 100
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: 142
                        height: 84
                        color: Theme.surface
                        radius: 6
                        border.width: index === picker.selectedIndex ? 2 : 1
                        border.color: index === picker.selectedIndex ? Theme.success : Theme.muted
                        SavedSetPreview {
                            anchors.fill: parent
                            anchors.margins: 7
                            wallpaperSet: modelData
                            monitorLayout: picker.monitorLayout
                            showLabels: false
                            decodeWidth: 180
                            decodeHeight: 120
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !picker.busy
                            onClicked: {
                                picker.selectedIndex = index
                                controls.forceActiveFocus()
                            }
                            onDoubleClicked: picker.confirm()
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: picker.errorText !== ""
                    text: picker.errorText
                    color: Theme.text
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "← / → Preview · Enter Apply · Esc Cancel"
                            + (picker.hiddenCount ? "\n" + picker.hiddenCount + " incompatible or incomplete sets hidden" : "")
                        color: Theme.subtext
                        font.pixelSize: 12
                    }
                    Button { focusPolicy: Qt.NoFocus; text: "‹"; enabled: !picker.busy && picker.sets.length > 1; onClicked: picker.move(-1) }
                    Button { focusPolicy: Qt.NoFocus; text: "›"; enabled: !picker.busy && picker.sets.length > 1; onClicked: picker.move(1) }
                    Button {
                        focusPolicy: Qt.NoFocus
                        text: applyProcess.running ? "Applying…" : "Apply"
                        enabled: !picker.busy && picker.selectedSet !== null
                        onClicked: picker.confirm()
                    }
                }
            }
        }
    }
}
