import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import com.nxgsstudio.nxgsgaming

Item {
    id: root
    property list<Item> restoreFocusItems
    property bool initialAsk: false
    readonly property bool preferSeparateStreamSettingsWindows: Chiaki.window.runtimeRendererBackend === 1 && Chiaki.session
    property bool useSeparateStreamSettingsWindows: false
    property bool kioskControlsAuthorized: false
    property bool kioskUnlockAttempted: false
    property bool kioskDialogInputGrabbed: false
    Material.theme: Material.Dark
    Material.accent: "#00a7ff"

    function controllerButton(name) {
        let type = "deck";
        for (let i = 0; i < Chiaki.controllers.length; ++i) {
            if (Chiaki.controllers[i].playStation) {
                type = "ps";
                break;
            }
        }
        return "image://svg/button-%1#%2".arg(type).arg(name);
    }
    function grabInput(item) {
        Chiaki.window.grabInput();
        restoreFocusItems.push(Window.window.activeFocusItem);
        if (item)
            item.forceActiveFocus(Qt.TabFocusReason);
    }

    function releaseInput() {
        Chiaki.window.releaseInput();
        let item = restoreFocusItems.pop();
        if (item && item.visible)
            item.forceActiveFocus(Qt.TabFocusReason);
    }

    function autoRegister(auto, host, ps5) {
        if(auto)
            Chiaki.autoRegister()
        else
            showRegistDialog(host, ps5);
    }

    function openDisplaySettings() {
        useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
        const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
        if(loader.status == Loader.Ready)
        {
            if(placeboSettingsRect.opacity || displaySettingsRect.opacity || colorMappingSettingsRect.opacity)
                closeDialog();
            displaySettingsRect.opacity = 0.8;
            grabInput(loader);
            if (!loader.item.restoreFocusItem) {
                let item = loader.item.mainItem.nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
            } else {
                loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                loader.item.restoreFocusItem = null;
            }
        }
    }
    function openPlaceboSettings() {
        if (!displaySettingsRect.opacity && !placeboSettingsRect.opacity && !colorMappingSettingsRect.opacity)
            useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
        const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
        if(loader.status == Loader.Ready)
        {
            if(placeboSettingsRect.opacity || displaySettingsRect.opacity || colorMappingSettingsRect.opacity)
                closeDialog();
            placeboSettingsRect.opacity = 0.8;
            grabInput(loader);
            if (!loader.item.restoreFocusItem) {
                let item = loader.item.mainItem.nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
            } else {
                loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                loader.item.restoreFocusItem = null;
            }
        }
    }

    function closeDialog() {
       if(displaySettingsRect.opacity) {
        displaySettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        releaseInput();
        useSeparateStreamSettingsWindows = false;
       }
       else if(placeboSettingsRect.opacity) {
        placeboSettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        releaseInput();
        useSeparateStreamSettingsWindows = false;
       }
       else if(colorMappingSettingsRect.opacity) {
        releaseInput();
        colorMappingSettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        root.openPlaceboSettings();
       }
       else
        stack.pop();
    }

    function showMainView() {
        if(displaySettingsRect.opacity) {
            displaySettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        else if(placeboSettingsRect.opacity) {
            placeboSettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        else if(colorMappingSettingsRect.opacity) {
            colorMappingSettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        if (stack.depth > 1)
            stack.pop(stack.get(0));
        else
            stack.replace(stack.get(0), rentalHomeViewComponent);
    }

    function showHostList() {
        stack.push(hostListViewComponent);
    }

    function showRentalHome() {
        Chiaki.window.setKioskManagementMode(false);
        if (stack.depth > 1)
            stack.pop(stack.get(0), StackView.Immediate);
        stack.replace(stack.get(0), rentalHomeViewComponent, {}, StackView.Immediate);
    }
    function showControllerAdmin() {
        Chiaki.window.setKioskManagementMode(Chiaki.rental.controllerAdminAuthenticated);
        stack.push(controllerAdminViewComponent);
    }

    function goBack() {
        if (stack.depth > 1)
            stack.pop();
        else
            showMainView();
    }

    function confirmQuit() {
        if (Chiaki.window.kioskLocked) {
            requestKioskUnlock();
            return;
        }
        root.showConfirmDialog(qsTr("Quit"), qsTr("Are you sure you want to quit?"), () => Qt.quit());
    }

    function requestKioskUnlock() {
        if (kioskUnlockDialog.visible)
            return;
        kioskControlsAuthorized = false;
        kioskUnlockAttempted = false;
        kioskPinField.text = "";
        kioskUnlockDialog.open();
    }

    function closeKioskUnlock() {
        kioskControlsAuthorized = false;
        kioskUnlockAttempted = false;
        kioskPinField.text = "";
        kioskUnlockDialog.close();
    }

    function showStreamView() {
        stack.replace(stack.get(0), streamViewComponent);
    }

    function showPsnView() {
        stack.replace(stack.get(0), psnViewComponent, {}, StackView.Immediate)
    }

    function showManualHostDialog() {
        stack.push(manualHostDialogComponent);
    }

    function showConfirmDialog(title, text, callback, rejectCallback = null) {
        confirmDialog.title = title;
        confirmDialog.text = text;
        confirmDialog.callback = callback;
        confirmDialog.rejectCallback = rejectCallback;
        confirmDialog.restoreFocusItem = Window.window.activeFocusItem;
        confirmDialog.open();
    }

    function showInfoDialog(title, text) {
        infoDialog.title = title;
        infoDialog.text = text;
        infoDialog.restoreFocusItem = Window.window.activeFocusItem;
        infoDialog.open();
    }

    function showRendererFallbackDialog(reason) {
        showInfoDialog(qsTr("Renderer Fallback"),
                       qsTr("Vulkan renderer is unavailable and NXGS Gaming switched to OpenGL.\n\nReason: %1").arg(reason));
    }

    function showRemindDialog(title, text, remotePlay, callback) {
        remindDialog.title = title;
        remindDialog.text = text;
        remindDialog.remotePlay = remotePlay;
        remindDialog.callback = callback;
        remindDialog.restoreFocusItem = Window.window.activeFocusItem;
        remindDialog.open();
    }


    function showRegistDialog(host, ps5) {
        stack.push(registDialogComponent, {host: host, ps5: ps5});
    }

    function showSettingsDialog() {
        stack.push(settingsDialogComponent);
    }

    function showDisplaySettingsDialog() {
        stack.push(displaySettingsDialogComponent);
    }

    function showPlaceboSettingsDialog() {
        stack.push(placeboSettingsDialogComponent);
    }

    function showPlaceboColorMappingDialog() {
        if(placeboSettingsRect.opacity)
        {
            root.closeDialog();
            useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
            const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
            if(loader.status == Loader.Ready)
            {
                grabInput(loader);
                colorMappingSettingsRect.opacity = 0.8;
                if (!loader.item.restoreFocusItem) {
                    let item = loader.item.mainItem.nextItemInFocusChain();
                    if (item)
                        item.forceActiveFocus(Qt.TabFocusReason);
                } else {
                    loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                    loader.item.restoreFocusItem = null;
                }
            }
        }
        else
            stack.push(placeboColorMappingDialogComponent);
    }

    function showProfileDialog() {
        stack.push(profileDialogComponent)
    }

    function showConsolePinDialog(consoleIndex) {
        stack.push(consolePinDialogComponent, {consoleIndex: consoleIndex});
    }

    function showSteamShortcutDialog(fromReminder) {
        stack.push(steamShortcutDialogComponent, {fromReminder: fromReminder});
    }

    function showPSNTokenDialog(psnurl, expired) {
        stack.push(psnTokenDialogComponent, {psnurl: psnurl, expired: expired});
    }

    function showControllerMappingDialog() {
        stack.push(controllerMappingDialogComponent)
    }

    Component.onCompleted: {
        if (Chiaki.session)
            stack.replace(stack.get(0), streamViewComponent, {}, StackView.Immediate);
        else if (Chiaki.autoConnect)
            stack.replace(stack.get(0), autoConnectViewComponent, {}, StackView.Immediate);
    }

    Pane {
        anchors.fill: parent
        visible: !Chiaki.window.hasVideo && !Chiaki.window.keepVideo
    }

    StackView {
        id: stack
        anchors.fill: parent
        hoverEnabled: false
        initialItem: rentalHomeViewComponent
        font.pixelSize: 20

        replaceEnter: Transition {
            PropertyAnimation {
                property: "opacity"
                from: 0.01
                to: 1.0
                duration: 200
            }
        }

        replaceExit: Transition {
            PropertyAnimation {
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: 200
            }
        }
    }

    Dialog {
        id: kioskUnlockDialog
        parent: Overlay.overlay
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        width: Math.min(root.width - 80, 560)
        title: root.kioskControlsAuthorized ? qsTr("System Controls") : qsTr("Authorized Access")
        modal: true
        closePolicy: Popup.NoAutoClose
        Material.roundedScale: Material.MediumScale

        onOpened: {
            if (!root.kioskDialogInputGrabbed) {
                root.grabInput(root.kioskControlsAuthorized ? kioskReturnButton : kioskPinField);
                root.kioskDialogInputGrabbed = true;
            }
            if (!root.kioskControlsAuthorized)
                kioskPinField.forceActiveFocus(Qt.TabFocusReason);
        }

        onClosed: {
            if (root.kioskDialogInputGrabbed) {
                root.releaseInput();
                root.kioskDialogInputGrabbed = false;
            }
        }

        ColumnLayout {
            width: kioskUnlockDialog.width - 48
            spacing: 14

            Label {
                Layout.fillWidth: true
                visible: !root.kioskControlsAuthorized
                text: qsTr("Enter the management access code to unlock system controls.")
                color: "#cbd5e1"
                wrapMode: Text.WordWrap
            }

            TextField {
                id: kioskPinField
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: !root.kioskControlsAuthorized
                enabled: !Chiaki.rental.adminBusy
                placeholderText: qsTr("Access code")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: kioskVerifyButton.clicked()
            }

            Label {
                Layout.fillWidth: true
                visible: !root.kioskControlsAuthorized
                    && root.kioskUnlockAttempted
                    && !Chiaki.rental.adminBusy
                    && Chiaki.rental.adminError.length > 0
                text: qsTr("Incorrect code. NXGS remains locked.")
                color: "#fb7185"
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.kioskControlsAuthorized
                spacing: 10

                Button {
                    Layout.fillWidth: true
                    enabled: !Chiaki.rental.adminBusy
                    text: qsTr("Cancel")
                    onClicked: root.closeKioskUnlock()
                }

                Button {
                    id: kioskVerifyButton
                    Layout.fillWidth: true
                    enabled: !Chiaki.rental.adminBusy && kioskPinField.text.length > 0
                    text: Chiaki.rental.adminBusy ? qsTr("Checking...") : qsTr("Unlock")
                    Material.background: "#00a7ff"
                    onClicked: {
                        if (!enabled)
                            return;
                        root.kioskUnlockAttempted = true;
                        Chiaki.rental.verifyControllerPin(kioskPinField.text);
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: root.kioskControlsAuthorized
                columns: width > 440 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Minimize App")
                    onClicked: {
                        root.closeKioskUnlock();
                        Chiaki.window.minimizeForAdmin();
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Exit Full Screen")
                    onClicked: {
                        root.closeKioskUnlock();
                        Chiaki.window.exitKioskMode();
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Open Management")
                    onClicked: {
                        root.closeKioskUnlock();
                        root.showControllerAdmin();
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Close NXGS")
                    onClicked: {
                        root.closeKioskUnlock();
                        Chiaki.window.closeForAdmin();
                    }
                }

                Button {
                    id: kioskReturnButton
                    Layout.columnSpan: parent.columns
                    Layout.fillWidth: true
                    text: qsTr("Return to Locked Mode")
                    Material.background: "#00a7ff"
                    onClicked: {
                        Chiaki.rental.controllerAdminLogout();
                        root.closeKioskUnlock();
                        Chiaki.window.enterKioskMode();
                    }
                }
            }
        }
    }

    Rectangle {
        id: placeboSettingsRect
        opacity: 0.0
        visible: opacity && !useSeparateStreamSettingsWindows
        height: 650
        width: 1200
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        color: Material.background
        Loader {
            anchors.fill: parent
            id: placeboSettingsLoader
            sourceComponent: placeboSettingsDialogComponent
        }
    }
    Rectangle {
        id: displaySettingsRect
        opacity: 0.0
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: 500
        width: 1200
        visible: opacity && !useSeparateStreamSettingsWindows
        color: Material.background
        Loader {
            anchors.fill: parent
            id: displaySettingsLoader
            sourceComponent: displaySettingsDialogComponent
        }
    }
    Rectangle {
        id: colorMappingSettingsRect
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: 0.0
        height: 600
        width: 1200
        visible: opacity && !useSeparateStreamSettingsWindows
        color: Material.background
        Loader {
            anchors.fill: parent
            id: colorMappingSettingsLoader
            sourceComponent: placeboColorMappingDialogComponent
        }
    }

    Window {
        id: separateDisplaySettingsWindow
        visible: useSeparateStreamSettingsWindows && displaySettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: separateDisplaySettingsLoader.item ? Math.min(Math.round(root.height), Math.round(separateDisplaySettingsLoader.item.gridHeight + 140)) : 500
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separateDisplaySettingsLoader
            sourceComponent: displaySettingsDialogComponent
        }
    }

    Window {
        id: separatePlaceboSettingsWindow
        visible: useSeparateStreamSettingsWindows && placeboSettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: Math.min(Math.round(root.height), 650)
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separatePlaceboSettingsLoader
            sourceComponent: placeboSettingsDialogComponent
        }
    }

    Window {
        id: separateColorMappingSettingsWindow
        visible: useSeparateStreamSettingsWindows && colorMappingSettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: Math.min(Math.round(root.height), 600)
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separateColorMappingSettingsLoader
            sourceComponent: placeboColorMappingDialogComponent
        }
    }
    Rectangle {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 30
        }
        color: Material.accent
        width: errorLayout.width + 40
        height: errorLayout.height + 20
        radius: 8
        opacity: errorHideTimer.running ? 0.8 : 0.0

        Behavior on opacity { NumberAnimation { duration: 500 } }

        ColumnLayout {
            id: errorLayout
            anchors.centerIn: parent

            Label {
                id: errorTitleLabel
                Layout.alignment: Qt.AlignCenter
                font.bold: true
                font.pixelSize: 24
            }

            Label {
                id: errorTextLabel
                Layout.alignment: Qt.AlignCenter
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 20
            }
        }

        Timer {
            id: errorHideTimer
            interval: 2000
        }
    }

    Dialog {
        id: infoDialog
        property alias text: infoDialogLabel.text
        property Item restoreFocusItem
        parent: Overlay.overlay
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        modal: true
        Material.roundedScale: Material.MediumScale
        onOpened: infoDialogLabel.forceActiveFocus(Qt.TabFocusReason)
        onClosed: {
            if (restoreFocusItem)
                restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
            infoDialogLabel.focus = false;
        }

        Component.onCompleted: {
            header.horizontalAlignment = Text.AlignHCenter;
            header.background = null;
        }

        ColumnLayout {
            spacing: 20

            Label {
                id: infoDialogLabel
                Keys.onEscapePressed: infoDialog.close()
                Keys.onReturnPressed: infoDialog.close()
            }

            RowLayout {
                Layout.alignment: Qt.AlignCenter

                Button {
                    text: qsTr("OK")
                    Material.background: Material.accent
                    flat: true
                    leftPadding: 50
                    onClicked: infoDialog.close()
                    Material.roundedScale: Material.SmallScale

                    Image {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                        }
                        width: 28
                        height: 28
                        sourceSize: Qt.size(width, height)
                        source: root.controllerButton("cross")
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: confirmDialog
    }

    RemindDialog {
        id: remindDialog
    }

    Dialog {
        id: rentalPaymentDialog
        property Item web: null
        parent: Overlay.overlay
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        width: Math.min(root.width - 80, 900)
        height: Math.min(root.height - 80, 720)
        title: qsTr("Payment")
        modal: true
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Cancel
        Material.roundedScale: Material.MediumScale

        function queryValue(url, key) {
            const marker = key + "=";
            const queryIndex = url.indexOf("?");
            if (queryIndex < 0)
                return "";
            const parts = url.substring(queryIndex + 1).split("&");
            for (let i = 0; i < parts.length; ++i) {
                if (parts[i].indexOf(marker) === 0)
                    return decodeURIComponent(parts[i].substring(marker.length));
            }
            return "";
        }

        function createPaymentWebView() {
            if (web)
                web.destroy();
            web = null;
            try {
                web = Qt.createQmlObject("
                    import QtWebEngine
                    import com.nxgsstudio.nxgsgaming
                    WebEngineView {
                        settings {
                            localContentCanAccessRemoteUrls: true
                        }
                        onContextMenuRequested: (request) => request.accepted = true
                        onNavigationRequested: (request) => {
                            const nextUrl = request.url.toString();
                            if (nextUrl.indexOf('nxgs://razorpay-success') === 0) {
                                Chiaki.rental.verifyPayment(
                                    rentalPaymentDialog.queryValue(nextUrl, 'razorpay_payment_id'),
                                    rentalPaymentDialog.queryValue(nextUrl, 'razorpay_order_id'),
                                    rentalPaymentDialog.queryValue(nextUrl, 'razorpay_signature'));
                                request.reject();
                                rentalPaymentDialog.close();
                            } else if (nextUrl.indexOf('nxgs://razorpay-cancelled') === 0) {
                                Chiaki.rental.clearPayment();
                                request.reject();
                                rentalPaymentDialog.close();
                            } else {
                                request.accept();
                            }
                        }
                    }", paymentWebHost, "rentalPaymentWebView");
                web.anchors.fill = paymentWebHost;
                web.loadHtml(Chiaki.rental.paymentHtml, "https://checkout.razorpay.com/");
            } catch (error) {
                Chiaki.rental.clearPayment();
                root.showInfoDialog(qsTr("Payment unavailable"), qsTr("Qt WebEngine is required to complete Razorpay checkout in NXGS."));
                rentalPaymentDialog.close();
            }
        }

        onOpened: createPaymentWebView()
        onRejected: Chiaki.rental.clearPayment()
        onClosed: {
            if (web) {
                web.destroy();
                web = null;
            }
        }

        Item {
            id: paymentWebHost
            width: rentalPaymentDialog.width - 48
            height: rentalPaymentDialog.height - 150
        }
    }

    Connections {
        target: Chiaki

        function onSessionChanged() {
            if (Chiaki.session)
                root.showStreamView();
        }

        function onShowPsnView() {
            root.showPsnView();
        }

        function onPsnCredsExpired() {
            Chiaki.settings.psnRefreshToken = ""
            Chiaki.settings.psnAuthToken = ""
            Chiaki.settings.psnAuthTokenExpiry = ""
            Chiaki.settings.psnAccountId = ""
            root.showPSNTokenDialog(true);
        }

        function onError(title, text) {
            errorTitleLabel.text = title;
            errorTextLabel.text = text;
            errorHideTimer.start();
        }

        function onRegistDialogRequested(host, ps5, duid) {
            if(!duid)
                showRegistDialog(host, ps5);
            else
            {
                if(ps5)
                    root.showConfirmDialog(qsTr("Registration Type"), qsTr("Would you like to use automatic registration?"), () => root.autoRegister(true, host, ps5), () => root.autoRegister(false, host, ps5))
                else
                    root.showConfirmDialog(qsTr("Registration Type"), qsTr("Would you like to use automatic registration (must be main PS4 console registered to your PSN)?"), () => root.autoRegister(true, host, ps5), () => root.autoRegister(false, host, ps5))
            }
        }

        function onWakeupStartInitiated() {
            stack.replace(stack.get(0), autoConnectViewComponent, {}, StackView.Immediate);
        }
    }

    Connections {
        target: Chiaki.rental

        function onPaymentHtmlChanged() {
            if (Chiaki.rental.paymentHtml.length > 0)
                rentalPaymentDialog.open();
        }
        function onControllerPinVerified() {
            if (!kioskUnlockDialog.visible || !root.kioskUnlockAttempted)
                return;
            root.kioskControlsAuthorized = true;
            root.kioskUnlockAttempted = false;
            kioskPinField.text = "";
            kioskReturnButton.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Connections {
        target: Chiaki.window

        function onKioskUnlockRequested() {
            root.requestKioskUnlock();
        }
    }
    Component {
        id: rentalHomeViewComponent
        RentalHomeView { }
    }

    Component {
        id: hostListViewComponent
        MainView { }
    }

    Component {
        id: controllerAdminViewComponent
        AdminDashboardView { }
    }

    Component {
        id: streamViewComponent
        StreamView { }
    }

    Component {
        id: autoConnectViewComponent
        AutoConnectView { }
    }

    Component {
        id: psnViewComponent
        PsnView {}
    }

    Component {
        id: manualHostDialogComponent
        ManualHostDialog { }
    }

    Component {
        id: settingsDialogComponent
        SettingsDialog { }
    }

    Component {
        id: displaySettingsDialogComponent
        DisplaySettingsDialog { }
    }

    Component {
        id: placeboSettingsDialogComponent
        PlaceboSettingsDialog { }
    }

    Component {
        id: placeboColorMappingDialogComponent
        PlaceboColorMappingDialog { }
    }

    Component {
        id: profileDialogComponent
        ProfileDialog { }
    }

    Component {
        id: consolePinDialogComponent
        ConsolePinDialog { }
    }

    Component {
        id: steamShortcutDialogComponent
        SteamShortcutDialog { }
    }

    Component {
        id: psnTokenDialogComponent
        PSNTokenDialog { }
    }

    Component {
        id: registDialogComponent
        RegistDialog { }
    }

    Component {
        id: controllerMappingDialogComponent
        ControllerMappingDialog { }
    }
}
