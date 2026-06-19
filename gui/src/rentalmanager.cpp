#include "rentalmanager.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>

namespace {
constexpr int kRequestTimeoutMs = 15000;
constexpr int kHeartbeatMs = 30000;
constexpr int kConsolePreflightTimeoutMs = 1500;

QVariantMap objectToMap(const QJsonObject &object)
{
    return object.toVariantMap();
}

QString jsonString(const QVariantMap &map)
{
    return QString::fromUtf8(QJsonDocument::fromVariant(map).toJson(QJsonDocument::Compact));
}

QString htmlEscape(QString value)
{
    return value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;");
}

QString hostAddressFromConsole(const QVariantMap &console)
{
    QString host = console.value(QStringLiteral("tailscale_ip")).toString().trimmed();
    const int cidrIndex = host.indexOf('/');
    if (cidrIndex >= 0)
        host = host.left(cidrIndex);
    return host;
}
}

RentalManager::RentalManager(QObject *parent)
    : QObject(parent)
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    supabase_url_ = env.value(QStringLiteral("NXGS_SUPABASE_URL")).trimmed();
    supabase_anon_key_ = env.value(QStringLiteral("NXGS_SUPABASE_ANON_KEY")).trimmed();
    function_base_url_ = env.value(QStringLiteral("NXGS_RENTAL_FUNCTION_BASE_URL")).trimmed();
    razorpay_key_id_ = env.value(QStringLiteral("NXGS_RAZORPAY_KEY_ID")).trimmed();
    const QString testPaymentBypass = env.value(QStringLiteral("NXGS_TEST_PAYMENT_BYPASS")).trimmed().toLower();
    test_payment_bypass_ = testPaymentBypass == QStringLiteral("1")
        || testPaymentBypass == QStringLiteral("true")
        || testPaymentBypass == QStringLiteral("yes")
        || testPaymentBypass == QStringLiteral("on");
    selected_store_id_ = QSettings().value(QStringLiteral("rental/assigned_store_id")).toString().trimmed();

    if (function_base_url_.isEmpty() && !supabase_url_.isEmpty())
        function_base_url_ = supabase_url_.trimmed().remove(QRegularExpression(QStringLiteral("/+$"))) + QStringLiteral("/functions/v1");

    connect(&network_, &QNetworkAccessManager::finished, this, &RentalManager::onReplyFinished);
    connect(&countdown_timer_, &QTimer::timeout, this, &RentalManager::updateCountdown);
    countdown_timer_.setInterval(1000);
    connect(&heartbeat_timer_, &QTimer::timeout, this, &RentalManager::heartbeat);
    heartbeat_timer_.setInterval(kHeartbeatMs);
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
    connect(&realtime_socket_, &QWebSocket::connected, this, &RentalManager::startRealtime);
    connect(&realtime_socket_, &QWebSocket::textMessageReceived, this, &RentalManager::handleRealtimeMessage);
#endif
}

RentalManager::~RentalManager()
{
    releaseReservationBlocking();
}

bool RentalManager::configured() const
{
    return !function_base_url_.isEmpty() && !supabase_anon_key_.isEmpty();
}

bool RentalManager::controllerAdminConfigured() const
{
    return !function_base_url_.isEmpty() && !supabase_anon_key_.isEmpty();
}

bool RentalManager::hasActiveRental() const
{
    return !active_session_id_.isEmpty();
}

void RentalManager::setSelectedStoreId(const QString &storeId)
{
    const QString trimmed = storeId.trimmed();
    if (selected_store_id_ == trimmed)
        return;
    selected_store_id_ = trimmed;
    emit selectedStoreIdChanged();
    emit selectedStoreNameChanged();
}

QString RentalManager::selectedStoreName() const
{
    const auto findName = [this](const QVariantList &items) {
        for (const QVariant &item : items) {
            const QVariantMap store = item.toMap();
            if (store.value(QStringLiteral("id")).toString() == selected_store_id_)
                return store.value(QStringLiteral("name")).toString();
        }
        return QString();
    };

    QString name = findName(stores_);
    if (name.isEmpty())
        name = findName(managed_stores_);
    return name;
}

void RentalManager::assignSystemStore(const QString &storeId)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setSelectedStoreId(storeId);
    QSettings settings;
    if (selected_store_id_.isEmpty())
        settings.remove(QStringLiteral("rental/assigned_store_id"));
    else
        settings.setValue(QStringLiteral("rental/assigned_store_id"), selected_store_id_);
    settings.sync();
    setAdminError(QString());
    emit controllerAdminDataSaved();
}

void RentalManager::loadPricing()
{
    if (!configured()) {
        setError(tr("Service is not available."));
        return;
    }
    postFunction(RequestKind::Pricing, QStringLiteral("createPaymentOrder"), {{"mode", "pricing"}});
}

void RentalManager::checkAvailability(const QVariantList &discovered)
{
    if (!configured()) {
        setAvailability(false, false, 0);
        return;
    }
    setError(QString());
    setState(QStringLiteral("checking_availability"));
    postFunction(RequestKind::Availability, QStringLiteral("checkAvailability"), {
        {"discovered", discovered},
    });
}

void RentalManager::reserveConsole(const QVariantList &discovered)
{
    if (!configured()) {
        setError(tr("Service is not available."));
        return;
    }
    if (busy_)
        return;
    if (availability_checked_ && !console_available_) {
        setState(QStringLiteral("idle"));
        emit noConsoleAvailable();
        return;
    }
    setError(QString());
    setWarning(QString());
    setState(QStringLiteral("reserving"));
    postFunction(RequestKind::Reserve, QStringLiteral("reserveConsole"), {
        {"discovered", discovered},
    });
}

void RentalManager::releaseReservation()
{
    if (reservation_id_.isEmpty())
        return;
    postFunction(RequestKind::ReleaseReservation, QStringLiteral("releaseReservation"), {
        {"reservation_id", reservation_id_},
    });
}

void RentalManager::createPaymentOrder(const QString &timePlanId)
{
    if (reservation_id_.isEmpty()) {
        setError(tr("No active reservation."));
        return;
    }
    if (selected_store_id_.isEmpty() || timePlanId.isEmpty()) {
        setError(tr("This system is not assigned to a store."));
        return;
    }
    if (!test_payment_bypass_ && razorpay_key_id_.isEmpty()) {
        setError(tr("Payment is not configured."));
        return;
    }
    pending_extension_ = false;
    setPaymentHtml(QString());
    setState(QStringLiteral("creating_payment"));
    postFunction(RequestKind::CreatePayment, QStringLiteral("createPaymentOrder"), {
        {"reservation_id", reservation_id_},
        {"store_id", selected_store_id_},
        {"time_plan_id", timePlanId},
        {"test_payment", test_payment_bypass_},
    });
}

void RentalManager::extendSession(const QString &timePlanId)
{
    if (active_session_id_.isEmpty()) {
        setError(tr("No active session to extend."));
        return;
    }
    const QString storeId = active_session_.value(QStringLiteral("store_id"), selected_store_id_).toString();
    if (storeId.isEmpty() || timePlanId.isEmpty()) {
        setError(tr("Select a time plan."));
        return;
    }
    if (!test_payment_bypass_ && razorpay_key_id_.isEmpty()) {
        setError(tr("Payment is not configured."));
        return;
    }
    pending_extension_ = true;
    setPaymentHtml(QString());
    setState(QStringLiteral("creating_extension_payment"));
    postFunction(RequestKind::ExtendPayment, QStringLiteral("extendSession"), {
        {"session_id", active_session_id_},
        {"store_id", storeId},
        {"time_plan_id", timePlanId},
        {"test_payment", test_payment_bypass_},
    });
}

void RentalManager::verifyPayment(const QString &razorpayPaymentId,
                                  const QString &razorpayOrderId,
                                  const QString &razorpaySignature)
{
    if (pending_payment_id_.isEmpty()) {
        setError(tr("No pending payment to verify."));
        return;
    }
    setState(QStringLiteral("verifying_payment"));
    postFunction(RequestKind::VerifyPayment, QStringLiteral("verifyPayment"), {
        {"payment_id", pending_payment_id_},
        {"razorpay_payment_id", razorpayPaymentId},
        {"razorpay_order_id", razorpayOrderId},
        {"razorpay_signature", razorpaySignature},
    });
}

void RentalManager::endSession()
{
    if (active_session_id_.isEmpty()) {
        resetSessionState();
        return;
    }
    postFunction(RequestKind::EndSession, QStringLiteral("endSession"), {
        {"session_id", active_session_id_},
    });
}

void RentalManager::heartbeat()
{
    if (active_session_id_.isEmpty())
        return;
    postFunction(RequestKind::Heartbeat, QStringLiteral("heartbeat"), {
        {"session_id", active_session_id_},
    });
}

void RentalManager::clearPayment()
{
    setPaymentHtml(QString());
    pending_payment_id_.clear();
    if (!pending_extension_ && !reservation_id_.isEmpty())
        releaseReservation();
    pending_extension_ = false;
}

void RentalManager::clearWarning()
{
    setWarning(QString());
}

void RentalManager::verifyControllerPin(const QString &pin)
{
    if (!controllerAdminConfigured()) {
        setAdminError(tr("Management access is not configured."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::VerifyControllerPin, QStringLiteral("verifyControllerPin"), {
        {"pin", pin},
    });
}

void RentalManager::controllerAdminLogout()
{
    if (controller_admin_token_.isEmpty())
        return;
    controller_admin_token_.clear();
    discovered_admin_consoles_.clear();
    managed_consoles_.clear();
    managed_stores_.clear();
    managed_time_plans_.clear();
    managed_pricing_.clear();
    emit controllerAdminAuthenticatedChanged();
    emit discoveredAdminConsolesChanged();
    emit managedConsolesChanged();
    emit managedStoresChanged();
    emit managedTimePlansChanged();
    emit managedPricingChanged();
}

void RentalManager::updateControllerPin(const QString &newPin)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::UpdateControllerPin, QStringLiteral("updateControllerPin"), {
        {"admin_token", controller_admin_token_},
        {"new_pin", newPin},
    });
}

void RentalManager::listDiscoveredConsoles(const QVariantList &discovered)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::ListDiscoveredConsoles, QStringLiteral("listDiscoveredConsoles"), {
        {"admin_token", controller_admin_token_},
        {"discovered", discovered},
    });
}

void RentalManager::listManagedConsoles()
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::ListManagedConsoles, QStringLiteral("listManagedConsoles"), {
        {"admin_token", controller_admin_token_},
    });
}

void RentalManager::addConsole(const QVariantMap &console)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = console;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::AddConsole, QStringLiteral("addConsole"), payload);
}

void RentalManager::updateConsole(const QVariantMap &console)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = console;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::UpdateConsole, QStringLiteral("updateConsole"), payload);
}

void RentalManager::setManualConsoleAvailability(const QVariantMap &availability)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = availability;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::SetManualConsoleAvailability,
                 QStringLiteral("setManualConsoleAvailability"),
                 payload);
}

void RentalManager::removeConsole(const QString &consoleId)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::RemoveConsole, QStringLiteral("removeConsole"), {
        {"admin_token", controller_admin_token_},
        {"id", consoleId},
    });
}

void RentalManager::listStores()
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::ListStores, QStringLiteral("listStores"), {
        {"admin_token", controller_admin_token_},
    });
}

void RentalManager::saveStore(const QVariantMap &store)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = store;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::SaveStore, QStringLiteral("saveStore"), payload);
}

void RentalManager::removeStore(const QString &storeId)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::RemoveStore, QStringLiteral("removeStore"), {
        {"admin_token", controller_admin_token_},
        {"id", storeId},
    });
}

void RentalManager::listTimePlans()
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::ListTimePlans, QStringLiteral("listTimePlans"), {
        {"admin_token", controller_admin_token_},
    });
}

void RentalManager::saveTimePlan(const QVariantMap &timePlan)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = timePlan;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::SaveTimePlan, QStringLiteral("saveTimePlan"), payload);
}

void RentalManager::removeTimePlan(const QString &timePlanId)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::RemoveTimePlan, QStringLiteral("removeTimePlan"), {
        {"admin_token", controller_admin_token_},
        {"id", timePlanId},
    });
}

void RentalManager::listPricingRules()
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::ListPricingRules, QStringLiteral("listPricingRules"), {
        {"admin_token", controller_admin_token_},
    });
}

void RentalManager::savePricingRule(const QVariantMap &pricingRule)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    QVariantMap payload = pricingRule;
    payload.insert(QStringLiteral("admin_token"), controller_admin_token_);
    setAdminError(QString());
    postFunction(RequestKind::SavePricingRule, QStringLiteral("savePricingRule"), payload);
}

void RentalManager::removePricingRule(const QString &pricingRuleId)
{
    if (!controllerAdminAuthenticated()) {
        setAdminError(tr("Access code required."));
        return;
    }
    setAdminError(QString());
    postFunction(RequestKind::RemovePricingRule, QStringLiteral("removePricingRule"), {
        {"admin_token", controller_admin_token_},
        {"id", pricingRuleId},
    });
}

QString RentalManager::priceLabel(const QString &storeId, const QString &timePlanId) const
{
    for (const QVariant &item : pricing_) {
        const QVariantMap price = item.toMap();
        if (price.value(QStringLiteral("store_id")).toString() != storeId
            || price.value(QStringLiteral("time_plan_id")).toString() != timePlanId
            || !price.value(QStringLiteral("active"), true).toBool())
            continue;
        const int amount = price.value(QStringLiteral("amount_paise")).toInt();
        const QString currency = price.value(QStringLiteral("currency"), QStringLiteral("INR")).toString();
        return QStringLiteral("%1 %2").arg(currency).arg(amount / 100.0, 0, 'f', 2);
    }
    return tr("Unavailable");
}

QString RentalManager::timePlanLabel(const QVariantMap &timePlan) const
{
    const QString name = timePlan.value(QStringLiteral("name")).toString();
    if (!name.isEmpty())
        return name;

    const int minutes = timePlan.value(QStringLiteral("duration_minutes")).toInt();
    if (minutes <= 0)
        return tr("Time Plan");
    const int hours = minutes / 60;
    const int remainingMinutes = minutes % 60;
    if (hours > 0 && remainingMinutes > 0)
        return tr("%1h %2m").arg(hours).arg(remainingMinutes);
    if (hours > 0)
        return tr("%1h").arg(hours);
    return tr("%1m").arg(minutes);
}

QVariantList RentalManager::availableTimePlansForStore(const QString &storeId) const
{
    QSet<QString> pricedPlanIds;
    for (const QVariant &item : pricing_) {
        const QVariantMap price = item.toMap();
        if (price.value(QStringLiteral("store_id")).toString() == storeId
            && price.value(QStringLiteral("active"), true).toBool()
            && price.value(QStringLiteral("amount_paise")).toInt() > 0) {
            pricedPlanIds.insert(price.value(QStringLiteral("time_plan_id")).toString());
        }
    }

    QVariantList out;
    for (const QVariant &item : time_plans_) {
        const QVariantMap plan = item.toMap();
        if (plan.value(QStringLiteral("active"), true).toBool()
            && pricedPlanIds.contains(plan.value(QStringLiteral("id")).toString())) {
            out.append(item);
        }
    }
    return out;
}

void RentalManager::setBusy(bool busy)
{
    if (busy_ == busy)
        return;
    busy_ = busy;
    emit busyChanged();
}

void RentalManager::setAdminBusy(bool busy)
{
    if (admin_busy_ == busy)
        return;
    admin_busy_ = busy;
    emit adminBusyChanged();
}

void RentalManager::setState(const QString &state)
{
    if (state_ == state)
        return;
    state_ = state;
    emit stateChanged();
}

void RentalManager::setAdminError(const QString &error)
{
    if (admin_error_ == error)
        return;
    admin_error_ = error;
    emit adminErrorChanged();
}

void RentalManager::setError(const QString &error)
{
    if (error_ == error)
        return;
    error_ = error;
    emit errorChanged();
}

void RentalManager::setAvailability(bool checked, bool available, int count)
{
    if (availability_checked_ == checked
        && console_available_ == available
        && available_console_count_ == count) {
        return;
    }
    availability_checked_ = checked;
    console_available_ = available;
    available_console_count_ = count;
    emit availabilityChanged();
}

void RentalManager::setWarning(const QString &warning)
{
    if (warning_ == warning)
        return;
    warning_ = warning;
    emit warningChanged();
}

void RentalManager::setPaymentHtml(const QString &html)
{
    if (payment_html_ == html)
        return;
    payment_html_ = html;
    emit paymentHtmlChanged();
}

void RentalManager::setActiveSession(const QVariantMap &session)
{
    active_session_ = session;
    active_session_id_ = session.value(QStringLiteral("id")).toString();
    const QString sessionStoreId = session.value(QStringLiteral("store_id")).toString();
    if (!sessionStoreId.isEmpty())
        setSelectedStoreId(sessionStoreId);
    session_ends_at_ = parseUtc(session.value(QStringLiteral("ends_at")));
    grace_ends_at_ = parseUtc(session.value(QStringLiteral("grace_ends_at")));
    emit activeSessionChanged();
    updateCountdown();
}

void RentalManager::setAssignedConsole(const QVariantMap &console)
{
    assigned_console_ = console;
    emit assignedConsoleChanged();
}

void RentalManager::setReservationId(const QString &reservationId)
{
    if (reservation_id_ == reservationId)
        return;
    reservation_id_ = reservationId;
    emit reservationChanged();
}

void RentalManager::clearReservation()
{
    setReservationId(QString());
}

void RentalManager::releaseReservationBlocking()
{
    if (reservation_id_.isEmpty() || !active_session_id_.isEmpty() || !configured())
        return;

    QUrl url(functionUrl(QStringLiteral("releaseReservation")));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Authorization", authHeader().toUtf8());
    request.setRawHeader("apikey", supabase_anon_key_.toUtf8());

    const QByteArray body = QJsonDocument::fromVariant(QVariantMap{
        {QStringLiteral("reservation_id"), reservation_id_},
    }).toJson(QJsonDocument::Compact);

    QNetworkAccessManager manager;
    QNetworkReply *reply = manager.post(request, body);
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeout.start(1500);
    loop.exec();
    if (!reply->isFinished())
        reply->abort();
    reply->deleteLater();
}

void RentalManager::resetSessionState()
{
    stopSessionTimers();
    active_session_id_.clear();
    active_session_.clear();
    assigned_console_.clear();
    session_ends_at_ = {};
    grace_ends_at_ = {};
    remaining_seconds_ = 0;
    grace_remaining_seconds_ = 0;
    in_grace_period_ = false;
    setWarning(QString());
    setState(QStringLiteral("idle"));
    emit activeSessionChanged();
    emit assignedConsoleChanged();
    emit remainingSecondsChanged();
    emit graceRemainingSecondsChanged();
    emit inGracePeriodChanged();
}

void RentalManager::postFunction(RequestKind kind, const QString &functionName, const QVariantMap &payload)
{
    QUrl url(functionUrl(functionName));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Authorization", authHeader().toUtf8());
    request.setRawHeader("apikey", supabase_anon_key_.toUtf8());

    QNetworkReply *reply = network_.post(request, QJsonDocument::fromVariant(payload).toJson(QJsonDocument::Compact));
    replies_.insert(reply, kind);
    reply_names_.insert(reply, functionName);

    QTimer *timeoutTimer = new QTimer(reply);
    timeoutTimer->setSingleShot(true);
    connect(timeoutTimer, &QTimer::timeout, reply, [reply]() {
        if (!reply->isFinished()) {
            reply->setProperty("timed_out", true);
            reply->abort();
        }
    });
    timeoutTimer->start(kRequestTimeoutMs);

    if (isAdminRequest(kind))
        setAdminBusy(true);
    else if (kind != RequestKind::Heartbeat && kind != RequestKind::Availability)
        setBusy(true);
}

bool RentalManager::isAdminRequest(RequestKind kind) const
{
    switch (kind) {
    case RequestKind::VerifyControllerPin:
    case RequestKind::UpdateControllerPin:
    case RequestKind::ListDiscoveredConsoles:
    case RequestKind::AddConsole:
    case RequestKind::UpdateConsole:
    case RequestKind::SetManualConsoleAvailability:
    case RequestKind::RemoveConsole:
    case RequestKind::ListManagedConsoles:
    case RequestKind::ListStores:
    case RequestKind::SaveStore:
    case RequestKind::RemoveStore:
    case RequestKind::ListTimePlans:
    case RequestKind::SaveTimePlan:
    case RequestKind::RemoveTimePlan:
    case RequestKind::ListPricingRules:
    case RequestKind::SavePricingRule:
    case RequestKind::RemovePricingRule:
        return true;
    default:
        return false;
    }
}

void RentalManager::onReplyFinished(QNetworkReply *reply)
{
    const RequestKind kind = replies_.take(reply);
    const QString functionName = reply_names_.take(reply);
    const QByteArray body = reply->readAll();
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const bool timedOut = reply->property("timed_out").toBool();

    if (isAdminRequest(kind))
        setAdminBusy(false);
    else if (kind != RequestKind::Heartbeat && kind != RequestKind::Availability)
        setBusy(false);

    if (reply->error() != QNetworkReply::NoError) {
        handleFailure(kind, timedOut ? tr("Request timed out") : reply->errorString(), statusCode);
        reply->deleteLater();
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        handleFailure(kind, tr("Invalid response from %1").arg(functionName), statusCode);
        reply->deleteLater();
        return;
    }

    const QVariantMap response = objectToMap(doc.object());
    if (statusCode >= 400 || response.value(QStringLiteral("error")).toBool()) {
        handleFailure(kind, response.value(QStringLiteral("message"), tr("Request failed.")).toString(), statusCode);
        reply->deleteLater();
        return;
    }

    handleSuccess(kind, response);
    reply->deleteLater();
}

void RentalManager::handleSuccess(RequestKind kind, const QVariantMap &response)
{
    switch (kind) {
    case RequestKind::Pricing:
        pricing_ = response.value(QStringLiteral("pricing")).toList();
        stores_ = response.value(QStringLiteral("stores")).toList();
        time_plans_ = response.value(QStringLiteral("time_plans")).toList();
        test_payment_bypass_ = test_payment_bypass_ || response.value(QStringLiteral("test_payment_bypass")).toBool();
        emit pricingChanged();
        emit storesChanged();
        emit timePlansChanged();
        emit selectedStoreNameChanged();
        break;
    case RequestKind::Availability: {
        const int count = response.value(QStringLiteral("available_count")).toInt();
        setAvailability(true, response.value(QStringLiteral("available")).toBool() && count > 0, count);
        pricing_ = response.value(QStringLiteral("pricing")).toList();
        stores_ = response.value(QStringLiteral("stores")).toList();
        time_plans_ = response.value(QStringLiteral("time_plans")).toList();
        test_payment_bypass_ = test_payment_bypass_ || response.value(QStringLiteral("test_payment_bypass")).toBool();
        emit pricingChanged();
        emit storesChanged();
        emit timePlansChanged();
        emit selectedStoreNameChanged();
        if (state_ == QStringLiteral("checking_availability"))
            setState(QStringLiteral("idle"));
        break;
    }
    case RequestKind::Reserve: {
        const QVariantMap reservation = response.value(QStringLiteral("reservation")).toMap();
        const QString reservationId = reservation.value(QStringLiteral("id")).toString();
        if (reservationId.isEmpty()) {
            setAvailability(true, false, 0);
            setState(QStringLiteral("idle"));
            emit noConsoleAvailable();
            break;
        }
        setReservationId(reservationId);
        const QVariantMap console = response.value(QStringLiteral("console")).toMap();
        if (!preflightAssignedConsole(console)) {
            setState(QStringLiteral("error"));
            releaseReservation();
            break;
        }
        const int remainingAvailable = qMax(0, available_console_count_ - 1);
        setAvailability(true, remainingAvailable > 0, remainingAvailable);
        pricing_ = response.value(QStringLiteral("pricing")).toList();
        stores_ = response.value(QStringLiteral("stores")).toList();
        time_plans_ = response.value(QStringLiteral("time_plans")).toList();
        test_payment_bypass_ = test_payment_bypass_ || response.value(QStringLiteral("test_payment_bypass")).toBool();
        emit pricingChanged();
        emit storesChanged();
        emit timePlansChanged();
        emit selectedStoreNameChanged();
        setState(QStringLiteral("reserved"));
        emit reservationReady();
        break;
    }
    case RequestKind::ReleaseReservation:
        clearReservation();
        if (state_ != QStringLiteral("active") && state_ != QStringLiteral("error")) {
            setState(QStringLiteral("idle"));
            checkAvailability();
        }
        break;
    case RequestKind::CreatePayment:
    case RequestKind::ExtendPayment: {
        const QVariantMap testSession = response.value(QStringLiteral("session")).toMap();
        if (!testSession.isEmpty()) {
            setPaymentHtml(QString());
            pending_payment_id_.clear();
            if (!pending_extension_)
                clearReservation();
            setActiveSession(testSession);
            setAssignedConsole(response.value(QStringLiteral("console")).toMap());
            startSessionTimers();
            setState(QStringLiteral("active"));
            const int remainingAvailable = qMax(0, available_console_count_ - 1);
            setAvailability(true, remainingAvailable > 0, remainingAvailable);
            if (!pending_extension_)
                emit consoleAssigned(assigned_console_);
            pending_extension_ = false;
            break;
        }

        const QVariantMap payment = response.value(QStringLiteral("payment")).toMap();
        const QVariantMap order = response.value(QStringLiteral("order")).toMap();
        pending_payment_id_ = payment.value(QStringLiteral("id")).toString();
        setPaymentHtml(buildPaymentHtml(payment, order));
        setState(QStringLiteral("awaiting_payment"));
        break;
    }
    case RequestKind::VerifyPayment: {
        setPaymentHtml(QString());
        pending_payment_id_.clear();
        clearReservation();
        setActiveSession(response.value(QStringLiteral("session")).toMap());
        setAssignedConsole(response.value(QStringLiteral("console")).toMap());
        startSessionTimers();
        setState(QStringLiteral("active"));
        const int remainingAvailable = qMax(0, available_console_count_ - 1);
        setAvailability(true, remainingAvailable > 0, remainingAvailable);
        if (!pending_extension_)
            emit consoleAssigned(assigned_console_);
        pending_extension_ = false;
        break;
    }
    case RequestKind::EndSession:
        resetSessionState();
        checkAvailability();
        break;
    case RequestKind::Heartbeat: {
        const QVariantMap session = response.value(QStringLiteral("session")).toMap();
        if (!session.isEmpty())
            setActiveSession(session);
        const QString sessionState = session.value(QStringLiteral("status")).toString();
        if (sessionState == QStringLiteral("completed") || sessionState == QStringLiteral("disconnected")) {
            emit stopRemotePlayRequested();
            resetSessionState();
        }
        break;
    }
    case RequestKind::VerifyControllerPin:
        controller_admin_token_ = response.value(QStringLiteral("admin_token")).toString();
        emit controllerAdminAuthenticatedChanged();
        emit controllerPinVerified();
        break;
    case RequestKind::UpdateControllerPin:
        break;
    case RequestKind::ListDiscoveredConsoles:
        discovered_admin_consoles_ = response.value(QStringLiteral("consoles")).toList();
        emit discoveredAdminConsolesChanged();
        break;
    case RequestKind::AddConsole:
    case RequestKind::UpdateConsole:
        emit controllerConsoleSaved();
        listManagedConsoles();
        break;
    case RequestKind::SetManualConsoleAvailability:
        emit manualConsoleAvailabilitySaved();
        listManagedConsoles();
        break;
    case RequestKind::RemoveConsole:
        emit controllerConsoleRemoved();
        listManagedConsoles();
        break;
    case RequestKind::ListManagedConsoles:
        managed_consoles_ = response.value(QStringLiteral("consoles")).toList();
        emit managedConsolesChanged();
        break;
    case RequestKind::ListStores:
        managed_stores_ = response.value(QStringLiteral("stores")).toList();
        stores_ = managed_stores_;
        emit managedStoresChanged();
        emit storesChanged();
        emit selectedStoreNameChanged();
        break;
    case RequestKind::ListTimePlans:
        managed_time_plans_ = response.value(QStringLiteral("time_plans")).toList();
        time_plans_ = managed_time_plans_;
        emit managedTimePlansChanged();
        emit timePlansChanged();
        break;
    case RequestKind::ListPricingRules:
        managed_pricing_ = response.value(QStringLiteral("pricing")).toList();
        pricing_ = managed_pricing_;
        emit managedPricingChanged();
        emit pricingChanged();
        break;
    case RequestKind::SaveStore:
    case RequestKind::RemoveStore:
        if (kind == RequestKind::SaveStore)
            emit controllerAdminDataSaved();
        else
            emit controllerAdminDataRemoved();
        listStores();
        listPricingRules();
        break;
    case RequestKind::SaveTimePlan:
    case RequestKind::RemoveTimePlan:
        if (kind == RequestKind::SaveTimePlan)
            emit controllerAdminDataSaved();
        else
            emit controllerAdminDataRemoved();
        listTimePlans();
        listPricingRules();
        break;
    case RequestKind::SavePricingRule:
    case RequestKind::RemovePricingRule:
        if (kind == RequestKind::SavePricingRule)
            emit controllerAdminDataSaved();
        else
            emit controllerAdminDataRemoved();
        listPricingRules();
        break;
    }
}

void RentalManager::handleFailure(RequestKind kind, const QString &message, int statusCode)
{
    if (isAdminRequest(kind)) {
        QString accessMessage = message;
        if (message.contains(QStringLiteral("controller_admin"), Qt::CaseInsensitive)
            || message.contains(QStringLiteral("admin_token"), Qt::CaseInsensitive)) {
            accessMessage = tr("Access code is invalid or expired.");
        }
        if (statusCode == 401 && !controller_admin_token_.isEmpty()) {
            controller_admin_token_.clear();
            emit controllerAdminAuthenticatedChanged();
        }
        setAdminError(accessMessage);
        return;
    }

    if (kind == RequestKind::Reserve && statusCode == 409) {
        setAvailability(true, false, 0);
        setState(QStringLiteral("idle"));
        emit noConsoleAvailable();
        return;
    }
    if (kind == RequestKind::Availability) {
        setAvailability(true, false, 0);
        setError(message);
        if (state_ == QStringLiteral("checking_availability"))
            setState(QStringLiteral("idle"));
        return;
    }
    if ((kind == RequestKind::CreatePayment || kind == RequestKind::VerifyPayment) && !pending_extension_ && !reservation_id_.isEmpty())
        releaseReservation();
    setError(message);
    if (kind != RequestKind::Heartbeat)
        setState(QStringLiteral("error"));
}

bool RentalManager::preflightAssignedConsole(const QVariantMap &console)
{
    const QString host = hostAddressFromConsole(console);
    if (host.isEmpty()) {
        setError(tr("Console temporarily unavailable. Please contact staff. Error code: NXGS-CN-9295"));
        return false;
    }

    QTcpSocket socket;
    socket.connectToHost(host, 9295);
    if (socket.waitForConnected(kConsolePreflightTimeoutMs)) {
        socket.disconnectFromHost();
        return true;
    }

    qWarning() << "Rental console preflight failed before payment for"
               << console.value(QStringLiteral("name")).toString()
               << "at" << host << ":" << socket.errorString();
    setError(tr("Console temporarily unavailable. Please contact staff. Error code: NXGS-CN-9295"));
    return false;
}

void RentalManager::updateCountdown()
{
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const int oldRemaining = remaining_seconds_;
    const int oldGrace = grace_remaining_seconds_;
    const bool oldInGrace = in_grace_period_;

    remaining_seconds_ = session_ends_at_.isValid() ? qMax(0, static_cast<int>(now.secsTo(session_ends_at_))) : 0;
    in_grace_period_ = session_ends_at_.isValid() && grace_ends_at_.isValid() && now >= session_ends_at_ && now < grace_ends_at_;
    grace_remaining_seconds_ = in_grace_period_ ? qMax(0, static_cast<int>(now.secsTo(grace_ends_at_))) : 0;

    if (oldRemaining != remaining_seconds_)
        emit remainingSecondsChanged();
    if (oldGrace != grace_remaining_seconds_)
        emit graceRemainingSecondsChanged();
    if (oldInGrace != in_grace_period_)
        emit inGracePeriodChanged();

    if (oldRemaining > 600 && remaining_seconds_ <= 600)
        setWarning(tr("10 minutes remaining"));
    else if (oldRemaining > 300 && remaining_seconds_ <= 300)
        setWarning(tr("5 minutes remaining"));
    else if (oldRemaining > 60 && remaining_seconds_ <= 60)
        setWarning(tr("1 minute remaining"));

    if (active_session_id_.isEmpty() || !grace_ends_at_.isValid())
        return;

    if (now >= grace_ends_at_) {
        emit stopRemotePlayRequested();
        endSession();
    }
}

void RentalManager::startSessionTimers()
{
    if (!countdown_timer_.isActive())
        countdown_timer_.start();
    if (!heartbeat_timer_.isActive())
        heartbeat_timer_.start();
    startRealtime();
    QTimer::singleShot(0, this, &RentalManager::heartbeat);
}

void RentalManager::stopSessionTimers()
{
    countdown_timer_.stop();
    heartbeat_timer_.stop();
    stopRealtime();
}

void RentalManager::startRealtime()
{
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
    if (active_session_id_.isEmpty() || supabase_url_.isEmpty() || supabase_anon_key_.isEmpty())
        return;

    if (realtime_socket_.state() == QAbstractSocket::ConnectedState) {
        const QString ref = QString::number(realtime_ref_++);
        const QJsonObject join = {
            {"topic", "realtime:public:play_sessions"},
            {"event", "phx_join"},
            {"payload", QJsonObject{
                {"config", QJsonObject{
                    {"postgres_changes", QJsonArray{
                        QJsonObject{
                            {"event", "UPDATE"},
                            {"schema", "public"},
                            {"table", "play_sessions"},
                            {"filter", QStringLiteral("id=eq.%1").arg(active_session_id_)},
                        },
                    }},
                    {"broadcast", QJsonObject{{"self", false}}},
                    {"presence", QJsonObject()},
                }},
            }},
            {"ref", ref},
            {"join_ref", ref},
        };
        realtime_socket_.sendTextMessage(QString::fromUtf8(QJsonDocument(join).toJson(QJsonDocument::Compact)));
        return;
    }

    QString websocketUrl = supabase_url_;
    websocketUrl.replace(QRegularExpression(QStringLiteral("^https://")), QStringLiteral("wss://"));
    websocketUrl.replace(QRegularExpression(QStringLiteral("^http://")), QStringLiteral("ws://"));
    while (websocketUrl.endsWith('/'))
        websocketUrl.chop(1);
    websocketUrl += QStringLiteral("/realtime/v1/websocket?apikey=%1&vsn=1.0.0").arg(QString::fromUtf8(QUrl::toPercentEncoding(supabase_anon_key_)));
    realtime_socket_.open(QUrl(websocketUrl));
#endif
}

void RentalManager::stopRealtime()
{
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
    if (realtime_socket_.state() != QAbstractSocket::UnconnectedState)
        realtime_socket_.close();
#endif
}

void RentalManager::handleRealtimeMessage(const QString &message)
{
#ifdef CHIAKI_HAVE_QT_WEBSOCKETS
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject())
        return;

    const QJsonObject object = doc.object();
    if (object.value(QStringLiteral("event")).toString() != QStringLiteral("postgres_changes"))
        return;

    const QJsonObject record = object
        .value(QStringLiteral("payload")).toObject()
        .value(QStringLiteral("data")).toObject()
        .value(QStringLiteral("record")).toObject();
    if (record.isEmpty())
        return;

    const QVariantMap session = objectToMap(record);
    if (session.value(QStringLiteral("id")).toString() != active_session_id_)
        return;

    setActiveSession(session);
    const QString sessionState = session.value(QStringLiteral("status")).toString();
    if (sessionState == QStringLiteral("completed") || sessionState == QStringLiteral("disconnected")) {
        emit stopRemotePlayRequested();
        resetSessionState();
    }
#else
    Q_UNUSED(message);
#endif
}

QDateTime RentalManager::parseUtc(const QVariant &value) const
{
    QDateTime parsed = QDateTime::fromString(value.toString(), Qt::ISODateWithMs);
    if (!parsed.isValid())
        parsed = QDateTime::fromString(value.toString(), Qt::ISODate);
    if (parsed.isValid())
        parsed = parsed.toUTC();
    return parsed;
}

QString RentalManager::buildPaymentHtml(const QVariantMap &payment, const QVariantMap &order) const
{
    const QString orderId = order.value(QStringLiteral("id")).toString();
    const QString amount = QString::number(order.value(QStringLiteral("amount")).toInt());
    const QString currency = order.value(QStringLiteral("currency"), QStringLiteral("INR")).toString();
    const QString description = payment.value(QStringLiteral("kind")).toString() == QStringLiteral("extension")
        ? tr("NXGS session extension")
        : tr("NXGS PS5 session");

    return QStringLiteral(R"(
<!doctype html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"><style>
body{margin:0;background:#101317;color:#fff;font-family:Arial,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh}
.box{text-align:center}.hint{opacity:.7;margin-top:12px}
</style></head>
<body>
<div class="box"><h2>Opening Razorpay...</h2><div class="hint">Keep this window open until payment finishes.</div></div>
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
var options = {
  key: "%1",
  amount: "%2",
  currency: "%3",
  name: "NXGS",
  description: "%4",
  order_id: "%5",
  handler: function (response) {
    location.href = "nxgs://razorpay-success?razorpay_payment_id=" + encodeURIComponent(response.razorpay_payment_id)
      + "&razorpay_order_id=" + encodeURIComponent(response.razorpay_order_id)
      + "&razorpay_signature=" + encodeURIComponent(response.razorpay_signature);
  },
  modal: {
    ondismiss: function () {
      location.href = "nxgs://razorpay-cancelled";
    }
  },
  theme: { color: "#00a7ff" }
};
var checkout = new Razorpay(options);
checkout.open();
</script>
</body>
</html>
)").arg(htmlEscape(razorpay_key_id_),
       htmlEscape(amount),
       htmlEscape(currency),
       htmlEscape(description),
       htmlEscape(orderId));
}

QString RentalManager::functionUrl(const QString &functionName) const
{
    QString base = function_base_url_;
    while (base.endsWith('/'))
        base.chop(1);
    return base + QStringLiteral("/") + functionName;
}

QString RentalManager::authHeader() const
{
    return QStringLiteral("Bearer %1").arg(supabase_anon_key_);
}
