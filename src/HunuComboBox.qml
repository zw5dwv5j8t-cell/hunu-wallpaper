import QtQuick
import QtQuick.Controls
ComboBox {
    id: control
    implicitWidth: 200
    implicitHeight: 40
    leftPadding: 12
    rightPadding: 32
    font.family: Theme.fontFamily
    font.pixelSize: 13
    contentItem: Text {
        text: control.displayText; font: control.font
        color: control.enabled ? Theme.text : Theme.muted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle { radius: Theme.radiusSmall; color: Theme.surface; border.color: control.activeFocus ? Theme.accent : Theme.border }
    indicator: Canvas {
        x: control.width-width-13; y: (control.height-height)/2; width: 10; height: 6
        onPaint: { const c=getContext("2d"); c.strokeStyle=Theme.subtext; c.lineWidth=1.6; c.moveTo(1,1);c.lineTo(5,5);c.lineTo(9,1);c.stroke() }
    }
    delegate: ItemDelegate {
        required property int index
        required property var modelData
        width: control.width - 12
        height: 38
        contentItem: Text {
            text: control.textRole && typeof modelData === "object" ? modelData[control.textRole] : String(modelData)
            color: parent.highlighted ? Theme.onAccent : Theme.text
            font: control.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        highlighted: control.highlightedIndex === index
        background: Rectangle { radius: 7; color: parent.highlighted ? Theme.accent : "transparent" }
    }
    popup: Popup {
        y: control.height + 5
        width: control.width
        padding: 6
        implicitHeight: Math.min(280, contentItem.implicitHeight + 12)
        background: Rectangle { color: Theme.raised; radius: 12; border.color: Theme.border }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
