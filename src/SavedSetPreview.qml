import QtQuick
import QtQuick.Controls

Item {
    id: preview
    required property var wallpaperSet
    required property var monitorLayout
property var rectangles: {
    if (!preview.wallpaperSet)
        return []
    return preview.wallpaperSet.monitors.map(function(monitor, index) {
        const geometry = preview.monitorLayout[monitor.output]
        return {image: monitor.url, slot: monitor.slot,
            x: geometry ? geometry.x : index * 65,
            y: geometry ? geometry.y : 0,
            w: geometry ? geometry.w : 60,
            h: geometry ? geometry.h : 34}
    })
}
property real minX: rectangles.length
    ? Math.min.apply(null, rectangles.map(function(r) { return r.x })) : 0
property real minY: rectangles.length
    ? Math.min.apply(null, rectangles.map(function(r) { return r.y })) : 0
property real spanW: rectangles.length
    ? Math.max(1, Math.max.apply(null, rectangles.map(function(r) { return r.x + r.w })) - minX) : 1
property real spanH: rectangles.length
    ? Math.max(1, Math.max.apply(null, rectangles.map(function(r) { return r.y + r.h })) - minY) : 1
property real scaleFactor: Math.max(0, Math.min(width / spanW, height / spanH))
Repeater {
    model: preview.rectangles
    delegate: Rectangle {
        required property var modelData
        x: (preview.width - preview.spanW * preview.scaleFactor) / 2
            + (modelData.x - preview.minX) * preview.scaleFactor
        y: (preview.height - preview.spanH * preview.scaleFactor) / 2
            + (modelData.y - preview.minY) * preview.scaleFactor
        width: modelData.w * preview.scaleFactor
        height: modelData.h * preview.scaleFactor
        color: Theme.surface
        border.color: Theme.subtext
        clip: true
        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: modelData.image
            sourceSize.width: 600
            sourceSize.height: 400
            fillMode: Image.Stretch
            asynchronous: true
        }
        Label {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "Monitor " + modelData.slot
            color: Theme.text
            padding: 4
            background: Rectangle { color: Qt.alpha(Theme.base, 0.85) }
        }
    }
}
}
