import QtQuick
import Quickshell.Io

Item {
    id: dialog
    visible: false
    objectName: "pickerPreferences"
    property var workspace: null
    property bool rotationEnabled: false
    property int rotationMinutes: 15
    property bool rotationAvoidRepeat: true
    property bool rotationAvailable: false
    property bool rotationDirty: false
    property bool saving: switcherSave.running || rotationSave.running
    property bool switcherEnabled: true
    property string switcherStyle: "carousel"
    property string switcherPosition: "center"
    property bool switcherShowButtons: true
    property bool switcherLivePreview: true
    property int switcherDelayMs: 400
    property bool switcherDirty: false
    property string switcherMessage: ""
    property string switcherError: ""
    readonly property bool switcherEditable: !switcherLoad.running && !switcherSave.running && !rotationLoad.running && !rotationSave.running && !(workspace && workspace.busy)

    function switcherHelper() {
        return decodeURIComponent(Qt.resolvedUrl("switcher-settings.py").toString().replace("file://", ""))
    }
    function readSwitcherValues(text) {
        const values = JSON.parse(text)
        switcherEnabled = values.enabled
        switcherStyle = values.style || "carousel"
        switcherPosition = values.position
        switcherShowButtons = values.showActionButtons
        switcherLivePreview = values.livePreview
        switcherDelayMs = values.delayMs
        switcherDirty = rotationDirty
    }
    function rotationHelper() {
        return decodeURIComponent(Qt.resolvedUrl("rotation-settings.py").toString().replace("file://", ""))
    }
    function readRotationValues(text) {
        const values = JSON.parse(text)
        rotationEnabled = values.enabled
        rotationMinutes = values.intervalMinutes
        rotationAvoidRepeat = values.avoidRepeat
        if (values.available !== undefined)
            rotationAvailable = values.available
        rotationDirty = false
        switcherDirty = false
    }
    function saveRotationSettings() {
        rotationSave.command = ["python3", rotationHelper(), "save", JSON.stringify({
            enabled: rotationEnabled, intervalMinutes: rotationMinutes, avoidRepeat: rotationAvoidRepeat
        })]
        rotationSave.running = true
    }
    function loadSwitcherSettings() {
        if (switcherLoad.running || switcherSave.running)
            return
        switcherError = ""
        switcherMessage = ""
        switcherLoad.command = ["python3", switcherHelper(), "get"]
        switcherLoad.running = true
        rotationLoad.command = ["python3", rotationHelper(), "get"]
        rotationLoad.running = true
    }
    function saveSwitcherSettings() {
        if (!switcherEditable)
            return
        switcherError = ""
        switcherMessage = ""
        switcherSave.command = ["python3", switcherHelper(), "save", JSON.stringify({
            enabled: switcherEnabled, style: switcherStyle, position: switcherPosition,
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
            else if (dialog.switcherError === "" && dialog.rotationDirty)
                dialog.saveRotationSettings()
            else if (dialog.switcherError === "")
                dialog.switcherMessage = "Saved. Changes apply the next time the switcher opens."
        }
    }

    Process {
        id: rotationLoad
        property string errorOutput: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { dialog.readRotationValues(text) }
                catch (error) { dialog.switcherError = "Could not read automatic cycling settings." }
            }
        }
        stderr: StdioCollector { onStreamFinished: rotationLoad.errorOutput = text.trim() }
        onExited: function(code) {
            if (code !== 0)
                dialog.switcherError = errorOutput || "Could not load automatic cycling settings."
        }
    }
    Process {
        id: rotationSave
        property string errorOutput: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { dialog.readRotationValues(text) }
                catch (error) { dialog.switcherError = "Could not read saved automatic cycling settings." }
            }
        }
        stderr: StdioCollector { onStreamFinished: rotationSave.errorOutput = text.trim() }
        onExited: function(code) {
            if (code !== 0) {
                dialog.switcherError = "Picker settings saved, but automatic cycling was not updated. " + errorOutput
                dialog.switcherDirty = true
            } else {
                dialog.switcherMessage = "Saved. Picker changes apply next time it opens; cycling updates immediately."
            }
        }
    }

}
