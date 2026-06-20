#include "qmlcontroller.h"

#include <QTimer>
#include <QKeyEvent>
#include <QDateTime>
#include <QHash>
#include <QStyleHints>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <cstdlib>

static const QVector<QPair<uint32_t, Qt::Key>> customer_navigation_key_map = {
    { CHIAKI_CONTROLLER_BUTTON_DPAD_UP, Qt::Key_Up },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN, Qt::Key_Down },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT, Qt::Key_Left },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT, Qt::Key_Right },
    { CHIAKI_CONTROLLER_BUTTON_CROSS, Qt::Key_Return },
    { CHIAKI_CONTROLLER_BUTTON_MOON, Qt::Key_Escape },
};

static const QVector<QPair<uint32_t, Qt::Key>> streaming_key_map = {
    { CHIAKI_CONTROLLER_BUTTON_DPAD_UP, Qt::Key_Up },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN, Qt::Key_Down },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT, Qt::Key_Left },
    { CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT, Qt::Key_Right },
    { CHIAKI_CONTROLLER_BUTTON_CROSS, Qt::Key_Return },
    { CHIAKI_CONTROLLER_BUTTON_MOON, Qt::Key_Escape },
    { CHIAKI_CONTROLLER_BUTTON_BOX, Qt::Key_No },
    { CHIAKI_CONTROLLER_BUTTON_PYRAMID, Qt::Key_Yes },
    { CHIAKI_CONTROLLER_BUTTON_L1, Qt::Key_PageUp },
    { CHIAKI_CONTROLLER_BUTTON_R1, Qt::Key_PageDown },
    { CHIAKI_CONTROLLER_BUTTON_OPTIONS, Qt::Key_Menu },
    { CHIAKI_CONTROLLER_BUTTON_L3, Qt::Key_F1},
    { CHIAKI_CONTROLLER_BUTTON_R3, Qt::Key_F2},
};

QmlController::QmlController(Controller *c, uint32_t shortcut, QObject *t, QObject *parent)
    : QObject(parent)
    , target(t)
    , escape_shortcut(shortcut)
    , controller(c)
{
    repeat_timer = new QTimer(this);
    connect(repeat_timer, &QTimer::timeout, this, [this]() {
        if (!repeat_running++)
            repeat_timer->start(80);
        sendKey(pressed_key);
        if (repeat_running == 50)
            repeat_timer->stop();
    });

    connect(controller, &Controller::StateChanged, this, [this]() {
        auto state = controller->GetState();
        auto buttons = state.buttons;
        const auto stick_moved = [](int16_t current, int16_t previous) {
            return std::abs(static_cast<int>(current)) >= 5000
                && std::abs(static_cast<int>(current) - static_cast<int>(previous)) >= 2048;
        };
        const bool controller_activity =
            state.buttons != activity_buttons
            || std::abs(static_cast<int>(state.l2_state) - static_cast<int>(activity_l2)) >= 6
            || std::abs(static_cast<int>(state.r2_state) - static_cast<int>(activity_r2)) >= 6
            || stick_moved(state.left_x, activity_left_x)
            || stick_moved(state.left_y, activity_left_y)
            || stick_moved(state.right_x, activity_right_x)
            || stick_moved(state.right_y, activity_right_y);

        if (controller_activity) {
            activity_buttons = state.buttons;
            activity_l2 = state.l2_state;
            activity_r2 = state.r2_state;
            activity_left_x = state.left_x;
            activity_left_y = state.left_y;
            activity_right_x = state.right_x;
            activity_right_y = state.right_y;
            emit inputActivity();
        }

        if (std::abs(static_cast<int>(state.left_x)) < 5000)
            activity_left_x = state.left_x;
        if (std::abs(static_cast<int>(state.left_y)) < 5000)
            activity_left_y = state.left_y;
        if (std::abs(static_cast<int>(state.right_x)) < 5000)
            activity_right_x = state.right_x;
        if (std::abs(static_cast<int>(state.right_y)) < 5000)
            activity_right_y = state.right_y;

        const bool streaming = target && target->property("hasVideo").toBool();
        const auto &active_key_map = streaming ? streaming_key_map : customer_navigation_key_map;

        if (streaming) {
            analog_navigation_button = 0;
            if (state.left_x > 30000)
                buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT;
            else if (state.left_x < -30000)
                buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT;

            if (state.left_y > 30000)
                buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN;
            else if (state.left_y < -30000)
                buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_UP;
        } else {
            constexpr int analog_press_threshold = 20000;
            constexpr int analog_release_threshold = 9000;
            const int left_x = static_cast<int>(state.left_x);
            const int left_y = static_cast<int>(state.left_y);
            const int abs_x = std::abs(left_x);
            const int abs_y = std::abs(left_y);

            if (analog_navigation_button != 0) {
                if (abs_x <= analog_release_threshold
                    && abs_y <= analog_release_threshold) {
                    analog_navigation_button = 0;
                }
            } else if (abs_x >= analog_press_threshold
                       || abs_y >= analog_press_threshold) {
                // Select only the dominant axis so diagonal stick movement
                // cannot produce two navigation actions at once.
                if (abs_x > abs_y) {
                    analog_navigation_button = left_x > 0
                        ? CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT
                        : CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT;
                } else {
                    analog_navigation_button = left_y > 0
                        ? CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN
                        : CHIAKI_CONTROLLER_BUTTON_DPAD_UP;
                }
            }

            buttons |= analog_navigation_button;
        }

        for (const auto &k : active_key_map) {
            const bool pressed = buttons & k.first;
            const bool old_pressed = old_buttons & k.first;
            if (pressed && !old_pressed) {
                pressed_key = k.second;
                sendKey(pressed_key);
                repeat_running = 0;
                if (pressed_key == Qt::Key_Up
                    || pressed_key == Qt::Key_Down
                    || pressed_key == Qt::Key_Left
                    || pressed_key == Qt::Key_Right) {
                    repeat_timer->start(300);
                } else {
                    repeat_timer->stop();
                }
            } else if (old_pressed && !pressed && pressed_key == k.second) {
                repeat_timer->stop();
                repeat_running = 1;
            }
        }

        if (streaming
            && (old_buttons & escape_shortcut) == escape_shortcut
            && (buttons & escape_shortcut) != escape_shortcut) {
            sendKey(Qt::Key_O, Qt::ControlModifier);
        }

        old_buttons = buttons;
    });
}

QmlController::~QmlController()
{
    controller->Unref();
}

bool QmlController::isDualSense() const
{
    return controller->IsDualSense();
}

bool QmlController::isHandheld() const
{
    return controller->IsHandheld();
}

bool QmlController::isPS() const
{
    return controller->IsPS();
}

bool QmlController::isSteamVirtual() const
{
    return controller->IsSteamVirtual();
}

bool QmlController::isDualSenseEdge() const
{
    return controller->IsDualSenseEdge();
}

QString QmlController::name() const
{
    const QString controller_name = controller->GetType().trimmed();
    return controller_name.isEmpty() ? tr("Game Controller") : controller_name;
}

QString QmlController::GetGUID() const
{
    return controller->GetGUIDString();
}

QString QmlController::GetVIDPID() const
{
    return controller->GetVIDPIDString();
}

void QmlController::sendKey(Qt::Key key, Qt::KeyboardModifiers modifiers)
{
    // SDL2-compat/SDL3 on macOS can expose a single physical controller as
    // two devices, creating two QmlController instances that both fire for
    // the same button press. Deduplicate by VID:PID + key as a workaround
    // for the aliased SDL devices, but do not refresh the timestamp on
    // suppressed copies so held-button repeat can continue.
    static QHash<QString, qint64> last_key_time_by_device;
    const QString dedup_key = GetVIDPID() + QLatin1Char(':') + QString::number(static_cast<int>(key));
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 last_time = last_key_time_by_device.value(dedup_key, 0);
    if ((now - last_time) < 50)
        return;

    last_key_time_by_device.insert(dedup_key, now);

    QObject *receiver = target;
    if (target && !target->property("hasVideo").toBool()) {
        if (auto *window = qobject_cast<QQuickWindow *>(target)) {
            if (QQuickItem *focus_item = window->activeFocusItem())
                receiver = focus_item;
        }
    }
    if (!receiver)
        return;

    QKeyEvent press(QEvent::KeyPress, key, modifiers);
    QKeyEvent release(QEvent::KeyRelease, key, modifiers);
    QGuiApplication::sendEvent(receiver, &press);
    QGuiApplication::sendEvent(receiver, &release);
}
