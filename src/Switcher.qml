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
    property bool initialized: false
    property bool liveEnabled: false
    property string liveReason: ""
    property string intent: ""
    property string inFlight: ""
    property string queuedName: ""
    property string previewedName: ""
    property bool normalExit: false
    readonly property bool busy: !initialized || intent !== ""

    function helper(name) {
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace("file://", ""))
    }
    function move(step) {
        if (!busy && sets.length)
            selectedIndex = (selectedIndex + step + sets.length) % sets.length
    }
    function schedulePreview() {
        if (initialized && liveEnabled && selectedSet && intent === "") {
            queuedName = selectedSet.name
            debounce.restart()
        }
    }
    onSelectedSetChanged: schedulePreview()
    function dispatch() {
        if (!initialized || !sessionProcess.running || inFlight !== "")
            return
        let action = intent
        let name = selectedSet ? selectedSet.name : ""
        if (action === "") {
            // Never send while the user is still cycling, even if the previous
            // backend request has just completed.
            if (debounce.running)
                return
            if (!liveEnabled || queuedName === "" || queuedName === previewedName) {
                queuedName = ""
                return
            }
            action = "preview"
            name = queuedName
            queuedName = ""
        }
        inFlight = action
        sessionProcess.write(JSON.stringify({action: action, name: name}) + "\n")
    }
    function confirm() {
        if (busy || !selectedSet)
            return
        intent = "commit"
        queuedName = ""
        debounce.stop()
        dispatch()
    }
    function cancel() {
        if (intent === "commit")
            return
        if (!initialized || !sessionProcess.running) {
            Qt.quit()
            return
        }
        intent = "cancel"
        queuedName = ""
        debounce.stop()
        dispatch()
    }
    function receive(line) {
        let result
        try { result = JSON.parse(line) }
        catch (error) { errorText = "Could not read preview session response."; return }
        if (result.event === "ready") {
            sets = result.sets
            monitorLayout = result.layout
            hiddenCount = result.hidden
            backend = result.backend
            liveEnabled = result.liveEnabled
            liveReason = result.liveReason
            const focusedScreen = Quickshell.screens.find(function(s) { return s.name === result.focusedOutput })
            if (focusedScreen)
                screen = focusedScreen
            const index = sets.findIndex(function(s) { return s.name === result.current })
            selectedIndex = Math.max(0, index)
            previewedName = result.current
            initialized = true
            visible = true
            controls.forceActiveFocus()
            return
        }
        inFlight = ""
        if (result.event === "committed" || result.event === "cancelled") {
            normalExit = true
            Qt.quit()
            return
        }
        if (result.event === "previewed") {
            previewedName = result.name
            errorText = ""
        } else if (result.event === "error") {
            errorText = result.message
            previewedName = ""
            if (result.action === "commit" || result.action === "cancel") {
                intent = ""
                visible = true
                controls.forceActiveFocus()
            }
        }
        if (intent !== "")
            dispatch()
        else if (queuedName !== "" && !debounce.running)
            dispatch()
    }
    onClosed: cancel()
    Component.onCompleted: {
        sessionProcess.command = ["python3", helper("switcher-controller.py"), "session"]
        sessionProcess.running = true
    }
    Timer { id: debounce; interval: 400; onTriggered: picker.dispatch() }
    IpcHandler {
        target: "picker"
        function next(): void { picker.move(1) }
    }
    Process {
        id: sessionProcess
        stdinEnabled: true
        property string errorOutput: ""
        stdout: SplitParser { onRead: data => picker.receive(data) }
        stderr: StdioCollector { onStreamFinished: sessionProcess.errorOutput = text.trim() }
        onExited: function(code) {
            if (!picker.normalExit) {
                picker.errorText = errorOutput || "The preview session ended. Close and reopen the switcher."
                picker.initialized = false
                picker.visible = true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: picker.intent !== "commit"
        onClicked: picker.cancel()
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: Math.min(1480, parent.width - 64)
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
                } else if (event.key === Qt.Key_Escape) {
                    picker.cancel()
                } else {
                    return
                }
                event.accepted = true
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                Item {
                    id: carousel
                    objectName: "previewCarousel"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: picker.sets.length > 0
                    readonly property bool hasNeighbors: picker.sets.length > 1

                    Repeater {
                        model: [-1, 1]
                        delegate: Item {
                            id: neighbor
                            required property int modelData
                            readonly property int neighborIndex: picker.sets.length
                                ? (picker.selectedIndex + modelData + picker.sets.length) % picker.sets.length : -1
                            readonly property var wallpaperSet: neighborIndex >= 0 ? picker.sets[neighborIndex] : null
                            objectName: modelData < 0 ? "previousPreview" : "nextPreview"
                            // With two sets, show the other set once on the right.
                            visible: picker.sets.length > (modelData < 0 ? 2 : 1)
                            width: carousel.width * 0.17
                            height: carousel.height * 0.65
                            anchors.verticalCenter: parent.verticalCenter
                            x: modelData < 0 ? 0 : carousel.width - width
                            Image {
                                id: neighborImage
                                anchors.fill: parent
                                property string failedUrl: ""
                                source: neighbor.wallpaperSet
                                    ? (failedUrl === neighbor.wallpaperSet.previewUrl
                                        ? neighbor.wallpaperSet.fallbackPreviewUrl : neighbor.wallpaperSet.previewUrl) : ""
                                sourceSize.width: 600
                                sourceSize.height: 400
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                opacity: neighborMouse.containsMouse ? 0.85 : 0.55
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                onStatusChanged: {
                                    if (status === Image.Error && neighbor.wallpaperSet)
                                        failedUrl = neighbor.wallpaperSet.previewUrl
                                }
                            }
                            MouseArea {
                                id: neighborMouse
                                anchors.fill: parent
                                enabled: !picker.busy
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    picker.move(neighbor.modelData)
                                    controls.forceActiveFocus()
                                }
                            }
                        }
                    }
                    Image {
                        id: fullPreview
                        objectName: "currentPreview"
                        anchors.centerIn: parent
                        width: carousel.hasNeighbors ? carousel.width * 0.62 : carousel.width
                        height: carousel.height
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
                    }
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: !picker.sets.length
                    visible: !picker.sets.length
                    verticalAlignment: Text.AlignVCenter
                    text: !picker.initialized ? "Loading saved wallpapers…" : "No saved wallpaper sets match this monitor layout."
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    wrapMode: Text.WordWrap
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    text: picker.selectedSet ? picker.selectedSet.title
                        + "   ·   " + (picker.selectedIndex + 1) + " / " + picker.sets.length : ""
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    font.pixelSize: 18
                    elide: Text.ElideMiddle
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    visible: picker.selectedSet !== null && !picker.selectedSet.previewIsSource
                    text: "Crop preview · Regenerate this set for a full-image preview"
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    font.pixelSize: 12
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    visible: picker.errorText !== ""
                    text: picker.errorText
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    wrapMode: Text.WordWrap
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    text: picker.intent === "cancel" ? "Restoring your previous wallpaper…"
                        : picker.intent === "commit" ? "Keeping this wallpaper…"
                        : picker.inFlight === "preview" ? "Previewing on your desktop…"
                        : picker.liveEnabled ? "← / → Live preview · Enter Keep · Esc Restore previous"
                        : "← / → Browse · Enter Apply · Esc Cancel"
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    font.pixelSize: 12
                }
                Label {
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    visible: picker.liveReason !== "" || picker.hiddenCount > 0
                    text: picker.liveReason + (picker.hiddenCount
                        ? (picker.liveReason ? "\n" : "") + picker.hiddenCount + " incompatible or incomplete sets hidden" : "")
                    color: "white"
                    style: Text.Outline
                    styleColor: "#aa000000"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Repeater {
                        model: ["‹", "›"]
                        delegate: Button {
                            required property int index
                            required property string modelData
                            focusPolicy: Qt.NoFocus
                            flat: true
                            palette.buttonText: "white"
                            background: Rectangle { color: "#44000000"; radius: 8 }
                            text: modelData
                            enabled: !picker.busy && picker.sets.length > 1
                            onClicked: picker.move(index === 0 ? -1 : 1)
                        }
                    }
                }
            }
        }
    }
}
