import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    required property var workspace

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
                model: ["General", "AI Cache", "About"]

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
                    model: ["Serpantinum", "hyprpaper", "awww"]
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
                    text: "Hunu Wallpaper Splitter"
                    color: Theme.text
                    font.pixelSize: 20
                    font.bold: true
                }
                Label {
                    text: "Settings development build"
                    color: Theme.subtext
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
                    text: dialog.workspace.upscalerAvailable
                        ? "Optional AI upscaling: available"
                        : "Optional AI upscaling: unavailable"
                    color: Theme.subtext
                }
                Label {
                    text: "License: MIT"
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