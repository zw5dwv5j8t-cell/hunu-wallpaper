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
    color: "transparent"
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

    Item {
        id: card
        anchors.centerIn: parent
        width: Math.min(1040, parent.width - 64)
        height: Math.min(720, parent.height - 64)
        // Keep the overlay surface transparent: only images and controls draw.
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
                spacing: 12
                Image {
                    id: fullPreview
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    property string failedUrl: ""
                    source: picker.selectedSet
                        ? (failedUrl === picker.selectedSet.previewUrl
                            ? picker.selectedSet.fallbackPreviewUrl : picker.selectedSet.previewUrl) : ""
                    sourceSize.width: 1600
                    sourceSize.height: 1000
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    onStatusChanged: {
                        if (status === Image.Error && picker.selectedSet)
                            failedUrl = picker.selectedSet.previewUrl
                    }
                    visible: picker.sets.length > 0
                }
                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: !picker.sets.length
                    visible: !picker.sets.length
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: loader.running ? "Loading saved wallpapers…" : "No saved wallpaper sets match this monitor layout."
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: picker.selectedSet ? picker.selectedSet.title : ""
                        color: "white"
                        style: Text.Outline
                        styleColor: "#aa000000"
                        font.pixelSize: 18
                        elide: Text.ElideMiddle
                    }
                    Label {
                        text: picker.sets.length ? (picker.selectedIndex + 1) + " / " + picker.sets.length : ""
                        color: "white"
                        style: Text.Outline
                        styleColor: "#aa000000"
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: picker.selectedSet !== null && !picker.selectedSet.previewIsSource
                    text: "Crop preview · Regenerate this set for a full-image preview"
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    font.pixelSize: 12
                }
                ListView {
                    id: filmstrip
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    model: picker.sets
                    currentIndex: picker.selectedIndex
                    highlightRangeMode: ListView.ApplyRange
                    highlightMoveDuration: 100
                    delegate: Item {
                        id: thumbnail
                        required property var modelData
                        required property int index
                        width: 142
                        height: 88
                        Image {
                            anchors.fill: parent
                            anchors.bottomMargin: 8
                            source: thumbnail.modelData.previewUrl
                            sourceSize.width: 280
                            sourceSize.height: 160
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            opacity: thumbnail.index === picker.selectedIndex ? 1 : 0.65
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 32
                            height: 2
                            radius: 1
                            color: "white"
                            visible: thumbnail.index === picker.selectedIndex
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !picker.busy
                            onClicked: {
                                picker.selectedIndex = thumbnail.index
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
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "← / → Preview · Enter Apply · Esc Cancel"
                            + (picker.hiddenCount ? "\n" + picker.hiddenCount + " incompatible or incomplete sets hidden" : "")
                        color: "white"
                        style: Text.Outline
                        styleColor: "#aa000000"
                        font.pixelSize: 12
                    }
                    Button {
                        focusPolicy: Qt.NoFocus
                        flat: true
                        palette.buttonText: "white"
                        background: Rectangle { color: "#44000000"; radius: 8 }
                        text: "‹"
                        enabled: !picker.busy && picker.sets.length > 1
                        onClicked: picker.move(-1)
                    }
                    Button {
                        focusPolicy: Qt.NoFocus
                        flat: true
                        palette.buttonText: "white"
                        background: Rectangle { color: "#44000000"; radius: 8 }
                        text: "›"
                        enabled: !picker.busy && picker.sets.length > 1
                        onClicked: picker.move(1)
                    }
                    Button {
                        focusPolicy: Qt.NoFocus
                        flat: true
                        palette.buttonText: "white"
                        background: Rectangle { color: "#44000000"; radius: 8 }
                        text: applyProcess.running ? "Applying…" : "Apply"
                        enabled: !picker.busy && picker.selectedSet !== null
                        onClicked: picker.confirm()
                    }
                }
            }
        }
    }
}
