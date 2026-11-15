import QtQuick
import QtQuick.Controls

// Distinct layouts sharing the picker's renderer and transaction controller.
Item {
    id: view
    required property var picker
    required property Component previewComponent
    readonly property bool strip: picker.pickerStyle === "filmstrip"
    readonly property bool browser: picker.pickerStyle === "browser"
    readonly property real gap: 14
    readonly property real libraryWidth: browser ? Math.min(300, width * 0.30) : 0
    readonly property real previewWidth: Math.max(1, width - (browser ? libraryWidth + 24 : 0))
    readonly property var requested: indices(picker.selectedIndex)
    readonly property var displayed: indices(picker.displayedIndex)

    function indices(index) {
        if (!picker.sets.length)
            return []
        if (!strip)
            return [index]
        const start = Math.floor(index / 5) * 5
        const result = []
        for (let i = start; i < Math.min(start + 5, picker.sets.length); ++i)
            result.push(i)
        return result
    }
    function showRequested() {
        if (!picker.sets.length)
            return
        for (let index of requested) {
            const slot = pool.itemAt(index)
            if (!slot || !slot.item || !slot.item.prepared
                    || (!picker.firstFrameReady && !slot.item.frameReady))
                return
        }
        picker.showSelection()
    }
    Repeater {
        id: pool
        model: view.picker.sets.length
        onItemAdded: Qt.callLater(view.showRequested)
        delegate: Loader {
            id: slot
            required property int index
            active: view.picker.decodingStarted && (view.requested.indexOf(index) >= 0 || view.displayed.indexOf(index) >= 0)
            width: view.strip ? Math.max(1, (view.width - view.gap * 4) / 5) : view.previewWidth
            height: view.height
            x: view.strip ? Math.max(0, (view.width - (view.displayed.length * (width + view.gap) - view.gap)) / 2) + (index % 5) * (width + view.gap) : 0
            opacity: view.displayed.indexOf(index) >= 0 ? 1 : 0
            enabled: opacity > 0 && !view.picker.busy
            onLoaded: Qt.callLater(view.showRequested)
            sourceComponent: Item {
                objectName: "alternativeTile"
                readonly property int wallpaperIndex: slot.index
                readonly property var wallpaperSet: view.picker.sets[slot.index] || null
                readonly property bool prepared: renderer.item ? renderer.item.prepared : false
                readonly property bool frameReady: renderer.item ? renderer.item.frameReady : false
                Rectangle {
                    anchors.fill: parent
                    visible: view.strip
                    radius: 18
                    color: "#1b222b"
                    border.width: slot.index === view.picker.selectedIndex ? 2 : 1
                    border.color: slot.index === view.picker.selectedIndex ? "#a7e7c4" : "#303c49"
                }
                Loader {
                    id: renderer
                    anchors.fill: parent
                    anchors.margins: view.strip ? 8 : 0
                    sourceComponent: view.previewComponent
                    onLoaded: {
                        item.sourceGeometry = Qt.binding(function() { return parent.wallpaperSet && parent.wallpaperSet.previewSize ? parent.wallpaperSet.previewSize : [1, 1] })
                        item.fallbackGeometry = Qt.binding(function() { return parent.wallpaperSet && parent.wallpaperSet.fallbackPreviewSize ? parent.wallpaperSet.fallbackPreviewSize : item.sourceGeometry })
                        item.sourceSize = view.strip ? Qt.size(600, 360) : Qt.size(1000, 700)
                        item.traceIndex = slot.index
                        item.shadowEnabled = !view.strip
                        item.highlighted = Qt.binding(function() { return !view.strip || slot.index === view.picker.selectedIndex })
                        item.fallbackSource = Qt.binding(function() { return parent.wallpaperSet ? parent.wallpaperSet.fallbackPreviewUrl : "" })
                        item.source = Qt.binding(function() { return parent.wallpaperSet ? parent.wallpaperSet.previewUrl : "" })
                    }
                }
                Connections {
                    target: renderer.item
                    function onPreparedChanged() { Qt.callLater(view.showRequested) }
                    function onFrameReadyChanged() { Qt.callLater(view.showRequested) }
                }
                MouseArea {
                    id: stripMouse
                    anchors.fill: parent
                    enabled: view.strip
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { view.picker.choose(slot.index); view.picker.focusPicker() }
                    onDoubleClicked: { view.picker.choose(slot.index); view.picker.confirm() }
                }
                ToolTip.visible: view.strip && stripMouse.containsMouse
                ToolTip.delay: 600
                ToolTip.text: wallpaperSet ? wallpaperSet.title : ""
                Accessible.name: wallpaperSet ? wallpaperSet.title : "Wallpaper preview"
            }
        }
    }
    Rectangle {
        visible: view.browser
        x: view.previewWidth + 12
        width: 1
        height: parent.height
        color: "#303c49"
    }
    ListView {
        id: library
        objectName: "browserLibrary"
        visible: view.browser
        x: parent.width - width
        width: view.libraryWidth
        height: parent.height
        clip: true
        spacing: 6
        model: view.browser ? view.picker.sets.length : 0
        currentIndex: view.picker.selectedIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: row
            required property int index
            objectName: "browserRow"
            readonly property var wallpaperSet: view.picker.sets[index] || null
            width: library.width - 12
            height: 52
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: row.index === view.picker.selectedIndex ? "#253e36" : rowMouse.containsMouse ? "#252e38" : "#1b222b"
                border.width: row.index === view.picker.selectedIndex ? 1 : 0
                border.color: "#a7e7c4"
            }
            Text {
                x: 12
                width: 28
                anchors.verticalCenter: parent.verticalCenter
                text: row.index + 1
                color: "#8d9da9"
                font.pixelSize: 12
            }
            Text {
                x: 46
                width: parent.width - 58
                anchors.verticalCenter: parent.verticalCenter
                text: row.wallpaperSet ? row.wallpaperSet.title.split("/").pop() : "Wallpaper"
                elide: Text.ElideMiddle
                color: "#e6edf3"
                font.pixelSize: 14
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                enabled: !view.picker.busy
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { view.picker.choose(row.index); view.picker.focusPicker() }
                onDoubleClicked: { view.picker.choose(row.index); view.picker.confirm() }
            }
            ToolTip.visible: rowMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: row.wallpaperSet ? row.wallpaperSet.title : ""
            Accessible.role: Accessible.Button
            Accessible.selected: row.index === view.picker.selectedIndex
            Accessible.name: row.wallpaperSet ? row.wallpaperSet.title : "Wallpaper"
            Accessible.onPressAction: view.picker.choose(row.index)
        }
    }
}
