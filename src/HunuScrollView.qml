import QtQuick
import QtQuick.Controls
ScrollView {
    id: view
    clip: true
    ScrollBar.vertical: HunuScrollBar {
        parent: view
        orientation: Qt.Vertical
        x: view.width - width
        y: view.topPadding
        height: view.availableHeight
        policy: ScrollBar.AsNeeded
    }
    ScrollBar.horizontal: HunuScrollBar {
        parent: view
        orientation: Qt.Horizontal
        x: view.leftPadding
        y: view.height - height
        width: view.availableWidth
        policy: ScrollBar.AsNeeded
    }
}
