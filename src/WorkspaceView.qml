import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import QtCore as Core

// Workspace owns job state and delegates crop rendering and controls.
Item {
    id: root

    property string configPath: ""
    property string sourcePath: ""
    property string sourceUrl: ""
    property string outputDirectory: ""
    property string applyBackend: "serpantinum"
    readonly property var applyBackendValues: ["serpantinum", "hyprpaper", "awww"]
    property bool backendReady: false
    property string backendStatus: "Checking wallpaper backend…"
    property real cacheBytes: 0
    property int cacheFiles: 0
    property bool cacheChecked: false

    onApplyBackendChanged: {
        backendReady = false
        backendStatus = "Checking wallpaper backend…"
        checkApplyBackend()
    }
    property string mode: "linked"
    property bool linkedOffsets: true

    property int monitorCount: 0
    property var activeSlots: []
    property int previewW: 1
    property int previewH: 1
    property int desktopW: 1
    property int desktopH: 1

    property int sourceW: 0
    property int sourceH: 0
    property int idealW: 0
    property int idealH: 0
    property bool sourceSufficient: true
    property int recommendedScale: 1

    property int upscaleScale: 1
    property bool upscalerAvailable: false
    property bool upscalerChecked: false
    property string upscaledSourcePath: ""

    // Slots are 1-based; index 0 is unused. Active slots may be non-contiguous.
    property var outputName: ["", "", "", ""]
    property var pixelW: [0, 0, 0, 0]
    property var pixelH: [0, 0, 0, 0]
    property var physX: [0, 0, 0, 0]
    property var physY: [0, 0, 0, 0]
    property var physW: [1, 1, 1, 1]
    property var physH: [1, 1, 1, 1]
    property var cropW: [1, 1, 1, 1]
    property var cropH: [1, 1, 1, 1]
    property var baseX: [0, 0, 0, 0]
    property var baseY: [0, 0, 0, 0]
    property var xMin: [0, 0, 0, 0]
    property var xMax: [0, 0, 0, 0]
    property var yMin: [0, 0, 0, 0]
    property var yMax: [0, 0, 0, 0]
    property var offsetX: [0, 0, 0, 0]
    property var offsetY: [0, 0, 0, 0]
    property var generatedFile: ["", "", "", ""]
    property string generatedPair: ""
    property string processError: ""
    property string statusMessage: "Choose a wallpaper."

    property bool applying: false
    readonly property bool busy: generating || applying || outputSaveProcess.running || backendSaveProcess.running || (cacheProcess.running && cacheProcess.action === "clear")
    property var pendingSplitCommand: []

    readonly property bool generating: generationProcess.running
    property bool cancelRequested: false
    property string jobPhase: ""
    property real jobProgress: -1

    signal monitorSetupRequested()

    SettingsView {
        id: settingsDialog
        workspace: root
        onChooseOutputFolderRequested: outputFolderDialog.open()
        onMonitorSetupRequested: root.monitorSetupRequested()
    }

    Component.onCompleted: {
        checkUpscaler()
        loadOutputDirectory()
    }
    onConfigPathChanged: loadOutputDirectory()

    function scriptPath(name) {
        return Qt.resolvedUrl(name).toString().replace("file://", "")
    }

    function cleanPath(url) {
        let p = url.toString()
        if (p.startsWith("file://"))
            p = decodeURIComponent(p.substring(7))
        return p
    }

    function valueAt(values, key, fallback) {
        return values[key] !== undefined ? values[key] : fallback
    }

    function intAt(values, key, fallback) {
        const n = parseInt(valueAt(values, key, String(fallback)))
        return isNaN(n) ? fallback : n
    }

    function invalidateGenerated() {
        generatedFile = ["", "", "", ""]
        generatedPair = ""
        processError = ""
    }

    function resetOffsets() {
        offsetX = [0, 0, 0, 0]
        offsetY = [0, 0, 0, 0]
        invalidateGenerated()
        if (sourcePath !== "")
            probe()
    }

    // Linked movement uses the intersection of all enabled crop ranges.
    function offsetMinimum(slot, axis) {
        const limits = axis === "x" ? xMin : yMin
        if (mode !== "linked" || !linkedOffsets || activeSlots.length === 0)
            return limits[slot]

        let minimum = limits[activeSlots[0]]
        for (let activeSlot of activeSlots)
            minimum = Math.max(minimum, limits[activeSlot])
        return minimum
    }

    function offsetMaximum(slot, axis) {
        const limits = axis === "x" ? xMax : yMax
        if (mode !== "linked" || !linkedOffsets || activeSlots.length === 0)
            return limits[slot]

        let maximum = limits[activeSlots[0]]
        for (let activeSlot of activeSlots)
            maximum = Math.min(maximum, limits[activeSlot])
        return maximum
    }

    function setOffset(slot, axis, value) {
        const position = Math.max(offsetMinimum(slot, axis),
            Math.min(offsetMaximum(slot, axis), Math.round(value)))
        let offsets = (axis === "x" ? offsetX : offsetY).slice()
        let changed = false

        const slots = mode === "linked" && linkedOffsets
            ? activeSlots : [slot]
        for (let activeSlot of slots) {
            if (offsets[activeSlot] !== position) {
                offsets[activeSlot] = position
                changed = true
            }
        }

        if (!changed)
            return

        if (axis === "x")
            offsetX = offsets
        else
            offsetY = offsets

        invalidateGenerated()
        statusMessage = "Preview changed — generate again."
    }

    function commandForSource(inputPath, includeProbe, positionScale) {
        let a = [
            scriptPath("split-wallpaper.sh"),
            inputPath,
            "--config", configPath,
            "--mode", mode
        ]
        for (let i = 1; i <= 3; ++i) {
            a.push("--monitor-" + i + "-x")
            a.push(String(Math.round(offsetX[i] * positionScale)))
            a.push("--monitor-" + i + "-y")
            a.push(String(Math.round(offsetY[i] * positionScale)))
        }
        if (includeProbe)
            a.push("--probe")
        return a
    }

    function commandBase(includeProbe) {
        return commandForSource(sourcePath, includeProbe, 1)
    }

    function probe() {
        if (sourcePath === "" || configPath === "")
            return
        probeProcess.command = commandBase(true)
        probeProcess.running = true
    }

    function checkApplyBackend() {
        if (backendCheckProcess.running)
            return
        backendCheckProcess.checkedBackend = applyBackend
        backendCheckProcess.command = [
            scriptPath("check-apply-backend.sh"), applyBackend
        ]
        backendCheckProcess.running = true
    }

    function saveApplyBackend(backend) {
        if (busy || configPath === "" || backend === applyBackend)
            return
        backendSaveProcess.requestedBackend = backend
        backendSaveProcess.command = [
            scriptPath("save-apply-backend.sh"), configPath, backend
        ]
        processError = ""
        statusMessage = "Saving Apply backend…"
        backendSaveProcess.running = true
    }

    function loadOutputDirectory() {
        if (configPath === "")
            return
        outputConfigLoader.command = [
            scriptPath("load-monitor-config.sh"), configPath
        ]
        outputConfigLoader.running = true
    }

        function manageCache(action) {
        if (cacheProcess.running || busy)
            return
        cacheProcess.action = action
        cacheProcess.command = [
            scriptPath("manage-cache.sh"), action
        ]
        cacheProcess.running = true
    }

    function checkUpscaler() {
        upscalerCheckProcess.command = [scriptPath("check-upscaler.sh")]
        upscalerCheckProcess.running = true
    }

    function applyProbe(text) {
        let values = {}
        for (let line of text.trim().split("\n")) {
            const p = line.indexOf("=")
            if (p >= 0)
                values[line.substring(0, p).trim()] = line.substring(p + 1).trim()
        }

        monitorCount = intAt(values, "MONITOR_COUNT", 0)
        previewW = intAt(values, "PREVIEW_W", 1)
        previewH = intAt(values, "PREVIEW_H", 1)
        desktopW = intAt(values, "DESKTOP_W", 1)
        desktopH = intAt(values, "DESKTOP_H", 1)

        sourceW = intAt(values, "SOURCE_W", 0)
        sourceH = intAt(values, "SOURCE_H", 0)
        idealW = intAt(values, "IDEAL_W", 0)
        idealH = intAt(values, "IDEAL_H", 0)
        sourceSufficient = valueAt(values, "SOURCE_SUFFICIENT", "true") === "true"
        recommendedScale = intAt(values, "RECOMMENDED_SCALE", 1)

        let names = ["", "", "", ""]
        let pw = [0,0,0,0], ph = [0,0,0,0]
        let px = [0,0,0,0], py = [0,0,0,0], pww = [1,1,1,1], phh = [1,1,1,1]
        let cw = [1,1,1,1], ch = [1,1,1,1], bx = [0,0,0,0], by = [0,0,0,0]
        let xmin = [0,0,0,0], xmax = [0,0,0,0], ymin = [0,0,0,0], ymax = [0,0,0,0]

        for (let i = 1; i <= 3; ++i) {
            names[i] = valueAt(values, "MONITOR_" + i + "_OUTPUT", "")
            pw[i] = intAt(values, "MONITOR_" + i + "_WIDTH", 0)
            ph[i] = intAt(values, "MONITOR_" + i + "_HEIGHT", 0)
            px[i] = intAt(values, "MONITOR_" + i + "_PHYS_X", 0)
            py[i] = intAt(values, "MONITOR_" + i + "_PHYS_Y", 0)
            pww[i] = intAt(values, "MONITOR_" + i + "_PHYS_W", 1)
            phh[i] = intAt(values, "MONITOR_" + i + "_PHYS_H", 1)
            cw[i] = intAt(values, "MONITOR_" + i + "_CROP_W", 1)
            ch[i] = intAt(values, "MONITOR_" + i + "_CROP_H", 1)
            bx[i] = intAt(values, "MONITOR_" + i + "_BASE_X", 0)
            by[i] = intAt(values, "MONITOR_" + i + "_BASE_Y", 0)
            xmin[i] = intAt(values, "MONITOR_" + i + "_X_MIN", 0)
            xmax[i] = intAt(values, "MONITOR_" + i + "_X_MAX", 0)
            ymin[i] = intAt(values, "MONITOR_" + i + "_Y_MIN", 0)
            ymax[i] = intAt(values, "MONITOR_" + i + "_Y_MAX", 0)
        }

        outputName = names; pixelW = pw; pixelH = ph
        physX = px; physY = py; physW = pww; physH = phh
        cropW = cw; cropH = ch; baseX = bx; baseY = by
        xMin = xmin; xMax = xmax; yMin = ymin; yMax = ymax
        let slots = []
        for (let i = 1; i <= 3; ++i) {
            if (valueAt(values, "MONITOR_" + i + "_ENABLED", "false") === "true")
                slots.push(i)
        }
        activeSlots = slots
        monitorCount = slots.length
    }

    // Capture settings once; the controller holds cache access across both stages.
    function generate() {
        if (busy)
            return
        if (sourcePath === "") {
            statusMessage = "Choose a wallpaper first."
            return
        }
        if (upscaleScale !== 1 && !upscalerAvailable) {
            statusMessage = "Real-ESRGAN is not available."
            return
        }

        invalidateGenerated()
        upscaledSourcePath = ""
        cancelRequested = false
        jobPhase = ""
        jobProgress = -1
        statusMessage = "Starting generation…"

        pendingSplitCommand = commandForSource(
            sourcePath, false, mode === "quality" ? upscaleScale : 1)

        generationProcess.command = [
            "python3", scriptPath("run-generation.py"),
            "--scale", String(upscaleScale), "--"
        ].concat(pendingSplitCommand)
        generationProcess.running = true
    }

    function cancelGeneration() {
        if (!generating || cancelRequested)
            return
        cancelRequested = true
        statusMessage = "Cancelling — cleaning up…"
        generationProcess.signal(15)
    }

    function readGenerationLine(line) {
        if (line.startsWith("JOB_PHASE=")) {
            jobPhase = line.substring(10)
        } else if (line.startsWith("JOB_STAGE=")) {
            if (!cancelRequested)
                statusMessage = line.substring(10)
        } else if (line.startsWith("JOB_PROGRESS=")) {
            jobProgress = Number(line.substring(13))
        } else if (line.startsWith("UPSCALE_OUTPUT=")) {
            upscaledSourcePath = line.substring(15)
        } else {
            generationProcess.resultText += line + "\n"
        }
    }

    function parseResult(text) {
        let files = ["", "", "", ""]
        for (let line of text.trim().split("\n")) {
            const p = line.indexOf("=")
            if (p < 0) continue
            const key = line.substring(0, p).trim()
            const value = line.substring(p + 1).trim()
            if (key === "PAIR")
                generatedPair = value
            for (let i = 1; i <= 3; ++i) {
                if (key === "MONITOR_" + i + "_FILE")
                    files[i] = value
            }
        }
        generatedFile = files
    }

    function generatedReady() {
        if (activeSlots.length < 1)
            return false
        for (let slot of activeSlots) {
            if (generatedFile[slot] === "")
                return false
        }
        return true
    }

    function applyGenerated() {
        if (!generatedReady() || !backendReady)
            return
        let a = [
            scriptPath("apply-wallpapers.sh"),
            "--backend", applyBackend
        ]
        for (let slot of activeSlots) {
            a.push(outputName[slot])
            a.push(generatedFile[slot])
        }
        applying = true
        processError = ""
        statusMessage = "Applying wallpapers…"
        applyProcess.command = a
        applyProcess.running = true
    }

    function reloadConfiguration() {
        loadOutputDirectory()
        invalidateGenerated()
        resetOffsets()
        statusMessage = sourcePath === "" ? "Monitor setup updated. Choose a wallpaper." : "Monitor setup updated."
        if (sourcePath !== "")
            probe()
    }

    Process {
        id: outputConfigLoader

        stdout: StdioCollector {
            onStreamFinished: {
                for (let line of text.split("\n")) {
                    if (line.startsWith("OUTPUT_DIR="))
                        root.outputDirectory = line.substring(11)
                    else if (line.startsWith("APPLY_BACKEND=")) {
                        const backend = line.substring(14)
                        root.applyBackend = root.applyBackendValues.indexOf(backend) >= 0
                            ? backend : "serpantinum"
                    }
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.processError = text.trim()
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: !root.busy
        onTriggered: root.checkApplyBackend()
    }

    Process {
        id: backendCheckProcess
        property string checkedBackend: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (backendCheckProcess.checkedBackend !== root.applyBackend)
                    return

                let ready = false
                let reason = "Could not determine backend readiness."

                for (let line of text.split("\n")) {
                    if (line.startsWith("BACKEND_READY="))
                        ready = line.substring(14) === "true"
                    else if (line.startsWith("BACKEND_REASON="))
                        reason = line.substring(15)
                }

                root.backendReady = ready
                root.backendStatus = reason
            }
        }

        stderr: StdioCollector {}

        onExited: function(exitCode) {
            if (exitCode !== 0 && checkedBackend === root.applyBackend) {
                root.backendReady = false
                root.backendStatus = "Backend check failed with code " + exitCode + "."
            }
        }
    }

    Process {
        id: backendSaveProcess
        property string requestedBackend: ""
        property string errorText: ""

        onRunningChanged: {
            if (running)
                errorText = ""
        }

        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: backendSaveProcess.errorText = text.trim()
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.processError = errorText !== ""
                    ? errorText : "Could not save Apply backend."
                root.statusMessage = "Apply backend was not changed."
                return
            }
            root.applyBackend = requestedBackend
            root.statusMessage = "Apply backend saved."
        }
    }

    FolderDialog {
        id: outputFolderDialog
        title: "Choose wallpaper output folder"

        onAccepted: {
            outputSaveProcess.requestedDirectory = root.cleanPath(selectedFolder)
            outputSaveProcess.command = [
                root.scriptPath("save-output-dir.sh"),
                root.configPath,
                outputSaveProcess.requestedDirectory
            ]
            root.processError = ""
            root.statusMessage = "Saving output folder…"
            outputSaveProcess.running = true
        }
    }

    Process {
        id: outputSaveProcess
        property string requestedDirectory: ""
        property string errorText: ""

        onRunningChanged: {
            if (running)
                errorText = ""
        }

        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: outputSaveProcess.errorText = text.trim()
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.processError = errorText !== ""
                    ? errorText : "Could not save output folder."
                root.statusMessage = "Output folder was not changed."
                return
            }
            root.outputDirectory = requestedDirectory
            root.invalidateGenerated()
            root.statusMessage = "Output folder saved — generate wallpapers when ready."
        }
    }

    FileDialog {
        id: wallpaperDialog
        title: "Choose wallpaper"
        currentFolder: wallpaperSettings.lastFolder
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)", "All files (*)"]

        onAccepted: {
            const selectedUrl = selectedFile.toString()

            root.sourceUrl = selectedUrl
            root.sourcePath = root.cleanPath(selectedUrl)
            root.resetOffsets()
            root.statusMessage = "Ready."

            wallpaperSettings.lastFolder = selectedUrl.substring(
                0, selectedUrl.lastIndexOf("/") + 1)
            wallpaperSettings.sync()
        }
    }

    Core.Settings {
        id: wallpaperSettings
        location: Qt.resolvedUrl("file-dialog.ini")
        category: "WallpaperDialog"
        property url lastFolder: ""
    }

    Process {
        id: probeProcess
        stdout: StdioCollector { onStreamFinished: root.applyProbe(text) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.processError = text.trim()
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.statusMessage = "Could not read wallpaper geometry."
        }
    }

    Process {
        id: generationProcess
        property string resultText: ""
        property string errorText: ""

        onRunningChanged: {
            if (running) {
                resultText = ""
                errorText = ""
            }
        }

        stdout: SplitParser {
            onRead: data => root.readGenerationLine(data)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                generationProcess.errorText = text.trim()
                    .split("\n").slice(-20).join("\n")
            }
        }

        onExited: function(exitCode) {
            if (exitCode === 130) {
                root.invalidateGenerated()
                root.statusMessage = "Generation cancelled."
            } else if (exitCode !== 0) {
                root.invalidateGenerated()
                root.processError = errorText !== ""
                    ? errorText
                    : "Generation controller exited with code " + exitCode + "."
                root.statusMessage = "Generation failed."
            } else {
                root.parseResult(resultText)
                root.statusMessage = root.generatedReady()
                    ? "Wallpapers generated — ready to apply."
                    : "Generation finished, but output paths were not returned."
            }

            root.cancelRequested = false
            root.jobPhase = ""
            root.jobProgress = -1
        }
    }

        Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: !root.busy
        onTriggered: root.manageCache("stats")
    }

    Process {
        id: cacheProcess
        property string action: "stats"
        property string errorText: ""

        onRunningChanged: {
            if (running)
                errorText = ""
        }

        stdout: StdioCollector {
            onStreamFinished: {
                for (let line of text.split("\n")) {
                    if (line.startsWith("CACHE_BYTES="))
                        root.cacheBytes = Number(line.substring(12))
                    else if (line.startsWith("CACHE_FILES="))
                        root.cacheFiles = Number(line.substring(12))
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: cacheProcess.errorText = text.trim()
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.processError = errorText !== ""
                    ? errorText : "Could not inspect or clear AI cache."
                return
            }

            root.cacheChecked = true
            if (action === "clear") {
                root.upscaledSourcePath = ""
                root.processError = ""
                root.statusMessage = "AI cache cleared."
            }
        }
    }

    Process {
        id: upscalerCheckProcess

        stdout: StdioCollector {
            onStreamFinished: {
                let available = false

                for (let line of text.trim().split("\n")) {
                    const p = line.indexOf("=")
                    if (p < 0)
                        continue

                    const key = line.substring(0, p).trim()
                    const value = line.substring(p + 1).trim()

                    if (key === "UPSCALER_AVAILABLE")
                        available = value === "true"
                }

                root.upscalerAvailable = available
                root.upscalerChecked = true

                if (!available)
                    root.upscaleScale = 1
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.upscalerAvailable = false
                root.upscalerChecked = true
                root.upscaleScale = 1
            }
        }
    }

    Process {
        id: applyProcess

        property string stdoutText: ""
        property string stderrText: ""

        stdout: StdioCollector {
            onStreamFinished: applyProcess.stdoutText = text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: applyProcess.stderrText = text.trim()
        }

        onRunningChanged: {
            if (running) {
                stdoutText = ""
                stderrText = ""
            }
        }

        onExited: function(exitCode) {
            root.applying = false

            if (exitCode === 0) {
                root.processError = ""
                root.statusMessage = "Wallpapers applied successfully."
                return
            }

            let detail = stderrText
            if (detail === "")
                detail = stdoutText
            if (detail === "")
                detail = "Wallpaper Apply helper exited with code " + exitCode + "."

            root.processError = detail
            root.statusMessage = "Apply failed — generated files are safe."
        }
    }

    // Upper controls scroll; results and cancellation remain fixed below.
    ScrollView {
        id: workspaceScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: workspaceResults.top
        anchors.margins: 22
        anchors.bottomMargin: 12
        clip: true
        contentWidth: availableWidth
        contentHeight: workspaceContent.implicitHeight

        ColumnLayout {
            id: workspaceContent
            width: workspaceScroll.availableWidth
            spacing: 12
            enabled: !root.busy

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: "Wallpaper Splitter"
                    color: Theme.text
                    font.pixelSize: 25
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    text: root.sourcePath === "" ? "No wallpaper selected" : root.sourcePath
                    color: Theme.subtext
                    elide: Text.ElideMiddle
                }
            }
            Button {
                text: "Settings"
                onClicked: settingsDialog.open()
                ToolTip.visible: hovered
                ToolTip.text: "Output folder, wallpaper backend, AI cache, and app information."
            }
            Button {
                text: "Choose Wallpaper"
                onClicked: wallpaperDialog.open()
                ToolTip.visible: hovered
                ToolTip.text: "Choose the source image that Hunu will crop for your monitors."
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: "Save to"
                color: Theme.subtext
            }
            Label {
                Layout.fillWidth: true
                text: root.outputDirectory === ""
                    ? "Save monitor setup first" : root.outputDirectory
                color: Theme.text
                elide: Text.ElideMiddle
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: root.mode === "linked" ? "Physical Layout Preview" : "Per-Monitor Preview"
                color: Theme.text
                font.bold: true
                font.pixelSize: 15
            }
            Label {
                text: "ⓘ"
                color: Theme.subtext
                font.pixelSize: 15
                ToolTip.visible: previewHelp.containsMouse
                ToolTip.text: root.mode === "linked"
                    ? "Monitor rectangles use the physical sizes and X/Y positions saved in Monitor Setup. The wallpaper remains one continuous composition across them."
                    : "Each monitor receives its own crop from the original image, maximizing usable source detail."
                MouseArea { id: previewHelp; anchors.fill: parent; hoverEnabled: true }
            }
            Item { Layout.fillWidth: true }
            Label {
                visible: root.monitorCount > 0
                text: root.monitorCount + (root.monitorCount === 1 ? " monitor" : " monitors")
                color: Theme.muted
            }
        }

        WorkspacePreview {
            workspace: root
            Layout.fillWidth: true
            Layout.preferredHeight: 210
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Label { text: "Mode"; color: Theme.text; font.bold: true }
            HunuRadioButton {
                text: "Linked / Seam"
                checked: root.mode === "linked"
                onClicked: {
                    root.mode = "linked"
                    root.resetOffsets()
                }
                ToolTip.visible: hovered
                ToolTip.text: "One continuous wallpaper composition across the physical monitor arrangement."
            }
            HunuRadioButton {
                text: "Maximum Quality / Independent"
                checked: root.mode === "quality"
                onClicked: {
                    root.mode = "quality"
                    root.resetOffsets()
                }
                ToolTip.visible: hovered
                ToolTip.text: "Crop the original image separately for each monitor to preserve maximum source detail."
            }
            CheckBox {
                id: linkedMovementControl
                text: "Move together"
                visible: root.mode === "linked"
                checked: root.linkedOffsets

                contentItem: Text {
                    text: linkedMovementControl.text
                    font: linkedMovementControl.font
                    color: linkedMovementControl.enabled
                        ? Theme.text : Theme.muted
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: linkedMovementControl.indicator.width
                        + linkedMovementControl.spacing
                }

                onClicked: {
                    root.linkedOffsets = checked
                    if (checked && root.activeSlots.length > 0) {
                        const slot = root.activeSlots[0]
                        root.setOffset(slot, "x", root.offsetX[slot])
                        root.setOffset(slot, "y", root.offsetY[slot])
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Center / Reset"
                enabled: root.sourcePath !== ""
                onClicked: root.resetOffsets()
                ToolTip.visible: hovered
                ToolTip.text: "Return every wallpaper crop to its calculated centered position."
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.mode === "linked"
                ? "Linked / Seam treats your measured monitor arrangement as one physical canvas."
                : "Maximum Quality crops the original wallpaper independently for each monitor."
            color: Theme.muted
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: Qt.alpha(Theme.subtext, 0.22)
            visible: root.sourcePath !== ""

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 18

                ColumnLayout {
                    spacing: 3

                    Label {
                        text: "Image Quality"
                        color: Theme.text
                        font.bold: true
                        font.pixelSize: 15
                    }

                    Label {
                        text: "Source  " + root.sourceW + " × " + root.sourceH
                            + "   ·   Recommended  " + root.idealW + " × " + root.idealH
                        color: Theme.subtext
                        font.pixelSize: 12
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    spacing: 5

                    Label {
                        Layout.alignment: Qt.AlignRight

                        text: root.sourceSufficient
                            ? "Source quality: Excellent"
                            : "Source quality: Below recommended"

                        color: root.sourceSufficient
                            ? Theme.success
                            : Theme.text

                        font.bold: true
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 4

                        Label {
                            text: "AI Upscaling"
                            color: Theme.subtext
                            font.pixelSize: 12
                        }

                        HunuRadioButton {
                            text: "Off"
                            checked: root.upscaleScale === 1
                            onClicked: root.upscaleScale = 1
                        }

                        HunuRadioButton {
                            text: "2×"
                            enabled: root.upscalerAvailable
                            checked: root.upscaleScale === 2
                            onClicked: root.upscaleScale = 2
                        }

                        HunuRadioButton {
                            text: "3×"
                            enabled: root.upscalerAvailable
                            checked: root.upscaleScale === 3
                            onClicked: root.upscaleScale = 3
                        }

                        HunuRadioButton {
                            text: "4×"
                            enabled: root.upscalerAvailable
                            checked: root.upscaleScale === 4
                            onClicked: root.upscaleScale = 4
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignRight

                        text: !root.upscalerChecked
                            ? "Checking Real-ESRGAN…"
                            : !root.upscalerAvailable
                                ? "Real-ESRGAN is not installed — AI upscaling is optional."
                                : root.sourceSufficient
                                    ? "No upscaling needed."
                                    : root.recommendedScale > 0
                                        ? "Recommended: " + root.recommendedScale + "×"
                                        : "4× is the highest available scale and remains below ideal."

                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Wallpaper Position"
                color: Theme.text
                font.bold: true
                font.pixelSize: 15
            }
            Label {
                text: "ⓘ"
                color: Theme.subtext
                ToolTip.visible: positionHelp.containsMouse
                ToolTip.text: "X moves the source image horizontally; Y moves it vertically. Available movement is limited so the crop never leaves empty space."
                MouseArea { id: positionHelp; anchors.fill: parent; hoverEnabled: true }
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: root.activeSlots.length
                delegate: HunuOffsetCard {
                    workspace: root
                    required property int index
                    slot: root.activeSlots[index]
                }
            }
        }

        } // workspaceContent
    } // workspaceScroll

    Rectangle {
        id: workspaceResults
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        height: 118
            radius: 10
            color: Theme.surface
            clip: true

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
                            visible: root.generating
                            from: 0
                            to: 100
                            value: Math.max(0, root.jobProgress)
                            indeterminate: root.jobProgress < 0
                        }

                        Label {
                            width: parent.width
                            visible: root.generating && root.jobProgress >= 0
                            text: Math.round(root.jobProgress) + "%"
                            color: Theme.subtext
                            font.pixelSize: 12
                        }
                        Label {
                            width: parent.width
                            text: root.backendStatus
                            color: root.backendReady ? Theme.success : Theme.subtext
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            width: parent.width
                            text: root.generatedPair !== ""
                                ? root.statusMessage + "  ·  Set " + root.generatedPair
                                : root.statusMessage
                            color: Theme.success
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: root.activeSlots.length
                            delegate: Label {
                                required property int index
                                property int slot: root.activeSlots[index]
                                width: resultContent.width
                                visible: root.generatedFile[slot] !== ""
                                text: "Monitor " + slot + " · " + root.outputName[slot]
                                    + " · " + root.generatedFile[slot].split("/").pop()
                                color: Theme.subtext
                                elide: Text.ElideRight
                            }
                        }

                        Label {
                            visible: root.processError !== ""
                            width: parent.width
                            text: root.processError
                            color: Theme.muted
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Button {
                    Layout.preferredWidth: 96
                    Layout.minimumWidth: 96
                    Layout.maximumWidth: 96
                    visible: root.generating
                    text: root.cancelRequested ? "Cancelling…" : "Cancel"
                    enabled: root.generating && !root.cancelRequested
                    onClicked: root.cancelGeneration()
                    ToolTip.visible: hovered
                    ToolTip.text: "Stop generation and clean up unfinished files."
                }

                Button {
                    Layout.preferredWidth: 112
                    Layout.minimumWidth: 112
                    Layout.maximumWidth: 112
                    text: root.generating
                        ? root.jobPhase === "upscale"
                            ? "Upscaling…" : "Generating…"
                        : "Generate"
                    enabled: root.sourcePath !== "" && !root.busy
                    onClicked: root.generate()
                    ToolTip.visible: hovered
                    ToolTip.text: "Create one correctly sized wallpaper file for every enabled monitor."
                }

                Button {
                    Layout.preferredWidth: 96
                    Layout.minimumWidth: 96
                    Layout.maximumWidth: 96
                    text: root.applying ? "Applying…" : "Apply"
                    enabled: root.generatedReady()
                        && root.backendReady
                        && !root.busy
                    onClicked: root.applyGenerated()
                    ToolTip.visible: hovered
                    ToolTip.text: "Apply generated wallpapers through the selected backend."
                 }
            }

    }
}