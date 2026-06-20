import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import com.nxgsstudio.nxgsgaming

Pane {
    id: controllerAdmin
    padding: 0

    property int section: 0
    readonly property var statusOptions: ["available", "offline", "maintenance", "disabled"]
    readonly property var tabLabels: [
        qsTr("System Store"),
        qsTr("Add Console"),
        qsTr("Manage Consoles"),
        qsTr("Add Store"),
        qsTr("Manage Stores"),
        qsTr("Add Time Plans"),
        qsTr("Manage Time Plans"),
        qsTr("Pricing")
    ]

    StackView.onActivated: pinField.forceActiveFocus(Qt.TabFocusReason)
    Keys.onEscapePressed: root.goBack()

    function refreshAddList() {
        Chiaki.rental.listDiscoveredConsoles(Chiaki.discoveredConsoleCandidates());
    }

    function refreshAllAdminData() {
        refreshAddList();
        Chiaki.rental.listManagedConsoles();
        Chiaki.rental.listStores();
        Chiaki.rental.listTimePlans();
        Chiaki.rental.listPricingRules();
    }

    function statusIndex(status) {
        for (let i = 0; i < statusOptions.length; ++i) {
            if (statusOptions[i] === status)
                return i;
        }
        return 0;
    }

    function storeIndex(storeId) {
        for (let i = 0; i < Chiaki.rental.managedStores.length; ++i) {
            if (Chiaki.rental.managedStores[i].id === storeId)
                return i;
        }
        return -1;
    }

    function syncSystemStoreSelector() {
        if (typeof systemStoreSelector !== "undefined" && systemStoreSelector)
            systemStoreSelector.currentIndex = controllerAdmin.storeIndex(Chiaki.rental.selectedStoreId);
    }

    function moneyText(amountPaise, currency) {
        return "%1 %2".arg(currency || "INR").arg((Number(amountPaise || 0) / 100).toFixed(2));
    }

    function rupeesToPaise(value) {
        return Math.round(Number(value || 0) * 100);
    }

    ToolButton {
        id: backButton
        anchors {
            top: parent.top
            left: parent.left
            margins: 20
        }
        z: 10
        width: 64
        height: 64
        flat: true
        text: "X"
        font.pixelSize: 30
        focusPolicy: Qt.NoFocus
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Back")
        onClicked: root.goBack()
    }

    ColumnLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 28
            leftMargin: 28
            rightMargin: 28
            bottomMargin: 28
        }
        spacing: 16

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 520
            spacing: 18
            visible: !Chiaki.rental.controllerAdminAuthenticated

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Enter Code")
                font.bold: true
                font.pixelSize: 32
            }

            TextField {
                id: pinField
                Layout.fillWidth: true
                placeholderText: qsTr("Code")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                enabled: !Chiaki.rental.adminBusy
                onAccepted: loginButton.clicked()
            }

            Button {
                id: loginButton
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                enabled: Chiaki.rental.controllerAdminConfigured && !Chiaki.rental.adminBusy && pinField.text.length > 0
                text: Chiaki.rental.adminBusy ? qsTr("Checking...") : qsTr("Continue")
                Material.background: Material.accent
                Material.roundedScale: Material.SmallScale
                onClicked: {
                    if (!enabled)
                        return;
                    Chiaki.rental.verifyControllerPin(pinField.text);
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#ef9a9a"
                visible: Chiaki.rental.adminError.length > 0
                text: Chiaki.rental.adminError
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14
            visible: Chiaki.rental.controllerAdminAuthenticated

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    clip: true
                    contentWidth: tabRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds

                    RowLayout {
                        id: tabRow
                        height: parent.height
                        spacing: 10

                        Repeater {
                            model: controllerAdmin.tabLabels

                            Button {
                                Layout.preferredWidth: index === 6 ? 190 : 150
                                Layout.preferredHeight: 52
                                text: modelData
                                Material.background: controllerAdmin.section === index ? Material.accent : undefined
                                Material.roundedScale: Material.SmallScale
                                onClicked: {
                                    controllerAdmin.section = index;
                                    if (index === 0)
                                        Chiaki.rental.listStores();
                                    else if (index === 1)
                                        controllerAdmin.refreshAddList();
                                    else if (index === 2)
                                        Chiaki.rental.listManagedConsoles();
                                    else if (index === 4)
                                        Chiaki.rental.listStores();
                                    else if (index === 6)
                                        Chiaki.rental.listTimePlans();
                                    else if (index === 7)
                                        Chiaki.rental.listPricingRules();
                                }
                            }
                        }
                    }
                }

                Button {
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 52
                    text: qsTr("Consoles")
                    enabled: !Chiaki.rental.adminBusy
                    Material.roundedScale: Material.SmallScale
                    onClicked: root.showHostList()
                }

                Button {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 52
                    icon.source: "qrc:/icons/settings-20px.svg"
                    icon.width: 30
                    icon.height: 30
                    display: AbstractButton.IconOnly
                    enabled: !Chiaki.rental.adminBusy
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Settings")
                    Material.roundedScale: Material.SmallScale
                    onClicked: root.showSettingsDialog()
                }

                Button {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 52
                    text: qsTr("Logout")
                    enabled: !Chiaki.rental.adminBusy
                    Material.roundedScale: Material.SmallScale
                    onClicked: Chiaki.rental.controllerAdminLogout()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TextField {
                    id: newAdminPin
                    Layout.preferredWidth: 180
                    placeholderText: qsTr("New PIN")
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: !Chiaki.rental.adminBusy
                }

                Button {
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 50
                    enabled: !Chiaki.rental.adminBusy && newAdminPin.text.length >= 4
                    text: Chiaki.rental.adminBusy ? qsTr("Updating...") : qsTr("Update PIN")
                    Material.roundedScale: Material.SmallScale
                    onClicked: {
                        if (!enabled)
                            return;
                        Chiaki.rental.updateControllerPin(newAdminPin.text);
                        newAdminPin.text = "";
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 50
                    enabled: !Chiaki.rental.adminBusy
                    text: Chiaki.rental.adminBusy ? qsTr("Refreshing...") : qsTr("Refresh")
                    Material.roundedScale: Material.SmallScale
                    onClicked: controllerAdmin.refreshAllAdminData()
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#ef9a9a"
                visible: Chiaki.rental.adminError.length > 0
                text: Chiaki.rental.adminError
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: controllerAdmin.section

                ColumnLayout {
                    spacing: 18

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Assign this system to a store")
                        font.bold: true
                        font.pixelSize: 28
                    }

                    Label {
                        Layout.fillWidth: true
                        text: Chiaki.rental.selectedStoreName.length > 0
                            ? qsTr("Current store: %1").arg(Chiaki.rental.selectedStoreName)
                            : qsTr("Current store: not assigned")
                        opacity: 0.78
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ComboBox {
                            id: systemStoreSelector
                            Layout.preferredWidth: 360
                            model: Chiaki.rental.managedStores
                            textRole: "name"
                            valueRole: "id"
                            enabled: !Chiaki.rental.adminBusy && Chiaki.rental.managedStores.length > 0
                            Component.onCompleted: controllerAdmin.syncSystemStoreSelector()
                        }

                        Button {
                            Layout.preferredWidth: 180
                            Layout.preferredHeight: 54
                            enabled: !Chiaki.rental.adminBusy && systemStoreSelector.currentValue
                            text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Assign Store")
                            Material.background: Material.accent
                            Material.roundedScale: Material.SmallScale
                            onClicked: {
                                if (!enabled)
                                    return;
                                Chiaki.rental.assignSystemStore(systemStoreSelector.currentValue);
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: Chiaki.rental.managedStores.length === 0
                        text: qsTr("Add a store before assigning this system.")
                        opacity: 0.75
                    }

                    Item { Layout.fillHeight: true }
                }

                ListView {
                    id: addList
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    spacing: 12
                    model: Chiaki.rental.discoveredAdminConsoles
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                    delegate: Rectangle {
                        width: addList.width
                        height: 260
                        radius: 6
                        color: "#24262c"

                        GridLayout {
                            anchors {
                                fill: parent
                                margins: 16
                            }
                            columns: 3
                            columnSpacing: 12
                            rowSpacing: 10

                            Label {
                                Layout.columnSpan: 3
                                Layout.fillWidth: true
                                text: qsTr("%1  ID: %2  IP: %3")
                                    .arg(modelData.detected_name || qsTr("Detected Console"))
                                    .arg(modelData.console_identifier)
                                    .arg(modelData.tailscale_ip || modelData.ip_address)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            TextField { id: addName; Layout.fillWidth: true; placeholderText: qsTr("Console name"); text: modelData.detected_name || "" }
                            TextField { id: addPin; Layout.fillWidth: true; placeholderText: qsTr("Console PIN"); echoMode: TextInput.Password }
                            TextField { id: addTailscale; Layout.fillWidth: true; placeholderText: qsTr("IP / Tailscale IP"); text: modelData.tailscale_ip || modelData.ip_address || "" }

                            Button {
                                Layout.columnSpan: 3
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy && addName.text.length > 0 && addTailscale.text.length > 0
                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save Console")
                                Material.background: Material.accent
                                Material.roundedScale: Material.SmallScale
                                onClicked: {
                                    if (!enabled)
                                        return;
                                    Chiaki.rental.addConsole({
                                        console_identifier: modelData.console_identifier,
                                        detected_name: modelData.detected_name,
                                        name: addName.text,
                                        tailscale_ip: addTailscale.text,
                                        registered_host_nickname: modelData.registered_host_nickname || modelData.detected_name || addName.text,
                                        remote_play_target: modelData.remote_play_target || "PS5",
                                        console_pin: addPin.text
                                    });
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: manageConsoleList
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    spacing: 12
                    model: Chiaki.rental.managedConsoles
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                    delegate: Rectangle {
                        width: manageConsoleList.width
                        height: 300
                        radius: 6
                        color: "#24262c"

                        GridLayout {
                            anchors {
                                fill: parent
                                margins: 16
                            }
                            columns: 3
                            columnSpacing: 12
                            rowSpacing: 10

                            Label {
                                Layout.columnSpan: 3
                                Layout.fillWidth: true
                                text: qsTr("%1  ID: %2  Session: %3")
                                    .arg(modelData.name)
                                    .arg(modelData.mac_address || modelData.id)
                                    .arg(modelData.current_session ? modelData.current_session.status : qsTr("none"))
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            TextField { id: editName; Layout.fillWidth: true; placeholderText: qsTr("Console name"); text: modelData.name || "" }
                            TextField { id: editPin; Layout.fillWidth: true; placeholderText: qsTr("Console PIN"); text: modelData.console_pin || ""; echoMode: TextInput.Password }
                            ComboBox { id: editStatus; Layout.fillWidth: true; model: controllerAdmin.statusOptions; currentIndex: controllerAdmin.statusIndex(modelData.state) }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy && editName.text.length > 0
                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                Material.background: Material.accent
                                Material.roundedScale: Material.SmallScale
                                onClicked: {
                                    if (!enabled)
                                        return;
                                    Chiaki.rental.updateConsole({
                                        id: modelData.id,
                                        name: editName.text,
                                        console_pin: editPin.text,
                                        state: editStatus.currentText
                                    });
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy
                                text: Chiaki.rental.adminBusy ? qsTr("Removing...") : qsTr("Remove")
                                Material.roundedScale: Material.SmallScale
                                onClicked: {
                                    if (!enabled)
                                        return;
                                    root.showConfirmDialog(qsTr("Remove Console"), qsTr("Remove this console?"), () => Chiaki.rental.removeConsole(modelData.id));
                                }
                            }
                        }
                    }
                }

                ScrollView {
                    id: addStoreScroll
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOn

                    GridLayout {
                        width: addStoreScroll.availableWidth
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 14

                        TextField { id: addStoreName; Layout.fillWidth: true; placeholderText: qsTr("Store Name") }
                        TextField { id: addStorePhone; Layout.fillWidth: true; placeholderText: qsTr("Store Phone Number") }
                        TextField { id: addStoreLocation; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Store Location") }
                        TextField { id: addStoreEmail; Layout.fillWidth: true; placeholderText: qsTr("Store Email") }
                        TextField { id: addStoreNotes; Layout.fillWidth: true; placeholderText: qsTr("Notes") }

                        Button {
                            Layout.columnSpan: 2
                            Layout.preferredHeight: 56
                            Layout.fillWidth: true
                            enabled: !Chiaki.rental.adminBusy && addStoreName.text.length > 0
                            text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save Store")
                            Material.background: Material.accent
                            Material.roundedScale: Material.SmallScale
                            onClicked: {
                                if (!enabled)
                                    return;
                                Chiaki.rental.saveStore({
                                    name: addStoreName.text,
                                    location: addStoreLocation.text,
                                    phone: addStorePhone.text,
                                    email: addStoreEmail.text,
                                    notes: addStoreNotes.text,
                                    active: true
                                });
                                addStoreName.text = "";
                                addStoreLocation.text = "";
                                addStorePhone.text = "";
                                addStoreEmail.text = "";
                                addStoreNotes.text = "";
                            }
                        }
                    }
                }

                ListView {
                    id: manageStoreList
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    spacing: 12
                    model: Chiaki.rental.managedStores
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                    delegate: Rectangle {
                        width: manageStoreList.width
                        height: 330
                        radius: 6
                        color: "#24262c"

                        GridLayout {
                            anchors { fill: parent; margins: 16 }
                            columns: 3
                            columnSpacing: 12
                            rowSpacing: 10

                            Label {
                                Layout.columnSpan: 3
                                Layout.fillWidth: true
                                text: qsTr("%1  Pricing: %2").arg(modelData.name).arg(modelData.pricing_count || 0)
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            TextField { id: storeName; Layout.fillWidth: true; placeholderText: qsTr("Store Name"); text: modelData.name || "" }
                            TextField { id: storePhone; Layout.fillWidth: true; placeholderText: qsTr("Phone"); text: modelData.phone || "" }
                            CheckBox { id: storeActive; text: qsTr("Enabled"); checked: modelData.active }
                            TextField { id: storeLocation; Layout.columnSpan: 3; Layout.fillWidth: true; placeholderText: qsTr("Location"); text: modelData.location || "" }
                            TextField { id: storeEmail; Layout.fillWidth: true; placeholderText: qsTr("Email"); text: modelData.email || "" }
                            TextField { id: storeNotes; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Notes"); text: modelData.notes || "" }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy && storeName.text.length > 0
                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                Material.background: Material.accent
                                Material.roundedScale: Material.SmallScale
                                onClicked: Chiaki.rental.saveStore({
                                    id: modelData.id,
                                    name: storeName.text,
                                    location: storeLocation.text,
                                    phone: storePhone.text,
                                    email: storeEmail.text,
                                    notes: storeNotes.text,
                                    active: storeActive.checked
                                })
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy
                                text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                Material.roundedScale: Material.SmallScale
                                onClicked: root.showConfirmDialog(qsTr("Delete Store"), qsTr("Delete this store?"), () => Chiaki.rental.removeStore(modelData.id))
                            }
                        }
                    }
                }

                ScrollView {
                    id: addPlanScroll
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOn

                    GridLayout {
                        width: addPlanScroll.availableWidth
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 14

                        TextField { id: addPlanName; Layout.fillWidth: true; placeholderText: qsTr("Plan Name") }
                        TextField { id: addPlanMinutes; Layout.fillWidth: true; placeholderText: qsTr("Duration Minutes"); inputMethodHints: Qt.ImhDigitsOnly }
                        TextField { id: addPlanSort; Layout.fillWidth: true; placeholderText: qsTr("Sort Order"); inputMethodHints: Qt.ImhDigitsOnly }

                        Button {
                            Layout.columnSpan: 2
                            Layout.preferredHeight: 56
                            Layout.fillWidth: true
                            enabled: !Chiaki.rental.adminBusy && addPlanName.text.length > 0 && Number(addPlanMinutes.text) > 0
                            text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save Time Plan")
                            Material.background: Material.accent
                            Material.roundedScale: Material.SmallScale
                            onClicked: {
                                if (!enabled)
                                    return;
                                Chiaki.rental.saveTimePlan({
                                    name: addPlanName.text,
                                    duration_minutes: Number(addPlanMinutes.text),
                                    sort_order: Number(addPlanSort.text || 0),
                                    active: true
                                });
                                addPlanName.text = "";
                                addPlanMinutes.text = "";
                                addPlanSort.text = "";
                            }
                        }
                    }
                }

                ListView {
                    id: managePlanList
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    spacing: 12
                    model: Chiaki.rental.managedTimePlans
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                    delegate: Rectangle {
                        width: managePlanList.width
                        height: 250
                        radius: 6
                        color: "#24262c"

                        GridLayout {
                            anchors { fill: parent; margins: 16 }
                            columns: 4
                            columnSpacing: 12
                            rowSpacing: 10

                            TextField { id: planName; Layout.fillWidth: true; placeholderText: qsTr("Plan Name"); text: modelData.name || "" }
                            TextField { id: planMinutes; Layout.fillWidth: true; placeholderText: qsTr("Minutes"); text: modelData.duration_minutes || ""; inputMethodHints: Qt.ImhDigitsOnly }
                            TextField { id: planSort; Layout.fillWidth: true; placeholderText: qsTr("Sort"); text: modelData.sort_order || ""; inputMethodHints: Qt.ImhDigitsOnly }
                            CheckBox { id: planActive; text: qsTr("Enabled"); checked: modelData.active }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy && planName.text.length > 0 && Number(planMinutes.text) > 0
                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                Material.background: Material.accent
                                Material.roundedScale: Material.SmallScale
                                onClicked: Chiaki.rental.saveTimePlan({
                                    id: modelData.id,
                                    name: planName.text,
                                    duration_minutes: Number(planMinutes.text),
                                    sort_order: Number(planSort.text || 0),
                                    active: planActive.checked
                                })
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                enabled: !Chiaki.rental.adminBusy
                                text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                Material.roundedScale: Material.SmallScale
                                onClicked: root.showConfirmDialog(qsTr("Delete Time Plan"), qsTr("Delete this time plan?"), () => Chiaki.rental.removeTimePlan(modelData.id))
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 14

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 12
                        rowSpacing: 10

                        ComboBox { id: priceStore; Layout.fillWidth: true; model: Chiaki.rental.managedStores; textRole: "name"; valueRole: "id" }
                        ComboBox { id: pricePlan; Layout.fillWidth: true; model: Chiaki.rental.managedTimePlans; textRole: "name"; valueRole: "id" }
                        TextField { id: priceAmount; Layout.fillWidth: true; placeholderText: qsTr("Price ₹"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        CheckBox { id: priceActive; text: qsTr("Enabled"); checked: true }

                        Button {
                            Layout.columnSpan: 4
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            enabled: !Chiaki.rental.adminBusy && priceStore.currentValue && pricePlan.currentValue && Number(priceAmount.text) > 0
                            text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save Price")
                            Material.background: Material.accent
                            Material.roundedScale: Material.SmallScale
                            onClicked: {
                                if (!enabled)
                                    return;
                                Chiaki.rental.savePricingRule({
                                    store_id: priceStore.currentValue,
                                    time_plan_id: pricePlan.currentValue,
                                    amount_paise: controllerAdmin.rupeesToPaise(priceAmount.text),
                                    currency: "INR",
                                    active: priceActive.checked
                                });
                                priceAmount.text = "";
                            }
                        }
                    }

                    ListView {
                        id: pricingList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        spacing: 12
                        model: Chiaki.rental.managedPricing
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }

                        delegate: Rectangle {
                            width: pricingList.width
                            height: 230
                            radius: 6
                            color: "#24262c"

                            GridLayout {
                                anchors { fill: parent; margins: 16 }
                                columns: 5
                                columnSpacing: 12
                                rowSpacing: 10

                                Label {
                                    Layout.columnSpan: 5
                                    Layout.fillWidth: true
                                    text: qsTr("%1 / %2").arg(modelData.store_name || modelData.store_id).arg(modelData.time_plan_name || modelData.time_plan_id)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                TextField { id: editPriceAmount; Layout.fillWidth: true; placeholderText: qsTr("Price ₹"); text: (Number(modelData.amount_paise || 0) / 100).toFixed(2); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                                CheckBox { id: editPriceActive; text: qsTr("Enabled"); checked: modelData.active }
                                Label { Layout.fillWidth: true; text: controllerAdmin.moneyText(modelData.amount_paise, modelData.currency); opacity: 0.75 }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    enabled: !Chiaki.rental.adminBusy && Number(editPriceAmount.text) > 0
                                    text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                    Material.background: Material.accent
                                    Material.roundedScale: Material.SmallScale
                                    onClicked: Chiaki.rental.savePricingRule({
                                        id: modelData.id,
                                        store_id: modelData.store_id,
                                        time_plan_id: modelData.time_plan_id,
                                        amount_paise: controllerAdmin.rupeesToPaise(editPriceAmount.text),
                                        currency: modelData.currency || "INR",
                                        active: editPriceActive.checked
                                    })
                                }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    enabled: !Chiaki.rental.adminBusy
                                    text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                    Material.roundedScale: Material.SmallScale
                                    onClicked: root.showConfirmDialog(qsTr("Delete Price"), qsTr("Delete this price?"), () => Chiaki.rental.removePricingRule(modelData.id))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: Chiaki.rental

        function onControllerPinVerified() {
            pinField.text = "";
            controllerAdmin.refreshAllAdminData();
        }

        function onManagedStoresChanged() {
            controllerAdmin.syncSystemStoreSelector();
        }

        function onSelectedStoreIdChanged() {
            controllerAdmin.syncSystemStoreSelector();
        }

        function onControllerConsoleSaved() {
            controllerAdmin.refreshAddList();
        }

        function onControllerConsoleRemoved() {
            controllerAdmin.refreshAddList();
        }

        function onControllerAdminDataSaved() {
            Chiaki.rental.loadPricing();
        }

        function onControllerAdminDataRemoved() {
            Chiaki.rental.loadPricing();
        }
    }
}
