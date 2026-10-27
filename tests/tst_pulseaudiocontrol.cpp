/*
 * PulseAudioControl (lipstick/src/volume/pulseaudiocontrol.cpp): lipstick's volume control over
 * PulseAudio's peer-to-peer D-Bus (MainVolume2).
 *
 * The real class (libdbus + dbus-glib) against fake PulseAudio servers: QDBusServer peer servers in a
 * worker thread that answer MainVolume2's GetAll / Set and record ListenForSignal. Checks the address
 * lookup (PULSE_DBUS_SERVER, else org.pulseaudio.Server on the session bus), the GetAll parsing, the
 * MainVolume2 signals, setVolume, and the reconnect after PulseAudio restarts: the dead connection
 * is dropped, a retry is scheduled while PulseAudio is not back, the retry delay grows by 5 s up to
 * a minute and starts again from 2 s once connected.
 */

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusServer>
#include <QDBusVariant>
#include <QMutex>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include <dbus/dbus.h>

#include "fakeservice.h"
#include "pulseaudiocontrol.h"

namespace {

const QString VOLUME_PATH = QStringLiteral("/com/meego/mainvolume2");
const QString VOLUME_IF = QStringLiteral("com.Meego.MainVolume2");

// One PulseAudio: a peer-to-peer server, its objects registered on each client connection.
class FakePulse : public QObject
{
    Q_OBJECT
public:
    explicit FakePulse(const QString &address)
        : server(new QDBusServer(address, this))
    {
        connect(server, &QDBusServer::newConnection, this, &FakePulse::accept);
        volume.respond(QStringLiteral("GetAll"), [this](const QDBusMessage &call) {
            QMutexLocker lock(&mutex);
            if (failGetAll)
                return call.createErrorReply(QStringLiteral("org.freedesktop.DBus.Error.Failed"), QStringLiteral("test"));
            return call.createReply(QVariant::fromValue(properties));
        });
    }

    // PulseAudio stops: its clients' connections close
    ~FakePulse() override
    {
        QList<QDBusConnection> closing;
        {
            QMutexLocker lock(&mutex);
            closing.swap(clients);
        }
        for (QDBusConnection &c : closing) {
            c.unregisterObject(VOLUME_PATH);
            c.unregisterObject(QStringLiteral("/org/pulseaudio/core1"));
            QDBusConnection::disconnectFromPeer(c.name());
        }
    }

    QString address() const { return server->address(); }

    QList<QDBusConnection> connections() const
    {
        QMutexLocker lock(&mutex);
        return clients;
    }

    void setProperties(const QVariantMap &p, bool fail = false)
    {
        QMutexLocker lock(&mutex);
        properties = p;
        failGetAll = fail;
    }

    void emitSignal(const QString &member, const QVariantList &args)
    {
        QDBusMessage signal = QDBusMessage::createSignal(VOLUME_PATH, VOLUME_IF, member);
        signal.setArguments(args);
        for (const QDBusConnection &c : connections())
            c.send(signal);
    }

    FakeObject volume;
    FakeObject core;

private slots:
    void accept(const QDBusConnection &connection)
    {
        {
            QMutexLocker lock(&mutex);
            clients << connection;
        }
        QDBusConnection c(connection);
        c.registerVirtualObject(VOLUME_PATH, &volume);
        c.registerVirtualObject(QStringLiteral("/org/pulseaudio/core1"), &core);
    }

private:
    QDBusServer *server;
    mutable QMutex mutex;
    QList<QDBusConnection> clients;
    QVariantMap properties;
    bool failGetAll = false;
};

QVariantMap volumeProperties(uint current, uint count)
{
    return QVariantMap {
        { QStringLiteral("StepCount"), count },
        { QStringLiteral("CurrentStep"), current },
        { QStringLiteral("HighVolumeStep"), 8u },
        { QStringLiteral("MediaState"), QStringLiteral("inactive") },
        { QStringLiteral("CallState"), QStringLiteral("inactive") }, // a string it does not use
        { QStringLiteral("Unrelated"), 7u },
        { QStringLiteral("Flag"), true },
    };
}

}

class Ut_PulseAudioControl : public QObject
{
    Q_OBJECT

private:
    FakeServiceHost *host = nullptr;
    QTemporaryDir dir;
    int serial = 0;

    FakePulse *startPulse()
    {
        const QString address = QStringLiteral("unix:path=%1/pulse-%2").arg(dir.path()).arg(++serial);
        FakePulse *pulse = nullptr;
        host->run([&] { pulse = new FakePulse(address); });
        return pulse;
    }

    void stopPulse(FakePulse *pulse)
    {
        host->run([pulse] { delete pulse; });
    }

    static QString nextAddress(int serial, const QTemporaryDir &dir)
    {
        return QStringLiteral("unix:path=%1/pulse-%2").arg(dir.path()).arg(serial);
    }

private slots:
    void initTestCase()
    {
        QVERIFY(TestBus::start());
        QVERIFY(dir.isValid());
        host = new FakeServiceHost;
    }

    void cleanupTestCase()
    {
        delete host;
        TestBus::stop();
    }

    void init()
    {
        qunsetenv("PULSE_DBUS_SERVER");
    }

    void noPulseAudioRetriesWithGrowingDelay()
    {
        // no PULSE_DBUS_SERVER and no org.pulseaudio.Server on the session bus
        PulseAudioControl control;
        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        QCOMPARE(control.reconnectTimeout, 2000);
        QList<int> delays;
        for (int i = 0; i < 14; ++i) {
            control.update();
            QVERIFY(control.dbusConnection == nullptr);
            delays << control.reconnectTimeout;
        }
        QCOMPARE(delays, QList<int>({ 7000, 12000, 17000, 22000, 27000, 32000, 37000, 42000, 47000, 52000,
                                      57000, 60000, 60000, 60000 }));
        control.setVolume(3); // nothing to send it to
        QVERIFY(control.dbusConnection == nullptr);
        QCOMPARE(volumeSpy.count(), 0);
    }

    void unreachableAddressRetries()
    {
        qputenv("PULSE_DBUS_SERVER", nextAddress(900, dir).toUtf8());
        PulseAudioControl control;
        control.update();
        QVERIFY(control.dbusConnection == nullptr);
        QCOMPARE(control.reconnectTimeout, 7000);
    }

    void readsVolumeAndListensForSignals()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(4, 11));
        qputenv("PULSE_DBUS_SERVER", pulse->address().toUtf8());

        PulseAudioControl control;
        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        QSignalSpy highSpy(&control, &PulseAudioControl::highVolume);
        QSignalSpy mediaSpy(&control, &PulseAudioControl::mediaStateChanged);
        control.update();
        QVERIFY(control.dbusConnection != nullptr);
        QCOMPARE(control.reconnectTimeout, 2000);
        QCOMPARE(volumeSpy.count(), 1);
        QCOMPARE(volumeSpy.first(), QVariantList({ 4, 10 })); // step count 11: steps 0..10
        QCOMPARE(highSpy.count(), 1);
        QCOMPARE(highSpy.first().first().toInt(), 8);
        QCOMPARE(mediaSpy.count(), 1);
        QCOMPARE(mediaSpy.first().first().toString(), QStringLiteral("inactive"));

        QStringList listened;
        QTRY_COMPARE(pulse->core.callsTo(QStringLiteral("ListenForSignal")).size(), 5);
        for (const RecordedCall &call : pulse->core.callsTo(QStringLiteral("ListenForSignal")))
            listened << call.args.value(0).toString();
        QCOMPARE(listened, QStringList({ QStringLiteral("com.Meego.MainVolume2.StepsUpdated"),
                                         QStringLiteral("com.Meego.MainVolume2.NotifyHighVolume"),
                                         QStringLiteral("com.Meego.MainVolume2.NotifyListeningTime"),
                                         QStringLiteral("com.Meego.MainVolume2.CallStateChanged"),
                                         QStringLiteral("com.Meego.MainVolume2.MediaStateChanged") }));

        // a second update keeps the connection
        DBusConnection *first = control.dbusConnection;
        control.update();
        QCOMPARE(control.dbusConnection, first);
        QCOMPARE(volumeSpy.count(), 2);
        QCOMPARE(pulse->core.callsTo(QStringLiteral("ListenForSignal")).size(), 5);

        // the volume API failing or incomplete: nothing is reported
        pulse->setProperties(QVariantMap(), true);
        control.update();
        pulse->setProperties(QVariantMap { { QStringLiteral("CurrentStep"), 2u } });
        control.update();
        QCOMPARE(volumeSpy.count(), 2);

        stopPulse(pulse);
    }

    void signals_()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(1, 5));
        qputenv("PULSE_DBUS_SERVER", pulse->address().toUtf8());
        PulseAudioControl control;
        control.update();
        QTRY_COMPARE(pulse->connections().size(), 1);

        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        QSignalSpy highSpy(&control, &PulseAudioControl::highVolume);
        QSignalSpy listeningSpy(&control, &PulseAudioControl::longListeningTime);
        QSignalSpy callSpy(&control, &PulseAudioControl::callActiveChanged);
        QSignalSpy mediaSpy(&control, &PulseAudioControl::mediaStateChanged);

        pulse->emitSignal(QStringLiteral("StepsUpdated"), { 16u, 9u }); // (StepCount, CurrentStep)
        QTRY_COMPARE(volumeSpy.count(), 1);
        QCOMPARE(volumeSpy.first(), QVariantList({ 9, 15 }));
        pulse->emitSignal(QStringLiteral("NotifyHighVolume"), { 12u });
        QTRY_COMPARE(highSpy.count(), 1);
        QCOMPARE(highSpy.first().first().toInt(), 12);
        pulse->emitSignal(QStringLiteral("NotifyListeningTime"), { 60u });
        QTRY_COMPARE(listeningSpy.count(), 1);
        QCOMPARE(listeningSpy.first().first().toInt(), 60);
        pulse->emitSignal(QStringLiteral("CallStateChanged"), { QStringLiteral("active") });
        QTRY_COMPARE(callSpy.count(), 1);
        QCOMPARE(callSpy.last().first().toBool(), true);
        pulse->emitSignal(QStringLiteral("CallStateChanged"), { QStringLiteral("inactive") });
        QTRY_COMPARE(callSpy.count(), 2);
        QCOMPARE(callSpy.last().first().toBool(), false);
        pulse->emitSignal(QStringLiteral("MediaStateChanged"), { QStringLiteral("active") });
        QTRY_COMPARE(mediaSpy.count(), 1);
        QCOMPARE(mediaSpy.first().first().toString(), QStringLiteral("active"));

        // wrong arguments are ignored
        pulse->emitSignal(QStringLiteral("StepsUpdated"), { QStringLiteral("x") });
        pulse->emitSignal(QStringLiteral("NotifyHighVolume"), { QStringLiteral("x") });
        pulse->emitSignal(QStringLiteral("NotifyListeningTime"), { QStringLiteral("x") });
        pulse->emitSignal(QStringLiteral("CallStateChanged"), { 1u });
        pulse->emitSignal(QStringLiteral("MediaStateChanged"), { 1u });
        pulse->emitSignal(QStringLiteral("SomethingElse"), {});
        // a marker signal after them: everything before it was handled
        pulse->emitSignal(QStringLiteral("NotifyHighVolume"), { 13u });
        QTRY_COMPARE(highSpy.count(), 2);
        QCOMPARE(highSpy.last().first().toInt(), 13);
        QCOMPARE(volumeSpy.count(), 1);
        QCOMPARE(listeningSpy.count(), 1);
        QCOMPARE(callSpy.count(), 2);
        QCOMPARE(mediaSpy.count(), 1);

        stopPulse(pulse);
    }

    void setVolumeSetsCurrentStep()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(1, 5));
        qputenv("PULSE_DBUS_SERVER", pulse->address().toUtf8());
        PulseAudioControl control;
        control.setVolume(3); // connects on its own
        QVERIFY(control.dbusConnection != nullptr);
        QTRY_COMPARE(pulse->volume.callsTo(QStringLiteral("Set")).size(), 1);
        const RecordedCall set = pulse->volume.callsTo(QStringLiteral("Set")).first();
        QCOMPARE(set.path, VOLUME_PATH);
        QCOMPARE(set.interface, QStringLiteral("org.freedesktop.DBus.Properties"));
        QCOMPARE(set.args.value(0).toString(), VOLUME_IF);
        QCOMPARE(set.args.value(1).toString(), QStringLiteral("CurrentStep"));
        const QVariant value = set.args.value(2).value<QDBusVariant>().variant();
        QCOMPARE(value.metaType(), QMetaType::fromType<uint>());
        QCOMPARE(value.toUInt(), 3u);
        stopPulse(pulse);
    }

    void looksUpTheAddressOnTheSessionBus()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(2, 5));
        const QString address = pulse->address();

        FakeService lookup(*host, QStringLiteral("org.pulseaudio.Server"), QStringLiteral("fake-pulse-lookup"));
        FakeObject *lookupObj = new FakeObject;
        lookupObj->respond(QStringLiteral("Get"), [address](const QDBusMessage &call) {
            return call.createReply(QVariant::fromValue(QDBusVariant(address)));
        });
        lookup.add(QStringLiteral("/org/pulseaudio/server_lookup1"), lookupObj);
        QVERIFY(lookup.registerName());

        PulseAudioControl control;
        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        control.update();
        QVERIFY(control.dbusConnection != nullptr);
        QCOMPARE(volumeSpy.count(), 1);
        QCOMPARE(volumeSpy.first(), QVariantList({ 2, 4 }));
        const RecordedCall get = lookupObj->callsTo(QStringLiteral("Get")).value(0);
        QCOMPARE(get.interface, QStringLiteral("org.freedesktop.DBus.Properties"));
        QCOMPARE(get.args, QVariantList({ QStringLiteral("org.PulseAudio.ServerLookup1"), QStringLiteral("Address") }));
        stopPulse(pulse);
    }

    // PulseAudio restarts and comes back at once: the dead connection is replaced
    void reconnectsAfterRestart()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(1, 5));
        qputenv("PULSE_DBUS_SERVER", pulse->address().toUtf8());
        PulseAudioControl control;
        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        control.update();
        QVERIFY(control.dbusConnection != nullptr);

        stopPulse(pulse);
        QTRY_VERIFY(!dbus_connection_get_is_connected(control.dbusConnection));

        FakePulse *restarted = startPulse();
        restarted->setProperties(volumeProperties(3, 5));
        qputenv("PULSE_DBUS_SERVER", restarted->address().toUtf8());
        control.update();
        QVERIFY(control.dbusConnection != nullptr);
        QVERIFY(dbus_connection_get_is_connected(control.dbusConnection));
        QCOMPARE(volumeSpy.last(), QVariantList({ 3, 4 }));
        QTRY_COMPARE(restarted->core.callsTo(QStringLiteral("ListenForSignal")).size(), 5);

        // signals come from the new server
        QSignalSpy highSpy(&control, &PulseAudioControl::highVolume);
        restarted->emitSignal(QStringLiteral("NotifyHighVolume"), { 10u });
        QTRY_COMPARE(highSpy.count(), 1);
        stopPulse(restarted);
    }

    // PulseAudio restarts and is not back yet: the old code kept the dead connection and scheduled
    // no retry, so volume keys and step signals stayed dead until the next key press
    void retriesUntilPulseAudioIsBack()
    {
        FakePulse *pulse = startPulse();
        pulse->setProperties(volumeProperties(1, 5));
        qputenv("PULSE_DBUS_SERVER", pulse->address().toUtf8());
        PulseAudioControl control;
        QSignalSpy volumeSpy(&control, &PulseAudioControl::volumeChanged);
        control.update();
        QCOMPARE(volumeSpy.count(), 1);

        stopPulse(pulse);
        QTRY_VERIFY(!dbus_connection_get_is_connected(control.dbusConnection));

        const QString nextAddr = nextAddress(serial + 1, dir);
        qputenv("PULSE_DBUS_SERVER", nextAddr.toUtf8());
        control.reconnectTimeout = 200; // the retry below comes after 200 ms instead of 2 s
        control.update();
        QVERIFY(control.dbusConnection == nullptr); // the dead one is gone
        QCOMPARE(control.reconnectTimeout, 5200);

        FakePulse *restarted = startPulse(); // at nextAddr
        QVERIFY(restarted->address().startsWith(nextAddr));
        restarted->setProperties(volumeProperties(4, 5));
        QTRY_COMPARE_WITH_TIMEOUT(volumeSpy.count(), 2, 8000); // the scheduled retry connected
        QCOMPARE(volumeSpy.last(), QVariantList({ 4, 4 }));
        QVERIFY(control.dbusConnection != nullptr);
        QCOMPARE(control.reconnectTimeout, 2000); // reset once connected
        stopPulse(restarted);
    }
};

QTEST_GUILESS_MAIN(Ut_PulseAudioControl)
#include "tst_pulseaudiocontrol.moc"
