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
    onErrorTextChanged: { if (errorText !== "") console.warn(errorText) }
    readonly property var selectedSet: sets.length ? sets[selectedIndex] : null
    property string verticalPosition: "center"
    property bool showActionButtons: true
    property int previewDelayMs: 400
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
            const preferences = result.switcherSettings || ({})
            verticalPosition = preferences.position || "center"
            previewDelayMs = preferences.delayMs || 400
            showActionButtons = preferences.showActionButtons !== false
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
    Timer { id: debounce; interval: picker.previewDelayMs; onTriggered: picker.dispatch() }
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
                picker.inFlight = ""
                picker.intent = ""
                picker.queuedName = ""
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
        objectName: "switcherContent"
        anchors.horizontalCenter: parent.horizontalCenter
        y: picker.verticalPosition === "top" ? 32
            : picker.verticalPosition === "bottom" ? parent.height - height - 32
            : (parent.height - height) / 2
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
                        Accessible.name: picker.selectedSet ? picker.selectedSet.title : "Wallpaper preview"
                        Accessible.description: picker.selectedSet && !picker.selectedSet.previewIsSource
                            ? "Monitor crop preview; regenerate this set for a full-image preview" : "Full source preview"
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
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Accessible.name: picker.errorText || picker.liveReason
                        || (!picker.sets.length && picker.initialized ? "No compatible wallpaper sets" : "")
                    BusyIndicator {
                        anchors.centerIn: parent
                        implicitWidth: 30
                        implicitHeight: 30
                        running: (!picker.initialized && picker.errorText === "")
                            || picker.inFlight !== "" || picker.intent !== ""
                        visible: running
                    }
                    PickerIcon {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        symbol: picker.errorText !== "" ? "warning" : "empty"
                        iconColor: "#e5bf7c"
                        visible: picker.inFlight === "" && picker.intent === ""
                            && (picker.errorText !== "" || (picker.initialized && !picker.sets.length))
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    IconButton {
                        objectName: "previousButton"
                        symbol: "previous"
                        actionName: "Previous wallpaper"
                        enabled: !picker.busy && picker.sets.length > 1
                        onClicked: picker.move(-1)
                    }
                    IconButton {
                        objectName: "nextButton"
                        symbol: "next"
                        actionName: "Next wallpaper"
                        enabled: !picker.busy && picker.sets.length > 1
                        onClicked: picker.move(1)
                    }
                }
                RowLayout {
                    objectName: "actionButtonsRow"
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    visible: picker.showActionButtons
                    IconButton {
                        objectName: "applyButton"
                        symbol: "apply"
                        actionName: "Keep wallpaper (Enter)"
                        enabled: !picker.busy && picker.selectedSet !== null
                        onClicked: picker.confirm()
                    }
                    IconButton {
                        objectName: "cancelButton"
                        symbol: "cancel"
                        actionName: "Cancel and restore previous wallpaper (Escape)"
                        enabled: picker.intent !== "commit"
                        onClicked: picker.cancel()
                    }
                }
            }
        }
    }

    // Draw icons ourselves so controls don't depend on a particular icon font.
    component PickerIcon: Canvas {
        property string symbol: ""
        property color iconColor: "white"
        onSymbolChanged: requestPaint()
        onIconColorChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.scale(width / 32, height / 32)
            ctx.strokeStyle = iconColor
            ctx.lineWidth = 2.6
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            if (symbol === "previous") {
                ctx.moveTo(20, 7); ctx.lineTo(11, 16); ctx.lineTo(20, 25)
            } else if (symbol === "next") {
                ctx.moveTo(12, 7); ctx.lineTo(21, 16); ctx.lineTo(12, 25)
            } else if (symbol === "apply") {
                ctx.moveTo(7, 16); ctx.lineTo(13, 22); ctx.lineTo(25, 10)
            } else if (symbol === "cancel") {
                ctx.moveTo(9, 9); ctx.lineTo(23, 23)
                ctx.moveTo(23, 9); ctx.lineTo(9, 23)
            } else if (symbol === "warning") {
                ctx.moveTo(16, 4); ctx.lineTo(29, 27); ctx.lineTo(3, 27); ctx.closePath()
                ctx.moveTo(16, 12); ctx.lineTo(16, 18)
                ctx.moveTo(16, 23); ctx.lineTo(16, 23.1)
            } else {
                ctx.rect(4, 6, 24, 20)
                ctx.moveTo(5, 24); ctx.lineTo(12, 16); ctx.lineTo(19, 23); ctx.lineTo(23, 18); ctx.lineTo(28, 23)
                ctx.moveTo(3, 3); ctx.lineTo(29, 29)
            }
            ctx.stroke()
        }
    }
    component IconButton: Button {
        property string symbol: ""
        property string actionName: ""
        implicitWidth: 64
        implicitHeight: 64
        padding: 16
        focusPolicy: Qt.NoFocus
        Accessible.name: actionName
        Accessible.description: picker.errorText || picker.liveReason
        background: Rectangle {
            radius: width / 2
            color: parent.down ? "#99000000" : parent.hovered ? "#77000000" : "#44000000"
            border.width: 1
            border.color: parent.hovered ? "#66ffffff" : "#22ffffff"
        }
        contentItem: PickerIcon {
            symbol: parent.symbol
            iconColor: parent.enabled ? "white" : "#55ffffff"
        }
    }
}
