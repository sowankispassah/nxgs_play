#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QDateTime>
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
#include <QAbstractSocket>
#include <QWebSocket>
#endif

class RentalManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool configured READ configured NOTIFY configuredChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool availabilityChecked READ availabilityChecked NOTIFY availabilityChanged)
    Q_PROPERTY(bool consoleAvailable READ consoleAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(int availableConsoleCount READ availableConsoleCount NOTIFY availabilityChanged)
    Q_PROPERTY(QString reservationId READ reservationId NOTIFY reservationChanged)
    Q_PROPERTY(QString activeSessionId READ activeSessionId NOTIFY activeSessionChanged)
    Q_PROPERTY(QVariantList pricing READ pricing NOTIFY pricingChanged)
    Q_PROPERTY(QVariantList stores READ stores NOTIFY storesChanged)
    Q_PROPERTY(QVariantList timePlans READ timePlans NOTIFY timePlansChanged)
    Q_PROPERTY(QString selectedStoreId READ selectedStoreId WRITE setSelectedStoreId NOTIFY selectedStoreIdChanged)
    Q_PROPERTY(QString selectedStoreName READ selectedStoreName NOTIFY selectedStoreNameChanged)
    Q_PROPERTY(QString paymentHtml READ paymentHtml NOTIFY paymentHtmlChanged)
    Q_PROPERTY(int remainingSeconds READ remainingSeconds NOTIFY remainingSecondsChanged)
    Q_PROPERTY(int graceRemainingSeconds READ graceRemainingSeconds NOTIFY graceRemainingSecondsChanged)
    Q_PROPERTY(bool inGracePeriod READ inGracePeriod NOTIFY inGracePeriodChanged)
    Q_PROPERTY(QString warning READ warning NOTIFY warningChanged)
    Q_PROPERTY(QVariantMap activeSession READ activeSession NOTIFY activeSessionChanged)
    Q_PROPERTY(QVariantMap assignedConsole READ assignedConsole NOTIFY assignedConsoleChanged)
    Q_PROPERTY(bool controllerAdminAuthenticated READ controllerAdminAuthenticated NOTIFY controllerAdminAuthenticatedChanged)
    Q_PROPERTY(bool controllerAdminConfigured READ controllerAdminConfigured NOTIFY configuredChanged)
    Q_PROPERTY(bool adminBusy READ adminBusy NOTIFY adminBusyChanged)
    Q_PROPERTY(QString adminError READ adminError NOTIFY adminErrorChanged)
    Q_PROPERTY(QVariantList discoveredAdminConsoles READ discoveredAdminConsoles NOTIFY discoveredAdminConsolesChanged)
    Q_PROPERTY(QVariantList managedConsoles READ managedConsoles NOTIFY managedConsolesChanged)
    Q_PROPERTY(QVariantList managedStores READ managedStores NOTIFY managedStoresChanged)
    Q_PROPERTY(QVariantList managedTimePlans READ managedTimePlans NOTIFY managedTimePlansChanged)
    Q_PROPERTY(QVariantList managedPricing READ managedPricing NOTIFY managedPricingChanged)

public:
    explicit RentalManager(QObject *parent = nullptr);
    ~RentalManager() override;

    bool configured() const;
    bool busy() const { return busy_; }
    QString state() const { return state_; }
    QString error() const { return error_; }
    bool availabilityChecked() const { return availability_checked_; }
    bool consoleAvailable() const { return console_available_; }
    int availableConsoleCount() const { return available_console_count_; }
    QString reservationId() const { return reservation_id_; }
    QString activeSessionId() const { return active_session_id_; }
    QVariantList pricing() const { return pricing_; }
    QVariantList stores() const { return stores_; }
    QVariantList timePlans() const { return time_plans_; }
    QString selectedStoreId() const { return selected_store_id_; }
    void setSelectedStoreId(const QString &storeId);
    QString selectedStoreName() const;
    QString paymentHtml() const { return payment_html_; }
    int remainingSeconds() const { return remaining_seconds_; }
    int graceRemainingSeconds() const { return grace_remaining_seconds_; }
    bool inGracePeriod() const { return in_grace_period_; }
    QString warning() const { return warning_; }
    QVariantMap activeSession() const { return active_session_; }
    QVariantMap assignedConsole() const { return assigned_console_; }
    bool controllerAdminAuthenticated() const { return !controller_admin_token_.isEmpty(); }
    bool controllerAdminConfigured() const;
    bool adminBusy() const { return admin_busy_; }
    QString adminError() const { return admin_error_; }
    QVariantList discoveredAdminConsoles() const { return discovered_admin_consoles_; }
    QVariantList managedConsoles() const { return managed_consoles_; }
    QVariantList managedStores() const { return managed_stores_; }
    QVariantList managedTimePlans() const { return managed_time_plans_; }
    QVariantList managedPricing() const { return managed_pricing_; }

    bool hasActiveRental() const;

    Q_INVOKABLE void loadPricing();
    Q_INVOKABLE void checkAvailability(const QVariantList &discovered = QVariantList());
    Q_INVOKABLE void reserveConsole(const QVariantList &discovered = QVariantList());
    Q_INVOKABLE void releaseReservation();
    Q_INVOKABLE void createPaymentOrder(const QString &timePlanId);
    Q_INVOKABLE void extendSession(const QString &timePlanId);
    Q_INVOKABLE void verifyPayment(const QString &razorpayPaymentId,
                                   const QString &razorpayOrderId,
                                   const QString &razorpaySignature);
    Q_INVOKABLE void endSession();
    Q_INVOKABLE void heartbeat();
    Q_INVOKABLE void clearPayment();
    Q_INVOKABLE void clearWarning();
    Q_INVOKABLE QString priceLabel(const QString &storeId, const QString &timePlanId) const;
    Q_INVOKABLE QString timePlanLabel(const QVariantMap &timePlan) const;
    Q_INVOKABLE QVariantList availableTimePlansForStore(const QString &storeId) const;
    Q_INVOKABLE void assignSystemStore(const QString &storeId);
    Q_INVOKABLE void verifyControllerPin(const QString &pin);
    Q_INVOKABLE void controllerAdminLogout();
    Q_INVOKABLE void updateControllerPin(const QString &newPin);
    Q_INVOKABLE void listDiscoveredConsoles(const QVariantList &discovered);
    Q_INVOKABLE void listManagedConsoles();
    Q_INVOKABLE void addConsole(const QVariantMap &console);
    Q_INVOKABLE void updateConsole(const QVariantMap &console);
    Q_INVOKABLE void setManualConsoleAvailability(const QVariantMap &availability);
    Q_INVOKABLE void removeConsole(const QString &consoleId);
    Q_INVOKABLE void listStores();
    Q_INVOKABLE void saveStore(const QVariantMap &store);
    Q_INVOKABLE void removeStore(const QString &storeId);
    Q_INVOKABLE void listTimePlans();
    Q_INVOKABLE void saveTimePlan(const QVariantMap &timePlan);
    Q_INVOKABLE void removeTimePlan(const QString &timePlanId);
    Q_INVOKABLE void listPricingRules();
    Q_INVOKABLE void savePricingRule(const QVariantMap &pricingRule);
    Q_INVOKABLE void removePricingRule(const QString &pricingRuleId);

signals:
    void configuredChanged();
    void busyChanged();
    void stateChanged();
    void errorChanged();
    void availabilityChanged();
    void reservationChanged();
    void activeSessionChanged();
    void pricingChanged();
    void storesChanged();
    void timePlansChanged();
    void selectedStoreIdChanged();
    void selectedStoreNameChanged();
    void paymentHtmlChanged();
    void remainingSecondsChanged();
    void graceRemainingSecondsChanged();
    void inGracePeriodChanged();
    void warningChanged();
    void assignedConsoleChanged();
    void controllerAdminAuthenticatedChanged();
    void adminBusyChanged();
    void adminErrorChanged();
    void discoveredAdminConsolesChanged();
    void managedConsolesChanged();
    void managedStoresChanged();
    void managedTimePlansChanged();
    void managedPricingChanged();
    void controllerPinVerified();
    void controllerConsoleSaved();
    void manualConsoleAvailabilitySaved();
    void controllerConsoleRemoved();
    void controllerAdminDataSaved();
    void controllerAdminDataRemoved();

    void reservationReady();
    void noConsoleAvailable();
    void consoleAssigned(const QVariantMap &console);
    void stopRemotePlayRequested();

private:
    enum class RequestKind
    {
        Pricing,
        Availability,
        Reserve,
        ReleaseReservation,
        CreatePayment,
        ExtendPayment,
        VerifyPayment,
        EndSession,
        Heartbeat,
        VerifyControllerPin,
        UpdateControllerPin,
        ListDiscoveredConsoles,
        AddConsole,
        UpdateConsole,
        SetManualConsoleAvailability,
        RemoveConsole,
        ListManagedConsoles,
        ListStores,
        SaveStore,
        RemoveStore,
        ListTimePlans,
        SaveTimePlan,
        RemoveTimePlan,
        ListPricingRules,
        SavePricingRule,
        RemovePricingRule,
    };

    void setBusy(bool busy);
    void setAdminBusy(bool busy);
    void setState(const QString &state);
    void setError(const QString &error);
    void setAvailability(bool checked, bool available, int count);
    void setAdminError(const QString &error);
    void setWarning(const QString &warning);
    void setPaymentHtml(const QString &html);
    void setActiveSession(const QVariantMap &session);
    void setAssignedConsole(const QVariantMap &console);
    void setReservationId(const QString &reservationId);
    void clearReservation();
    void releaseReservationBlocking();
    void resetSessionState();
    void postFunction(RequestKind kind, const QString &functionName, const QVariantMap &payload = {});
    bool isAdminRequest(RequestKind kind) const;
    void onReplyFinished(QNetworkReply *reply);
    void handleSuccess(RequestKind kind, const QVariantMap &response);
    void handleFailure(RequestKind kind, const QString &message, int statusCode);
    bool preflightAssignedConsole(const QVariantMap &console);
    void updateCountdown();
    void startSessionTimers();
    void stopSessionTimers();
    void startRealtime();
    void stopRealtime();
    void handleRealtimeMessage(const QString &message);
    QDateTime parseUtc(const QVariant &value) const;
    QString buildPaymentHtml(const QVariantMap &payment, const QVariantMap &order) const;
    QString functionUrl(const QString &functionName) const;
    QString authHeader() const;

    QNetworkAccessManager network_;
    QHash<QNetworkReply *, RequestKind> replies_;
    QHash<QNetworkReply *, QString> reply_names_;
    QTimer countdown_timer_;
    QTimer heartbeat_timer_;
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
    QWebSocket realtime_socket_;
    int realtime_ref_ = 1;
#endif
    QString supabase_url_;
    QString supabase_anon_key_;
    QString function_base_url_;
    QString razorpay_key_id_;
    bool test_payment_bypass_ = false;

    bool busy_ = false;
    bool admin_busy_ = false;
    bool availability_checked_ = false;
    bool console_available_ = false;
    int available_console_count_ = 0;
    QString state_ = QStringLiteral("idle");
    QString error_;
    QString admin_error_;
    QString reservation_id_;
    QString active_session_id_;
    QVariantList pricing_;
    QVariantList stores_;
    QVariantList time_plans_;
    QString selected_store_id_;
    QString payment_html_;
    QVariantMap active_session_;
    QVariantMap assigned_console_;
    QString pending_payment_id_;
    bool pending_extension_ = false;
    QDateTime session_ends_at_;
    QDateTime grace_ends_at_;
    int remaining_seconds_ = 0;
    int grace_remaining_seconds_ = 0;
    bool in_grace_period_ = false;
    QString warning_;
    QString controller_admin_token_;
    QVariantList discovered_admin_consoles_;
    QVariantList managed_consoles_;
    QVariantList managed_stores_;
    QVariantList managed_time_plans_;
    QVariantList managed_pricing_;
};
