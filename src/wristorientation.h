/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef WRISTORIENTATION_H
#define WRISTORIENTATION_H

#include <QDBusConnection>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>

class QDBusServiceWatcher;

/*
 * The crown's sign after the flip (wrist-orientation-06): an event filter that turns the
 * compositor window's wheel events around once, so the compositor's own items (RotaryInput,
 * WheelHandler) and the clients the compositor forwards the wheel to
 * (lipstickcompositorwindow.cpp) see stock's direction: stock negates the crown scroll when the
 * display is rotated 180 (AOSP RotaryEncoderInputMapper::sync). The user's rotary-invert key stays
 * an extra inversion, applied by RotaryInput on top.
 *
 * It is installed on the application, not on the window: qml-asteroid's RotaryInput is an
 * application-level filter that consumes the window's wheel event, and Qt runs the application's
 * filters (newest installed first) before the window's own. attachWindow() therefore installs it
 * again each time it is called, which puts it in front of RotaryInput whatever was installed
 * since. It acts on the attached window only: Qt Quick's copies for the items pass the
 * application's filters too, and must not be turned a second time.
 */
class WristCrownFilter : public QObject
{
    Q_OBJECT
public:
    explicit WristCrownFilter(QObject *parent = nullptr) : QObject(parent) {}
    bool flip() const { return m_flip; }
    void setFlip(bool flip) { m_flip = flip; }
    // the one window whose wheel events are turned (null: none)
    void setWindow(QObject *window) { m_window = window; }
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    QPointer<QObject> m_window;
    bool m_flip = false;
    bool m_busy = false;        // the turned copy passes this filter again
};

/*
 * The wrist and crown setting of the launcher (W3-launcher-wrist). The mode (0..3, EosWrist in
 * lipstick/src/eoswrist.h) is read once, synchronously, before the compositor scene is loaded
 * (main.cpp), so the first frame is already turned (-14), and again when the dconf key changes
 * (-03). QML reads rotation (the compositor root's rotation, 0 or 180: -04), flip, crownLeft,
 * rightWrist and gestureXSign (-12). Nothing here runs on a timer.
 *
 * The sensor hub's wrist-orientation algorithms (tilt to wake, wrist gestures, off body) need
 * the mode too: the system bus method org.eos.UsfHub.SetWristOrientation(int) of sensorfwd
 * (com.nokia.SensorService, /org/eos/usfhub) is called at the start, on a change, and when the
 * service (re)appears on the bus. sensorfwd keeps the value for its next start.
 * It answers 0, 1 (kept, hub not connected) or -22 (out of range).
 */
class WristOrientation : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int mode READ mode NOTIFY changed)
    Q_PROPERTY(int rotation READ rotation NOTIFY changed)
    Q_PROPERTY(bool flip READ flip NOTIFY changed)
    Q_PROPERTY(bool crownLeft READ crownLeft NOTIFY changed)
    Q_PROPERTY(bool rightWrist READ rightWrist NOTIFY changed)
    Q_PROPERTY(int gestureXSign READ gestureXSign NOTIFY changed)

public:
    explicit WristOrientation(QObject *parent = nullptr,
                              const QDBusConnection &bus = QDBusConnection::systemBus(),
                              const QString &hubService = QStringLiteral("com.nokia.SensorService"));

    int mode() const { return m_mode; }
    int rotation() const;
    bool flip() const;
    bool crownLeft() const;
    bool rightWrist() const;
    int gestureXSign() const;

    // The stored value (any QVariant: an unreadable one is the default 0). start: the first call
    // at launch, which tells the hub even when the value is the default.
    void setMode(const QVariant &stored, bool start = false);

    // The compositor's window: its wheel events are turned while flipped (QML calls this once
    // the scene is in its window, after its imports, RotaryInput's among them, are loaded). The
    // filter goes on the application and to the front of its filters each time this is called.
    Q_INVOKABLE void attachWindow(QObject *window);

signals:
    // the mode changed
    void changed();
    // the picture turned (modes 0/2 <-> 1/3)
    void flipChanged();

private:
    void tellHub();

    int m_mode = 0;
    QDBusConnection m_bus;
    QString m_hubService;
    QDBusServiceWatcher *m_watcher = nullptr;
    WristCrownFilter m_filter;
    QPointer<QObject> m_window;
};

#endif // WRISTORIENTATION_H
