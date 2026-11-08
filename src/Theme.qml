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
	readonly property color fallbackBase: "#111318"
	readonly property color fallbackSurface: "#1b1e25"
    readonly property color fallbackText: "#f0f2f6"
    readonly property color fallbackSubtext: "#929aa8"
    readonly property color fallbackMuted: "#6e7785"
    readonly property color fallbackSuccess: "#a7e7c4"

    property color base: fallbackBase
    property color surface: fallbackSurface
    property color text: fallbackText
    property color subtext: fallbackSubtext
    property color muted: fallbackMuted
    property color success: fallbackSuccess
    readonly property color accent: success
    readonly property color onAccent: accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114 > 0.56 ? "#102018" : "white"
    readonly property color raised: Qt.lighter(surface, 1.16)
    readonly property color hoverSurface: Qt.lighter(surface, 1.3)
    readonly property color border: Qt.alpha(subtext, 0.24)
    readonly property string fontFamily: "Sans Serif"
    readonly property int radius: 14
    readonly property int radiusSmall: 9

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

            // Support Serpantinum's palette and Material/Matugen roles.
            base = data.base
                ?? data.background
                ?? fallbackBase
            surface = data.surface0
                ?? data.surface
                ?? fallbackSurface
            text = data.text
                ?? data.on_background
                ?? data.onBackground
                ?? fallbackText
            subtext = data.subtext0
                ?? data.on_surface_variant
                ?? data.onSurfaceVariant
                ?? fallbackSubtext
            muted = data.subtext1
                ?? data.outline
                ?? fallbackMuted
            success = data.green
                ?? data.primary
                ?? fallbackSuccess

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
