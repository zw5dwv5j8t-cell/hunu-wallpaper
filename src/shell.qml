import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root

    title: "Hunu Wallpaper Splitter"
    implicitWidth: 980
    implicitHeight: 820
    color: Theme.base

    // 0 = startup check, 1 = monitor setup, 2 = wallpaper workspace.
    property int appPage: 0
    property bool hasSavedConfig: false
    property string configPath: ""
    property string startupError: ""

    function scriptPath(name) {
        return Qt.resolvedUrl(name).toString().replace("file://", "")
    }

    function checkConfig() {
        appPage = 0
        startupError = ""
        configCheck.command = [scriptPath("check-monitor-config.sh")]
        configCheck.running = true
    }

    function openMonitorSetup() {
        // Start each editing session from the saved configuration.
        setupView.allowCancel = hasSavedConfig
        setupView.page = 0
        if (hasSavedConfig)
            setupView.loadSavedSetup()
        appPage = 1
    }

    Component.onCompleted: checkConfig()

    Process {
        id: configCheck

        stdout: StdioCollector {
            onStreamFinished: {
                let values = {}
                const lines = text.trim().split("\n")
                for (let line of lines) {
                    const pos = line.indexOf("=")
                    if (pos >= 0)
                        values[line.substring(0, pos).trim()] =
                            line.substring(pos + 1).trim()
                }

                root.hasSavedConfig = values.CONFIG_EXISTS === "true"
                root.configPath = values.CONFIG_PATH || ""

                // First run goes straight to setup. Otherwise open the workspace.
                if (root.hasSavedConfig)
                    root.appPage = 2
                else
                    root.openMonitorSetup()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.startupError = text.trim()
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.hasSavedConfig = false
                root.openMonitorSetup()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base

        StackLayout {
            anchors.fill: parent
            currentIndex: root.appPage

            // PAGE 0 — startup/config check
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 600)
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        text: "Hunu Wallpaper Splitter"
                        color: Theme.text
                        font.pixelSize: 26
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.startupError === ""
                            ? "Checking monitor configuration…"
                            : root.startupError
                        color: Theme.subtext
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // PAGE 1 — same-process monitor setup
            SetupView {
                id: setupView
                Layout.fillWidth: true
                Layout.fillHeight: true
                configPath: root.configPath

                onSetupSaved: {
                    root.hasSavedConfig = true
                    workspaceView.reloadConfiguration()
                    root.appPage = 2
                }

                onCancelRequested: {
                    if (root.hasSavedConfig) {
                        setupView.forceActiveFocus()
                        root.appPage = 2
                    }
                }
            }

            // PAGE 2 — generalized 1–3 monitor wallpaper workspace
            WorkspaceView {
                id: workspaceView
                Layout.fillWidth: true
                Layout.fillHeight: true
                configPath: root.configPath

                onMonitorSetupRequested: root.openMonitorSetup()
            }
        }
    }
}
