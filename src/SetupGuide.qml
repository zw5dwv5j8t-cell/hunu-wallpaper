import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: guide

    property int step: 0
    property bool animationPaused: false
    property real animationTime: 0
    readonly property var movementFrames: [
        {t: 0, x: 165, y: 5},
        {t: 2000, x: 165, y: 65},
        {t: 2800, x: 165, y: 65},
        {t: 4800, x: 165, y: 5},
        {t: 5600, x: 165, y: 5},
        {t: 6600, x: 165, y: 35},
        {t: 8400, x: 128, y: 35},
        {t: 9200, x: 128, y: 35},
        {t: 11400, x: 205, y: 35},
        {t: 12200, x: 205, y: 35},
        {t: 14000, x: 165, y: 35},
        {t: 14800, x: 165, y: 35},
        {t: 15800, x: 165, y: 5},
        {t: 16600, x: 165, y: 5}
    ]

    function animatedCoordinate(axis) {
        for (let i = 1; i < movementFrames.length; ++i) {
            const end = movementFrames[i]
            if (animationTime <= end.t) {
                const start = movementFrames[i - 1]
                const progress = Math.max(0, Math.min(1,
                    (animationTime - start.t) / (end.t - start.t)))
                const eased = (1 - Math.cos(Math.PI * progress)) / 2
                return start[axis] + (end[axis] - start[axis]) * eased
            }
        }
        return movementFrames[0][axis]
    }
    onStepChanged: resetIllustration()

    function resetIllustration() {
        placementAnimation.stop()
        animationPaused = false
        animationTime = 0
        if (visible && step === 1)
            placementAnimation.start()
    }

    onClosed: resetIllustration()
    readonly property var headings: [
        "Measure the whole monitor",
        "Describe its position on your desk",
        "Match the fields to your monitors"
    ]
    readonly property var explanations: [
        "Measure the outside width and height in centimeters, including the bezels. "
            + "Exclude the stand. For a portrait monitor, measure it in its current orientation.",
        "Choose one common origin (0, 0) for your physical layout. "
            + "Enter each monitor's outside top-left position relative to that origin, in centimeters. "
            + "X increases right and Y increases down; positions left or above the origin use negative values. "
            + "Top-aligned monitors share the same Y value. Include any real gap between monitors. "
            + "These values describe monitor placement, not wallpaper offsets.",
        "Assign each enabled slot a different detected output. Keep the detected pixel resolution. "
            + "Enter your measured Width, Height, X, and Y in centimeters, then check the physical preview. "
            + "The illustration uses example values, not measurements for your setup."
    ]

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(740, parent.width - 40)
    height: Math.min(560, parent.height - 40)
    modal: true
    padding: 20
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        step = 0
        resetIllustration()
    }

    background: Rectangle {
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Qt.alpha(Theme.subtext, 0.3)
    }

    header: Label {
        text: "How to measure · " + (guide.step + 1) + " / 3"
        color: Theme.text
        font.pixelSize: 22
        font.bold: true
        padding: 20
        bottomPadding: 8
    }

    contentItem: ColumnLayout {
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: guide.headings[guide.step]
            color: Theme.text
            font.pixelSize: 18
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240
            color: Theme.surface
            radius: 10

            Item {
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 24)
                height: 240

                // These rectangles illustrate physical measurements only.
                Rectangle {
                    id: firstMonitor
                    x: 38
                    y: 35
                    width: guide.step === 0 ? 240 : 90
                    height: guide.step === 0 ? 120 : 140
                    radius: 5
                    color: Theme.base
                    border.width: 5
                    border.color: Theme.subtext

                    Label {
                        anchors.centerIn: parent
                        text: guide.step === 0 ? "Monitor + bezels" : "Monitor 1"
                        color: Theme.text
                    }
                }

                Label {
                    visible: guide.step === 0
                    x: firstMonitor.x
                    y: 8
                    width: firstMonitor.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "←  Outside width  →"
                    color: Theme.success
                }
                Label {
                    visible: guide.step === 0
                    x: firstMonitor.x + firstMonitor.width + 12
                    y: firstMonitor.y + 35
                    text: "↑\nOutside\nheight\n↓"
                    color: Theme.success
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    id: secondMonitor
                    visible: guide.step !== 0
                    x: guide.step === 1 ? guide.animatedCoordinate("x") : 165
                    y: guide.step === 1 ? guide.animatedCoordinate("y") : 55
                    width: 200
                    height: 110
                    radius: 5
                    color: Theme.base
                    border.width: 5
                    border.color: Theme.success

                    Label {
                        anchors.centerIn: parent
                        text: "Monitor 2"
                        color: Theme.text
                    }

                    // Keep one timeline running through movement and holds.
                    NumberAnimation {
                        id: placementAnimation
                        target: guide
                        property: "animationTime"
                        from: 0
                        to: 16600
                        duration: 16600
                        easing.type: Easing.Linear
                        paused: guide.animationPaused
                        loops: Animation.Infinite
                    }
                }

                Label {
                    visible: guide.step !== 0
                    x: 38
                    y: 185
                    text: "Origin (0, 0)     X → right     Y ↓ down"
                    color: Theme.subtext
                }

                // Scene-graph lines avoid repainting a Canvas every frame.
                Item {
                    visible: guide.step === 1
                    anchors.fill: parent
                    Rectangle {
                        x: 38; y: 26
                        width: Math.max(0, secondMonitor.x - 38); height: 2
                        color: Theme.success
                    }
                    Rectangle {
                        x: 37; y: 27; width: 2; height: 8
                        color: Theme.success
                    }
                    Rectangle {
                        x: 35; y: 32; width: 6; height: 6; radius: 3
                        color: Theme.success
                    }
                    Repeater {
                        model: [0, 1, 2, 3]
                        delegate: Rectangle {
                            required property int index
                            x: index < 2 ? 38 : secondMonitor.x - 6
                            y: index % 2 === 0 ? 24 : 28
                            width: 7; height: 2
                            rotation: index % 2 === 0 ? -40 : 40
                            color: Theme.success
                        }
                    }
                    Rectangle {
                        x: secondMonitor.x - 11
                        y: Math.min(35, secondMonitor.y)
                        width: 2; height: Math.abs(secondMonitor.y - 35)
                        color: Theme.success
                    }
                    Rectangle {
                        x: secondMonitor.x - 15; y: 34
                        width: 15; height: 2
                        color: Theme.success
                    }
                    Rectangle {
                        x: secondMonitor.x - 15; y: secondMonitor.y - 1
                        width: 15; height: 2
                        color: Theme.success
                    }
                }
                Label {
                    visible: guide.step === 1
                    x: 38
                    y: 210
                    text: "Example: X = "
                        + ((secondMonitor.x - 38) / 5).toFixed(1)
                        + " cm, Y = "
                        + ((secondMonitor.y - 35) / 5).toFixed(1) + " cm"
                    color: Theme.success
                }
                Label {
                    visible: guide.step === 2
                    x: 165
                    y: 20
                    text: "Width · Height · X · Y: centimeters"
                    color: Theme.success
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: guide.explanations[guide.step]
            color: Theme.subtext
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: "Physical centimeters are separate from Hyprland's pixel coordinates."
            color: Theme.muted
            wrapMode: Text.WordWrap
        }
    }

    footer: RowLayout {
        spacing: 10

        Button {
            text: "Skip"
            onClicked: guide.close()
        }

        Button {
            visible: guide.step === 1
            text: guide.animationPaused ? "Play" : "Pause"
            onClicked: guide.animationPaused = !guide.animationPaused
        }

        Item { Layout.fillWidth: true }

        Button {
            text: "Previous"
            enabled: guide.step > 0
            onClicked: guide.step--
        }
        Button {
            text: guide.step === 2 ? "Done" : "Next"
            onClicked: {
                if (guide.step === 2)
                    guide.close()
                else
                    guide.step++
            }
        }
    }
}