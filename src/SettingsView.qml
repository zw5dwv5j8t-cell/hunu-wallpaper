import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Dialog {
    id: dialog
    required property var workspace

    property var dependencyAvailability: ({})
    property string dependencyError: ""

    property bool switcherEnabled: true
    property string switcherPosition: "center"
    property bool switcherShowButtons: true
    property bool switcherLivePreview: true
    property int switcherDelayMs: 400
    property bool switcherDirty: false
    property string switcherMessage: ""
    property string switcherError: ""
    readonly property bool switcherEditable: !switcherLoad.running && !switcherSave.running && !workspace.busy

    function switcherHelper() {
        return decodeURIComponent(Qt.resolvedUrl("switcher-settings.py").toString().replace("file://", ""))
    }
    function readSwitcherValues(text) {
        const values = JSON.parse(text)
        switcherEnabled = values.enabled
        switcherPosition = values.position
        switcherShowButtons = values.showActionButtons
        switcherLivePreview = values.livePreview
        switcherDelayMs = values.delayMs
        switcherDirty = false
    }
    function loadSwitcherSettings() {
        if (switcherLoad.running || switcherSave.running)
            return
        switcherError = ""
        switcherMessage = ""
        switcherLoad.command = ["python3", switcherHelper(), "get"]
        switcherLoad.running = true
    }
    function saveSwitcherSettings() {
        if (!switcherEditable)
            return
        switcherError = ""
        switcherMessage = ""
        switcherSave.command = ["python3", switcherHelper(), "save", JSON.stringify({
            enabled: switcherEnabled, position: switcherPosition,
            livePreview: switcherLivePreview, delayMs: switcherDelayMs, showActionButtons: switcherShowButtons
        })]
        switcherSave.running = true
    }
    Process {
        id: switcherLoad
        property string errorOutput: ""
        onRunningChanged: if (running) errorOutput = ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { dialog.readSwitcherValues(text) }
                catch (error) { dialog.switcherError = "Could not read switcher settings." }
            }
        }
        stderr: StdioCollector { onStreamFinished: switcherLoad.errorOutput = text.trim() }
        onExited: function(code) {
            if (code !== 0)
                dialog.switcherError = errorOutput || "Could not load switcher settings."
        }
    }
    Process {
        id: switcherSave
        property string errorOutput: ""
        onRunningChanged: if (running) errorOutput = ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { dialog.readSwitcherValues(text) }
                catch (error) { dialog.switcherError = "Could not read saved switcher settings." }
            }
        }
        stderr: StdioCollector { onStreamFinished: switcherSave.errorOutput = text.trim() }
        onExited: function(code) {
            if (code !== 0)
                dialog.switcherError = errorOutput || "Could not save switcher settings."
            else if (dialog.switcherError === "")
                dialog.switcherMessage = "Saved. Changes apply the next time the switcher opens."
        }
    }

    property string updateStatus: ""
    property string updateMessage: ""
    property string updateUrl: ""

    Process {
        id: updateCheck
        command: [
            "python3",
            Qt.resolvedUrl("check-updates.py")
                .toString().replace("file://", ""),
            AppInfo.version
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                let values = {}
                for (let line of text.trim().split("\n")) {
                    const separator = line.indexOf("=")
                    if (separator > 0)
                        values[line.substring(0, separator)] =
                            line.substring(separator + 1)
                }

                dialog.updateStatus = values.UPDATE_STATUS || "error"
                dialog.updateUrl = ""

                if (dialog.updateStatus === "available") {
                    dialog.updateMessage =
                        "New version available: v" + values.UPDATE_VERSION
                    dialog.updateUrl = values.UPDATE_URL || ""
                } else if (dialog.updateStatus === "current") {
                    dialog.updateMessage = "You are up to date."
                } else {
                    dialog.updateMessage = values.UPDATE_MESSAGE
                        || "Could not check for updates. Try again later."
                }
            }
        }

        stderr: StdioCollector {}

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                dialog.updateStatus = "error"
                dialog.updateUrl = ""
                dialog.updateMessage =
                    "Could not check for updates. Try again later."
            }
        }
    }

    readonly property var requiredCommands: [
        "hyprctl", "quickshell", "magick", "jq", "bash",
        "awk", "flock", "sha256sum", "timeout", "python3"
    ]

    readonly property string requiredDependencyStatus: {
        const missing = requiredCommands.filter(function(command) {
            return dependencyAvailability[command] === false
        })
        if (missing.length > 0)
            return "Missing required commands: " + missing.join(", ")
        if (requiredCommands.every(function(command) {
            return dependencyAvailability[command] === true
        }))
            return "Required commands: all available"
        return "Checking required commands…"
    }

    onOpened: {
        loadSwitcherSettings()
        if (!dependencyCheck.running) {
            dependencyAvailability = ({})
            dependencyError = ""
            dependencyCheck.running = true
        }
    }

    Process {
        id: dependencyCheck
        command: [
            "bash",
            Qt.resolvedUrl("check-dependencies.sh")
                .toString().replace("file://", "")
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                let available = {}
                for (let line of text.trim().split("\n")) {
                    const separator = line.indexOf("=")
                    if (separator > 0)
                        available[line.substring(0, separator)] =
                            line.substring(separator + 1) === "true"
                }
                dialog.dependencyAvailability = available
            }
        }

        stderr: StdioCollector {
            onStreamFinished: dialog.dependencyError = text.trim()
        }

        onExited: function(exitCode) {
            if (exitCode !== 0 && dialog.dependencyError === "")
                dialog.dependencyError = "Dependency check failed."
        }
    }

    // Use the existing workspace actions so settings have one source of truth.
    signal chooseOutputFolderRequested()
    signal monitorSetupRequested()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(720, parent.width - 40)
    height: Math.min(490, parent.height - 40)
    modal: true
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.base
        radius: 12
        border.color: Qt.alpha(Theme.subtext, 0.3)
    }

    header: Label {
        text: "Settings"
        color: Theme.text
        font.pixelSize: 22
        font.bold: true
        padding: 20
        bottomPadding: 8
    }

    contentItem: RowLayout {
        spacing: 24

        ColumnLayout {
            Layout.preferredWidth: 140
            Layout.alignment: Qt.AlignTop
            spacing: 8

            Repeater {
                model: ["General", "Switcher", "AI Cache", "About"]

                delegate: Button {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    checkable: true
                    checked: pages.currentIndex === index
                    onClicked: pages.currentIndex = index
                }
            }
        }

        StackLayout {
            id: pages
            objectName: "settingsPages"
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                spacing: 12

                Label {
                    text: "Wallpaper output folder"
                    color: Theme.text
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    text: dialog.workspace.outputDirectory || "Save monitor setup first"
                    color: Theme.subtext
                    wrapMode: Text.WrapAnywhere
                }
                Button {
                    text: "Choose Folder"
                    enabled: !dialog.workspace.busy
                        && dialog.workspace.outputDirectory !== ""
                    onClicked: {
                        dialog.close()
                        dialog.chooseOutputFolderRequested()
                    }
                }

                Label {
                    text: "Apply using"
                    color: Theme.text
                    font.bold: true
                    Layout.topMargin: 8
                }
                ComboBox {
                    Layout.preferredWidth: 190
                    model: ["Serpantinum", "hyprpaper", "awww", "Noctalia"]
                    enabled: !dialog.workspace.busy
                    currentIndex: Math.max(0,
                        dialog.workspace.applyBackendValues.indexOf(
                            dialog.workspace.applyBackend))

                    onActivated: function(index) {
                        dialog.workspace.saveApplyBackend(
                            dialog.workspace.applyBackendValues[index])
                        currentIndex = Qt.binding(function() {
                            return Math.max(0,
                                dialog.workspace.applyBackendValues.indexOf(
                                    dialog.workspace.applyBackend))
                        })
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: dialog.workspace.backendStatus
                    color: dialog.workspace.backendReady
                        ? Theme.success : Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Button {
                    text: "Monitor Setup"
                    enabled: !dialog.workspace.busy
                    onClicked: {
                        dialog.close()
                        dialog.monitorSetupRequested()
                    }
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                spacing: 12
                ScrollView {
                    id: switcherScroll
                    objectName: "switcherSettingsPage"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: switcherScroll.availableWidth
                        spacing: 12
                        Label {
                            text: "Wallpaper switcher"
                            color: Theme.text
                            font.bold: true
                        }
                        CheckBox {
                            palette.windowText: Theme.text
                            objectName: "switcherEnabledSetting"
                            text: "Enable wallpaper switcher"
                            checked: dialog.switcherEnabled
                            enabled: dialog.switcherEditable
                            onToggled: { dialog.switcherEnabled = checked; dialog.switcherDirty = true }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Open the visual picker using your configured hotkey. When disabled, the hotkey does nothing."
                            color: Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                        Label { text: "Screen position"; color: Theme.text; font.bold: true }
                        ComboBox {
                            objectName: "switcherPositionSetting"
                            property var positions: ["top", "center", "bottom"]
                            model: ["Top", "Center", "Bottom"]
                            Layout.preferredWidth: 190
                            enabled: dialog.switcherEditable && dialog.switcherEnabled
                            currentIndex: Math.max(0, positions.indexOf(dialog.switcherPosition))
                            onActivated: function(index) {
                                dialog.switcherPosition = positions[index]
                                dialog.switcherDirty = true
                                currentIndex = Qt.binding(function() { return positions.indexOf(dialog.switcherPosition) })
                            }
                        }
                        CheckBox {
                            palette.windowText: Theme.text
                            objectName: "switcherButtonsSetting"
                            text: "Show apply and cancel buttons"
                            checked: dialog.switcherShowButtons
                            enabled: dialog.switcherEditable && dialog.switcherEnabled
                            onToggled: { dialog.switcherShowButtons = checked; dialog.switcherDirty = true }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Enter and Escape always work, even when these buttons are hidden."
                            color: Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                        CheckBox {
                            palette.windowText: Theme.text
                            objectName: "switcherLivePreviewSetting"
                            text: "Preview wallpapers on the desktop"
                            checked: dialog.switcherLivePreview
                            enabled: dialog.switcherEditable && dialog.switcherEnabled
                            onToggled: { dialog.switcherLivePreview = checked; dialog.switcherDirty = true }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "With native Noctalia, browsing changes the desktop temporarily. Enter keeps it; Escape restores the original. When off, only the picker preview changes until you confirm."
                            color: Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                        Label { text: "Live preview delay (ms)"; color: Theme.text; font.bold: true }
                        SpinBox {
                            objectName: "switcherDelaySetting"
                            from: 100
                            to: 1500
                            stepSize: 50
                            editable: true
                            value: dialog.switcherDelayMs
                            enabled: dialog.switcherEditable && dialog.switcherEnabled && dialog.switcherLivePreview
                            onValueModified: { dialog.switcherDelayMs = value; dialog.switcherDirty = true }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Wait until you pause cycling before changing the desktop. Default: 400 ms."
                            color: Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Button {
                    objectName: "saveSwitcherSettings"
                    text: switcherSave.running ? "Saving…" : "Save switcher settings"
                    enabled: dialog.switcherEditable && dialog.switcherDirty
                    onClicked: dialog.saveSwitcherSettings()
                }
                Label {
                    Layout.fillWidth: true
                    visible: dialog.switcherMessage !== "" || dialog.switcherError !== ""
                    text: dialog.switcherError || dialog.switcherMessage
                    color: dialog.switcherError ? Theme.text : Theme.success
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                spacing: 12

                Label {
                    text: "Reusable AI images"
                    color: Theme.text
                    font.bold: true
                }
                Label {
                    text: !dialog.workspace.cacheChecked
                        ? "Checking cache…"
                        : (dialog.workspace.cacheBytes / (1024 * 1024)).toFixed(1)
                            + " MiB · " + dialog.workspace.cacheFiles
                            + (dialog.workspace.cacheFiles === 1
                                ? " image" : " images")
                    color: Theme.subtext
                }
                Label {
                    Layout.fillWidth: true
                    text: "Cached images speed up repeated generation with the same source and AI settings."
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Button {
                    text: "Clear AI Cache"
                    enabled: dialog.workspace.cacheChecked
                        && dialog.workspace.cacheFiles > 0
                        && !dialog.workspace.busy
                    onClicked: dialog.workspace.manageCache("clear")
                }
                Label {
                    Layout.fillWidth: true
                    text: "Source images and generated wallpapers are preserved."
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                spacing: 12

                Label {
                    text: AppInfo.name
                    color: Theme.text
                    font.pixelSize: 20
                    font.bold: true
                }
                Label {
                    text: "Version " + AppInfo.version
                    color: Theme.subtext
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        text: updateCheck.running
                            ? "Checking…" : "Check for updates"
                        enabled: !updateCheck.running
                        onClicked: {
                            dialog.updateStatus = ""
                            dialog.updateMessage = ""
                            dialog.updateUrl = ""
                            updateCheck.running = true
                        }
                    }

                    Button {
                        visible: dialog.updateStatus === "available"
                            && dialog.updateUrl !== ""
                        text: "Open release page"
                        onClicked: Qt.openUrlExternally(dialog.updateUrl)
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: dialog.updateMessage !== ""
                    text: dialog.updateMessage
                    color: dialog.updateStatus === "available"
                        ? Theme.success : Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: "Create coordinated wallpapers for one to three monitors."
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: Theme.usingSystemTheme
                        ? "Theme: Serpantinum / Matugen"
                        : "Theme: built-in palette"
                    color: Theme.text
                }
                Label {
                    Layout.fillWidth: true
                    text: dialog.dependencyError !== ""
                        ? dialog.dependencyError
                        : dialog.requiredDependencyStatus
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: dialog.workspace.upscalerAvailable
                        ? "Optional AI upscaling: available"
                        : "Optional AI upscaling: unavailable"
                    color: Theme.subtext
                }
                Label {
                    text: "License: " + AppInfo.license
                    color: Theme.subtext
                }
                Button {
                    text: "GitHub Repository"
                    onClicked: Qt.openUrlExternally(
                        "https://github.com/zw5dwv5j8t-cell/hunu-wallpaper")
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    footer: DialogButtonBox {
        Button {
            text: "Close"
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        onRejected: dialog.close()
    }
}