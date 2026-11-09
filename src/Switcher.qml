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
    property int displayedIndex: 0
    property bool confirmWhenVisible: false
    property int hiddenCount: 0
    property string backend: ""
    property string errorText: ""
    onErrorTextChanged: { if (errorText !== "") console.warn(errorText) }
    readonly property var selectedSet: sets.length ? sets[selectedIndex] : null
    property string verticalPosition: "center"
    property bool showActionButtons: true
    property int previewDelayMs: 400
    property bool firstFrameReady: false
    property bool prefetchEnabled: false
    property bool initialized: false
    property bool snapshotReady: false
    property bool hasNavigated: false
    property bool liveEnabled: false
    property string liveReason: ""
    property string intent: ""
    property string inFlight: ""
    property string queuedName: ""
    property string previewedName: ""
    property bool normalExit: false
    readonly property bool busy: !initialized || intent !== "" || confirmWhenVisible

    function helper(name) {
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace("file://", ""))
    }
    function move(step) {
        if (!busy && sets.length) {
            hasNavigated = true
            selectedIndex = (selectedIndex + step + sets.length) % sets.length
        }
    }
    function schedulePreview() {
        if (initialized && liveEnabled && selectedSet && intent === "") {
            queuedName = selectedSet.name
            debounce.restart()
        }
    }
    onSelectedSetChanged: {
        schedulePreview()
        Qt.callLater(function() { if (carousel) carousel.showRequested() })
    }
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
        if (displayedIndex !== selectedIndex) {
            confirmWhenVisible = true
            return
        }
        intent = "commit"
        queuedName = ""
        debounce.stop()
        dispatch()
    }
    function cancel() {
        confirmWhenVisible = false
        if (intent === "commit")
            return
        if (!initialized || !snapshotReady || !sessionProcess.running) {
            normalExit = true
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
        if (result.event === "ready" && initialized) {
            snapshotReady = true
            liveEnabled = result.liveEnabled
            liveReason = result.liveReason
            previewedName = result.current
            if (!hasNavigated && intent === "" && !confirmWhenVisible) {
                const index = sets.findIndex(function(s) { return s.name === result.current })
                selectedIndex = Math.max(0, index)
                Qt.callLater(function() { carousel.showRequested() })
            } else if (hasNavigated && intent === "") {
                schedulePreview()
            }
            return
        }
        if (result.event === "catalog" || result.event === "ready") {
            snapshotReady = result.event === "ready"
            sets = result.sets
            monitorLayout = result.layout
            hiddenCount = result.hidden
            backend = result.backend
            liveEnabled = snapshotReady && result.liveEnabled === true
            liveReason = result.liveReason || ""
            const preferences = result.switcherSettings || ({})
            verticalPosition = preferences.position || "center"
            previewDelayMs = preferences.delayMs || 400
            showActionButtons = preferences.showActionButtons !== false
            const focusedScreen = Quickshell.screens.find(function(s) { return s.name === result.focusedOutput })
            if (focusedScreen)
                screen = focusedScreen
            const index = sets.findIndex(function(s) { return s.name === result.current })
            selectedIndex = Math.max(0, index)
            displayedIndex = selectedIndex
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
    Timer {
        id: prefetchTimer
        interval: 100
        onTriggered: picker.prefetchEnabled = true
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
        // Keep Canvas rasterization active during warmup. This opacity is below
        // one 8-bit alpha step, so controls and images remain imperceptible.
        opacity: picker.firstFrameReady || picker.errorText !== "" || (picker.initialized && !picker.sets.length) ? 1 : 0.001
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

                    function offset(index, base) {
                        const count = picker.sets.length
                        if (!count)
                            return 0
                        let distance = (index - base + count) % count
                        if (count > 2 && distance > count / 2)
                            distance -= count
                        return distance
                    }
                    function showRequested() {
                        const count = picker.sets.length
                        if (!count)
                            return
                        const targets = [picker.selectedIndex]
                        if (count > 1)
                            targets.push((picker.selectedIndex + 1) % count)
                        if (count > 2)
                            targets.push((picker.selectedIndex + count - 1) % count)
                        for (let index of targets) {
                            const loader = previewPool.itemAt(index)
                            if (!loader || !loader.item || !loader.item.prepared
                                    || (!picker.firstFrameReady && !loader.item.frameReady))
                                return
                        }
                        // Commit all three positions in the same QML update.
                        picker.displayedIndex = picker.selectedIndex
                        if (!picker.firstFrameReady) {
                            picker.firstFrameReady = true
                            prefetchTimer.start()
                        }
                        if (picker.confirmWhenVisible) {
                            picker.confirmWhenVisible = false
                            picker.confirm()
                        }
                    }
                    Repeater {
                        id: previewPool
                        // Lightweight loaders only; keep at most five requested
                        // previews plus the outgoing triplet decoded in memory.
                        model: picker.sets.length
                        onItemAdded: Qt.callLater(carousel.showRequested)
                        delegate: Loader {
                            id: slot
                            required property int index
                            readonly property int displacement: carousel.offset(index, picker.displayedIndex)
                            readonly property bool onScreen: Math.abs(displacement) <= 1
                            active: onScreen || Math.abs(carousel.offset(index, picker.selectedIndex)) <= 1
                                || (picker.prefetchEnabled && Math.abs(carousel.offset(index, picker.selectedIndex)) <= 2)
                            width: carousel.hasNeighbors ? carousel.width * 0.62 : carousel.width
                            height: carousel.height
                            readonly property real sideScale: Math.min(0.65,
                                carousel.width * 0.17 / Math.max(1, item ? item.paintedWidth : width))
                            readonly property real visualSideWidth: (item ? item.paintedWidth : width) * sideScale
                            scale: displacement === 0 ? 1 : sideScale
                            anchors.verticalCenter: parent.verticalCenter
                            x: (displacement === 0 ? carousel.width / 2
                                : displacement < 0 ? visualSideWidth / 2
                                : carousel.width - visualSideWidth / 2) - width / 2
                            opacity: !onScreen ? 0 : displacement === 0 ? 1
                                : item && item.hovered ? 0.9 : 0.65
                            enabled: onScreen && !picker.busy
                            onLoaded: Qt.callLater(carousel.showRequested)
                            sourceComponent: RoundedPreview {
                                id: asset
                                readonly property int neighborIndex: slot.index
                                readonly property bool hovered: previewMouse.containsMouse
                                objectName: slot.displacement === 0 ? "currentPreview"
                                    : slot.displacement === -1 ? "previousPreview"
                                    : slot.displacement === 1 ? "nextPreview" : "prefetchedPreview"
                                readonly property var wallpaperSet: picker.sets[slot.index] || null
                                source: wallpaperSet ? wallpaperSet.previewUrl : ""
                                fallbackSource: wallpaperSet ? wallpaperSet.fallbackPreviewUrl : ""
                                // Identical decode size in every position: moving
                                // from side to center never reloads the asset.
                                sourceSize: Qt.size(1000, 700)
                                highlighted: true
                                Accessible.name: wallpaperSet ? wallpaperSet.title : "Wallpaper preview"
                                Accessible.description: wallpaperSet && !wallpaperSet.previewIsSource
                                    ? "Monitor crop preview" : "Full source preview"
                                onPreparedChanged: if (prepared) Qt.callLater(carousel.showRequested)
                                MouseArea {
                                    id: previewMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: slot.displacement ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (slot.displacement !== 0)
                                            picker.move(slot.displacement < 0 ? -1 : 1)
                                        controls.forceActiveFocus()
                                    }
                                }
                            }
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

    // Clip the pixels and paint the border in one rounded path. Canvas uses the
    // same implementation with GPU and software rendering; no shader mask needed.
    component RoundedPreview: Item {
        id: preview
        property url source: ""
        property url fallbackSource: ""
        property size sourceSize: Qt.size(1600, 1000)
        property bool highlighted: false
        property bool shadowEnabled: true
        property string failedUrl: ""
        readonly property real aspectRatio: paintedImage.displayedRatio
        readonly property real paintedWidth: imageFrame.width
        readonly property real paintedHeight: imageFrame.height
        readonly property bool prepared: photo.status === Image.Error
            || (photo.status === Image.Ready && paintedImage.displayedUrl.toString() === photo.source.toString())
        readonly property bool frameReady: photo.status === Image.Error
            || (prepared && paintedImage.renderedUrl.toString() === photo.source.toString())
        onFrameReadyChanged: if (frameReady) Qt.callLater(carousel.showRequested)
        onHighlightedChanged: paintedImage.requestPaint()
        onShadowEnabledChanged: paintedImage.requestPaint()

        // Keep image decoding bounded and use its intrinsic size for aspect fit.
        Image {
            id: photo
            objectName: "previewDecoder"
            visible: false
            source: preview.failedUrl === preview.source.toString() ? preview.fallbackSource : preview.source
            sourceSize: preview.sourceSize
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Error)
                    preview.failedUrl = preview.source.toString()
            }
        }
        Item {
            id: imageFrame
            objectName: "roundedImageFrame"
            anchors.centerIn: parent
            width: paintedImage.displayedUrl.toString() !== ""
                ? Math.min(preview.width, preview.height * preview.aspectRatio) : 0
            height: width / Math.max(0.001, preview.aspectRatio)
            readonly property real cornerRadius: Math.min(22, width / 10, height / 10)
            Canvas {
                id: paintedImage
                objectName: "roundedImageCanvas"
                readonly property int padding: 24
                property url imageUrl: photo.status === Image.Ready ? photo.source : ""
                property url loadedUrl: ""
                property url renderedUrl: ""
                onPainted: renderedUrl = displayedUrl
                property url displayedUrl: ""
                property real displayedRatio: 1
                property real pendingRatio: 1
                x: -padding
                y: -padding
                width: imageFrame.width + padding * 2
                height: imageFrame.height + padding * 2
                antialiasing: true
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                function imageReady() {
                    if (imageUrl.toString() === "" || !isImageLoaded(imageUrl))
                        return
                    if (displayedUrl.toString() === imageUrl.toString()) {
                        requestPaint()
                        return
                    }
                    const oldUrl = displayedUrl
                    displayedRatio = pendingRatio
                    displayedUrl = imageUrl
                    requestPaint()
                    // Keep the outgoing pixels/cache alive until a decoded
                    // replacement exists. Never clear the visible frame to load.
                    if (oldUrl.toString() !== "" && oldUrl.toString() !== imageUrl.toString())
                        unloadImage(oldUrl)
                }
                function reload() {
                    if (loadedUrl.toString() !== "" && loadedUrl.toString() !== displayedUrl.toString()
                            && loadedUrl.toString() !== imageUrl.toString())
                        unloadImage(loadedUrl)
                    loadedUrl = imageUrl
                    if (imageUrl.toString() !== "") {
                        pendingRatio = photo.implicitWidth / Math.max(1, photo.implicitHeight)
                        loadImage(imageUrl, preview.sourceSize)
                        if (isImageLoaded(imageUrl))
                            imageReady()
                    }
                }
                onImageUrlChanged: reload()
                onImageLoaded: imageReady()
                Component.onCompleted: reload()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    if (!isImageLoaded(displayedUrl) || imageFrame.width <= 0 || imageFrame.height <= 0)
                        return
                    const w = imageFrame.width
                    const h = imageFrame.height
                    const r = imageFrame.cornerRadius
                    function roundedPath(x, y, width, height, radius) {
                        ctx.beginPath()
                        ctx.moveTo(x + radius, y)
                        ctx.lineTo(x + width - radius, y)
                        ctx.quadraticCurveTo(x + width, y, x + width, y + radius)
                        ctx.lineTo(x + width, y + height - radius)
                        ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
                        ctx.lineTo(x + radius, y + height)
                        ctx.quadraticCurveTo(x, y + height, x, y + height - radius)
                        ctx.lineTo(x, y + radius)
                        ctx.quadraticCurveTo(x, y, x + radius, y)
                        ctx.closePath()
                    }
                    if (preview.shadowEnabled) {
                        roundedPath(padding, padding, w, h, r)
                        ctx.shadowColor = preview.highlighted ? "rgba(0,0,0,0.35)" : "rgba(0,0,0,0.2)"
                        ctx.shadowBlur = 14
                        ctx.shadowOffsetY = 6
                        ctx.fillStyle = "rgba(0,0,0,0.3)"
                        ctx.fill()
                        ctx.shadowColor = "transparent"
                        ctx.shadowBlur = 0
                        ctx.shadowOffsetY = 0
                    }
                    ctx.save()
                    roundedPath(padding, padding, w, h, r)
                    ctx.clip()
                    ctx.drawImage(displayedUrl, padding, padding, w, h)
                    ctx.restore()
                    const line = preview.highlighted ? 2 : 1
                    roundedPath(padding + line / 2, padding + line / 2,
                        w - line, h - line, Math.max(0, r - line / 2))
                    ctx.lineWidth = line
                    ctx.strokeStyle = preview.highlighted ? "rgba(255,255,255,0.7)" : "rgba(255,255,255,0.33)"
                    ctx.stroke()
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
