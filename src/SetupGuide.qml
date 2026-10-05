import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: guide

    property int step: 0
    property bool animationPaused: false
    onStepChanged: animationPaused = false
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
        animationPaused = false
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
                    x: 165
                    y: 55
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

                    SequentialAnimation {
                        running: guide.visible && guide.step === 1
                        paused: guide.animationPaused
                        loops: Animation.Infinite

                        // Demonstrate vertical placement with X held fixed.
                        PropertyAction {
                            target: secondMonitor
                            property: "x"
                            value: 165
                        }
                        NumberAnimation {
                            target: secondMonitor
                            property: "y"
                            from: 5
                            to: 65
                            duration: 2000
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                        NumberAnimation {
                            target: secondMonitor
                            property: "y"
                            from: 65
                            to: 5
                            duration: 2000
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                        NumberAnimation {
                            target: secondMonitor
                            property: "y"
                            from: 5
                            to: 35
                            duration: 1000
                            easing.type: Easing.InOutSine
                        }

                        // Move inward, outward, then return. X remains positive.
                        NumberAnimation {
                            target: secondMonitor
                            property: "x"
                            from: 165
                            to: 128
                            duration: 1800
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                        NumberAnimation {
                            target: secondMonitor
                            property: "x"
                            from: 128
                            to: 205
                            duration: 2200
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                        NumberAnimation {
                            target: secondMonitor
                            property: "x"
                            from: 205
                            to: 165
                            duration: 1800
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                        // Return to the starting position before repeating.
                        NumberAnimation {
                            target: secondMonitor
                            property: "y"
                            from: 35
                            to: 5
                            duration: 1000
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 800 }
                    }
                }

                Label {
                    visible: guide.step !== 0
                    x: 38
                    y: 185
                    text: "Origin (0, 0)     X → right     Y ↓ down"
                    color: Theme.subtext
                }

                Canvas {
                    id: positionArrows
                    anchors.fill: parent
                    visible: guide.step === 1

                    onVisibleChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = Theme.success.toString()
                        ctx.fillStyle = Theme.success.toString()
                        ctx.lineWidth = 2

                        const left = secondMonitor.x
                        const top = secondMonitor.y

                        // X follows Monitor 2's outside left edge.
                        ctx.beginPath()
                        ctx.moveTo(38, 27)
                        ctx.lineTo(left, 27)
                        ctx.moveTo(43, 23)
                        ctx.lineTo(38, 27)
                        ctx.lineTo(43, 31)
                        ctx.moveTo(left - 5, 23)
                        ctx.lineTo(left, 27)
                        ctx.lineTo(left - 5, 31)
                        ctx.moveTo(38, 27)
                        ctx.lineTo(38, 35)
                        ctx.stroke()

                        // Y follows Monitor 2's outside top edge.
                        ctx.beginPath()
                        ctx.moveTo(left - 10, 35)
                        ctx.lineTo(left - 10, top)
                        ctx.moveTo(left - 15, 35)
                        ctx.lineTo(left, 35)
                        ctx.moveTo(left - 15, top)
                        ctx.lineTo(left, top)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.arc(38, 35, 3, 0, Math.PI * 2)
                        ctx.fill()
                    }

                    Connections {
                        target: secondMonitor

                        function onXChanged() {
                            positionArrows.requestPaint()
                        }
                        function onYChanged() {
                            positionArrows.requestPaint()
                        }
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