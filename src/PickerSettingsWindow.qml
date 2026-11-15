import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

FloatingWindow {
    id: window
    objectName: "pickerSettingsWindow"
    title: "Hunu — Picker settings"
    implicitWidth: 720
    implicitHeight: 760
    color: Theme.base
    visible: true
    property bool embedded: false
    signal closeRequested()
    onClosed: {
        if (embedded)
            closeRequested()
        else
            Qt.quit()
    }
    function finish() {
        if (embedded)
            closeRequested()
        else
            Qt.quit()
    }
    PickerPreferences { id: pickerPreferences }
    Component.onCompleted: pickerPreferences.loadSwitcherSettings()
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            HunuText { text: "Picker settings"; font.pixelSize: 26; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
        }
        HunuText {
            Layout.fillWidth: true
            text: "Choose a picker style and how wallpapers change."
            color: Theme.subtext
            wrapMode: Text.WordWrap
        }
        PickerSettingsPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            preferences: pickerPreferences
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        HunuText {
            Layout.fillWidth: true
            text: pickerPreferences.switcherError || pickerPreferences.switcherMessage || "Picker changes apply the next time it opens."
            color: pickerPreferences.switcherError ? Theme.text : Theme.subtext
            wrapMode: Text.WordWrap
            font.pixelSize: 12
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            HunuActionButton {
                objectName: "savePickerPreferences"
                text: pickerPreferences.saving ? "Saving…" : "Save changes"
                primary: true
                enabled: pickerPreferences.switcherEditable && pickerPreferences.switcherDirty
                onClicked: pickerPreferences.saveSwitcherSettings()
            }
            HunuActionButton { text: "Close"; onClicked: window.finish() }
        }
    }
}
