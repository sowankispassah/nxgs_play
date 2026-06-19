import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import com.nxgsstudio.nxgsgaming

Pane {
    id: admin
    padding: 0

    property int section: 0
    property bool sidebarCollapsed: width < 1080
    property string searchText: ""
    property bool showStoreForm: false
    property bool showPlanForm: false
    property bool showPricingForm: false
    property bool showDiscoverPanel: false
    property string selectedPricingStoreId: ""
    readonly property var statusOptions: ["available", "offline", "maintenance", "disabled"]
    readonly property var manualStateOptions: [
        { label: qsTr("Available"), value: "available" },
        { label: qsTr("Reserved"), value: "reserved" },
        { label: qsTr("In Session / Occupied"), value: "occupied" },
        { label: qsTr("Maintenance"), value: "maintenance" },
        { label: qsTr("Disabled"), value: "disabled" }
    ]
    readonly property var manualDurationOptions: [
        { label: qsTr("30 minutes"), value: 30 },
        { label: qsTr("1 hour"), value: 60 },
        { label: qsTr("2 hours"), value: 120 },
        { label: qsTr("3 hours"), value: 180 },
        { label: qsTr("Custom duration"), value: -1 },
        { label: qsTr("Until manually released"), value: 0 }
    ]
    readonly property var navItems: [
        { label: qsTr("Dashboard"), symbol: "DB" },
        { label: qsTr("Consoles"), symbol: "CS" },
        { label: qsTr("Stores"), symbol: "ST" },
        { label: qsTr("Time Plans"), symbol: "TP" },
        { label: qsTr("Pricing"), symbol: "PR" },
        { label: qsTr("Sessions"), symbol: "SE" },
        { label: qsTr("Reservations"), symbol: "RS" },
        { label: qsTr("Payments"), symbol: "PY" },
        { label: qsTr("Controller"), symbol: "CT" },
        { label: qsTr("Logs"), symbol: "LG" }
    ]

    component ManagementScrollView: ScrollView {
        clip: true
        contentWidth: availableWidth
        contentHeight: contentItem.childrenRect.height
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    }

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

    function navigate(index) {
        section = index;
        searchText = "";
        if (index !== 4) {
            selectedPricingStoreId = "";
            showPricingForm = false;
        }
        if (index === 1)
            Chiaki.rental.listManagedConsoles();
        else if (index === 2 || index === 8)
            Chiaki.rental.listStores();
        else if (index === 3)
            Chiaki.rental.listTimePlans();
        else if (index === 4)
            Chiaki.rental.listPricingRules();
    }

    function pageTitle() {
        return navItems[section].label;
    }

    function statusIndex(status) {
        for (let i = 0; i < statusOptions.length; ++i) {
            if (statusOptions[i] === status)
                return i;
        }
        return 0;
    }

    function manualStateIndex(status) {
        for (let i = 0; i < manualStateOptions.length; ++i) {
            if (manualStateOptions[i].value === status)
                return i;
        }
        return 0;
    }

    function durationIndex(minutes) {
        for (let i = 0; i < manualDurationOptions.length; ++i) {
            if (manualDurationOptions[i].value === minutes)
                return i;
        }
        return minutes > 0 ? 4 : 5;
    }

    function openConsoleAvailability(consoleData) {
        consoleAvailabilityDialog.consoleData = consoleData;
        const manualLock = consoleData.manual_lock || {};
        const effectiveState = consoleData.effective_state || consoleData.state || "available";
        consoleStateSelector.currentIndex = manualStateIndex(effectiveState);
        consoleLockNote.text = manualLock.note || "";

        if (manualLock.expires_at) {
            const remainingMinutes = Math.max(1, Math.ceil((Date.parse(manualLock.expires_at) - Date.now()) / 60000));
            consoleDurationSelector.currentIndex = durationIndex(remainingMinutes);
            consoleCustomDuration.text = String(remainingMinutes);
        } else {
            consoleDurationSelector.currentIndex = manualLock.id ? 5 : 0;
            consoleCustomDuration.text = "";
        }
        consoleAvailabilityDialog.open();
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
            systemStoreSelector.currentIndex = admin.storeIndex(Chiaki.rental.selectedStoreId);
    }

    function moneyText(amountPaise, currency) {
        return "%1 %2".arg(currency || "INR").arg((Number(amountPaise || 0) / 100).toFixed(2));
    }

    function rupeesToPaise(value) {
        return Math.round(Number(value || 0) * 100);
    }

    function countConsoleState(state) {
        let count = 0;
        for (let i = 0; i < Chiaki.rental.managedConsoles.length; ++i) {
            if ((Chiaki.rental.managedConsoles[i].state || "") === state)
                ++count;
        }
        return count;
    }

    function consolesInSession() {
        let count = 0;
        for (let i = 0; i < Chiaki.rental.managedConsoles.length; ++i) {
            const session = Chiaki.rental.managedConsoles[i].current_session;
            if (session && session.status && session.status !== "completed" && session.status !== "disconnected")
                ++count;
        }
        return count;
    }

    function metricModel() {
        return [
            { label: qsTr("Available Consoles"), value: String(countConsoleState("available")), detail: qsTr("Ready for assignment"), symbol: "AV", color: "#22c55e" },
            { label: qsTr("Active Consoles"), value: String(consolesInSession()), detail: qsTr("Currently in session"), symbol: "ON", color: "#00a7ff" },
            { label: qsTr("Offline Consoles"), value: String(countConsoleState("offline")), detail: qsTr("Require attention"), symbol: "OF", color: "#f97316" },
            { label: qsTr("Stores"), value: String(Chiaki.rental.managedStores.length), detail: qsTr("Configured locations"), symbol: "ST", color: "#a855f7" },
            { label: qsTr("Current Sessions"), value: Chiaki.rental.activeSessionId.length > 0 ? "1" : "0", detail: qsTr("On this controller"), symbol: "SE", color: "#14b8a6" },
            { label: qsTr("Reservations"), value: Chiaki.rental.reservationId.length > 0 ? "1" : "0", detail: qsTr("Active on this controller"), symbol: "RS", color: "#eab308" },
            { label: qsTr("Time Plans"), value: String(Chiaki.rental.managedTimePlans.length), detail: qsTr("Configured durations"), symbol: "TP", color: "#ec4899" },
            { label: qsTr("Pricing Rules"), value: String(Chiaki.rental.managedPricing.length), detail: qsTr("Store and plan combinations"), symbol: "PR", color: "#6366f1" }
        ];
    }

    function normalized(value) {
        return String(value || "").toLowerCase();
    }

    function matchesConsole(item) {
        const query = normalized(searchText);
        return query.length === 0
            || normalized(item.name).indexOf(query) >= 0
            || normalized(item.mac_address || item.id).indexOf(query) >= 0
            || normalized(item.state).indexOf(query) >= 0;
    }

    function matchesStore(item) {
        const query = normalized(searchText);
        return query.length === 0
            || normalized(item.name).indexOf(query) >= 0
            || normalized(item.location).indexOf(query) >= 0
            || normalized(item.phone).indexOf(query) >= 0;
    }

    function matchesPlan(item) {
        const query = normalized(searchText);
        return query.length === 0
            || normalized(item.name).indexOf(query) >= 0
            || normalized(item.duration_minutes).indexOf(query) >= 0;
    }

    function matchesPrice(item) {
        const query = normalized(searchText);
        return query.length === 0
            || normalized(item.store_name || item.store_id).indexOf(query) >= 0
            || normalized(item.time_plan_name || item.time_plan_id).indexOf(query) >= 0;
    }

    function sortedPricing() {
        const rows = Array.from(Chiaki.rental.managedPricing);
        rows.sort((left, right) => {
            const amountDifference = Number(left.amount_paise || 0) - Number(right.amount_paise || 0);
            if (amountDifference !== 0)
                return amountDifference;
            return String(left.store_name || left.store_id || "").localeCompare(
                String(right.store_name || right.store_id || ""));
        });
        return rows;
    }

    function pricingCountForStore(storeId) {
        let count = 0;
        for (let i = 0; i < Chiaki.rental.managedPricing.length; ++i) {
            if (Chiaki.rental.managedPricing[i].store_id === storeId)
                ++count;
        }
        return count;
    }

    function selectedPricingStore() {
        for (let i = 0; i < Chiaki.rental.managedStores.length; ++i) {
            if (Chiaki.rental.managedStores[i].id === selectedPricingStoreId)
                return Chiaki.rental.managedStores[i];
        }
        return {};
    }

    function selectedStorePricing() {
        if (!selectedPricingStoreId)
            return [];
        return sortedPricing().filter((row) => row.store_id === selectedPricingStoreId);
    }

    function openStorePricing(storeId) {
        selectedPricingStoreId = storeId;
        showPricingForm = false;
        searchText = "";
    }

    function closeStorePricing() {
        selectedPricingStoreId = "";
        showPricingForm = false;
        searchText = "";
    }

    function sessionStatus(item) {
        if (!item.current_session)
            return "disconnected";
        return item.current_session.status || "active";
    }

    function lastSeenText(item) {
        return item.last_seen || item.last_seen_at || item.updated_at || qsTr("Not reported");
    }

    Rectangle {
        anchors.fill: parent
        color: "#0b1019"
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        spacing: 18
        visible: !Chiaki.rental.controllerAdminAuthenticated

        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 190
            Layout.preferredHeight: 86
            fillMode: Image.PreserveAspectFit
            source: "qrc:/icons/nxgs-gaming-logo-white.png"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Management Access")
            color: "#ffffff"
            font.bold: true
            font.pixelSize: 30
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Enter the access code to continue.")
            color: "#8f9bb3"
            wrapMode: Text.WordWrap
        }

        AdminCard {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: qsTr("Access Code")
                color: "#cbd5e1"
                font.bold: true
                font.pixelSize: 14
            }

            TextField {
                id: pinField
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                placeholderText: qsTr("Enter code")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                enabled: !Chiaki.rental.adminBusy
                onAccepted: loginButton.clicked()
            }

            Button {
                id: loginButton
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                enabled: Chiaki.rental.controllerAdminConfigured && !Chiaki.rental.adminBusy && pinField.text.length > 0
                text: Chiaki.rental.adminBusy ? qsTr("Checking...") : qsTr("Continue")
                Material.background: "#00a7ff"
                onClicked: {
                    if (enabled)
                        Chiaki.rental.verifyControllerPin(pinField.text);
                }
            }
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#fb7185"
            visible: Chiaki.rental.adminError.length > 0
            text: Chiaki.rental.adminError
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Back to Player")
            flat: true
            onClicked: root.goBack()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: Chiaki.rental.controllerAdminAuthenticated

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: admin.sidebarCollapsed ? 84 : 250
            color: "#0f1520"
            border.width: 1
            border.color: "#202a3a"

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58

                    Image {
                        Layout.preferredWidth: admin.sidebarCollapsed ? 48 : 150
                        Layout.preferredHeight: 44
                        fillMode: Image.PreserveAspectFit
                        source: admin.sidebarCollapsed
                            ? "qrc:/icons/nxgs-gaming-logo-white.png"
                            : "qrc:/icons/nxgs-gaming-logo-white.png"
                    }

                    Item { Layout.fillWidth: true }
                }

                Label {
                    Layout.leftMargin: 12
                    visible: !admin.sidebarCollapsed
                    text: qsTr("MANAGEMENT")
                    color: "#56657d"
                    font.bold: true
                    font.pixelSize: 11
                }

                Repeater {
                    model: admin.navItems

                    AdminNavButton {
                        text: modelData.label
                        symbol: modelData.symbol
                        collapsed: admin.sidebarCollapsed
                        selected: admin.section === index
                        onClicked: admin.navigate(index)
                    }
                }

                Item { Layout.fillHeight: true }

                AdminNavButton {
                    text: qsTr("Console Browser")
                    symbol: "CB"
                    collapsed: admin.sidebarCollapsed
                    onClicked: root.showHostList()
                }

                AdminNavButton {
                    text: qsTr("Settings")
                    symbol: "SG"
                    collapsed: admin.sidebarCollapsed
                    onClicked: root.showSettingsDialog()
                }

                AdminNavButton {
                    text: qsTr("Logout")
                    symbol: "LO"
                    collapsed: admin.sidebarCollapsed
                    onClicked: Chiaki.rental.controllerAdminLogout()
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                color: "#0d131e"
                border.width: 1
                border.color: "#202a3a"

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 24
                        rightMargin: 24
                    }
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: admin.pageTitle()
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 25
                        }

                        Label {
                            text: Chiaki.rental.selectedStoreName.length > 0
                                ? Chiaki.rental.selectedStoreName
                                : qsTr("NXGS Gaming management console")
                            color: "#718096"
                            font.pixelSize: 13
                        }
                    }

                    TextField {
                        Layout.preferredWidth: admin.width > 1250 ? 280 : 190
                        Layout.preferredHeight: 44
                        visible: admin.section >= 1 && admin.section <= 4
                        placeholderText: qsTr("Search...")
                        text: admin.searchText
                        onTextChanged: admin.searchText = text
                    }

                    Rectangle {
                        Layout.preferredWidth: 126
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Chiaki.rental.configured ? "#123426" : "#3a2025"

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: Chiaki.rental.configured ? "#22c55e" : "#fb7185"
                            }

                            Label {
                                text: Chiaki.rental.configured ? qsTr("Service Ready") : qsTr("Not Configured")
                                color: Chiaki.rental.configured ? "#86efac" : "#fda4af"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                    }

                    Button {
                        Layout.preferredWidth: 104
                        Layout.preferredHeight: 42
                        enabled: !Chiaki.rental.adminBusy
                        text: Chiaki.rental.adminBusy ? qsTr("Syncing...") : qsTr("Refresh")
                        onClicked: {
                            if (enabled)
                                admin.refreshAllAdminData();
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 12
                visible: Chiaki.rental.adminError.length > 0
                text: Chiaki.rental.adminError
                color: "#fb7185"
                wrapMode: Text.WordWrap
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: admin.section

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 20

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0
                            columns: width >= 1180 ? 4 : width >= 620 ? 2 : 1
                            columnSpacing: 16
                            rowSpacing: 16

                            Repeater {
                                model: admin.metricModel()

                                AdminMetricCard {
                                    Layout.fillWidth: true
                                    label: modelData.label
                                    value: modelData.value
                                    detail: modelData.detail
                                    symbol: modelData.symbol
                                    accentColor: modelData.color
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            spacing: 16

                            AdminCard {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 250
                                title: qsTr("Console Fleet")
                                subtitle: qsTr("Live state of the managed NXGS consoles.")

                                RowLayout {
                                    Layout.fillWidth: true

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Label { text: qsTr("Total Consoles"); color: "#8f9bb3"; font.pixelSize: 13 }
                                        Label { text: String(Chiaki.rental.managedConsoles.length); color: "#ffffff"; font.bold: true; font.pixelSize: 28 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Label { text: qsTr("In Session"); color: "#8f9bb3"; font.pixelSize: 13 }
                                        Label { text: String(admin.consolesInSession()); color: "#00a7ff"; font.bold: true; font.pixelSize: 28 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Label { text: qsTr("Maintenance"); color: "#8f9bb3"; font.pixelSize: 13 }
                                        Label { text: String(admin.countConsoleState("maintenance")); color: "#f59e0b"; font.bold: true; font.pixelSize: 28 }
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    text: qsTr("Manage Consoles")
                                    Material.background: "#00a7ff"
                                    onClicked: admin.navigate(1)
                                }
                            }

                            AdminCard {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 250
                                title: qsTr("Controller Status")
                                subtitle: qsTr("Current player-side reservation and session state.")

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("State: %1").arg(Chiaki.rental.state)
                                    color: "#d7dfec"
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: Chiaki.rental.activeSessionId.length > 0
                                        ? qsTr("Session active · %1 remaining").arg(Math.ceil(Chiaki.rental.remainingSeconds / 60) + " min")
                                        : qsTr("No active session on this controller")
                                    color: "#8f9bb3"
                                }

                                Item { Layout.fillHeight: true }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    text: qsTr("View Sessions")
                                    onClicked: admin.navigate(5)
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 managed consoles").arg(Chiaki.rental.managedConsoles.length)
                                color: "#8f9bb3"
                            }

                            Button {
                                text: admin.showDiscoverPanel ? qsTr("Hide Discovered") : qsTr("Add Console")
                                enabled: !Chiaki.rental.adminBusy
                                onClicked: {
                                    admin.showDiscoverPanel = !admin.showDiscoverPanel;
                                    if (admin.showDiscoverPanel)
                                        admin.refreshAddList();
                                }
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.showDiscoverPanel
                            title: qsTr("Discovered Consoles")
                            subtitle: qsTr("Add a locally discovered and registered PlayStation to NXGS management.")

                            Repeater {
                                model: Chiaki.rental.discoveredAdminConsoles

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 220
                                    color: "#101722"
                                    radius: 12
                                    border.width: 1
                                    border.color: "#263247"

                                    GridLayout {
                                        anchors { fill: parent; margins: 16 }
                                        columns: width > 760 ? 3 : 1
                                        columnSpacing: 12
                                        rowSpacing: 10

                                        Label {
                                            Layout.columnSpan: parent.columns
                                            Layout.fillWidth: true
                                            text: modelData.detected_name || qsTr("Detected Console")
                                            color: "#ffffff"
                                            font.bold: true
                                            font.pixelSize: 18
                                        }

                                        TextField { id: addName; Layout.fillWidth: true; placeholderText: qsTr("Console name"); text: modelData.detected_name || "" }
                                        TextField { id: addPin; Layout.fillWidth: true; placeholderText: qsTr("Console PIN"); echoMode: TextInput.Password }
                                        TextField { id: addTailscale; Layout.fillWidth: true; placeholderText: qsTr("IP / Tailscale IP"); text: modelData.tailscale_ip || modelData.ip_address || "" }

                                        Button {
                                            Layout.columnSpan: parent.columns
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 48
                                            enabled: !Chiaki.rental.adminBusy && addName.text.length > 0 && addTailscale.text.length > 0
                                            text: Chiaki.rental.adminBusy ? qsTr("Saving Console...") : qsTr("Save Console")
                                            Material.background: "#00a7ff"
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

                            Label {
                                Layout.fillWidth: true
                                visible: Chiaki.rental.discoveredAdminConsoles.length === 0
                                text: qsTr("No eligible discovered consoles are available.")
                                color: "#8f9bb3"
                            }
                        }

                        AdminCard {
                            id: consoleTable
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            title: qsTr("Console Fleet")
                            subtitle: qsTr("Select Edit to change a console. Rows remain read-only by default.")
                            readonly property real availableColumnWidth: Math.max(760, width - 40 - 84)
                            readonly property real actionsColumnWidth: Math.max(348, availableColumnWidth * 0.24)
                            readonly property real dataColumnWidth: availableColumnWidth - actionsColumnWidth
                            readonly property real nameColumnWidth: dataColumnWidth * 0.24
                            readonly property real idColumnWidth: dataColumnWidth * 0.18
                            readonly property real pinColumnWidth: dataColumnWidth * 0.08
                            readonly property real statusColumnWidth: dataColumnWidth * 0.12
                            readonly property real sessionColumnWidth: dataColumnWidth * 0.14
                            readonly property real lastSeenColumnWidth: dataColumnWidth * 0.24

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14

                                Label { Layout.preferredWidth: consoleTable.nameColumnWidth; Layout.minimumWidth: consoleTable.nameColumnWidth; Layout.maximumWidth: consoleTable.nameColumnWidth; text: qsTr("CONSOLE NAME"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.idColumnWidth; Layout.minimumWidth: consoleTable.idColumnWidth; Layout.maximumWidth: consoleTable.idColumnWidth; text: qsTr("CONSOLE ID"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.pinColumnWidth; Layout.minimumWidth: consoleTable.pinColumnWidth; Layout.maximumWidth: consoleTable.pinColumnWidth; text: qsTr("PIN"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.statusColumnWidth; Layout.minimumWidth: consoleTable.statusColumnWidth; Layout.maximumWidth: consoleTable.statusColumnWidth; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.sessionColumnWidth; Layout.minimumWidth: consoleTable.sessionColumnWidth; Layout.maximumWidth: consoleTable.sessionColumnWidth; text: qsTr("SESSION"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.lastSeenColumnWidth; Layout.minimumWidth: consoleTable.lastSeenColumnWidth; Layout.maximumWidth: consoleTable.lastSeenColumnWidth; text: qsTr("LAST SEEN"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: consoleTable.actionsColumnWidth; Layout.minimumWidth: consoleTable.actionsColumnWidth; Layout.maximumWidth: consoleTable.actionsColumnWidth; text: qsTr("ACTIONS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: "#273247"
                            }

                            Repeater {
                                model: Chiaki.rental.managedConsoles

                                Rectangle {
                                    id: consoleRow
                                    property bool editing: false
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? (editing ? 94 : 64) : 0
                                    visible: admin.matchesConsole(modelData)
                                    radius: 10
                                    color: editing ? "#111e2c" : (rowMouse.containsMouse ? "#121b29" : "#101722")
                                    border.width: editing ? 1 : 0
                                    border.color: "#245c85"

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }

                                    RowLayout {
                                        anchors { fill: parent; margins: 12 }
                                        spacing: 14

                                        Item {
                                            Layout.preferredWidth: consoleTable.nameColumnWidth
                                            Layout.minimumWidth: consoleTable.nameColumnWidth
                                            Layout.maximumWidth: consoleTable.nameColumnWidth
                                            Layout.fillHeight: true

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                visible: !consoleRow.editing
                                                text: modelData.name || qsTr("Console")
                                                color: "#f8fafc"
                                                font.bold: true
                                                font.pixelSize: 14
                                                elide: Text.ElideRight
                                            }

                                            TextField {
                                                id: editName
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: 38
                                                visible: consoleRow.editing
                                                placeholderText: qsTr("Console name")
                                                text: modelData.name || ""
                                                font.pixelSize: 13
                                            }
                                        }

                                        Label {
                                            Layout.preferredWidth: consoleTable.idColumnWidth
                                            Layout.minimumWidth: consoleTable.idColumnWidth
                                            Layout.maximumWidth: consoleTable.idColumnWidth
                                            text: modelData.mac_address || modelData.id
                                            color: "#94a3b8"
                                            font.pixelSize: 12
                                            elide: Text.ElideMiddle
                                        }

                                        Item {
                                            Layout.preferredWidth: consoleTable.pinColumnWidth
                                            Layout.minimumWidth: consoleTable.pinColumnWidth
                                            Layout.maximumWidth: consoleTable.pinColumnWidth
                                            Layout.fillHeight: true

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: !consoleRow.editing
                                                text: modelData.console_pin ? "••••" : "—"
                                                color: "#94a3b8"
                                            }

                                            TextField {
                                                id: editPin
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: 38
                                                visible: consoleRow.editing
                                                placeholderText: qsTr("PIN")
                                                text: modelData.console_pin || ""
                                                echoMode: TextInput.Password
                                                font.pixelSize: 13
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: consoleTable.statusColumnWidth
                                            Layout.minimumWidth: consoleTable.statusColumnWidth
                                            Layout.maximumWidth: consoleTable.statusColumnWidth
                                            Layout.fillHeight: true

                                            AdminStatusBadge {
                                                anchors.verticalCenter: parent.verticalCenter
                                                status: modelData.effective_state || modelData.state || "offline"
                                            }

                                        }

                                        Item {
                                            Layout.preferredWidth: consoleTable.sessionColumnWidth
                                            Layout.minimumWidth: consoleTable.sessionColumnWidth
                                            Layout.maximumWidth: consoleTable.sessionColumnWidth
                                            Layout.fillHeight: true

                                            AdminStatusBadge {
                                                anchors.verticalCenter: parent.verticalCenter
                                                status: admin.sessionStatus(modelData)
                                            }
                                        }

                                        Label {
                                            Layout.preferredWidth: consoleTable.lastSeenColumnWidth
                                            Layout.minimumWidth: consoleTable.lastSeenColumnWidth
                                            Layout.maximumWidth: consoleTable.lastSeenColumnWidth
                                            text: admin.lastSeenText(modelData)
                                            color: "#94a3b8"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.preferredWidth: consoleTable.actionsColumnWidth
                                            Layout.minimumWidth: consoleTable.actionsColumnWidth
                                            Layout.maximumWidth: consoleTable.actionsColumnWidth
                                            spacing: 6

                                            Button {
                                                Layout.preferredWidth: (consoleTable.actionsColumnWidth - 12) / 3
                                                Layout.minimumWidth: 108
                                                Layout.preferredHeight: 34
                                                visible: !consoleRow.editing
                                                text: qsTr("Edit")
                                                font.pixelSize: 12
                                                onClicked: consoleRow.editing = true
                                            }

                                            Button {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 108
                                                Layout.preferredHeight: 34
                                                visible: consoleRow.editing
                                                enabled: !Chiaki.rental.adminBusy && editName.text.length > 0
                                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                                font.pixelSize: 12
                                                Material.background: "#00a7ff"
                                                onClicked: {
                                                    if (!enabled)
                                                        return;
                                                    Chiaki.rental.updateConsole({ id: modelData.id, name: editName.text, console_pin: editPin.text, state: modelData.state });
                                                }
                                            }

                                            Button {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 108
                                                Layout.preferredHeight: 34
                                                visible: consoleRow.editing
                                                text: qsTr("Cancel")
                                                font.pixelSize: 12
                                                onClicked: {
                                                    editName.text = modelData.name || "";
                                                    editPin.text = modelData.console_pin || "";
                                                    consoleRow.editing = false;
                                                }
                                            }

                                            Button {
                                                Layout.preferredWidth: (consoleTable.actionsColumnWidth - 12) / 3
                                                Layout.minimumWidth: 108
                                                Layout.preferredHeight: 34
                                                visible: !consoleRow.editing
                                                enabled: !Chiaki.rental.adminBusy
                                                text: qsTr("State")
                                                font.pixelSize: 12
                                                onClicked: admin.openConsoleAvailability(modelData)
                                            }

                                            Button {
                                                Layout.preferredWidth: (consoleTable.actionsColumnWidth - 12) / 3
                                                Layout.minimumWidth: 108
                                                Layout.preferredHeight: 34
                                                visible: !consoleRow.editing
                                                enabled: !Chiaki.rental.adminBusy
                                                text: Chiaki.rental.adminBusy ? qsTr("Removing...") : qsTr("Remove")
                                                font.pixelSize: 12
                                                onClicked: {
                                                    if (enabled)
                                                        root.showConfirmDialog(qsTr("Remove Console"), qsTr("Remove this console?"), () => Chiaki.rental.removeConsole(modelData.id));
                                                }
                                            }
                                        }
                                    }

                                    Connections {
                                        target: Chiaki.rental
                                        function onControllerConsoleSaved() {
                                            consoleRow.editing = false;
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: Chiaki.rental.managedConsoles.length === 0
                                text: qsTr("No managed consoles found.")
                                color: "#8f9bb3"
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 stores").arg(Chiaki.rental.managedStores.length)
                                color: "#8f9bb3"
                            }

                            Button {
                                text: admin.showStoreForm ? qsTr("Cancel") : qsTr("Add Store")
                                onClicked: admin.showStoreForm = !admin.showStoreForm
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.showStoreForm
                            title: qsTr("New Store")
                            subtitle: qsTr("Create a store location without changing pricing or assignment behavior.")

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 2 : 1
                                columnSpacing: 12
                                rowSpacing: 10

                                TextField { id: addStoreName; Layout.fillWidth: true; placeholderText: qsTr("Store Name") }
                                TextField { id: addStorePhone; Layout.fillWidth: true; placeholderText: qsTr("Store Phone Number") }
                                TextField { id: addStoreLocation; Layout.fillWidth: true; placeholderText: qsTr("Store Location") }
                                TextField { id: addStoreEmail; Layout.fillWidth: true; placeholderText: qsTr("Store Email") }
                                TextField { id: addStoreNotes; Layout.fillWidth: true; placeholderText: qsTr("Notes") }

                                Button {
                                    Layout.fillWidth: true
                                    enabled: !Chiaki.rental.adminBusy && addStoreName.text.length > 0
                                    text: Chiaki.rental.adminBusy ? qsTr("Saving Store...") : qsTr("Save Store")
                                    Material.background: "#00a7ff"
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

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            title: qsTr("Store Directory")
                            subtitle: qsTr("Store details remain compact until a row enters edit mode.")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; Layout.minimumWidth: 150; text: qsTr("STORE"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 210; text: qsTr("LOCATION"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 140; text: qsTr("PHONE"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 100; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 90; text: qsTr("PRICING"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 176; text: qsTr("ACTIONS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Repeater {
                                model: Chiaki.rental.managedStores

                                Rectangle {
                                    id: storeRow
                                    property bool editing: false
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? (editing ? 132 : 64) : 0
                                    visible: admin.matchesStore(modelData)
                                    radius: 10
                                    color: editing ? "#111e2c" : "#101722"
                                    border.width: editing ? 1 : 0
                                    border.color: "#245c85"

                                    ColumnLayout {
                                        anchors { fill: parent; margins: 12 }
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 14

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 150
                                                Layout.preferredHeight: 38
                                                Label { anchors.verticalCenter: parent.verticalCenter; width: parent.width; visible: !storeRow.editing; text: modelData.name || qsTr("Store"); color: "#f8fafc"; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight }
                                                TextField { id: storeName; anchors.fill: parent; visible: storeRow.editing; placeholderText: qsTr("Store Name"); text: modelData.name || ""; font.pixelSize: 13 }
                                            }

                                            Item {
                                                Layout.preferredWidth: 210
                                                Layout.preferredHeight: 38
                                                Label { anchors.verticalCenter: parent.verticalCenter; width: parent.width; visible: !storeRow.editing; text: modelData.location || "—"; color: "#94a3b8"; font.pixelSize: 12; elide: Text.ElideRight }
                                                TextField { id: storeLocation; anchors.fill: parent; visible: storeRow.editing; placeholderText: qsTr("Location"); text: modelData.location || ""; font.pixelSize: 13 }
                                            }

                                            Item {
                                                Layout.preferredWidth: 140
                                                Layout.preferredHeight: 38
                                                Label { anchors.verticalCenter: parent.verticalCenter; width: parent.width; visible: !storeRow.editing; text: modelData.phone || "—"; color: "#94a3b8"; font.pixelSize: 12; elide: Text.ElideRight }
                                                TextField { id: storePhone; anchors.fill: parent; visible: storeRow.editing; placeholderText: qsTr("Phone"); text: modelData.phone || ""; font.pixelSize: 13 }
                                            }

                                            Item {
                                                Layout.preferredWidth: 100
                                                Layout.preferredHeight: 38
                                                AdminStatusBadge { anchors.verticalCenter: parent.verticalCenter; visible: !storeRow.editing; status: modelData.active ? "enabled" : "disabled" }
                                                CheckBox { id: storeActive; anchors.verticalCenter: parent.verticalCenter; visible: storeRow.editing; text: qsTr("Enabled"); checked: modelData.active; font.pixelSize: 12 }
                                            }

                                            Label {
                                                Layout.preferredWidth: 90
                                                text: String(modelData.pricing_count || 0)
                                                color: "#cbd5e1"
                                                font.bold: true
                                            }

                                            RowLayout {
                                                Layout.preferredWidth: 176
                                                spacing: 6
                                                Button { Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: !storeRow.editing; text: qsTr("Edit"); font.pixelSize: 12; onClicked: storeRow.editing = true }
                                                Button {
                                                    Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: storeRow.editing
                                                    enabled: !Chiaki.rental.adminBusy && storeName.text.length > 0
                                                    text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                                    font.pixelSize: 12; Material.background: "#00a7ff"
                                                    onClicked: {
                                                        if (!enabled)
                                                            return;
                                                        Chiaki.rental.saveStore({ id: modelData.id, name: storeName.text, location: storeLocation.text, phone: storePhone.text, email: storeEmail.text, notes: storeNotes.text, active: storeActive.checked });
                                                    }
                                                }
                                                Button {
                                                    Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: storeRow.editing; text: qsTr("Cancel"); font.pixelSize: 12
                                                    onClicked: {
                                                        storeName.text = modelData.name || "";
                                                        storeLocation.text = modelData.location || "";
                                                        storePhone.text = modelData.phone || "";
                                                        storeEmail.text = modelData.email || "";
                                                        storeNotes.text = modelData.notes || "";
                                                        storeActive.checked = modelData.active;
                                                        storeRow.editing = false;
                                                    }
                                                }
                                                Button {
                                                    Layout.preferredWidth: 84; Layout.preferredHeight: 34; visible: !storeRow.editing
                                                    enabled: !Chiaki.rental.adminBusy
                                                    text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                                    font.pixelSize: 12
                                                    onClicked: if (enabled) root.showConfirmDialog(qsTr("Delete Store"), qsTr("Delete this store?"), () => Chiaki.rental.removeStore(modelData.id))
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: storeRow.editing
                                            spacing: 12
                                            TextField { id: storeEmail; Layout.fillWidth: true; Layout.preferredHeight: 38; placeholderText: qsTr("Email"); text: modelData.email || ""; font.pixelSize: 13 }
                                            TextField { id: storeNotes; Layout.fillWidth: true; Layout.preferredHeight: 38; placeholderText: qsTr("Notes"); text: modelData.notes || ""; font.pixelSize: 13 }
                                            Item { Layout.preferredWidth: 176 }
                                        }
                                    }

                                    Connections {
                                        target: Chiaki.rental
                                        function onControllerAdminDataSaved() {
                                            storeRow.editing = false;
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 time plans").arg(Chiaki.rental.managedTimePlans.length)
                                color: "#8f9bb3"
                            }

                            Button {
                                text: admin.showPlanForm ? qsTr("Cancel") : qsTr("Add Time Plan")
                                onClicked: admin.showPlanForm = !admin.showPlanForm
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.showPlanForm
                            title: qsTr("New Time Plan")

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 3 : 1
                                columnSpacing: 12
                                rowSpacing: 10

                                TextField { id: addPlanName; Layout.fillWidth: true; placeholderText: qsTr("Plan Name") }
                                TextField { id: addPlanMinutes; Layout.fillWidth: true; placeholderText: qsTr("Duration Minutes"); inputMethodHints: Qt.ImhDigitsOnly }
                                TextField { id: addPlanSort; Layout.fillWidth: true; placeholderText: qsTr("Sort Order"); inputMethodHints: Qt.ImhDigitsOnly }

                                Button {
                                    Layout.columnSpan: parent.columns
                                    Layout.fillWidth: true
                                    enabled: !Chiaki.rental.adminBusy && addPlanName.text.length > 0 && Number(addPlanMinutes.text) > 0
                                    text: Chiaki.rental.adminBusy ? qsTr("Saving Plan...") : qsTr("Save Time Plan")
                                    Material.background: "#00a7ff"
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

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            title: qsTr("Time Plan Catalog")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; text: qsTr("PLAN NAME"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 150; text: qsTr("DURATION"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 110; text: qsTr("SORT ORDER"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 100; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 176; text: qsTr("ACTIONS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Repeater {
                                model: Chiaki.rental.managedTimePlans

                                Rectangle {
                                    id: planRow
                                    property bool editing: false
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 64 : 0
                                    visible: admin.matchesPlan(modelData)
                                    radius: 10
                                    color: editing ? "#111e2c" : "#101722"
                                    border.width: editing ? 1 : 0
                                    border.color: "#245c85"

                                    RowLayout {
                                        anchors { fill: parent; margins: 12 }
                                        spacing: 14

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 38
                                            Label { anchors.verticalCenter: parent.verticalCenter; width: parent.width; visible: !planRow.editing; text: modelData.name || qsTr("Time Plan"); color: "#f8fafc"; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight }
                                            TextField { id: planName; anchors.fill: parent; visible: planRow.editing; placeholderText: qsTr("Plan Name"); text: modelData.name || ""; font.pixelSize: 13 }
                                        }

                                        Item {
                                            Layout.preferredWidth: 150
                                            Layout.preferredHeight: 38
                                            Label { anchors.verticalCenter: parent.verticalCenter; visible: !planRow.editing; text: qsTr("%1 minutes").arg(modelData.duration_minutes || 0); color: "#cbd5e1"; font.pixelSize: 13 }
                                            TextField { id: planMinutes; anchors.fill: parent; visible: planRow.editing; placeholderText: qsTr("Minutes"); text: modelData.duration_minutes || ""; inputMethodHints: Qt.ImhDigitsOnly; font.pixelSize: 13 }
                                        }

                                        Item {
                                            Layout.preferredWidth: 110
                                            Layout.preferredHeight: 38
                                            Label { anchors.verticalCenter: parent.verticalCenter; visible: !planRow.editing; text: String(modelData.sort_order || 0); color: "#94a3b8" }
                                            TextField { id: planSort; anchors.fill: parent; visible: planRow.editing; placeholderText: qsTr("Sort"); text: modelData.sort_order || ""; inputMethodHints: Qt.ImhDigitsOnly; font.pixelSize: 13 }
                                        }

                                        Item {
                                            Layout.preferredWidth: 100
                                            Layout.preferredHeight: 38
                                            AdminStatusBadge { anchors.verticalCenter: parent.verticalCenter; visible: !planRow.editing; status: modelData.active ? "enabled" : "disabled" }
                                            CheckBox { id: planActive; anchors.verticalCenter: parent.verticalCenter; visible: planRow.editing; text: qsTr("Enabled"); checked: modelData.active; font.pixelSize: 12 }
                                        }

                                        RowLayout {
                                            Layout.preferredWidth: 176
                                            spacing: 6
                                            Button { Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: !planRow.editing; text: qsTr("Edit"); font.pixelSize: 12; onClicked: planRow.editing = true }
                                            Button {
                                                Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: planRow.editing
                                                enabled: !Chiaki.rental.adminBusy && planName.text.length > 0 && Number(planMinutes.text) > 0
                                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                                font.pixelSize: 12; Material.background: "#00a7ff"
                                                onClicked: {
                                                    if (!enabled)
                                                        return;
                                                    Chiaki.rental.saveTimePlan({ id: modelData.id, name: planName.text, duration_minutes: Number(planMinutes.text), sort_order: Number(planSort.text || 0), active: planActive.checked });
                                                }
                                            }
                                            Button {
                                                Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: planRow.editing; text: qsTr("Cancel"); font.pixelSize: 12
                                                onClicked: {
                                                    planName.text = modelData.name || "";
                                                    planMinutes.text = modelData.duration_minutes || "";
                                                    planSort.text = modelData.sort_order || "";
                                                    planActive.checked = modelData.active;
                                                    planRow.editing = false;
                                                }
                                            }
                                            Button {
                                                Layout.preferredWidth: 84; Layout.preferredHeight: 34; visible: !planRow.editing
                                                enabled: !Chiaki.rental.adminBusy
                                                text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                                font.pixelSize: 12
                                                onClicked: if (enabled) root.showConfirmDialog(qsTr("Delete Time Plan"), qsTr("Delete this time plan?"), () => Chiaki.rental.removeTimePlan(modelData.id))
                                            }
                                        }
                                    }

                                    Connections {
                                        target: Chiaki.rental
                                        function onControllerAdminDataSaved() {
                                            planRow.editing = false;
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0

                            Button {
                                visible: admin.selectedPricingStoreId.length > 0
                                Layout.preferredWidth: 112
                                text: qsTr("Back to Stores")
                                onClicked: admin.closeStorePricing()
                            }

                            Label {
                                Layout.fillWidth: true
                                text: admin.selectedPricingStoreId.length > 0
                                    ? qsTr("%1 pricing rules for %2")
                                        .arg(admin.selectedStorePricing().length)
                                        .arg(admin.selectedPricingStore().name || qsTr("Store"))
                                    : qsTr("%1 stores with %2 pricing rules")
                                        .arg(Chiaki.rental.managedStores.length)
                                        .arg(Chiaki.rental.managedPricing.length)
                                color: "#8f9bb3"
                            }

                            Button {
                                visible: admin.selectedPricingStoreId.length > 0
                                text: admin.showPricingForm ? qsTr("Cancel") : qsTr("Add Price")
                                onClicked: admin.showPricingForm = !admin.showPricingForm
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.selectedPricingStoreId.length === 0
                            title: qsTr("Store Pricing")
                            subtitle: qsTr("Select a store to view and manage only that location's pricing.")

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 1060 ? 3 : (width > 680 ? 2 : 1)
                                columnSpacing: 14
                                rowSpacing: 14

                                Repeater {
                                    model: Chiaki.rental.managedStores

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? 132 : 0
                                        visible: admin.matchesStore(modelData)
                                        radius: 12
                                        color: storePricingMouse.containsMouse ? "#142236" : "#101722"
                                        border.width: 1
                                        border.color: storePricingMouse.containsMouse ? "#00a7ff" : "#273247"

                                        MouseArea {
                                            id: storePricingMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: admin.openStorePricing(modelData.id)
                                        }

                                        ColumnLayout {
                                            anchors { fill: parent; margins: 16 }
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: modelData.name || qsTr("Store")
                                                    color: "#f8fafc"
                                                    font.bold: true
                                                    font.pixelSize: 16
                                                    elide: Text.ElideRight
                                                }

                                                AdminStatusBadge {
                                                    status: modelData.active ? "enabled" : "disabled"
                                                }
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.location || qsTr("Location not set")
                                                color: "#8f9bb3"
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }

                                            Item { Layout.fillHeight: true }

                                            RowLayout {
                                                Layout.fillWidth: true

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: qsTr("%1 price rules").arg(admin.pricingCountForStore(modelData.id))
                                                    color: "#cbd5e1"
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                }

                                                Label {
                                                    text: qsTr("Manage  >")
                                                    color: "#38bdf8"
                                                    font.bold: true
                                                    font.pixelSize: 12
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: Chiaki.rental.managedStores.length === 0
                                text: qsTr("No stores found. Add a store before creating pricing rules.")
                                color: "#8f9bb3"
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.selectedPricingStoreId.length > 0 && admin.showPricingForm
                            title: qsTr("New Price for %1").arg(admin.selectedPricingStore().name || qsTr("Store"))

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 3 : 1
                                columnSpacing: 12
                                rowSpacing: 10

                                ComboBox { id: pricePlan; Layout.fillWidth: true; model: Chiaki.rental.managedTimePlans; textRole: "name"; valueRole: "id" }
                                TextField { id: priceAmount; Layout.fillWidth: true; placeholderText: qsTr("Price ₹"); inputMethodHints: Qt.ImhFormattedNumbersOnly }
                                CheckBox { id: priceActive; text: qsTr("Enabled"); checked: true }

                                Button {
                                    Layout.columnSpan: parent.columns
                                    Layout.fillWidth: true
                                    enabled: !Chiaki.rental.adminBusy
                                        && admin.selectedPricingStoreId.length > 0
                                        && pricePlan.currentValue
                                        && Number(priceAmount.text) > 0
                                    text: Chiaki.rental.adminBusy ? qsTr("Saving Price...") : qsTr("Save Price")
                                    Material.background: "#00a7ff"
                                    onClicked: {
                                        if (!enabled)
                                            return;
                                        Chiaki.rental.savePricingRule({
                                            store_id: admin.selectedPricingStoreId,
                                            time_plan_id: pricePlan.currentValue,
                                            amount_paise: admin.rupeesToPaise(priceAmount.text),
                                            currency: "INR",
                                            active: priceActive.checked
                                        });
                                        priceAmount.text = "";
                                    }
                                }
                            }
                        }

                        AdminCard {
                            id: pricingTable
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            visible: admin.selectedPricingStoreId.length > 0
                            title: qsTr("%1 Pricing").arg(admin.selectedPricingStore().name || qsTr("Store"))
                            subtitle: qsTr("Prices are sorted from lowest to highest for this store.")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; Layout.minimumWidth: 220; text: qsTr("TIME PLAN"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 140; text: qsTr("PRICE"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 100; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 176; text: qsTr("ACTIONS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Repeater {
                                model: admin.selectedStorePricing()

                                Rectangle {
                                    id: priceRow
                                    property bool editing: false
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 64 : 0
                                    visible: admin.matchesPrice(modelData)
                                    radius: 10
                                    color: editing ? "#111e2c" : "#101722"
                                    border.width: editing ? 1 : 0
                                    border.color: "#245c85"

                                    RowLayout {
                                        anchors { fill: parent; margins: 12 }
                                        spacing: 14

                                        Label { Layout.fillWidth: true; Layout.minimumWidth: 220; text: modelData.time_plan_name || modelData.time_plan_id; color: "#f8fafc"; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight }

                                        Item {
                                            Layout.preferredWidth: 140
                                            Layout.preferredHeight: 38
                                            Label { anchors.verticalCenter: parent.verticalCenter; visible: !priceRow.editing; text: admin.moneyText(modelData.amount_paise, modelData.currency); color: "#ffffff"; font.bold: true }
                                            TextField { id: editPriceAmount; anchors.fill: parent; visible: priceRow.editing; placeholderText: qsTr("Price ₹"); text: (Number(modelData.amount_paise || 0) / 100).toFixed(2); inputMethodHints: Qt.ImhFormattedNumbersOnly; font.pixelSize: 13 }
                                        }

                                        Item {
                                            Layout.preferredWidth: 100
                                            Layout.preferredHeight: 38
                                            AdminStatusBadge { anchors.verticalCenter: parent.verticalCenter; visible: !priceRow.editing; status: modelData.active ? "enabled" : "disabled" }
                                            CheckBox { id: editPriceActive; anchors.verticalCenter: parent.verticalCenter; visible: priceRow.editing; text: qsTr("Enabled"); checked: modelData.active; font.pixelSize: 12 }
                                        }

                                        RowLayout {
                                            Layout.preferredWidth: 176
                                            spacing: 6
                                            Button { Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: !priceRow.editing; text: qsTr("Edit"); font.pixelSize: 12; onClicked: priceRow.editing = true }
                                            Button {
                                                Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: priceRow.editing
                                                enabled: !Chiaki.rental.adminBusy && Number(editPriceAmount.text) > 0
                                                text: Chiaki.rental.adminBusy ? qsTr("Saving...") : qsTr("Save")
                                                font.pixelSize: 12; Material.background: "#00a7ff"
                                                onClicked: {
                                                    if (!enabled)
                                                        return;
                                                    Chiaki.rental.savePricingRule({ id: modelData.id, store_id: modelData.store_id, time_plan_id: modelData.time_plan_id, amount_paise: admin.rupeesToPaise(editPriceAmount.text), currency: modelData.currency || "INR", active: editPriceActive.checked });
                                                }
                                            }
                                            Button {
                                                Layout.preferredWidth: 68; Layout.preferredHeight: 34; visible: priceRow.editing; text: qsTr("Cancel"); font.pixelSize: 12
                                                onClicked: {
                                                    editPriceAmount.text = (Number(modelData.amount_paise || 0) / 100).toFixed(2);
                                                    editPriceActive.checked = modelData.active;
                                                    priceRow.editing = false;
                                                }
                                            }
                                            Button {
                                                Layout.preferredWidth: 84; Layout.preferredHeight: 34; visible: !priceRow.editing
                                                enabled: !Chiaki.rental.adminBusy
                                                text: Chiaki.rental.adminBusy ? qsTr("Deleting...") : qsTr("Delete")
                                                font.pixelSize: 12
                                                onClicked: if (enabled) root.showConfirmDialog(qsTr("Delete Price"), qsTr("Delete this price?"), () => Chiaki.rental.removePricingRule(modelData.id))
                                            }
                                        }
                                    }

                                    Connections {
                                        target: Chiaki.rental
                                        function onControllerAdminDataSaved() {
                                            priceRow.editing = false;
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: admin.selectedStorePricing().length === 0
                                text: qsTr("No pricing rules have been added for this store.")
                                color: "#8f9bb3"
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0
                            title: qsTr("Current Controller Session")
                            subtitle: qsTr("Live session state exposed by the existing rental manager.")

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 3 : 1
                                columnSpacing: 16
                                rowSpacing: 12

                                Label { text: qsTr("Status"); color: "#718096" }
                                Label { text: qsTr("Remaining"); color: "#718096" }
                                Label { text: qsTr("Console"); color: "#718096" }
                                Label { text: Chiaki.rental.activeSession.status || (Chiaki.rental.activeSessionId.length > 0 ? qsTr("active") : qsTr("none")); color: "#ffffff"; font.bold: true }
                                Label { text: Chiaki.rental.activeSessionId.length > 0 ? Math.ceil(Chiaki.rental.remainingSeconds / 60) + qsTr(" min") : "—"; color: "#ffffff"; font.bold: true }
                                Label { text: Chiaki.rental.assignedConsole.name || "—"; color: "#ffffff"; font.bold: true }
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            title: qsTr("Console Sessions")
                            subtitle: qsTr("Session summaries attached to managed consoles.")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; text: qsTr("CONSOLE"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 180; text: qsTr("SESSION ID"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 120; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 120; text: qsTr("REMAINING"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Repeater {
                                model: Chiaki.rental.managedConsoles

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 64
                                    radius: 10
                                    color: "#101722"
                                    visible: modelData.current_session

                                    RowLayout {
                                        anchors { fill: parent; margins: 12 }
                                        spacing: 14
                                        Label { Layout.fillWidth: true; text: modelData.name || qsTr("Console"); color: "#ffffff"; font.bold: true; font.pixelSize: 14 }
                                        Label { Layout.preferredWidth: 180; text: modelData.current_session ? modelData.current_session.id || "—" : "—"; color: "#94a3b8"; font.pixelSize: 12; elide: Text.ElideMiddle }
                                        Item {
                                            Layout.preferredWidth: 120
                                            AdminStatusBadge { anchors.verticalCenter: parent.verticalCenter; status: modelData.current_session ? modelData.current_session.status || "active" : "disconnected" }
                                        }
                                        Label {
                                            Layout.preferredWidth: 120
                                            text: modelData.current_session && modelData.current_session.remaining_seconds
                                                ? Math.ceil(modelData.current_session.remaining_seconds / 60) + qsTr(" min")
                                                : "—"
                                            color: "#cbd5e1"
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: admin.consolesInSession() === 0
                                text: qsTr("No managed console sessions are currently reported.")
                                color: "#8f9bb3"
                            }
                        }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            title: qsTr("Reservation Monitor")
                            subtitle: qsTr("Current reservation state for this controller. Reservation logic is unchanged.")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; text: qsTr("RESERVATION ID"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 160; text: qsTr("AVAILABLE CONSOLES"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 140; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                radius: 10
                                color: "#101722"

                                RowLayout {
                                    anchors { fill: parent; margins: 12 }
                                    spacing: 14
                                    Label { Layout.fillWidth: true; text: Chiaki.rental.reservationId.length > 0 ? Chiaki.rental.reservationId : qsTr("No active reservation"); color: "#ffffff"; font.bold: true; font.pixelSize: 13; elide: Text.ElideMiddle }
                                    Label { Layout.preferredWidth: 160; text: String(Chiaki.rental.availableConsoleCount); color: "#22c55e"; font.bold: true; font.pixelSize: 16 }
                                    Item {
                                        Layout.preferredWidth: 140
                                        Layout.fillHeight: true
                                        AdminStatusBadge { anchors.verticalCenter: parent.verticalCenter; status: Chiaki.rental.reservationId.length > 0 ? "reserved" : Chiaki.rental.state }
                                    }
                                }
                            }
                        }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            title: qsTr("Payment Status")
                            subtitle: qsTr("Read-only visibility into the existing Razorpay checkout state.")

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                spacing: 14
                                Label { Layout.fillWidth: true; text: qsTr("CHECKOUT"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 180; text: qsTr("SESSION"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 140; text: qsTr("PROVIDER"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                                Label { Layout.preferredWidth: 130; text: qsTr("STATUS"); color: "#64748b"; font.bold: true; font.pixelSize: 11 }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#273247" }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                radius: 10
                                color: "#101722"

                                RowLayout {
                                    anchors { fill: parent; margins: 12 }
                                    spacing: 14
                                    Label { Layout.fillWidth: true; text: Chiaki.rental.paymentHtml.length > 0 ? qsTr("Razorpay checkout pending") : qsTr("No pending checkout"); color: "#ffffff"; font.bold: true; font.pixelSize: 13 }
                                    Label { Layout.preferredWidth: 180; text: Chiaki.rental.activeSessionId.length > 0 ? Chiaki.rental.activeSessionId : "—"; color: "#94a3b8"; font.pixelSize: 12; elide: Text.ElideMiddle }
                                    Label { Layout.preferredWidth: 140; text: "Razorpay"; color: "#cbd5e1"; font.bold: true; font.pixelSize: 13 }
                                    Item {
                                        Layout.preferredWidth: 130
                                        Layout.fillHeight: true
                                        AdminStatusBadge {
                                            anchors.verticalCenter: parent.verticalCenter
                                            status: Chiaki.rental.paymentHtml.length > 0
                                                ? "awaiting_payment"
                                                : Chiaki.rental.activeSessionId.length > 0 ? "paid" : "inactive"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            Layout.bottomMargin: 0
                            title: qsTr("System Store Assignment")
                            subtitle: Chiaki.rental.selectedStoreName.length > 0
                                ? qsTr("Current store: %1").arg(Chiaki.rental.selectedStoreName)
                                : qsTr("This controller is not assigned to a store.")

                            RowLayout {
                                Layout.fillWidth: true

                                ComboBox {
                                    id: systemStoreSelector
                                    Layout.fillWidth: true
                                    model: Chiaki.rental.managedStores
                                    textRole: "name"
                                    valueRole: "id"
                                    enabled: !Chiaki.rental.adminBusy && Chiaki.rental.managedStores.length > 0
                                    Component.onCompleted: admin.syncSystemStoreSelector()
                                }

                                Button {
                                    Layout.preferredWidth: 180
                                    enabled: !Chiaki.rental.adminBusy && systemStoreSelector.currentValue
                                    text: Chiaki.rental.adminBusy ? qsTr("Assigning...") : qsTr("Assign Store")
                                    Material.background: "#00a7ff"
                                    onClicked: {
                                        if (enabled)
                                            Chiaki.rental.assignSystemStore(systemStoreSelector.currentValue);
                                    }
                                }
                            }
                        }

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            title: qsTr("Access Security")
                            subtitle: qsTr("Update the access code for this management page.")

                            RowLayout {
                                Layout.fillWidth: true

                                TextField {
                                    id: newAdminPin
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("New access code")
                                    echoMode: TextInput.Password
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    enabled: !Chiaki.rental.adminBusy
                                }

                                Button {
                                    Layout.preferredWidth: 170
                                    enabled: !Chiaki.rental.adminBusy && newAdminPin.text.length >= 4
                                    text: Chiaki.rental.adminBusy ? qsTr("Updating...") : qsTr("Update Code")
                                    onClicked: {
                                        if (!enabled)
                                            return;
                                        Chiaki.rental.updateControllerPin(newAdminPin.text);
                                        newAdminPin.text = "";
                                    }
                                }
                            }
                        }
                    }
                }

                ManagementScrollView {

                    ColumnLayout {
                        width: parent.width
                        spacing: 18

                        AdminCard {
                            Layout.fillWidth: true
                            Layout.margins: 24
                            title: qsTr("Runtime Status")
                            subtitle: qsTr("Current application operating status.")

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 2 : 1
                                columnSpacing: 18
                                rowSpacing: 12

                                Label { text: qsTr("Service ready"); color: "#718096" }
                                Label { text: Chiaki.rental.configured ? qsTr("Yes") : qsTr("No"); color: "#ffffff"; font.bold: true }
                                Label { text: qsTr("Rental state"); color: "#718096" }
                                Label { text: Chiaki.rental.state; color: "#ffffff"; font.bold: true }
                                Label { text: qsTr("Warning"); color: "#718096" }
                                Label { text: Chiaki.rental.warning.length > 0 ? Chiaki.rental.warning : qsTr("None"); color: Chiaki.rental.warning.length > 0 ? "#fbbf24" : "#ffffff"; wrapMode: Text.WordWrap }
                                Label { text: qsTr("Last error"); color: "#718096" }
                                Label { text: Chiaki.rental.error.length > 0 ? Chiaki.rental.error : qsTr("None"); color: Chiaki.rental.error.length > 0 ? "#fb7185" : "#ffffff"; wrapMode: Text.WordWrap }
                            }

                            Button {
                                Layout.fillWidth: true
                                text: qsTr("Open Console Browser")
                                onClicked: root.showHostList()
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: consoleAvailabilityDialog
        property var consoleData: ({})
        readonly property bool timedBlock: consoleStateSelector.currentValue === "reserved"
            || consoleStateSelector.currentValue === "occupied"
        readonly property bool customDuration: timedBlock && consoleDurationSelector.currentValue === -1

        parent: Overlay.overlay
        x: Math.round((admin.width - width) / 2)
        y: Math.round((admin.height - height) / 2)
        width: Math.min(admin.width - 80, 560)
        modal: true
        title: qsTr("Console Availability")
        closePolicy: Popup.CloseOnEscape

        ColumnLayout {
            width: consoleAvailabilityDialog.width - 48
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: consoleAvailabilityDialog.consoleData.name || qsTr("Console")
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 20
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Set a manual occupancy state without creating a customer session.")
                color: "#8f9bb3"
                wrapMode: Text.WordWrap
            }

            Label { text: qsTr("Availability state"); color: "#cbd5e1"; font.bold: true; font.pixelSize: 13 }

            ComboBox {
                id: consoleStateSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                model: admin.manualStateOptions
                textRole: "label"
                valueRole: "value"
                enabled: !Chiaki.rental.adminBusy
            }

            Label {
                visible: consoleAvailabilityDialog.timedBlock
                text: qsTr("Unavailable for")
                color: "#cbd5e1"
                font.bold: true
                font.pixelSize: 13
            }

            ComboBox {
                id: consoleDurationSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                visible: consoleAvailabilityDialog.timedBlock
                model: admin.manualDurationOptions
                textRole: "label"
                valueRole: "value"
                enabled: !Chiaki.rental.adminBusy
            }

            TextField {
                id: consoleCustomDuration
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                visible: consoleAvailabilityDialog.customDuration
                placeholderText: qsTr("Custom duration in minutes")
                inputMethodHints: Qt.ImhDigitsOnly
                enabled: !Chiaki.rental.adminBusy
            }

            Label { text: qsTr("Note / reason (optional)"); color: "#cbd5e1"; font.bold: true; font.pixelSize: 13 }

            TextArea {
                id: consoleLockNote
                Layout.fillWidth: true
                Layout.preferredHeight: 86
                placeholderText: qsTr("Used physically in store, local customer, testing...")
                wrapMode: TextEdit.Wrap
                enabled: !Chiaki.rental.adminBusy
            }

            Label {
                Layout.fillWidth: true
                visible: consoleAvailabilityDialog.consoleData.current_session
                text: qsTr("This console has active customer activity and cannot be manually changed until it ends.")
                color: "#fbbf24"
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                Button {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 42
                    text: qsTr("Cancel")
                    enabled: !Chiaki.rental.adminBusy
                    onClicked: consoleAvailabilityDialog.close()
                }

                Button {
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 42
                    enabled: !Chiaki.rental.adminBusy
                        && !consoleAvailabilityDialog.consoleData.current_session
                        && (!consoleAvailabilityDialog.customDuration || Number(consoleCustomDuration.text) > 0)
                    text: Chiaki.rental.adminBusy ? qsTr("Applying...") : qsTr("Apply State")
                    Material.background: "#00a7ff"
                    onClicked: {
                        if (!enabled)
                            return;
                        let durationMinutes = null;
                        if (consoleAvailabilityDialog.timedBlock) {
                            if (consoleDurationSelector.currentValue === -1)
                                durationMinutes = Number(consoleCustomDuration.text);
                            else if (consoleDurationSelector.currentValue > 0)
                                durationMinutes = consoleDurationSelector.currentValue;
                        }
                        Chiaki.rental.setManualConsoleAvailability({
                            id: consoleAvailabilityDialog.consoleData.id,
                            action: consoleStateSelector.currentValue,
                            duration_minutes: durationMinutes,
                            note: consoleLockNote.text
                        });
                    }
                }
            }
        }
    }

    Connections {
        target: Chiaki.rental

        function onControllerPinVerified() {
            pinField.text = "";
            admin.refreshAllAdminData();
        }

        function onManagedStoresChanged() {
            admin.syncSystemStoreSelector();
        }

        function onSelectedStoreIdChanged() {
            admin.syncSystemStoreSelector();
        }

        function onControllerConsoleSaved() {
            admin.refreshAddList();
        }

        function onControllerConsoleRemoved() {
            admin.refreshAddList();
        }

        function onManualConsoleAvailabilitySaved() {
            consoleAvailabilityDialog.close();
            Chiaki.rental.checkAvailability(Chiaki.discoveredConsoleCandidates());
        }

        function onControllerAdminDataSaved() {
            Chiaki.rental.loadPricing();
        }

        function onControllerAdminDataRemoved() {
            Chiaki.rental.loadPricing();
        }
    }
}
