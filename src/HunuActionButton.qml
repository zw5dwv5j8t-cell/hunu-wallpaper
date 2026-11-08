import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: control
    property bool primary: false
    property bool compact: false
    property bool alignLeft: false
    property string glyph: ""
    implicitHeight: compact ? 32 : 40
    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    leftPadding: compact ? 11 : 15
    rightPadding: leftPadding
    topPadding: 6
    bottomPadding: 6
    font.family: Theme.fontFamily
    font.pixelSize: 13
    font.weight: primary || checked ? Font.DemiBold : Font.Medium
    background: Rectangle {
        radius: Theme.radiusSmall
        color: !control.enabled ? Qt.alpha(Theme.surface, 0.5)
            : control.primary || control.checked ? Theme.accent
            : control.down ? Theme.hoverSurface
            : control.hovered ? Theme.raised : control.flat ? "transparent" : Theme.surface
        border.width: 1
        border.color: control.primary || control.checked ? Theme.accent
            : control.activeFocus ? Theme.accent : control.hovered ? Qt.alpha(Theme.subtext, 0.5)
            : control.flat ? "transparent" : Theme.border
    }
    contentItem: RowLayout {
        spacing: 8
        Item { Layout.fillWidth: !control.alignLeft; visible: !control.alignLeft }
        HunuIcon {
            visible: control.glyph !== ""
            symbol: control.glyph
            iconColor: !control.enabled ? Theme.muted : control.primary || control.checked ? Theme.onAccent : Theme.text
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
        }
        Text {
            text: control.text
            font: control.font
            color: !control.enabled ? Theme.muted : control.primary || control.checked ? Theme.onAccent : Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Item { Layout.fillWidth: !control.alignLeft; visible: !control.alignLeft }
    }
}
