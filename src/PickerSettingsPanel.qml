import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

HunuScrollView {
    required property var preferences
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
                checked: preferences.switcherEnabled
                enabled: preferences.switcherEditable
                onToggled: { preferences.switcherEnabled = checked; preferences.switcherDirty = true }
            }
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Picker style"
            detail: "Choose how saved wallpapers are presented."
            HunuComboBox {
                objectName: "switcherStyleSetting"
                Accessible.name: "Wallpaper picker style"
                property var styles: ["carousel", "grid", "spotlight", "filmstrip", "browser"]
                model: ["Carousel", "Grid", "Spotlight", "Filmstrip", "Browser"]
                enabled: preferences.switcherEditable && preferences.switcherEnabled
                currentIndex: Math.max(0, styles.indexOf(preferences.switcherStyle))
                onActivated: function(index) {
                    preferences.switcherStyle = styles[index]
                    preferences.switcherDirty = true
                }
            }
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Screen position"
            HunuSegmented {
                objectName: "switcherPositionSetting"
                property var positions: ["top", "center", "bottom"]
                options: ["Top", "Center", "Bottom"]
                enabled: preferences.switcherEditable && preferences.switcherEnabled
                currentIndex: Math.max(0, positions.indexOf(preferences.switcherPosition))
                onSelected: function(index) { preferences.switcherPosition = positions[index]; preferences.switcherDirty = true }
            }
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Show confirmation buttons"
            detail: "Enter and Escape always work."
            HunuToggle {
                objectName: "switcherButtonsSetting"
                Accessible.name: "Show apply and cancel buttons"
                checked: preferences.switcherShowButtons
                enabled: preferences.switcherEditable && preferences.switcherEnabled
                onToggled: { preferences.switcherShowButtons = checked; preferences.switcherDirty = true }
            }
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Live desktop preview"
            detail: "Preview while browsing. Escape restores your wallpaper."
            HunuToggle {
                objectName: "switcherLivePreviewSetting"
                Accessible.name: "Live desktop preview"
                checked: preferences.switcherLivePreview
                enabled: preferences.switcherEditable && preferences.switcherEnabled
                onToggled: { preferences.switcherLivePreview = checked; preferences.switcherDirty = true }
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
                value: preferences.switcherDelayMs
                enabled: preferences.switcherEditable && preferences.switcherEnabled && preferences.switcherLivePreview
                onValueModified: { preferences.switcherDelayMs = value; preferences.switcherDirty = true }
            }
            HunuText { text: "ms"; color: Theme.subtext }
        }
        HunuText {
            Layout.fillWidth: true
            Layout.topMargin: 22
            Layout.bottomMargin: 8
            text: "Automatic cycling"
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Random wallpapers"
            detail: "Change the desktop even when Hunu is closed."
            HunuToggle {
                objectName: "rotationEnabledSetting"
                Accessible.name: "Enable random wallpaper cycling"
                checked: preferences.rotationEnabled
                enabled: preferences.switcherEditable && (preferences.rotationAvailable || preferences.rotationEnabled)
                onToggled: { preferences.rotationEnabled = checked; preferences.rotationDirty = true; preferences.switcherDirty = true }
            }
        }
        HunuText {
            Layout.fillWidth: true
            visible: !preferences.rotationAvailable
            text: "A systemd user session is needed to enable automatic cycling."
            color: Theme.subtext
            wrapMode: Text.WordWrap
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Time interval"
            detail: "Between 1 minute and 24 hours."
            HunuSpinBox {
                objectName: "rotationIntervalSetting"
                Accessible.name: "Wallpaper cycling interval in minutes"
                from: 1; to: 1440; stepSize: 1; editable: true
                value: preferences.rotationMinutes
                enabled: preferences.switcherEditable && preferences.rotationEnabled
                onValueModified: { preferences.rotationMinutes = value; preferences.rotationDirty = true; preferences.switcherDirty = true }
            }
            HunuText { text: "min"; color: Theme.subtext }
        }
        HunuSettingsRow {
            Layout.fillWidth: true
            heading: "Avoid immediate repeats"
            detail: "Choose a different wallpaper at each change."
            HunuToggle {
                objectName: "rotationRepeatSetting"
                Accessible.name: "Avoid repeating the current wallpaper"
                checked: preferences.rotationAvoidRepeat
                enabled: preferences.switcherEditable && preferences.rotationEnabled
                onToggled: { preferences.rotationAvoidRepeat = checked; preferences.rotationDirty = true; preferences.switcherDirty = true }
            }
        }
        HunuText {
            Layout.fillWidth: true
            Layout.topMargin: 10
            text: "Only wallpapers compatible with your current monitors are used. Cycling pauses while the picker is open."
            color: Theme.subtext
            wrapMode: Text.WordWrap
        }
    }
}
