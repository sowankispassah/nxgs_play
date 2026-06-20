import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import com.nxgsstudio.nxgsgaming

Pane {
    id: rentalHome
    padding: 0
    property var availablePlans: []
    property var connectedControllers: []

    StackView.onActivated: playButton.forceActiveFocus(Qt.TabFocusReason)
    Keys.onEscapePressed: root.confirmQuit()

    Component.onCompleted: {
        updateConnectedControllers();
        if (Chiaki.rental.configured) {
            Chiaki.rental.loadPricing();
            Chiaki.rental.checkAvailability(Chiaki.discoveredConsoleCandidates());
        }
    }

    function updateAvailablePlans() {
        availablePlans = Chiaki.rental.availableTimePlansForStore(Chiaki.rental.selectedStoreId);
    }

    function updateConnectedControllers() {
        const controllers = [];
        for (let index = 0; index < Chiaki.controllers.length; ++index) {
            const controller = Chiaki.controllers[index];
            if (!controller.handheld && !controller.steamVirtual)
                controllers.push(controller);
        }
        connectedControllers = controllers;
    }

    function statusText() {
        if (!Chiaki.rental.configured)
            return qsTr("Service is not available.");
        if (Chiaki.rental.selectedStoreId.length === 0)
            return qsTr("This system is not assigned to a store.");
        if (Chiaki.rental.selectedStoreName.length === 0)
            return qsTr("Loading store assignment...");
        if (rentalHome.availablePlans.length === 0)
            return qsTr("No play plans are available for this system.");
        if (!Chiaki.rental.availabilityChecked || Chiaki.rental.state === "checking_availability")
            return qsTr("Checking console availability...");
        if (!Chiaki.rental.consoleAvailable)
            return qsTr("No console available. Please try again later.");
        return qsTr("Press Play to start.");
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 720)
        spacing: 28

        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
            Layout.preferredHeight: 120
            fillMode: Image.PreserveAspectFit
            source: "qrc:/icons/nxgs-gaming-logo-white.png"
            opacity: 0.9
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Powered by NXGS Gaming")
            font.bold: true
            font.pixelSize: 30
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: 640
            text: rentalHome.statusText()
            opacity: 0.75
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: Chiaki.rental.configured && Chiaki.rental.selectedStoreName.length > 0
            text: Chiaki.rental.selectedStoreName
            font.bold: true
            font.pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
            Layout.maximumWidth: 520
            elide: Text.ElideRight
        }

        Button {
            id: playButton
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 320
            Layout.preferredHeight: 120
            enabled: Chiaki.rental.configured
                && !Chiaki.rental.busy
                && Chiaki.rental.state !== "checking_availability"
                && Chiaki.rental.selectedStoreId.length > 0
                && Chiaki.rental.selectedStoreName.length > 0
                && rentalHome.availablePlans.length > 0
            text: Chiaki.rental.busy && Chiaki.rental.state === "reserving"
                ? qsTr("Reserving...")
                : Chiaki.rental.state === "checking_availability" ? qsTr("Checking...") : qsTr("Play")
            font.bold: true
            font.pixelSize: 40
            Material.background: Material.accent
            Material.roundedScale: Material.SmallScale
            onClicked: {
                if (!enabled)
                    return;
                if (Chiaki.rental.availabilityChecked && !Chiaki.rental.consoleAvailable) {
                    noConsoleDialog.open();
                    Chiaki.rental.checkAvailability(Chiaki.discoveredConsoleCandidates());
                    return;
                }
                Chiaki.rental.reserveConsole(Chiaki.discoveredConsoleCandidates());
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(520, rentalHome.width - 80)
            Layout.preferredHeight: controllerListColumn.implicitHeight + 28
            visible: rentalHome.connectedControllers.length > 0
            radius: 12
            color: "#111827"
            border.width: 1
            border.color: "#263247"

            ColumnLayout {
                id: controllerListColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: "#22c55e"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Connected Controllers")
                        color: "#e5e7eb"
                        font.bold: true
                        font.pixelSize: 16
                    }

                    Label {
                        text: String(rentalHome.connectedControllers.length)
                        color: "#8f9bb3"
                        font.pixelSize: 14
                    }
                }

                Repeater {
                    model: rentalHome.connectedControllers

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            Layout.preferredWidth: 24
                            text: String(index + 1)
                            color: "#00a7ff"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: "#cbd5e1"
                            elide: Text.ElideRight
                            font.pixelSize: 15
                        }

                        Label {
                            text: qsTr("Connected")
                            color: "#22c55e"
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: "#ef9a9a"
            visible: Chiaki.rental.error.length > 0
            text: Chiaki.rental.error
            wrapMode: Text.WordWrap
            Layout.maximumWidth: 640
        }
    }

    Label {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 20
        }
        text: Qt.application.version
    }

    Dialog {
        id: durationDialog
        property bool paymentStarted: false
        parent: Overlay.overlay
        x: Math.round((rentalHome.width - width) / 2)
        y: Math.round((rentalHome.height - height) / 2)
        title: qsTr("Select Play Duration")
        modal: true
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Cancel
        onOpened: paymentStarted = false
        onRejected: {
            if (!paymentStarted)
                Chiaki.rental.releaseReservation();
        }
        Material.roundedScale: Material.MediumScale

            ColumnLayout {
            spacing: 16

            Repeater {
                model: rentalHome.availablePlans

                Button {
                    Layout.preferredWidth: 360
                    Layout.preferredHeight: 64
                    enabled: !Chiaki.rental.busy
                    text: Chiaki.rental.busy
                        ? qsTr("Creating order...")
                        : qsTr("%1  %2").arg(Chiaki.rental.timePlanLabel(modelData)).arg(Chiaki.rental.priceLabel(Chiaki.rental.selectedStoreId, modelData.id))
                    Material.roundedScale: Material.SmallScale
                    onClicked: {
                        if (!enabled)
                            return;
                        durationDialog.paymentStarted = true;
                        Chiaki.rental.createPaymentOrder(modelData.id);
                        durationDialog.close();
                    }
                }
            }

            Label {
                Layout.preferredWidth: 360
                visible: rentalHome.availablePlans.length === 0
                text: qsTr("No active time plans are priced for this store.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.75
            }
        }
    }

    Dialog {
        id: noConsoleDialog
        parent: Overlay.overlay
        x: Math.round((rentalHome.width - width) / 2)
        y: Math.round((rentalHome.height - height) / 2)
        title: qsTr("No console available")
        modal: true
        standardButtons: Dialog.Ok
        Material.roundedScale: Material.MediumScale

        Label {
            text: qsTr("No console available. Please try again later.")
            wrapMode: Text.WordWrap
            width: 360
        }
    }

    Dialog {
        id: serviceErrorDialog
        parent: Overlay.overlay
        x: Math.round((rentalHome.width - width) / 2)
        y: Math.round((rentalHome.height - height) / 2)
        title: qsTr("Service unavailable")
        modal: true
        standardButtons: Dialog.Ok
        Material.roundedScale: Material.MediumScale

        Label {
            text: Chiaki.rental.error
            wrapMode: Text.WordWrap
            width: 420
        }
    }

    Connections {
        target: Chiaki.rental

        function onReservationReady() {
            rentalHome.updateAvailablePlans();
            durationDialog.open();
        }

        function onNoConsoleAvailable() {
            noConsoleDialog.open();
        }

        function onPricingChanged() {
            rentalHome.updateAvailablePlans();
        }

        function onTimePlansChanged() {
            rentalHome.updateAvailablePlans();
        }

        function onSelectedStoreIdChanged() {
            rentalHome.updateAvailablePlans();
        }

        function onErrorChanged() {
            if (Chiaki.rental.state === "error" && Chiaki.rental.error.length > 0)
                serviceErrorDialog.open();
        }

        function onStateChanged() {
            if (Chiaki.rental.state === "error" && Chiaki.rental.error.length > 0)
                serviceErrorDialog.open();
        }
    }

    Connections {
        target: Chiaki

        function onControllersChanged() {
            rentalHome.updateConnectedControllers();
        }

        function onHostsChanged() {
            if (Chiaki.rental.configured && !Chiaki.rental.busy)
                Chiaki.rental.checkAvailability(Chiaki.discoveredConsoleCandidates());
        }
    }

}
