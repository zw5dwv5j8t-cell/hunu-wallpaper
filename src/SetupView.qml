import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    implicitWidth: 980
    implicitHeight: 820

    // The setup view is embedded in the main Hunu window.
    // allowCancel is false during mandatory first-run setup.
    property bool allowCancel: false
    property string configPath: ""
    property bool loadingSavedSetup: false
    signal setupSaved()
    signal cancelRequested()

    property int page: 0
    property int detectedCount: 0
    property int supportedCount: 0
    property bool hasExtraMonitors: false
    property string detectorError: ""
    property var monitors: []

    // The setup UI supports three Hunu slots. A slot stores an index into
    // root.monitors; -1 means disabled/unassigned.
    property int slot1Index: 0
    property int slot2Index: supportedCount > 1 ? 1 : -1
    property int slot3Index: -1

    property real slot1WidthCm: 0
    property real slot1HeightCm: 0
    property real slot1Xcm: 0
    property real slot1Ycm: 0

    property real slot2WidthCm: 0
    property real slot2HeightCm: 0
    property real slot2Xcm: 0
    property real slot2Ycm: 0

    property real slot3WidthCm: 0
    property real slot3HeightCm: 0
    property real slot3Xcm: 0
    property real slot3Ycm: 0

    property bool initializedMeasurements: false
    property string saveStatus: ""

    function monitorAt(i) {
        if (i < 0 || i >= monitors.length)
            return null
        return monitors[i]
    }

    function parseDetector(text) {
        let values = {}
        const lines = text.trim().split("\n")
        for (let line of lines) {
            const pos = line.indexOf("=")
            if (pos < 0)
                continue
            values[line.substring(0, pos).trim()] =
                line.substring(pos + 1).trim()
        }

        detectedCount = parseInt(values.DETECTED_COUNT || "0")
        supportedCount = parseInt(values.SUPPORTED_COUNT || "0")
        hasExtraMonitors = values.HAS_EXTRA_MONITORS === "true"

        let found = []
        for (let i = 1; i <= supportedCount; ++i) {
            found.push({
                name: values["MONITOR_" + i + "_NAME"] || "",
                description: values["MONITOR_" + i + "_DESCRIPTION"] || "",
                make: values["MONITOR_" + i + "_MAKE"] || "",
                model: values["MONITOR_" + i + "_MODEL"] || "",
                width: parseInt(values["MONITOR_" + i + "_WIDTH"] || "0"),
                height: parseInt(values["MONITOR_" + i + "_HEIGHT"] || "0"),
                orientation: values["MONITOR_" + i + "_ORIENTATION"] || "",
                transform: parseInt(values["MONITOR_" + i + "_TRANSFORM"] || "0"),
                refresh: values["MONITOR_" + i + "_REFRESH"] || "",
                scale: values["MONITOR_" + i + "_SCALE"] || "",
                suggestedWidth: parseFloat(values["MONITOR_" + i + "_SUGGESTED_PHYSICAL_WIDTH_CM"] || "0"),
                suggestedHeight: parseFloat(values["MONITOR_" + i + "_SUGGESTED_PHYSICAL_HEIGHT_CM"] || "0")
            })
        }
        monitors = found

        slot1Index = found.length > 0 ? 0 : -1
        slot2Index = found.length > 1 ? 1 : -1
        slot3Index = -1
        initializeMeasurements()
        detectorError = ""
    }

    function initializeMeasurements() {
        const m1 = monitorAt(slot1Index)
        const m2 = monitorAt(slot2Index)
        const m3 = monitorAt(slot3Index)

        slot1WidthCm = m1 ? m1.suggestedWidth : 0
        slot1HeightCm = m1 ? m1.suggestedHeight : 0
        slot1Xcm = 0
        slot1Ycm = 0

        slot2WidthCm = m2 ? m2.suggestedWidth : 0
        slot2HeightCm = m2 ? m2.suggestedHeight : 0
        slot2Xcm = m1 ? m1.suggestedWidth : 0
        slot2Ycm = 0

        slot3WidthCm = m3 ? m3.suggestedWidth : 0
        slot3HeightCm = m3 ? m3.suggestedHeight : 0
        slot3Xcm = (m1 ? m1.suggestedWidth : 0) + (m2 ? m2.suggestedWidth : 0)
        slot3Ycm = 0
        initializedMeasurements = true
    }

    function resetPhysicalLayout() {
        slot1Xcm = 0
        slot1Ycm = 0
        slot2Xcm = slot1WidthCm
        slot2Ycm = 0
        slot3Xcm = slot1WidthCm + slot2WidthCm
        slot3Ycm = 0
    }

    function claimOutput(slot, detectorIndex) {
        const assignments = [slot1Index, slot2Index, slot3Index]

        if (detectorIndex === assignments[slot - 1])
            return false
        if (detectorIndex < -1 || detectorIndex >= monitors.length)
            return false
        if (slot === 1 && detectorIndex < 0)
            return false

        // An output belongs to only one slot. Reject duplicate selections.
        if (detectorIndex >= 0) {
            for (let i = 0; i < assignments.length; ++i) {
                if (i !== slot - 1 && assignments[i] === detectorIndex) {
                    saveStatus = "That output is already assigned to another monitor slot."
                    return false
                }
            }
        }

        if (slot === 1)
            slot1Index = detectorIndex
        else if (slot === 2)
            slot2Index = detectorIndex
        else if (slot === 3)
            slot3Index = detectorIndex

        saveStatus = ""
        return true
    }

    function assignmentValid() {
        if (slot1Index < 0)
            return false
        if (slot2Index >= 0 && slot2Index === slot1Index)
            return false
        if (slot3Index >= 0 && (slot3Index === slot1Index || slot3Index === slot2Index))
            return false
        return slot1WidthCm > 0 && slot1HeightCm > 0
            && (slot2Index < 0 || (slot2WidthCm > 0 && slot2HeightCm > 0))
            && (slot3Index < 0 || (slot3WidthCm > 0 && slot3HeightCm > 0))
    }

    function detectorIndexForOutput(outputName) {
        if (outputName === "")
            return -1
        for (let i = 0; i < monitors.length; ++i) {
            if (monitors[i].name === outputName)
                return i
        }
        return -1
    }

    function loadSavedSetup() {
        if (configPath === "")
            return
        savedConfigLoader.command = [
            Qt.resolvedUrl("load-monitor-config.sh").toString().replace("file://", ""),
            configPath
        ]
        savedConfigLoader.running = true
    }

    function applySavedSetup(text) {
        let values = {}
        for (let line of text.trim().split("\n")) {
            const pos = line.indexOf("=")
            if (pos < 0)
                continue
            values[line.substring(0, pos).trim()] =
                line.substring(pos + 1).trim()
        }

        if (values.CONFIG_LOADED !== "true")
            return

        loadingSavedSetup = true

        const i1 = detectorIndexForOutput(values.MONITOR_1_OUTPUT || "")
        const i2 = values.MONITOR_2_ENABLED === "true"
            ? detectorIndexForOutput(values.MONITOR_2_OUTPUT || "") : -1
        const i3 = values.MONITOR_3_ENABLED === "true"
            ? detectorIndexForOutput(values.MONITOR_3_OUTPUT || "") : -1

        // Preserve the user's slot ordering from config.conf. If a previously
        // configured output is no longer connected, leave that optional slot
        // disabled rather than silently assigning a different display.
        slot1Index = i1 >= 0 ? i1 : (monitors.length > 0 ? 0 : -1)
        slot2Index = i2
        slot3Index = i3

        function savedNumber(key, fallback) {
            const n = Number(values[key])
            return isNaN(n) ? fallback : n
        }

        const m1 = monitorAt(slot1Index)
        const m2 = monitorAt(slot2Index)
        const m3 = monitorAt(slot3Index)

        slot1WidthCm  = savedNumber("MONITOR_1_PHYSICAL_WIDTH_CM",  m1 ? m1.suggestedWidth : 0)
        slot1HeightCm = savedNumber("MONITOR_1_PHYSICAL_HEIGHT_CM", m1 ? m1.suggestedHeight : 0)
        slot1Xcm      = savedNumber("MONITOR_1_X_CM", 0)
        slot1Ycm      = savedNumber("MONITOR_1_Y_CM", 0)

        slot2WidthCm  = savedNumber("MONITOR_2_PHYSICAL_WIDTH_CM",  m2 ? m2.suggestedWidth : 0)
        slot2HeightCm = savedNumber("MONITOR_2_PHYSICAL_HEIGHT_CM", m2 ? m2.suggestedHeight : 0)
        slot2Xcm      = savedNumber("MONITOR_2_X_CM", slot1WidthCm)
        slot2Ycm      = savedNumber("MONITOR_2_Y_CM", 0)

        slot3WidthCm  = savedNumber("MONITOR_3_PHYSICAL_WIDTH_CM",  m3 ? m3.suggestedWidth : 0)
        slot3HeightCm = savedNumber("MONITOR_3_PHYSICAL_HEIGHT_CM", m3 ? m3.suggestedHeight : 0)
        slot3Xcm      = savedNumber("MONITOR_3_X_CM", slot1WidthCm + slot2WidthCm)
        slot3Ycm      = savedNumber("MONITOR_3_Y_CM", 0)

        initializedMeasurements = true
        loadingSavedSetup = false
    }

    function detect() {
        detectorError = ""
        detector.running = true
    }

    Component.onCompleted: detect()

    Process {
        id: detector
        command: [Qt.resolvedUrl("detect-monitors.sh").toString().replace("file://", "")]
        stdout: StdioCollector { onStreamFinished: root.parseDetector(text) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.detectorError = text.trim()
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.detectorError === "")
                root.detectorError = "Monitor detection failed."
            else if (exitCode === 0)
                root.loadSavedSetup()
        }
    }

    Process {
        id: savedConfigLoader
        stdout: StdioCollector {
            onStreamFinished: root.applySavedSetup(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                // A missing config is normal on first run, so only surface
                // unexpected loader messages.
                if (text.trim() !== "" && root.allowCancel)
                    root.detectorError = text.trim()
            }
        }
    }

    // Save is deliberately delegated to a helper script. This keeps shell
    // escaping and filesystem writes out of QML.
    Process {
        id: saver
        property var args: []
        command: args
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.saveStatus = text.trim()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.saveStatus = text.trim()
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.saveStatus = "Monitor setup saved."
                root.setupSaved()
            } else if (root.saveStatus === "") {
                root.saveStatus = "Could not save monitor setup."
            }
        }
    }

    component HunuButton: Rectangle {
        id: hb
        required property string label
        property bool enabled: true
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 28
        implicitHeight: 34
        radius: 8
        color: enabled
            ? (buttonMouse.containsMouse ? Qt.alpha(Theme.text, 0.16) : Theme.surface)
            : Qt.alpha(Theme.surface, 0.45)
        border.width: 1
        border.color: Qt.alpha(Theme.subtext, enabled ? 0.35 : 0.15)

        Label {
            id: buttonLabel
            anchors.centerIn: parent
            text: hb.label
            color: hb.enabled ? Theme.text : Theme.muted
            font.pixelSize: 13
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: hb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }

    component InfoTip: Label {
        required property string helpText
        text: "ⓘ"
        color: Theme.subtext
        font.pixelSize: 15
        ToolTip.visible: tipMouse.containsMouse
        ToolTip.text: helpText
        ToolTip.delay: 250
        MouseArea {
            id: tipMouse
            anchors.fill: parent
            hoverEnabled: true
        }
    }



    component AssignmentBox: ComboBox {
        id: combo
        property int assignedIndex: -1
        property bool allowDisabled: true
        property bool syncing: false
        signal outputSelected(int detectorIndex)

        implicitWidth: 260
        implicitHeight: 36

        // Always show every detected output. If the user selects an
        // output that is currently assigned to another Hunu slot, the root
        // assignment handler moves it here and automatically disables the
        // conflicting optional slot. This makes reassignment a one-click
        // operation instead of forcing the user to disable another slot first.
        property var availableEntries: {
            let result = []
            if (allowDisabled)
                result.push({ label: "Disabled", detectorIndex: -1 })

            for (let i = 0; i < root.monitors.length; ++i) {
                const m = root.monitors[i]
                result.push({
                    label: m.name + " — " + m.model,
                    detectorIndex: i
                })
            }
            return result
        }

        model: availableEntries.map(function(entry) { return entry.label })

        function syncCurrentIndex() {
            let wanted = -1
            for (let i = 0; i < availableEntries.length; ++i) {
                if (availableEntries[i].detectorIndex === assignedIndex) {
                    wanted = i
                    break
                }
            }

            if (wanted < 0 && availableEntries.length > 0)
                wanted = 0

            if (currentIndex !== wanted) {
                syncing = true
                currentIndex = wanted
                syncing = false
            }
        }

        Component.onCompleted: Qt.callLater(syncCurrentIndex)
        onAssignedIndexChanged: syncCurrentIndex()
        onAvailableEntriesChanged: Qt.callLater(syncCurrentIndex)
        onModelChanged: Qt.callLater(syncCurrentIndex)

        onActivated: function(i) {
            if (!syncing && i >= 0 && i < availableEntries.length) {
                outputSelected(availableEntries[i].detectorIndex)
                Qt.callLater(syncCurrentIndex)
            }
        }
    }

    component SetupCard: Rectangle {
        id: setupCard
        required property int slot
        required property int assignedIndex
        signal outputSelected(int detectorIndex)
        property alias widthValue: widthBox.numberValue
        property alias heightValue: heightBox.numberValue
        property alias xValue: xBox.numberValue
        property alias yValue: yBox.numberValue

        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 28
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Qt.alpha(Theme.subtext, 0.22)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Monitor " + slot
                    color: Theme.text
                    font.pixelSize: 17
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                AssignmentBox {
                    id: assignBox
                    allowDisabled: setupCard.slot !== 1
                    assignedIndex: setupCard.assignedIndex
                    onOutputSelected: function(detectorIndex) {
                        setupCard.outputSelected(detectorIndex)
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: root.monitorAt(assignBox.assignedIndex) !== null
                text: {
                    const m = root.monitorAt(assignBox.assignedIndex)
                    return m ? m.make + " " + m.model + "  •  "
                        + m.width + " × " + m.height + "  •  "
                        + m.orientation + "  •  " + m.refresh + " Hz" : ""
                }
                color: Theme.subtext
            }

            RowLayout {
                visible: assignBox.assignedIndex >= 0
                Layout.fillWidth: true
                spacing: 9

                Label { text: "Physical size"; color: Theme.text }
                InfoTip {
                    helpText: "Measure the complete visible monitor rectangle including its bezel. EDID values are only starting suggestions."
                }
                Item { Layout.fillWidth: true }

                Label { text: "W"; color: Theme.subtext }
                HunuNumberInput { id: widthBox }
                Label { text: "cm"; color: Theme.subtext }
                Label { text: "H"; color: Theme.subtext }
                HunuNumberInput { id: heightBox }
                Label { text: "cm"; color: Theme.subtext }
            }

            RowLayout {
                visible: assignBox.assignedIndex >= 0
                Layout.fillWidth: true
                spacing: 9

                Label { text: "Physical position"; color: Theme.text }
                InfoTip {
                    helpText: "X and Y describe where this physical monitor rectangle sits relative to the others. Positive X moves right; positive Y moves down."
                }
                Item { Layout.fillWidth: true }

                Label { text: "X"; color: Theme.subtext }
                HunuNumberInput { id: xBox }
                Label { text: "cm"; color: Theme.subtext }
                Label { text: "Y"; color: Theme.subtext }
                HunuNumberInput { id: yBox }
                Label { text: "cm"; color: Theme.subtext }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base

        StackLayout {
            anchors.fill: parent
            anchors.margins: 22
            currentIndex: root.page

            // PAGE 0 — detection
            ColumnLayout {
                spacing: 14

                Label {
                    text: "Monitor Setup"
                    color: Theme.text
                    font.pixelSize: 25
                    font.bold: true
                }
                Label {
                    text: detector.running ? "Detecting Hyprland displays…"
                        : detectedCount + (detectedCount === 1 ? " display detected" : " displays detected")
                    color: Theme.subtext
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Display names, resolution, orientation and refresh rate are detected automatically. Physical measurements are calibrated on the next screen."
                    color: Theme.subtext
                }

                Repeater {
                    model: root.monitors
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 105
                        radius: 12
                        color: Theme.surface
                        border.width: 1
                        border.color: Qt.alpha(Theme.subtext, 0.22)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6
                            Label {
                                text: "Detected display " + (index + 1)
                                color: Theme.text
                                font.bold: true
                            }
                            Label {
                                text: modelData.make + " " + modelData.model
                                color: Theme.text
                            }
                            Label {
                                text: modelData.name + "  •  " + modelData.width + " × "
                                    + modelData.height + "  •  " + modelData.orientation
                                    + "  •  " + modelData.refresh + " Hz"
                                color: Theme.subtext
                            }
                            Label {
                                text: "EDID size suggestion: " + modelData.suggestedWidth
                                    + " × " + modelData.suggestedHeight + " cm"
                                color: Theme.muted
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true

                    HunuButton {
                        label: "Back"
                        visible: root.allowCancel
                        enabled: !detector.running
                        onClicked: root.cancelRequested()
                    }

                    HunuButton {
                        label: "Detect Again"
                        enabled: !detector.running
                        onClicked: root.detect()
                    }

                    Item { Layout.fillWidth: true }

                    HunuButton {
                        label: "Continue"
                        enabled: root.supportedCount > 0 && !detector.running
                        onClicked: root.page = 1
                    }
                }
            }

            // PAGE 1 — assignment and calibration
            ColumnLayout {
                spacing: 12

                Label {
                    text: "Assign & Calibrate"
                    color: Theme.text
                    font.pixelSize: 25
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Choose which detected output belongs to each Hunu monitor slot. Then measure the complete monitor rectangle including the bezel and enter its real position on your desk."
                    color: Theme.subtext
                }

                ScrollView {
                    id: calibrationScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: calibrationScroll.availableWidth
                        spacing: 10

                        SetupCard {
                            id: card1
                            slot: 1
                            assignedIndex: root.slot1Index
                            widthValue: root.slot1WidthCm
                            heightValue: root.slot1HeightCm
                            xValue: root.slot1Xcm
                            yValue: root.slot1Ycm

                            onOutputSelected: function(detectorIndex) {
                                if (!root.claimOutput(1, detectorIndex))
                                    return
                                const m = root.monitorAt(root.slot1Index)
                                if (m) {
                                    root.slot1WidthCm = m.suggestedWidth
                                    root.slot1HeightCm = m.suggestedHeight
                                }
                            }
                            onWidthValueChanged: root.slot1WidthCm = widthValue
                            onHeightValueChanged: root.slot1HeightCm = heightValue
                            onXValueChanged: root.slot1Xcm = xValue
                            onYValueChanged: root.slot1Ycm = yValue
                        }

                        SetupCard {
                            id: card2
                            slot: 2
                            assignedIndex: root.slot2Index
                            widthValue: root.slot2WidthCm
                            heightValue: root.slot2HeightCm
                            xValue: root.slot2Xcm
                            yValue: root.slot2Ycm

                            onOutputSelected: function(detectorIndex) {
                                if (!root.claimOutput(2, detectorIndex))
                                    return
                                const m = root.monitorAt(root.slot2Index)
                                if (m) {
                                    root.slot2WidthCm = m.suggestedWidth
                                    root.slot2HeightCm = m.suggestedHeight
                                }
                            }
                            onWidthValueChanged: root.slot2WidthCm = widthValue
                            onHeightValueChanged: root.slot2HeightCm = heightValue
                            onXValueChanged: root.slot2Xcm = xValue
                            onYValueChanged: root.slot2Ycm = yValue
                        }

                        SetupCard {
                            id: card3
                            slot: 3
                            assignedIndex: root.slot3Index
                            widthValue: root.slot3WidthCm
                            heightValue: root.slot3HeightCm
                            xValue: root.slot3Xcm
                            yValue: root.slot3Ycm

                            onOutputSelected: function(detectorIndex) {
                                if (!root.claimOutput(3, detectorIndex))
                                    return
                                const m = root.monitorAt(root.slot3Index)
                                if (m) {
                                    root.slot3WidthCm = m.suggestedWidth
                                    root.slot3HeightCm = m.suggestedHeight
                                }
                            }
                            onWidthValueChanged: root.slot3WidthCm = widthValue
                            onHeightValueChanged: root.slot3HeightCm = heightValue
                            onXValueChanged: root.slot3Xcm = xValue
                            onYValueChanged: root.slot3Ycm = yValue
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Physical layout preview"
                                color: Theme.text
                                font.bold: true
                            }
                            InfoTip {
                                helpText: "This preview uses centimeters, not Hyprland logical pixels. It represents how the monitor rectangles physically sit on your desk."
                            }
                            Item { Layout.fillWidth: true }
                            HunuButton {
                                label: "Reset Layout"
                                onClicked: root.resetPhysicalLayout()
                            }
                        }

                        SetupLayoutPreview {
                            setup: root
                        }
                    }
                }

                Label {
                    visible: !root.assignmentValid()
                    Layout.fillWidth: true
                    text: "Each enabled monitor needs a unique output and positive physical width/height."
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }

                Label {
                    visible: root.saveStatus !== ""
                    Layout.fillWidth: true
                    text: root.saveStatus
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    HunuButton {
                        label: "Back"
                        onClicked: {
                            if (root.allowCancel)
                                root.loadSavedSetup()
                            root.page = 0
                        }
                    }
                    HunuButton {
                        visible: root.allowCancel
                        label: "Cancel"
                        onClicked: root.cancelRequested()
                    }
                    Item { Layout.fillWidth: true }
                    HunuButton {
                        label: saver.running ? "Saving…" : "Save Setup"
                        enabled: root.assignmentValid() && !saver.running
                        onClicked: {
                            const m1 = root.monitorAt(root.slot1Index)
                            const m2 = root.monitorAt(root.slot2Index)
                            const m3 = root.monitorAt(root.slot3Index)

                            let a = [
                                Qt.resolvedUrl("save-monitor-config.sh").toString().replace("file://", ""),
                                "--config", root.configPath,
                                "--m1-output", m1.name,
                                "--m1-width", String(m1.width),
                                "--m1-height", String(m1.height),
                                "--m1-physical-width", String(root.slot1WidthCm),
                                "--m1-physical-height", String(root.slot1HeightCm),
                                "--m1-x", String(root.slot1Xcm),
                                "--m1-y", String(root.slot1Ycm)
                            ]

                            if (m2) a = a.concat([
                                "--m2-output", m2.name,
                                "--m2-width", String(m2.width),
                                "--m2-height", String(m2.height),
                                "--m2-physical-width", String(root.slot2WidthCm),
                                "--m2-physical-height", String(root.slot2HeightCm),
                                "--m2-x", String(root.slot2Xcm),
                                "--m2-y", String(root.slot2Ycm)
                            ])

                            if (m3) a = a.concat([
                                "--m3-output", m3.name,
                                "--m3-width", String(m3.width),
                                "--m3-height", String(m3.height),
                                "--m3-physical-width", String(root.slot3WidthCm),
                                "--m3-physical-height", String(root.slot3HeightCm),
                                "--m3-x", String(root.slot3Xcm),
                                "--m3-y", String(root.slot3Ycm)
                            ])

                            saver.args = a
                            root.saveStatus = "Saving…"
                            saver.running = true
                        }
                    }
                }
            }
        }
    }
}
