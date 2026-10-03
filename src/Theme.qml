pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Hunu's built-in palette.
    //
    // This is always available and means external theming is never a
    // requirement for running the application.
	readonly property color fallbackBase: "#181825"
	readonly property color fallbackSurface: "#11111b"
    readonly property color fallbackText: "#cdd6f4"
    readonly property color fallbackSubtext: "#a6adc8"
    readonly property color fallbackMuted: "#6c7086"
    readonly property color fallbackSuccess: "#a6e3a1"

    property color base: fallbackBase
    property color surface: fallbackSurface
    property color text: fallbackText
    property color subtext: fallbackSubtext
    property color muted: fallbackMuted
    property color success: fallbackSuccess

    // Exposed for future Settings/About UI.
    property string provider: "fallback"
    property string externalThemePath: ""
    readonly property bool usingSystemTheme: provider !== "fallback"

    function resetToFallback() {
        base = fallbackBase
        surface = fallbackSurface
        text = fallbackText
        subtext = fallbackSubtext
        muted = fallbackMuted
        success = fallbackSuccess

        provider = "fallback"
        externalThemePath = ""
    }

    function loadColors(contents) {
        if (!contents || contents.trim() === "") {
            resetToFallback()
            return
        }

        try {
            const data = JSON.parse(contents)

            // Material/Matugen roles currently exported by Serpantinum.
            // Every value has an independent Hunu fallback.
            base = data.background ?? fallbackBase
            surface = data.surface ?? base
            text = data.on_background
                ?? data.onBackground
                ?? fallbackText
            subtext = data.on_surface_variant
                ?? data.onSurfaceVariant
                ?? fallbackSubtext
            muted = data.outline ?? fallbackMuted
            success = data.primary ?? fallbackSuccess

            provider = "serpantinum"
        } catch (e) {
            resetToFallback()
        }
    }

    function parseDetection(contents) {
        let detectedProvider = "fallback"
        let detectedPath = ""

        for (let line of contents.trim().split("\n")) {
            const pos = line.indexOf("=")

            if (pos < 0)
                continue

            const key = line.substring(0, pos).trim()
            const value = line.substring(pos + 1).trim()

            if (key === "THEME_PROVIDER")
                detectedProvider = value
            else if (key === "THEME_FILE")
                detectedPath = value
        }

        if (detectedProvider === "serpantinum" && detectedPath !== "") {
            provider = "serpantinum"
            externalThemePath = detectedPath
        } else {
            resetToFallback()
        }
    }

    // Detect optional providers first. This prevents FileView from ever
    // attempting to open a missing Serpantinum file.
    property Process themeDetector: Process {
        command: [
            Qt.resolvedUrl("detect-theme.sh")
                .toString()
                .replace("file://", "")
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseDetection(text)
            }
        }

        running: true
    }

    // An empty path means no external provider was detected.
    // FileView therefore remains harmless when Hunu is used without
    // Serpantinum.
    property FileView colorsFile: FileView {
        path: root.externalThemePath

        watchChanges: root.externalThemePath !== ""

        onLoaded: {
            root.loadColors(text())
        }

        onFileChanged: {
            reload()
        }
    }
}
