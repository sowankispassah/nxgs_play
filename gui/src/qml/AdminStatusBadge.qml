import QtQuick
import QtQuick.Controls

Rectangle {
    id: badge

    property string status: ""
    property string label: status.length > 0
        ? status.charAt(0).toUpperCase() + status.slice(1).replace("_", " ")
        : qsTr("Unknown")

    readonly property color statusColor: {
        switch (status.toLowerCase()) {
        case "available":
        case "active":
        case "completed":
        case "paid":
        case "enabled":
            return "#22c55e";
        case "in_session":
        case "occupied":
        case "reserved":
        case "awaiting_payment":
            return "#00a7ff";
        case "maintenance":
        case "pending":
            return "#f59e0b";
        case "offline":
        case "disconnected":
        case "disabled":
        case "expired":
            return "#f87171";
        default:
            return "#94a3b8";
        }
    }

    implicitWidth: badgeLabel.implicitWidth + 22
    implicitHeight: 26
    radius: 13
    color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.14)
    border.width: 1
    border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.36)

    Label {
        id: badgeLabel
        anchors.centerIn: parent
        text: badge.label
        color: badge.statusColor
        font.bold: true
        font.pixelSize: 11
    }
}
