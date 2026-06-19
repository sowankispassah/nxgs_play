import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: metric

    property string label: ""
    property string value: "0"
    property string detail: ""
    property string symbol: "NX"
    property color accentColor: "#00a7ff"

    color: "#151b27"
    radius: 16
    border.width: 1
    border.color: "#253044"
    implicitHeight: 142

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 3
        radius: 2
        color: metric.accentColor
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 18
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: metric.label
                color: "#94a3b8"
                font.pixelSize: 14
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 10
                color: Qt.rgba(metric.accentColor.r, metric.accentColor.g, metric.accentColor.b, 0.16)

                Label {
                    anchors.centerIn: parent
                    text: metric.symbol
                    color: metric.accentColor
                    font.bold: true
                    font.pixelSize: 12
                }
            }
        }

        Label {
            text: metric.value
            color: "#ffffff"
            font.bold: true
            font.pixelSize: 30
        }

        Label {
            Layout.fillWidth: true
            text: metric.detail
            color: "#74829a"
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }
}
