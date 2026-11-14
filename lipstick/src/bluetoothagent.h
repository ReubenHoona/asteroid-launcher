/*
 * Copyright (C) 2017 - Florent Revest <revestflo@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef BLUETOOTHAGENT_H
#define BLUETOOTHAGENT_H

#include <QObject>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusObjectPath>
#include <QDBusServiceWatcher>
#include <QDBusMessage>
#include <QTimer>

class BluetoothAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_ENUMS(State);
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
    Q_PROPERTY(bool windowVisible READ windowVisible WRITE setWindowVisible NOTIFY windowVisibleChanged)

    Q_PROPERTY(State state READ getState NOTIFY stateChanged)
    Q_PROPERTY(QString pinCode READ getPinCode WRITE setPinCode NOTIFY pinCodeChanged)
    Q_PROPERTY(quint32 passkey READ getPasskey WRITE setPasskey NOTIFY passkeyChanged)
    // The device asking: its alias (never its address; empty until BlueZ has answered) and
    // whether its class is Phone (connectivity-system-ux-01, -02)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY deviceChanged)
    Q_PROPERTY(bool deviceIsPhone READ deviceIsPhone NOTIFY deviceChanged)

public:
    Q_INVOKABLE void userAccepts();
    Q_INVOKABLE void userCancels();

    BluetoothAgent(QObject *parent = 0);
    QDBusObjectPath getPath();

    bool windowVisible() const;
    void setWindowVisible(bool visible);

    enum State
    {
        Idle,
        ReqPinCode,
        ReqPasskey,
        DispPinCode,
        DispPasskey,
        ReqConfirmation,
        ReqAuthorization,
        AuthService
    };

    State getState();
    void setState(State s);

    QString deviceName() const { return m_deviceName; }
    bool deviceIsPhone() const { return m_deviceIsPhone; }

    QString getPinCode();
    void setPinCode(QString);

    quint32 getPasskey();
    void setPasskey(quint32);

signals:
    void windowVisibleChanged();
    void stateChanged();
    void pinCodeChanged();
    void passkeyChanged();
    void deviceChanged();

private:
    QDBusInterface *m_mceDbus;
    QString mPath;
    bool m_visible = false;
    State state;
    bool reqConfirm, reqAuth;
    QString pinCode;
    quint32 passkey;
    QDBusObjectPath device;
    QDBusServiceWatcher *mWatcher;
    QDBusMessage m_latestMessage;
    // Ends a pairing window nobody answers (a display-only passkey, a lost
    // Cancel): it keeps the display on while it shows
    QTimer m_windowTimeout;

    // The pairing window holds the display on (mce inhibit_blank_mode 3) and gives back what mce had before,
    // not a fixed 0: the first run setup and the "screen never off" setting hold the same value
    // (W3-launcher-setup, setup-wizard-05).
    bool m_inhibitHeld = false;   // the window wants the hold
    bool m_inhibitSet = false;    // and the 3 was written
    int m_prevInhibit = 0;
    void holdDisplayOn();
    void releaseDisplayHold();

    QString m_deviceName;
    bool m_deviceIsPhone = false;

    void setTrusted(QDBusObjectPath path);
    void loadDevice(const QDBusObjectPath &path);
    void setDeviceInfo(const QString &name, bool isPhone);
    void reject();
    void restoreStaleDisplaySettings();

private slots:
    void serviceRegistered(const QString& name);
    void serviceUnregistered(const QString& name);

public slots:
    void Release();
    QString RequestPinCode(QDBusObjectPath object, const QDBusMessage &message);
    void DisplayPinCode(QDBusObjectPath object, QString pinCode);
    quint32 RequestPasskey(QDBusObjectPath object, const QDBusMessage &message);
    void DisplayPasskey(QDBusObjectPath object, quint32 passkey, quint16 entered);
    void RequestConfirmation(QDBusObjectPath object, quint32 passKey, const QDBusMessage &message);
    void RequestAuthorization(QDBusObjectPath object, const QDBusMessage &message);
    void AuthorizeService(QDBusObjectPath object, QString uuid, const QDBusMessage &message);
    void Cancel();
};

#endif // BLUETOOTHAGENT_H
