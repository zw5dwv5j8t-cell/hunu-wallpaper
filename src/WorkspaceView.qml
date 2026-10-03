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
    property int previewW: 1
    property int previewH: 1
    property int desktopW: 1
    property int desktopH: 1

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

    signal monitorSetupRequested()

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

    function commandBase(includeProbe) {
        let a = [
            scriptPath("split-wallpaper.sh"),
            sourcePath,
            "--config", configPath,
            "--mode", mode
        ]
        for (let i = 1; i <= 3; ++i) {
            a.push("--monitor-" + i + "-x")
            a.push(String(offsetX[i]))
            a.push("--monitor-" + i + "-y")
            a.push(String(offsetY[i]))
        }
        if (includeProbe)
            a.push("--probe")
        return a
    }

    function probe() {
        if (sourcePath === "" || configPath === "")
            return
        probeProcess.command = commandBase(true)
        probeProcess.running = true
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
    }

    function generate() {
        if (sourcePath === "") {
            statusMessage = "Choose a wallpaper first."
            return
        }
        invalidateGenerated()
        statusMessage = "Generating wallpapers…"
        splitterProcess.command = commandBase(false)
        splitterProcess.running = true
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
        if (monitorCount < 1) return false
        for (let i = 1; i <= monitorCount; ++i)
            if (generatedFile[i] === "") return false
        return true
    }

    function applyGenerated() {
        if (!generatedReady())
            return
        let a = [scriptPath("apply-serpantinum.sh")]
        for (let i = 1; i <= monitorCount; ++i) {
            a.push(outputName[i])
            a.push(generatedFile[i])
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
        id: applyProcess
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.statusMessage = text.trim()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.processError = text.trim()
        }
        onExited: function(exitCode) {
            root.applying = false
            if (exitCode === 0)
                root.statusMessage = "Wallpapers applied."
            else
                root.statusMessage = "Apply unavailable or failed. Generated files are safe."
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
                Label {
                    text: String(root.offsetX[parent.parent.parent.slot])
                    color: Theme.subtext
                    Layout.preferredWidth: 58
                    horizontalAlignment: Text.AlignRight
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
                Label {
                    text: String(root.offsetY[parent.parent.parent.slot])
                    color: Theme.subtext
                    Layout.preferredWidth: 58
                    horizontalAlignment: Text.AlignRight
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
                    model: root.monitorCount
                    delegate: MonitorPreview {
                        required property int index
                        slot: index + 1
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
                    model: root.monitorCount
                    delegate: Item {
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property int slot: index + 1

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
            RadioButton {
                text: "Linked / Seam"
                checked: root.mode === "linked"
                onClicked: {
                    root.mode = "linked"
                    root.resetOffsets()
                }
                ToolTip.visible: hovered
                ToolTip.text: "One continuous wallpaper composition across the physical monitor arrangement."
            }
            RadioButton {
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
                model: root.monitorCount
                delegate: OffsetCard {
                    required property int index
                    slot: index + 1
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.generatedReady() ? 118 : 82
            radius: 10
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Label {
                        text: root.generatedPair !== ""
                            ? root.statusMessage + "  ·  Set " + root.generatedPair
                            : root.statusMessage
                        color: Theme.success
                        font.bold: true
                    }
                    Repeater {
                        model: root.monitorCount
                        delegate: Label {
                            required property int index
                            property int slot: index + 1
                            visible: root.generatedFile[slot] !== ""
                            text: "Monitor " + slot + " · " + root.outputName[slot]
                                + " · " + root.generatedFile[slot].split("/").pop()
                            color: Theme.subtext
                        }
                    }
                    Label {
                        visible: root.processError !== ""
                        Layout.fillWidth: true
                        text: root.processError
                        color: Theme.muted
                        elide: Text.ElideRight
                    }
                }

                Button {
                    text: splitterProcess.running ? "Generating…" : "Generate"
                    enabled: root.sourcePath !== "" && !splitterProcess.running && !root.applying
                    onClicked: root.generate()
                    ToolTip.visible: hovered
                    ToolTip.text: "Create one correctly sized wallpaper file for every enabled monitor."
                }
                Button {
                    text: root.applying ? "Applying…" : "Apply"
                    enabled: root.generatedReady() && !splitterProcess.running && !root.applying
                    onClicked: root.applyGenerated()
                    ToolTip.visible: hovered
                    ToolTip.text: "Optional: applies through Serpantinum when its wallpaper IPC is installed."
                }
            }
        }
    }
}
