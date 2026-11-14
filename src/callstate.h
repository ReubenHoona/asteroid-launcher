/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef CALLSTATE_H
#define CALLSTATE_H

#include <QDBusConnection>
#include <QObject>
#include <QString>

class MDConfItem;

/*
 * The state of the phone call as the launcher knows it (CR-03, CR-09), for the
 * apps that must stay quiet in a call (the alarm presenter silences its alert
 * while a call rings or is in progress) and for the Phone app. The value is
 * lipstickSettings.callState, set by IncomingCall.qml from the phone's call
 * notifications: 0 none, 1 ringing, 2 in progress. main.cpp hands every change
 * of LipstickSettings::callState to setState().
 *
 * On the session bus (the launcher's name org.asteroidos.launcher, CR-01),
 * object /org/asteroidos/launcher/call, interface org.asteroidos.launcher.Call:
 *   CallState() -> i        0 none, 1 ringing, 2 in progress
 *   signal CallStateChanged(i)   on every change (Nemo.DBus handler
 *                           rcCallStateChanged; declared Q_SCRIPTABLE and exported)
 * and the dconf key /org/asteroidos/phone/call-active (b): true while the state
 * is above 0, false at start (CR-09).
 * Nothing polls: a change of the state is the only trigger.
 */
class CallStateService : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.asteroidos.launcher.Call")
    Q_PROPERTY(int state READ state WRITE setState NOTIFY changed)

public:
    static constexpr const char *Path = "/org/asteroidos/launcher/call";
    static constexpr const char *ActiveKey = "/org/asteroidos/phone/call-active";

    /* activeKey: the dconf key that follows "a call is on"; empty: none (no dconf) */
    explicit CallStateService(QObject *parent = nullptr,
                              const QDBusConnection &bus = QDBusConnection::sessionBus(),
                              const QString &activeKey = QLatin1String(ActiveKey));

    int state() const { return mState; }
    // Anything outside 0..2 counts as 0 (no call)
    void setState(int state);

public slots:
    Q_SCRIPTABLE int CallState() const { return mState; }

signals:
    void changed();
    Q_SCRIPTABLE void CallStateChanged(int state);

private:
    int mState = 0;
    MDConfItem *mActive = nullptr;
};

#endif // CALLSTATE_H
