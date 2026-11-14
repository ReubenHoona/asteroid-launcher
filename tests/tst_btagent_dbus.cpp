/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The BlueZ agent (lipstick/src/bluetoothagent.cpp) against a fake BlueZ on a private bus
 * (connectivity-system-ux-01, -02, -03): the device's name and class come from the device's properties,
 * never its address; a service of a bonded device is allowed at once and the device marked trusted, a
 * service of an unbonded device is refused, and neither opens a window. Run on a private bus:
 *   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS ./tst_btagent_dbus'
 * (the agent registers on the "system" bus, which the test makes the session bus).
 */

#include "bluetoothagent.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QEventLoop>
#include <QTimer>
#include <QVariantMap>

#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

// a fake org.bluez device: the properties of org.bluez.Device1 (QtDBus answers Properties.GetAll and Set
// from them) and a record of what the agent did to Trusted
class FakeBluez : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Device1")
    Q_PROPERTY(QString Alias READ alias)
    Q_PROPERTY(QString Name READ name)
    Q_PROPERTY(uint Class READ cod)
    Q_PROPERTY(bool Paired READ paired)
    Q_PROPERTY(bool Trusted READ trusted WRITE setTrusted)
public:
    QString m_alias, m_name;
    uint m_class = 0;
    bool m_paired = false;
    bool m_trusted = false;
    int trustedSets = 0;

    void set(const QString &alias, const QString &name, uint cod, bool paired)
    {
        m_alias = alias; m_name = name; m_class = cod; m_paired = paired;
    }
    QString alias() const { return m_alias; }
    QString name() const { return m_name; }
    uint cod() const { return m_class; }
    bool paired() const { return m_paired; }
    bool trusted() const { return m_trusted; }
    void setTrusted(bool t) { m_trusted = t; trustedSets++; }
};

// a fake org.bluez.AgentManager1 on /org/bluez (RegisterAgent and RequestDefaultAgent only)
class FakeManager : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.AgentManager1")
public slots:
    void RegisterAgent(const QDBusObjectPath &, const QString &) {}
    void RequestDefaultAgent(const QDBusObjectPath &) {}
};

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QDBusConnection bus = QDBusConnection::systemBus();
    CHECK(bus.isConnected());
    CHECK(bus.registerService(QStringLiteral("org.bluez")));

    FakeBluez bluez;
    FakeManager manager;
    bluez.set("Pixel 8", "Pixel 8", 0x5a020cu, true);
    const QString devPath = QStringLiteral("/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF");
    CHECK(bus.registerObject(devPath, &bluez, QDBusConnection::ExportAllProperties));
    CHECK(bus.registerObject(QStringLiteral("/org/bluez"), &manager, QDBusConnection::ExportAllSlots));

    BluetoothAgent agent;
    spin(200);

    // ---- the device behind a pairing request: name and class, no address
    CHECK(agent.deviceName().isEmpty());
    CHECK(!agent.deviceIsPhone());
    int changes = 0;
    QObject::connect(&agent, &BluetoothAgent::deviceChanged, [&] { changes++; });
    agent.DisplayPasskey(QDBusObjectPath(devPath), 123456, 0);
    CHECK(agent.windowVisible());
    CHECK(agent.getState() == BluetoothAgent::DispPasskey);
    // the name is empty until BlueZ has answered (the dialog says "device"), then it is the alias
    CHECK(agent.deviceName().isEmpty());
    spin(300);
    CHECK(agent.deviceName() == QLatin1String("Pixel 8"));
    CHECK(agent.deviceIsPhone());
    CHECK(changes >= 1);
    agent.userCancels();
    agent.setWindowVisible(false);

    // a device whose alias is its address has no name to show; an LE only device has no class
    bluez.set("AA-BB-CC-DD-EE-FF", "", 0u, false);
    agent.DisplayPasskey(QDBusObjectPath(devPath), 7, 0);
    spin(300);
    CHECK(agent.deviceName().isEmpty());
    CHECK(!agent.deviceIsPhone());
    agent.userCancels();
    agent.setWindowVisible(false);

    // ---- a service request: no window, answered at once for a bonded device
    QDBusConnection client = QDBusConnection::connectToBus(qgetenv("DBUS_SYSTEM_BUS_ADDRESS").constData(), QStringLiteral("client"));
    CHECK(client.isConnected());
    // the agent's object is on this process' connection: its unique name is the owner
    // (the test calls it by that name)
    const QString owner = bus.baseService();
    auto askService = [&](bool paired) {
        bluez.set("Pixel 8", "", 0x5a020cu, paired);
        QDBusMessage m = QDBusMessage::createMethodCall(owner, QStringLiteral("/org/nemomobile/lipstick/agent"),
                                                        QStringLiteral("org.bluez.Agent1"), QStringLiteral("AuthorizeService"));
        m << QVariant::fromValue(QDBusObjectPath(devPath)) << QStringLiteral("0000110b-0000-1000-8000-00805f9b34fb");
        QDBusPendingCall call = client.asyncCall(m, 3000);
        QEventLoop loop;
        QDBusPendingCallWatcher w(call);
        QObject::connect(&w, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
        QTimer::singleShot(4000, &loop, &QEventLoop::quit);
        loop.exec();
        return w.isFinished() ? (w.isError() ? w.error().name() : QString()) : QStringLiteral("no answer");
    };

    bluez.trustedSets = 0;
    bluez.m_trusted = false;
    QString r = askService(true);
    CHECK(r.isEmpty());                                  // allowed
    spin(100);
    CHECK(bluez.m_trusted);                              // and trusted, so BlueZ stops asking
    CHECK(!agent.windowVisible());                       // no window
    CHECK(agent.getState() == BluetoothAgent::Idle);     // no state either
    CHECK(agent.getPinCode().isEmpty());                 // the UUID is not kept

    bluez.trustedSets = 0;
    bluez.m_trusted = false;
    r = askService(false);
    CHECK(r == QLatin1String("org.bluez.Error.Rejected")); // refused, silently
    spin(100);
    CHECK(!bluez.m_trusted);
    CHECK(!agent.windowVisible());
    CHECK(agent.getState() == BluetoothAgent::Idle);

    // a service request while a pairing prompt is up leaves the prompt alone
    bluez.set("Pixel 8", "", 0x5a020cu, true);
    agent.DisplayPasskey(QDBusObjectPath(devPath), 42, 0);
    spin(200);
    CHECK(agent.getState() == BluetoothAgent::DispPasskey);
    r = askService(true);
    CHECK(r.isEmpty());
    CHECK(agent.getState() == BluetoothAgent::DispPasskey);
    CHECK(agent.windowVisible());
    CHECK(agent.deviceName() == QLatin1String("Pixel 8"));
    agent.userCancels();
    agent.setWindowVisible(false);

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_btagent_dbus.moc"
