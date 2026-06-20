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

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(720, rentalHome.width - 80)
            Layout.preferredHeight: controllerDisplayRow.implicitHeight
            visible: rentalHome.connectedControllers.length > 0

            Row {
                id: controllerDisplayRow
                anchors.centerIn: parent
                spacing: 18

                Repeater {
                    model: rentalHome.connectedControllers

                    Rectangle {
                        width: 172
                        height: 116
                        radius: 12
                        color: "#0f1724"
                        border.width: 1
                        border.color: activityGlow.opacity > 0
                            ? "#00a7ff"
                            : "#263247"

                        Rectangle {
                            id: activityGlow
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: parent.radius + 1
                            color: "transparent"
                            border.width: 2
                            border.color: "#00a7ff"
                            opacity: 0
                        }

                        Item {
                            id: controllerIconFrame
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                top: parent.top
                                topMargin: 14
                            }
                            width: 64
                            height: 42

                            Image {
                                id: controllerIcon
                                x: 2
                                y: 1
                                width: 60
                                height: 38
                                source: "qrc:/icons/dualsense-controller.svg"
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 320
                                sourceSize.height: 190
                            }
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            width: parent.width - 20
                            height: 44
                            text: modelData.name
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        SequentialAnimation {
                            id: controllerActivityAnimation
                            alwaysRunToEnd: false

                            ScriptAction {
                                script: {
                                    controllerIcon.x = 2;
                                    activityGlow.opacity = 0;
                                }
                            }

                            ParallelAnimation {
                                SequentialAnimation {
                                    NumberAnimation { target: controllerIcon; property: "x"; to: -2; duration: 28; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: controllerIcon; property: "x"; to: 6; duration: 36; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: controllerIcon; property: "x"; to: -1; duration: 36; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: controllerIcon; property: "x"; to: 5; duration: 32; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: controllerIcon; property: "x"; to: 2; duration: 38; easing.type: Easing.OutQuad }
                                }

                                SequentialAnimation {
                                    NumberAnimation { target: activityGlow; property: "opacity"; to: 0.9; duration: 70; easing.type: Easing.OutQuad }
                                    PauseAnimation { duration: 50 }
                                    NumberAnimation { target: activityGlow; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InQuad }
                                }
                            }
                        }

                        Connections {
                            target: modelData

                            function onInputActivity() {
                                controllerActivityAnimation.restart();
                            }
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
