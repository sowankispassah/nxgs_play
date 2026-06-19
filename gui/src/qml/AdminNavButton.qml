import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Button {
    id: navButton

    property string symbol: ""
    property bool selected: false
    property bool collapsed: false

    Layout.fillWidth: true
    Layout.preferredHeight: 48
    hoverEnabled: true
    flat: true
    padding: 0

    background: Rectangle {
        radius: 11
        color: navButton.selected
            ? "#163451"
            : navButton.hovered ? "#182131" : "transparent"
        border.width: navButton.selected ? 1 : 0
        border.color: "#245c85"
    }

    contentItem: RowLayout {
        spacing: 12

        Rectangle {
            Layout.leftMargin: navButton.collapsed ? 0 : 13
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 9
            color: navButton.selected ? "#00a7ff" : "#202b3d"

            Label {
                anchors.centerIn: parent
                text: navButton.symbol
                color: navButton.selected ? "#07111e" : "#a9b5c8"
                font.bold: true
                font.pixelSize: 11
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !navButton.collapsed
            text: navButton.text
            color: navButton.selected ? "#ffffff" : "#a9b5c8"
            font.bold: navButton.selected
            font.pixelSize: 15
            elide: Text.ElideRight
        }
    }

    ToolTip.visible: collapsed && hovered
    ToolTip.text: text
}
