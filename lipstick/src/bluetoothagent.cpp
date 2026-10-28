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

#include <QDBusInterface>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QDBusPendingCall>
#include <QDebug>
#include <QDBusVariant>

#include "bluetoothagent.h"

#define AGENT_CAPABILITY        "DisplayYesNo"
// BlueZ cancels an unanswered request after 60 s; this is the backstop
#define WINDOW_TIMEOUT_MS       120000

static const char INHIBIT_BLANK_MODE[] = "/system/osso/dsm/display/inhibit_blank_mode";
static const char TKLOCK_BLANK_DISABLE[] = "/system/osso/dsm/locks/tklock_blank_disable";

BluetoothAgent::BluetoothAgent(QObject *parent) : QObject(parent)
{
    m_mceDbus = new QDBusInterface("com.nokia.mce", "/com/nokia/mce/request", "com.nokia.mce.request", QDBusConnection::systemBus());
    QDBusConnection bus = QDBusConnection::systemBus();
    mPath = "/org/nemomobile/lipstick/agent";
    bus.registerObject(mPath, this, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties);

    mWatcher = new QDBusServiceWatcher("org.bluez", bus);
    connect(mWatcher, SIGNAL(serviceRegistered(const QString&)), this, SLOT(serviceRegistered(const QString&)));
    connect(mWatcher, SIGNAL(serviceUnregistered(const QString&)), this, SLOT(serviceUnregistered(const QString&)));

    if(bus.interface()->isServiceRegistered("org.bluez").value())
        serviceRegistered("org.bluez");

    state = Idle;
    pinCode = "";
    passkey = 0;

    m_windowTimeout.setSingleShot(true);
    m_windowTimeout.setInterval(WINDOW_TIMEOUT_MS);
    connect(&m_windowTimeout, &QTimer::timeout, this, [this] {
        qWarning() << "BluetoothAgent: no answer to the pairing request, closing it";
        if (state == ReqPinCode || state == ReqPasskey || state == ReqConfirmation
                || state == ReqAuthorization || state == AuthService)
            reject();
        setState(Idle);
        setWindowVisible(false);
    });

    restoreStaleDisplaySettings();
}

// The pairing window keeps the display on through mce settings, which mce
// saves: when lipstick stopped while the window showed (crash, restart), the
// display never blanked again, also after a reboot. Undo exactly what
// setWindowVisible(true) set. Before the QML is loaded (the first run sets
// the same values, after this), with short timeouts.
void BluetoothAgent::restoreStaleDisplaySettings()
{
    auto get = [](const char *key) -> int {
        QDBusMessage call = QDBusMessage::createMethodCall("com.nokia.mce", "/com/nokia/mce/request",
                                                           "com.nokia.mce.request", "get_config");
        call << QVariant::fromValue(QDBusObjectPath(key));
        const QDBusMessage reply = QDBusConnection::systemBus().call(call, QDBus::Block, 1000);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return -1;
        return reply.arguments().first().value<QDBusVariant>().variant().toInt();
    };
    if (get(INHIBIT_BLANK_MODE) != 3 || get(TKLOCK_BLANK_DISABLE) != 1)
        return;
    qWarning() << "BluetoothAgent: the display was left always on by an earlier pairing window, restoring";
    m_mceDbus->asyncCall("set_config", QDBusObjectPath(INHIBIT_BLANK_MODE).path(), QVariant::fromValue(QDBusVariant(0)));
    m_mceDbus->asyncCall("set_config", QDBusObjectPath(TKLOCK_BLANK_DISABLE).path(), QVariant::fromValue(QDBusVariant(0)));
}

void BluetoothAgent::serviceRegistered(const QString&)
{
    QDBusInterface agentManager("org.bluez", "/org/bluez", "org.bluez.AgentManager1", QDBusConnection::systemBus());
    agentManager.call("RegisterAgent", QVariant::fromValue(getPath()), AGENT_CAPABILITY);
    agentManager.asyncCall("RequestDefaultAgent", QVariant::fromValue(getPath()));
}

void BluetoothAgent::serviceUnregistered(const QString&)
{
    setWindowVisible(false);
    setState(Idle);
}

void BluetoothAgent::setTrusted(QDBusObjectPath path)
{
    QDBusInterface device("org.bluez", path.path(), "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());
    // Properties.Set takes the value as a variant: a plain bool is refused (InvalidArgs)
    device.asyncCall("Set", "org.bluez.Device1", "Trusted", QVariant::fromValue(QDBusVariant(true)));
}

void BluetoothAgent::reject()
{
    // Only a request has a message to answer: an error reply to none aborts in libdbus
    if (m_latestMessage.type() != QDBusMessage::MethodCallMessage)
        return;
    QDBusMessage pendingErrorReply = m_latestMessage.createErrorReply("org.bluez.Error.Rejected", "Rejected");
    QDBusConnection::systemBus().send(pendingErrorReply);
}

QDBusObjectPath BluetoothAgent::getPath()
{
    return QDBusObjectPath(mPath);
}

BluetoothAgent::State BluetoothAgent::getState()
{
    return state;
}

void BluetoothAgent::setState(State s)
{
    if(state != s) {
        state = s;
        emit stateChanged();
    }
}

QString BluetoothAgent::getPinCode()
{
    return pinCode;
}

void BluetoothAgent::setPinCode(QString s)
{
    if(pinCode != s) {
        pinCode = s;
        emit pinCodeChanged();
    }
}

quint32 BluetoothAgent::getPasskey()
{
    return passkey;
}

void BluetoothAgent::setPasskey(quint32 pk)
{
    if(passkey != pk) {
        passkey = pk;
        emit passkeyChanged();
    }
}

bool BluetoothAgent::windowVisible() const
{
    return m_visible;
}

void BluetoothAgent::setWindowVisible(bool visible)
{
    if (visible == m_visible)
        return;

    m_visible = visible;
    if (visible)
        m_windowTimeout.start();
    else
        m_windowTimeout.stop();
    if (visible) {
        // Turn the screen on and keep it on and unlocked for the duration of
        // the pairing. Pairing usually starts from the phone while the watch
        // display is off: blank inhibition alone keeps an off display off, so
        // the code was never shown and the off touchscreen ignored the buttons.
        m_mceDbus->asyncCall("req_display_state_on");
        m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/display/inhibit_blank_mode").path(), QVariant::fromValue(QDBusVariant(3)));
        m_mceDbus->asyncCall("req_tklock_mode_change", "unlocked");
        m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/locks/tklock_blank_disable").path(), QVariant::fromValue(QDBusVariant(1)));
    } else {
        m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/display/inhibit_blank_mode").path(), QVariant::fromValue(QDBusVariant(0)));
        m_mceDbus->asyncCall("req_tklock_mode_change", "locked");
        m_mceDbus->asyncCall("set_config", QDBusObjectPath("/system/osso/dsm/locks/tklock_blank_disable").path(), QVariant::fromValue(QDBusVariant(0)));
    }
    emit windowVisibleChanged();
}

void BluetoothAgent::userAccepts()
{
    QDBusMessage pendingReply = m_latestMessage.createReply();
    if(state == ReqPinCode)
        pendingReply << pinCode;
    else if(state == ReqPasskey)
        pendingReply << passkey;
    else if(state == ReqConfirmation)
        setTrusted(device);

    if(state == ReqPinCode || state == ReqPasskey || state == ReqConfirmation
        || state == ReqAuthorization || state == AuthService)
        QDBusConnection::systemBus().send(pendingReply);

    setState(Idle);
}

void BluetoothAgent::userCancels()
{
    // A display-only code (DisplayPinCode / DisplayPasskey) waits for no answer:
    // m_latestMessage is then an earlier, answered request, or none at all
    if (state == ReqPinCode || state == ReqPasskey || state == ReqConfirmation
            || state == ReqAuthorization || state == AuthService)
        reject();
    setState(Idle);
}

/* Exposed slots */
QString BluetoothAgent::RequestPinCode(QDBusObjectPath object, const QDBusMessage &message)
{
    device = object;
    setTrusted(device);
    setWindowVisible(true);
    setState(ReqPinCode);

    message.setDelayedReply(true);
    // userAccepts() answers this message (it answered the previous request)
    m_latestMessage = message;

    return "";
}

quint32 BluetoothAgent::RequestPasskey(QDBusObjectPath object, const QDBusMessage &message)
{
    device = object;
    setTrusted(device);
    setWindowVisible(true);
    setState(ReqPasskey);

    message.setDelayedReply(true);
    m_latestMessage = message;

    return 0;
}

void BluetoothAgent::DisplayPinCode(QDBusObjectPath object, QString pc)
{
    device = object;
    setPinCode(pc);
    setWindowVisible(true);
    setState(DispPinCode);
}

void BluetoothAgent::DisplayPasskey(QDBusObjectPath object, quint32 pk, quint16)
{
    device = object;
    setPasskey(pk);
    setWindowVisible(true);
    setState(DispPasskey);
}

void BluetoothAgent::RequestConfirmation(QDBusObjectPath object, quint32 pk, const QDBusMessage &message)
{
    device = object;
    setPasskey(pk);
    setWindowVisible(true);
    setState(ReqConfirmation);

    message.setDelayedReply(true);

    m_latestMessage = message;
}

void BluetoothAgent::RequestAuthorization(QDBusObjectPath object, const QDBusMessage &message)
{
    device = object;
    setWindowVisible(true);
    setState(ReqAuthorization);

    message.setDelayedReply(true);

    m_latestMessage = message;
}

void BluetoothAgent::AuthorizeService(QDBusObjectPath object, QString uuid, const QDBusMessage &message)
{
    device = object;
    setWindowVisible(true);
    setState(AuthService);
    setPinCode(uuid);

    message.setDelayedReply(true);

    m_latestMessage = message;
}

void BluetoothAgent::Cancel()
{
    setWindowVisible(false);
    setState(Idle);
}

void BluetoothAgent::Release()
{
    setWindowVisible(false);
    setState(Idle);
}

