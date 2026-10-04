import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string configPath: ""
    property string sourcePath: ""
    property string sourceUrl: ""
    property string mode: "linked"

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
    readonly property bool busy: upscaleProcess.running || splitterProcess.running || applying
	property var pendingSplitCommand: []

    signal monitorSetupRequested()
    Component.onCompleted: checkUpscaler()

    function scriptPath(name) {
        return Qt.resolvedUrl(name).toString().replace("file://", "")
    }

    function cleanPath(url) {
        let p = url.toString()
        if (p.startsWith("file://"))
            p = decodeURIComponent(p.substring(7))
        return p
    }

    function replaceAt(a, i, value) {
        let b = a.slice()
        b[i] = value
        return b
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

    function setOffset(slot, axis, value) {
        if (axis === "x")
            offsetX = replaceAt(offsetX, slot, Math.round(value))
        else
            offsetY = replaceAt(offsetY, slot, Math.round(value))
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

    function generate() {
        if (sourcePath === "") {
            statusMessage = "Choose a wallpaper first."
            return
        }

        invalidateGenerated()
        upscaledSourcePath = ""
        pendingSplitCommand = commandForSource(
            sourcePath, false, mode === "quality" ? upscaleScale : 1)

        if (upscaleScale === 1) {
            statusMessage = "Generating wallpapers…"
            splitterProcess.command = commandBase(false)
            splitterProcess.running = true
            return
        }

        if (!upscalerAvailable) {
            statusMessage = "Real-ESRGAN is not available."
            return
        }

        statusMessage = "AI upscaling source " + upscaleScale + "×…"
        upscaleProcess.command = [
            scriptPath("upscale-image.sh"),
            "--input", sourcePath,
            "--scale", String(upscaleScale)
        ]
        upscaleProcess.running = true
    }

    function parseUpscaleResult(text) {
        for (let line of text.trim().split("\n")) {
            const p = line.indexOf("=")
            if (p < 0)
                continue
            const key = line.substring(0, p).trim()
            const value = line.substring(p + 1).trim()
            if (key === "UPSCALE_OUTPUT")
                upscaledSourcePath = value
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
        if (!generatedReady())
            return
        let a = [scriptPath("apply-serpantinum.sh")]
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
        invalidateGenerated()
        resetOffsets()
        statusMessage = sourcePath === "" ? "Monitor setup updated. Choose a wallpaper." : "Monitor setup updated."
        if (sourcePath !== "")
            probe()
    }

    FileDialog {
        id: wallpaperDialog
        title: "Choose wallpaper"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)", "All files (*)"]
        onAccepted: {
            root.sourceUrl = selectedFile.toString()
            root.sourcePath = root.cleanPath(selectedFile)
            root.resetOffsets()
            root.statusMessage = "Ready."
        }
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
        id: splitterProcess
        stdout: StdioCollector { onStreamFinished: root.parseResult(text) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.processError = text.trim()
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.statusMessage = "Generation failed."
            else if (!root.generatedReady())
                root.statusMessage = "Generation finished, but output paths were not returned."
            else
                root.statusMessage = "Wallpapers generated — ready to apply."
        }
    }

    Process {
        id: upscaleProcess

        stdout: StdioCollector {
            onStreamFinished: root.parseUpscaleResult(text)
        }
        stderr: StdioCollector {
            // Real-ESRGAN writes normal GPU/progress diagnostics to stderr.
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.statusMessage = "AI upscaling failed."
                root.processError = "Real-ESRGAN exited with an error."
                return
            }
            if (root.upscaledSourcePath === "") {
                root.statusMessage = "AI upscaling finished, but no output path was returned."
                return
            }

            root.statusMessage = "Upscaling complete — generating wallpapers…"
            let splitCommand = root.pendingSplitCommand.slice()
            splitCommand[1] = root.upscaledSourcePath
            splitterProcess.command = splitCommand
             splitterProcess.running = true
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
                detail = "apply-serpantinum.sh exited with code " + exitCode + "."

            root.processError = detail
            root.statusMessage = "Apply failed — generated files are safe."
        }
    }

    component HunuRadioButton: RadioButton {
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: parent.enabled ? Theme.text : Theme.muted
            verticalAlignment: Text.AlignVCenter
            leftPadding: parent.indicator.width + parent.spacing
        }
    }

    component HelpTip: ToolTip {
        delay: 450
        timeout: 7000
        background: Rectangle {
            radius: 7
            color: Theme.surface
            border.width: 1
            border.color: Qt.alpha(Theme.subtext, 0.28)
        }
        contentItem: Label {
            text: parent.text
            color: Theme.text
            wrapMode: Text.WordWrap
            font.pixelSize: 12
        }
    }

    component MonitorPreview: Rectangle {
        required property int slot
        required property bool linked
        property real previewScale: 1

        color: Theme.surface
        radius: 7
        clip: true
        border.width: 1
        border.color: Qt.alpha(Theme.subtext, 0.25)

        Image {
            source: root.sourceUrl
            asynchronous: true
            smooth: true
            fillMode: Image.Stretch
            width: root.previewW * parent.previewScale
            height: root.previewH * parent.previewScale
            x: -(root.baseX[parent.slot] + root.offsetX[parent.slot]) * parent.previewScale
            y: -(root.baseY[parent.slot] + root.offsetY[parent.slot]) * parent.previewScale
            visible: root.sourceUrl !== ""
        }

        Column {
            anchors.centerIn: parent
            spacing: 2
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Monitor " + parent.parent.slot
                color: Theme.text
                font.bold: true
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.outputName[parent.parent.slot]
                    + " · " + root.pixelW[parent.parent.slot]
                    + "×" + root.pixelH[parent.parent.slot]
                color: Theme.subtext
                font.pixelSize: 11
            }
        }
    }

    component OffsetInput: TextField {
        id: field
        required property int slot
        required property string axis

        readonly property int currentValue: axis === "x"
            ? root.offsetX[slot] : root.offsetY[slot]
        readonly property int minimum: axis === "x"
            ? root.xMin[slot] : root.yMin[slot]
        readonly property int maximum: axis === "x"
            ? root.xMax[slot] : root.yMax[slot]

        Layout.preferredWidth: 80
        text: String(currentValue)
        color: Theme.text
        horizontalAlignment: TextInput.AlignRight
        selectByMouse: true
        validator: IntValidator {}
        background: Rectangle {
            radius: 6
            color: Theme.base
            border.width: 1
            border.color: field.activeFocus
                ? Theme.subtext : Qt.alpha(Theme.subtext, 0.35)
        }

        function commitValue() {
            if (acceptableInput) {
                const value = Math.max(minimum,
                    Math.min(maximum, Number(text)))
                if (value !== currentValue)
                    root.setOffset(slot, axis, value)
            }
            text = String(currentValue)
        }

        onCurrentValueChanged: {
            if (!activeFocus)
                text = String(currentValue)
        }
        onAccepted: commitValue()
        onActiveFocusChanged: {
            if (activeFocus)
                selectAll()
            else
                commitValue()
        }
    }

    component OffsetCard: Rectangle {
        required property int slot
        Layout.fillWidth: true
        implicitHeight: 188
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Qt.alpha(Theme.subtext, 0.22)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 7

            Label {
                text: "Monitor " + parent.parent.slot + " — " + root.outputName[parent.parent.slot]
                color: Theme.text
                font.bold: true
                font.pixelSize: 15
            }
            Label {
                text: root.pixelW[parent.parent.slot] + " × " + root.pixelH[parent.parent.slot]
                color: Theme.muted
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "X"; color: Theme.text; Layout.preferredWidth: 18 }
                Slider {
                    Layout.fillWidth: true
                    from: root.xMin[parent.parent.parent.slot]
                    to: root.xMax[parent.parent.parent.slot]
                    value: root.offsetX[parent.parent.parent.slot]
                    stepSize: 1
                    enabled: from !== to
                    onMoved: root.setOffset(parent.parent.parent.slot, "x", value)
                }
                OffsetInput {
                    slot: parent.parent.parent.slot
                    axis: "x"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Y"; color: Theme.text; Layout.preferredWidth: 18 }
                Slider {
                    Layout.fillWidth: true
                    from: root.yMin[parent.parent.parent.slot]
                    to: root.yMax[parent.parent.parent.slot]
                    value: root.offsetY[parent.parent.parent.slot]
                    stepSize: 1
                    enabled: from !== to
                    onMoved: root.setOffset(parent.parent.parent.slot, "y", value)
                }
                OffsetInput {
                    slot: parent.parent.parent.slot
                    axis: "y"
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.mode === "linked"
                    ? "Move this crop while preserving the shared composition."
                    : "Move this monitor's independent crop within the original image."
                color: Theme.muted
                wrapMode: Text.WordWrap
                font.pixelSize: 12
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
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
                text: "Monitor Setup"
                onClicked: root.monitorSetupRequested()
                ToolTip.visible: hovered
                ToolTip.text: "Change monitor assignment, physical measurements, or desk position."
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

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 255

            Item {
                id: linkedPreview
                anchors.centerIn: parent
                visible: root.mode === "linked"
                width: Math.min(parent.width, parent.height * root.desktopW / Math.max(1, root.desktopH))
                height: width * root.desktopH / Math.max(1, root.desktopW)
                property real unitScale: width / Math.max(1, root.desktopW)

                Repeater {
                    model: root.activeSlots.length
                    delegate: MonitorPreview {
                        required property int index
                        slot: root.activeSlots[index]
                        linked: true
                        x: root.physX[slot] * linkedPreview.unitScale
                        y: root.physY[slot] * linkedPreview.unitScale
                        width: root.physW[slot] * linkedPreview.unitScale
                        height: root.physH[slot] * linkedPreview.unitScale
                        previewScale: width / Math.max(1, root.cropW[slot])
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 16
                visible: root.mode === "quality"

                Repeater {
                    model: root.activeSlots.length
                    delegate: Item {
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property int slot: root.activeSlots[index]

                        MonitorPreview {
                            anchors.centerIn: parent
                            slot: parent.slot
                            linked: false
                            width: {
                                const ar = root.pixelW[slot] / Math.max(1, root.pixelH[slot])
                                return Math.min(parent.width - 8, (parent.height - 8) * ar)
                            }
                            height: width * root.pixelH[slot] / Math.max(1, root.pixelW[slot])
                            previewScale: Math.min(width / Math.max(1, root.cropW[slot]),
                                                   height / Math.max(1, root.cropH[slot]))
                        }
                    }
                }
            }
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
                delegate: OffsetCard {
                    required property int index
                    slot: root.activeSlots[index]
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 118
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
                    Layout.preferredWidth: 112
                    Layout.minimumWidth: 112
                    Layout.maximumWidth: 112
                    text: upscaleProcess.running ? "Upscaling…"
                        : splitterProcess.running ? "Generating…" : "Generate"
                    enabled: root.sourcePath !== ""
                        && !upscaleProcess.running
                        && !splitterProcess.running
                        && !root.applying
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
                        && !upscaleProcess.running
                        && !splitterProcess.running
                        && !root.applying
                    onClicked: root.applyGenerated()
                    ToolTip.visible: hovered
                    ToolTip.text: "Optional: applies through Serpantinum when its wallpaper IPC is installed."
                }
            }
        }
    }
}
