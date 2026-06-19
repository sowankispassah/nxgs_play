import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: card

    default property alias content: contentColumn.data
    property string title: ""
    property string subtitle: ""
    property color surfaceColor: "#151b27"
    property color borderColor: "#253044"

    color: surfaceColor
    radius: 16
    border.width: 1
    border.color: borderColor
    implicitHeight: contentColumn.implicitHeight + 40

    ColumnLayout {
        id: contentColumn
        anchors {
            fill: parent
            margins: 20
        }
        spacing: 14

        Label {
            Layout.fillWidth: true
            visible: card.title.length > 0
            text: card.title
            color: "#f7f9fc"
            font.bold: true
            font.pixelSize: 20
            elide: Text.ElideRight
        }

        Label {
            Layout.fillWidth: true
            visible: card.subtitle.length > 0
            text: card.subtitle
            color: "#8f9bb3"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }
    }
}
