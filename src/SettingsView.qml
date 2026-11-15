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

    PickerPreferences { id: pickerPreferences; workspace: dialog.workspace }
    property alias switcherEnabled: pickerPreferences.switcherEnabled
    property alias switcherStyle: pickerPreferences.switcherStyle
    property alias switcherPosition: pickerPreferences.switcherPosition
    property alias switcherShowButtons: pickerPreferences.switcherShowButtons
    property alias switcherLivePreview: pickerPreferences.switcherLivePreview
    property alias switcherDelayMs: pickerPreferences.switcherDelayMs
    property alias switcherDirty: pickerPreferences.switcherDirty
    property alias switcherMessage: pickerPreferences.switcherMessage
    property alias switcherError: pickerPreferences.switcherError
    property alias switcherEditable: pickerPreferences.switcherEditable
    function readSwitcherValues(text) { pickerPreferences.readSwitcherValues(text) }
    function loadSwitcherSettings() { pickerPreferences.loadSwitcherSettings() }
    function saveSwitcherSettings() { pickerPreferences.saveSwitcherSettings() }

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
                PickerSettingsPanel { preferences: pickerPreferences }
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
                    text: pickerPreferences.saving ? "Saving…" : "Save changes"
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
