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
    width: Math.min(920, parent.width - 40)
    height: Math.min(680, parent.height - 40)
    modal: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    font.family: Theme.fontFamily
    font.pixelSize: 13
    background: Rectangle { color: Theme.base; radius: 16; border.color: Theme.border }

    contentItem: RowLayout {
        spacing: 0
        Rectangle {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            color: "transparent"
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8
                HunuText { text: "Settings"; font.pixelSize: 24; font.weight: Font.DemiBold; Layout.bottomMargin: 20 }
                Repeater {
                    model: ["General", "Switcher", "AI Cache", "About"]
                    delegate: HunuActionButton {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        glyph: ["settings", "image", "cache", "info"][index]
                        alignLeft: true
                        flat: true
                        checked: pages.currentIndex === index
                        onClicked: pages.currentIndex = index
                    }
                }
                Item { Layout.fillHeight: true }
                HunuText { text: "Hunu  ·  " + AppInfo.version; color: Theme.muted; font.pixelSize: 11 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.topMargin: 26
                Layout.bottomMargin: 12
                spacing: 7
                HunuText {
                    text: ["General", "Wallpaper switcher", "AI cache", "About Hunu"][pages.currentIndex]
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }
                HunuText {
                    Layout.fillWidth: true
                    text: ["Your workspace, outputs, and wallpaper backend.",
                        "Your saved wallpapers, one shortcut away.",
                        "Keep reusable upscales. Make room when you need it.",
                        "A continuous wallpaper, across your whole desk."][pages.currentIndex]
                    color: Theme.subtext
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
            StackLayout {
                id: pages
                objectName: "settingsPages"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                HunuScrollView {
                    id: generalScroll
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: generalScroll.availableWidth
                        spacing: 0
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Wallpaper output folder"
                            detail: dialog.workspace.outputDirectory || "Save monitor setup first"
                            HunuActionButton {
                                text: "Choose Folder"; glyph: "folder"
                                enabled: !dialog.workspace.busy && dialog.workspace.outputDirectory !== ""
                                onClicked: { dialog.close(); dialog.chooseOutputFolderRequested() }
                            }
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Apply using"
                            detail: "Choose the service that manages your wallpapers."
                            HunuComboBox {
                                objectName: "applyBackendSetting"
                                Layout.preferredWidth: 180
                                property var backends: ["serpantinum", "hyprpaper", "awww", "noctalia"]
                                model: ["Serpantinum", "hyprpaper", "awww", "Noctalia"]
                                enabled: !dialog.workspace.busy
                                currentIndex: Math.max(0, backends.indexOf(dialog.workspace.applyBackend))
                                onActivated: function(index) {
                                    dialog.workspace.saveApplyBackend(backends[index])
                                    currentIndex = Qt.binding(function() { return Math.max(0, backends.indexOf(dialog.workspace.applyBackend)) })
                                }
                            }
                        }
                        HunuText {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: dialog.workspace.backendStatus
                            color: dialog.workspace.backendReady ? Theme.accent : Theme.subtext
                            wrapMode: Text.WordWrap
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Monitor setup"
                            detail: "Assign your displays and calibrate physical placement."
                            divider: false
                            HunuActionButton {
                                text: "Configure"; glyph: "monitor"; enabled: !dialog.workspace.busy
                                onClicked: { dialog.close(); dialog.monitorSetupRequested() }
                            }
                        }
                    }
                }
                HunuScrollView {
                    id: switcherScroll
                    objectName: "switcherSettingsPage"
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: switcherScroll.availableWidth
                        spacing: 0
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Enable switcher"
                            detail: "Open the picker with your configured hotkey."
                            HunuToggle {
                                objectName: "switcherEnabledSetting"
                                Accessible.name: "Enable wallpaper switcher"
                                checked: dialog.switcherEnabled
                                enabled: dialog.switcherEditable
                                onToggled: { dialog.switcherEnabled = checked; dialog.switcherDirty = true }
                            }
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Screen position"
                            HunuSegmented {
                                objectName: "switcherPositionSetting"
                                property var positions: ["top", "center", "bottom"]
                                options: ["Top", "Center", "Bottom"]
                                enabled: dialog.switcherEditable && dialog.switcherEnabled
                                currentIndex: Math.max(0, positions.indexOf(dialog.switcherPosition))
                                onSelected: function(index) { dialog.switcherPosition = positions[index]; dialog.switcherDirty = true }
                            }
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Show confirmation buttons"
                            detail: "Enter and Escape always work."
                            HunuToggle {
                                objectName: "switcherButtonsSetting"
                                Accessible.name: "Show apply and cancel buttons"
                                checked: dialog.switcherShowButtons
                                enabled: dialog.switcherEditable && dialog.switcherEnabled
                                onToggled: { dialog.switcherShowButtons = checked; dialog.switcherDirty = true }
                            }
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Live desktop preview"
                            detail: "Preview while browsing. Escape restores your wallpaper."
                            HunuToggle {
                                objectName: "switcherLivePreviewSetting"
                                Accessible.name: "Live desktop preview"
                                checked: dialog.switcherLivePreview
                                enabled: dialog.switcherEditable && dialog.switcherEnabled
                                onToggled: { dialog.switcherLivePreview = checked; dialog.switcherDirty = true }
                            }
                        }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Preview delay"
                            detail: "Wait until you pause cycling."
                            HunuSpinBox {
                                objectName: "switcherDelaySetting"
                                Accessible.name: "Live preview delay in milliseconds"
                                from: 100; to: 1500; stepSize: 50; editable: true
                                value: dialog.switcherDelayMs
                                enabled: dialog.switcherEditable && dialog.switcherEnabled && dialog.switcherLivePreview
                                onValueModified: { dialog.switcherDelayMs = value; dialog.switcherDirty = true }
                            }
                            HunuText { text: "ms"; color: Theme.subtext }
                        }
                    }
                }
                ColumnLayout {
                    spacing: 20
                    HunuSettingsRow {
                        Layout.fillWidth: true
                        heading: "Reusable AI images"
                        detail: !dialog.workspace.cacheChecked ? "Checking cache…"
                            : (dialog.workspace.cacheBytes / (1024 * 1024)).toFixed(1) + " MiB · "
                            + dialog.workspace.cacheFiles + " cached images"
                        HunuActionButton {
                            text: "Clear AI Cache"
                            enabled: dialog.workspace.cacheChecked && dialog.workspace.cacheFiles > 0 && !dialog.workspace.busy
                            onClicked: dialog.workspace.manageCache("clear")
                        }
                    }
                    HunuText {
                        Layout.fillWidth: true
                        text: "Cached images speed up repeated generation with the same source and AI settings. Clearing the cache keeps your source images and generated wallpapers."
                        color: Theme.subtext
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
                HunuScrollView {
                    id: aboutScroll
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: aboutScroll.availableWidth
                        spacing: 14
                        HunuText { text: AppInfo.name; font.pixelSize: 20; font.weight: Font.DemiBold }
                        HunuText { text: "Version " + AppInfo.version + " · " + AppInfo.license + " license"; color: Theme.subtext }
                        RowLayout {
                            spacing: 10
                            HunuActionButton {
                                text: updateCheck.running ? "Checking…" : "Check for updates"
                                enabled: !updateCheck.running
                                onClicked: { dialog.updateStatus = ""; dialog.updateMessage = ""; dialog.updateUrl = ""; updateCheck.running = true }
                            }
                            HunuActionButton {
                                visible: dialog.updateStatus === "available" && dialog.updateUrl !== ""
                                text: "Open release page"
                                onClicked: Qt.openUrlExternally(dialog.updateUrl)
                            }
                        }
                        HunuText { Layout.fillWidth: true; visible: dialog.updateMessage !== ""; text: dialog.updateMessage; color: Theme.accent; wrapMode: Text.WordWrap }
                        HunuSettingsRow {
                            Layout.fillWidth: true
                            heading: "Theme"
                            detail: Theme.usingSystemTheme ? "Serpantinum / Matugen" : "Hunu charcoal"
                        }
                        HunuText { Layout.fillWidth: true; text: requiredDependencyStatus; color: Theme.subtext; wrapMode: Text.WordWrap }
                        HunuText { Layout.fillWidth: true; visible: dependencyError !== ""; text: dependencyError; color: Theme.muted; wrapMode: Text.WordWrap }
                        HunuText { text: dialog.workspace.upscalerAvailable ? "Real-ESRGAN available" : "Real-ESRGAN not installed (optional)"; color: Theme.subtext }
                        HunuActionButton { text: "GitHub Repository"; onClicked: Qt.openUrlExternally(AppInfo.repositoryUrl) }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; height: 1; color: Theme.border }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 22
                spacing: 12
                HunuText {
                    Layout.fillWidth: true
                    visible: pages.currentIndex === 1
                    text: dialog.switcherError || dialog.switcherMessage || "Changes apply the next time the switcher opens."
                    color: dialog.switcherError ? Theme.text : Theme.subtext
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Item { Layout.fillWidth: true; visible: pages.currentIndex !== 1 }
                HunuActionButton {
                    objectName: "saveSwitcherSettings"
                    text: switcherSave.running ? "Saving…" : "Save changes"
                    primary: true
                    visible: pages.currentIndex === 1
                    enabled: dialog.switcherEditable && dialog.switcherDirty
                    onClicked: dialog.saveSwitcherSettings()
                }
                HunuActionButton { text: "Close"; onClicked: dialog.close() }
            }
        }
    }
}
