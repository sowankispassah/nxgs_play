#pragma once

#include "controllermanager.h"

class QTimer;

class QmlController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool dualSense READ isDualSense CONSTANT)
    Q_PROPERTY(bool handheld READ isHandheld CONSTANT)
    Q_PROPERTY(bool steamVirtual READ isSteamVirtual CONSTANT)
    Q_PROPERTY(bool dualSenseEdge READ isDualSenseEdge CONSTANT)
    Q_PROPERTY(bool playStation READ isPS CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)

public:
    QmlController(Controller *controller, uint32_t shortcut, QObject *target, QObject *parent = nullptr);
    ~QmlController();

    bool isDualSense() const;
    bool isHandheld() const;
    bool isSteamVirtual() const;
    bool isDualSenseEdge() const;
    bool isPS() const;
    QString name() const;
    void setEscapeShortcut(uint32_t shortcut) { escape_shortcut = shortcut; };
    QString GetGUID() const;
    QString GetVIDPID() const;

signals:
    void inputActivity();

private:
    bool sendKey(Qt::Key key, Qt::KeyboardModifiers modifiers = Qt::NoModifier);

    QObject *target = {};
    uint32_t escape_shortcut = 0;
    uint32_t old_buttons = 0;
    uint32_t analog_navigation_button = 0;
    uint32_t activity_buttons = 0;
    uint8_t activity_l2 = 0;
    uint8_t activity_r2 = 0;
    int16_t activity_left_x = 0;
    int16_t activity_left_y = 0;
    int16_t activity_right_x = 0;
    int16_t activity_right_y = 0;
    Controller *controller = {};
    QTimer *repeat_timer = {};
    int repeat_running = 0;
    Qt::Key pressed_key = Qt::Key_unknown;
};
