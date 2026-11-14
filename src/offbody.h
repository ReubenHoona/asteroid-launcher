/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef OFFBODY_H
#define OFFBODY_H

#include <QDBusConnection>
#include <QObject>

class QDBusServiceWatcher;

/*
 * Whether the watch is on the wrist: the sensor hub's low-latency off-body
 * sensor (usf type 0x32), as sensorfwd's usf plugin offers it on the system bus
 * (W2-launcher-ambient: choice-settings-07, wake-sleep-display-18):
 *
 *   service  com.nokia.SensorService, object /org/eos/usfhub,
 *   interface org.eos.UsfHub
 *   method   GetOffBody() -> int   -1 unknown (no sensor, hub not up), 0 on the
 *                                  wrist, 1 off the wrist
 *   signal   OffBodyChanged(int)   the same values, on change only
 *
 * The sensor is on-change: nothing here polls, and no timer runs. The state is
 * read once at start and when the service appears (sensorfwd restarted), then
 * follows the signal. Context property `offBody` of the launcher:
 * `known` and `offBody` (true off the wrist).
 */
class OffBody : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool known READ known NOTIFY changed)
    Q_PROPERTY(bool offBody READ offBody NOTIFY changed)
    Q_PROPERTY(int state READ state NOTIFY changed)

public:
    explicit OffBody(QObject *parent = nullptr,
                     const QDBusConnection &bus = QDBusConnection::systemBus());

    // -1 unknown, 0 on the wrist, 1 off the wrist
    int state() const { return m_state; }
    bool known() const { return m_state >= 0; }
    bool offBody() const { return m_state == 1; }

    static constexpr const char *Service = "com.nokia.SensorService";
    static constexpr const char *Path = "/org/eos/usfhub";
    static constexpr const char *Interface = "org.eos.UsfHub";

signals:
    void changed();

private slots:
    void onSignal(int state);
    void refresh();
    void serviceGone();

private:
    void set(int state);

    QDBusConnection m_bus;
    QDBusServiceWatcher *m_watcher;
    int m_state = -1;
};

#endif // OFFBODY_H
