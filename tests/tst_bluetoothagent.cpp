/*
 * BluetoothAgent (lipstick/src/bluetoothagent.cpp): the org.bluez.Agent1 lipstick exports for pairing.
 *
 * The real class on a private bus: the test plays BlueZ (calls the agent's Agent1 methods, owns
 * org.bluez with an AgentManager1 and the device's Properties) and mce (records the display requests,
 * answers get_config). Checks the pairing flows (confirmation, PIN, passkey, authorisation, service
 * authorisation, display-only codes), that every request is answered with its own message (the
 * PIN / passkey requests used to answer the previous one), the window's display-on requests, the
 * 120 s backstop that closes an unanswered window, the restore of a display left always on by a
 * window that never closed, and the agent's (re)registration when bluetoothd comes and goes.
 */

#include <QAtomicInt>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QObject>
#include <QProcess>
#include <QSignalSpy>
#include <QTimer>
#include <QtTest>

#include "fakeservice.h"
#include "mce.h"

// the test drives the private window timeout (120 s) with a short interval
#define private public
#include "bluetoothagent.h"
#undef private

namespace {

const QString AGENT_PATH = QStringLiteral("/org/nemomobile/lipstick/agent");
const QString AGENT_IF = QStringLiteral("org.bluez.Agent1");
// a documentation-range (RFC 7042) address
const QString DEVICE = QStringLiteral("/org/bluez/hci0/dev_00_00_5E_00_53_01");
const QString INHIBIT = QStringLiteral("/system/osso/dsm/display/inhibit_blank_mode");
const QString TKLOCK = QStringLiteral("/system/osso/dsm/locks/tklock_blank_disable");

const QStringList WINDOW_SHOWN {
    QStringLiteral("req_display_state_on"),
    QStringLiteral("set_config ") + INHIBIT + QStringLiteral(" 3"),
    QStringLiteral("req_tklock_mode_change unlocked"),
    QStringLiteral("set_config ") + TKLOCK + QStringLiteral(" 1"),
};
const QStringList WINDOW_HIDDEN {
    QStringLiteral("set_config ") + INHIBIT + QStringLiteral(" 0"),
    QStringLiteral("req_tklock_mode_change locked"),
    QStringLiteral("set_config ") + TKLOCK + QStringLiteral(" 0"),
};

QString bluezIntrospection()
{
    return QStringLiteral(
        "<interface name=\"org.bluez.AgentManager1\">"
        "<method name=\"RegisterAgent\"><arg type=\"o\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/></method>"
        "<method name=\"RequestDefaultAgent\"><arg type=\"o\" direction=\"in\"/></method>"
        "</interface>"
        "<interface name=\"org.freedesktop.DBus.Properties\">"
        "<method name=\"Set\"><arg type=\"s\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/>"
        "<arg type=\"v\" direction=\"in\"/></method>"
        "</interface>");
}

QVariant path(const QString &p)
{
    return QVariant::fromValue(QDBusObjectPath(p));
}

}

class TestBluetoothAgent : public QObject
{
    Q_OBJECT

private:
    FakeServiceHost *host = nullptr;
    FakeService *mce = nullptr;
    FakeObject *mceObj = nullptr;
    FakeService *bluez = nullptr;
    FakeObject *bluezObj = nullptr;
    QAtomicInt inhibitValue;
    QAtomicInt tklockValue;

    QDBusPendingCall callAgent(const QString &member, const QVariantList &args)
    {
        QDBusMessage call = QDBusMessage::createMethodCall(QDBusConnection::systemBus().baseService(),
                                                           AGENT_PATH, AGENT_IF, member);
        call.setArguments(args);
        return bluez->connection().asyncCall(call, 30000);
    }

    // device paths the agent asked to mark Trusted (with whatever argument type)
    QStringList trusted() const
    {
        QStringList out;
        for (const RecordedCall &call : bluezObj->callsTo(QStringLiteral("Set"))) {
            if (call.args.size() == 3 && call.args.at(0).toString() == QLatin1String("org.bluez.Device1")
                    && call.args.at(1).toString() == QLatin1String("Trusted"))
                out << call.path;
        }
        return out;
    }

    // Properties.Set takes its value as a variant ("ssv"); BlueZ answers anything else with InvalidArgs
    bool trustedSentAsVariant() const
    {
        const QList<RecordedCall> sets = bluezObj->callsTo(QStringLiteral("Set"));
        return !sets.isEmpty() && sets.last().args.value(2).metaType() == QMetaType::fromType<QDBusVariant>()
                && sets.last().args.value(2).value<QDBusVariant>().variant().toBool();
    }

    QStringList mceSetConfigs() const
    {
        return mceRequests(mceObj).filter(QStringLiteral("set_config"));
    }

private slots:
    void initTestCase()
    {
        QVERIFY(TestBus::start());
        host = new FakeServiceHost;

        mce = new FakeService(*host, QStringLiteral("com.nokia.mce"), QStringLiteral("fake-mce"));
        mceObj = new FakeObject(mceIntrospection());
        mceObj->respond(QStringLiteral("get_config"), [this](const QDBusMessage &call) {
            const QString key = call.arguments().value(0).value<QDBusObjectPath>().path();
            const int value = key == INHIBIT ? inhibitValue.loadRelaxed() : tklockValue.loadRelaxed();
            return call.createReply(QVariant::fromValue(QDBusVariant(value)));
        });
        mceObj->respond(QStringLiteral("set_config"), [](const QDBusMessage &call) {
            return call.createReply(true);
        });
        mce->add(QStringLiteral("/com/nokia/mce/request"), mceObj);

        bluez = new FakeService(*host, QStringLiteral("org.bluez"), QStringLiteral("fake-bluez"));
        bluezObj = new FakeObject(bluezIntrospection());
        bluez->add(QStringLiteral("/org/bluez"), bluezObj);
        // mce and bluetoothd are not on the bus until the tests that need them
    }

    void cleanupTestCase()
    {
        delete bluez;
        delete mce;
        delete host;
        TestBus::stop();
    }

    void init()
    {
        mceObj->clear();
        bluezObj->clear();
        inhibitValue.storeRelaxed(0);
        tklockValue.storeRelaxed(0);
        // mce and bluetoothd are on the bus, except where a test wants them away (each test runs alone too)
        const QByteArray test = QTest::currentTestFunction();
        if (test == "startsWithoutMceOrBluez") {
            mce->unregisterName();
            bluez->unregisterName();
        } else {
            mce->registerName();
            if (test == "registersWhenBluezAppears")
                bluez->unregisterName();
            else
                bluez->registerName();
        }
        QTRY_VERIFY(!QDBusConnection::systemBus().interface()->isServiceRegistered(QStringLiteral("org.bluez")).value()
                    == (test == "startsWithoutMceOrBluez" || test == "registersWhenBluezAppears"));
        bluezObj->clear();
    }

    // first: nothing on the bus yet
    void startsWithoutMceOrBluez()
    {
        BluetoothAgent agent;
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
        QVERIFY(!agent.windowVisible());
        QCOMPARE(agent.getPath().path(), AGENT_PATH);
        QCOMPARE(agent.getPinCode(), QString());
        QCOMPARE(agent.getPasskey(), 0u);
        QVERIFY(bluezObj->calls().isEmpty());
    }

    void restoresDisplayLeftAlwaysOn()
    {
        inhibitValue.storeRelaxed(3);
        tklockValue.storeRelaxed(1);
        BluetoothAgent agent;
        QCOMPARE(mceObj->callsTo(QStringLiteral("get_config")).size(), 2);
        QTRY_COMPARE(mceSetConfigs(), QStringList({ QStringLiteral("set_config ") + INHIBIT + QStringLiteral(" 0"),
                                                    QStringLiteral("set_config ") + TKLOCK + QStringLiteral(" 0") }));
    }

    void keepsDisplaySettingsItDidNotSet_data()
    {
        QTest::addColumn<int>("inhibit");
        QTest::addColumn<int>("tklock");
        QTest::addColumn<int>("reads");
        QTest::newRow("default") << 0 << 0 << 1;
        QTest::newRow("user's always-on, no tklock") << 3 << 0 << 2;
        QTest::newRow("other inhibit mode") << 2 << 1 << 1;
    }

    void keepsDisplaySettingsItDidNotSet()
    {
        QFETCH(int, inhibit);
        QFETCH(int, tklock);
        QFETCH(int, reads);
        inhibitValue.storeRelaxed(inhibit);
        tklockValue.storeRelaxed(tklock);
        BluetoothAgent agent;
        QCOMPARE(mceObj->callsTo(QStringLiteral("get_config")).size(), reads);
        QTest::qWait(50);
        QVERIFY(mceSetConfigs().isEmpty());
    }

    void registersWhenBluezAppears()
    {
        BluetoothAgent agent;
        QTest::qWait(20);
        QVERIFY(bluezObj->calls().isEmpty());
        QVERIFY(bluez->registerName());
        QTRY_COMPARE(bluezObj->callsTo(QStringLiteral("RequestDefaultAgent")).size(), 1);
        const QList<RecordedCall> reg = bluezObj->callsTo(QStringLiteral("RegisterAgent"));
        QCOMPARE(reg.size(), 1);
        QCOMPARE(reg.first().path, QStringLiteral("/org/bluez"));
        QCOMPARE(reg.first().interface, QStringLiteral("org.bluez.AgentManager1"));
        QCOMPARE(reg.first().args.value(0).value<QDBusObjectPath>().path(), AGENT_PATH);
        QCOMPARE(reg.first().args.value(1).toString(), QStringLiteral("DisplayYesNo"));
        QCOMPARE(bluezObj->callsTo(QStringLiteral("RequestDefaultAgent")).first().args.value(0)
                 .value<QDBusObjectPath>().path(), AGENT_PATH);
    }

    void registersWithBluezAlreadyThere()
    {
        BluetoothAgent agent;
        // the constructor's RegisterAgent is a blocking call
        QCOMPARE(bluezObj->callsTo(QStringLiteral("RegisterAgent")).size(), 1);
        QTRY_COMPARE(bluezObj->callsTo(QStringLiteral("RequestDefaultAgent")).size(), 1);
    }

    void confirmationAccepted()
    {
        BluetoothAgent agent;
        mceObj->clear();
        QSignalSpy visibleSpy(&agent, &BluetoothAgent::windowVisibleChanged);
        QSignalSpy passkeySpy(&agent, &BluetoothAgent::passkeyChanged);

        QDBusPendingCall call = callAgent(QStringLiteral("RequestConfirmation"), { path(DEVICE), QVariant::fromValue(quint32(123456)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqConfirmation);
        QVERIFY(agent.windowVisible());
        QCOMPARE(visibleSpy.count(), 1);
        QCOMPARE(agent.getPasskey(), 123456u);
        QCOMPARE(passkeySpy.count(), 1);
        QVERIFY(agent.m_windowTimeout.isActive());
        QTRY_COMPARE(mceRequests(mceObj), WINDOW_SHOWN);
        QTest::qWait(20);
        QVERIFY(!call.isFinished()); // waits for the user

        agent.userAccepts();
        QTRY_VERIFY(call.isFinished());
        QCOMPARE(call.reply().type(), QDBusMessage::ReplyMessage);
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
        QTRY_COMPARE(trusted(), QStringList { DEVICE });
        QEXPECT_FAIL("", "BUG (upstream): setTrusted() passes a bool, BlueZ needs a variant: the device is never "
                         "trusted (patches/launcher/0001)", Continue);
        QVERIFY(trustedSentAsVariant());

        // the QML closes the window
        mceObj->clear();
        agent.setWindowVisible(false);
        QVERIFY(!agent.m_windowTimeout.isActive());
        QCOMPARE(visibleSpy.count(), 2);
        QTRY_COMPARE(mceRequests(mceObj), WINDOW_HIDDEN);
        agent.setWindowVisible(false); // no change, nothing sent
        QCOMPARE(visibleSpy.count(), 2);
    }

    void confirmationRejected()
    {
        BluetoothAgent agent;
        QDBusPendingCall call = callAgent(QStringLiteral("RequestConfirmation"), { path(DEVICE), QVariant::fromValue(quint32(1)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqConfirmation);
        agent.userCancels();
        QTRY_VERIFY(call.isFinished());
        QCOMPARE(call.reply().type(), QDBusMessage::ErrorMessage);
        QCOMPARE(call.error().name(), QStringLiteral("org.bluez.Error.Rejected"));
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
        QTest::qWait(20);
        QVERIFY(trusted().isEmpty());
    }

    // RequestPinCode used not to keep its message: the PIN went to the previous, answered request
    // and BlueZ timed the pairing out
    void pinCodeAnswersItsOwnRequest()
    {
        BluetoothAgent agent;
        QDBusPendingCall first = callAgent(QStringLiteral("RequestConfirmation"), { path(DEVICE), QVariant::fromValue(quint32(2)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqConfirmation);
        agent.userAccepts();
        QTRY_VERIFY(first.isFinished());
        bluezObj->clear();

        QDBusPendingCall pin = callAgent(QStringLiteral("RequestPinCode"), { path(DEVICE) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqPinCode);
        QTRY_COMPARE(trusted(), QStringList { DEVICE }); // trusted up front, as upstream
        agent.setPinCode(QStringLiteral("0000"));
        agent.userAccepts();
        QTRY_VERIFY_WITH_TIMEOUT(pin.isFinished(), 3000);
        QCOMPARE(pin.reply().type(), QDBusMessage::ReplyMessage);
        QCOMPARE(pin.reply().arguments().value(0).toString(), QStringLiteral("0000"));
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
    }

    void passkeyAnswersItsOwnRequest()
    {
        BluetoothAgent agent;
        QDBusPendingCall first = callAgent(QStringLiteral("RequestAuthorization"), { path(DEVICE) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqAuthorization);
        agent.userAccepts();
        QTRY_VERIFY(first.isFinished());

        QDBusPendingCall passkey = callAgent(QStringLiteral("RequestPasskey"), { path(DEVICE) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqPasskey);
        agent.setPasskey(4321);
        agent.userAccepts();
        QTRY_VERIFY_WITH_TIMEOUT(passkey.isFinished(), 3000);
        QCOMPARE(passkey.reply().type(), QDBusMessage::ReplyMessage);
        QCOMPARE(passkey.reply().arguments().value(0).toUInt(), 4321u);
    }

    void pinCodeRejected()
    {
        BluetoothAgent agent;
        QDBusPendingCall pin = callAgent(QStringLiteral("RequestPinCode"), { path(DEVICE) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqPinCode);
        agent.userCancels();
        QTRY_VERIFY(pin.isFinished());
        QCOMPARE(pin.error().name(), QStringLiteral("org.bluez.Error.Rejected"));
    }

    void displayOnlyCodes()
    {
        BluetoothAgent agent;
        QSignalSpy pinSpy(&agent, &BluetoothAgent::pinCodeChanged);
        QDBusPendingCall pin = callAgent(QStringLiteral("DisplayPinCode"), { path(DEVICE), QStringLiteral("123456") });
        QTRY_VERIFY(pin.isFinished()); // nothing to answer
        QCOMPARE(pin.reply().type(), QDBusMessage::ReplyMessage);
        QCOMPARE(agent.getState(), BluetoothAgent::DispPinCode);
        QCOMPARE(agent.getPinCode(), QStringLiteral("123456"));
        QCOMPARE(pinSpy.count(), 1);
        QVERIFY(agent.windowVisible());

        QDBusPendingCall passkey = callAgent(QStringLiteral("DisplayPasskey"),
                                             { path(DEVICE), QVariant::fromValue(quint32(654321)), QVariant::fromValue(quint16(2)) });
        QTRY_VERIFY(passkey.isFinished());
        QCOMPARE(agent.getState(), BluetoothAgent::DispPasskey);
        QCOMPARE(agent.getPasskey(), 654321u);

        // accepting a code that needs no answer sends nothing
        agent.userAccepts();
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
    }

    void authorizeService()
    {
        BluetoothAgent agent;
        const QString uuid = QStringLiteral("0000110a-0000-1000-8000-00805f9b34fb");
        QDBusPendingCall call = callAgent(QStringLiteral("AuthorizeService"), { path(DEVICE), uuid });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::AuthService);
        QCOMPARE(agent.getPinCode(), uuid);
        agent.userAccepts();
        QTRY_VERIFY(call.isFinished());
        QCOMPARE(call.reply().type(), QDBusMessage::ReplyMessage);

        QDBusPendingCall again = callAgent(QStringLiteral("AuthorizeService"), { path(DEVICE), uuid });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::AuthService);
        agent.userCancels();
        QTRY_VERIFY(again.isFinished());
        QCOMPARE(again.error().name(), QStringLiteral("org.bluez.Error.Rejected"));
    }

    void cancelAndRelease_data()
    {
        QTest::addColumn<QString>("member");
        QTest::newRow("Cancel") << QStringLiteral("Cancel");
        QTest::newRow("Release") << QStringLiteral("Release");
    }

    void cancelAndRelease()
    {
        QFETCH(QString, member);
        BluetoothAgent agent;
        mceObj->clear(); // its get_config at start
        callAgent(QStringLiteral("RequestConfirmation"), { path(DEVICE), QVariant::fromValue(quint32(3)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqConfirmation);
        QTRY_COMPARE(mceRequests(mceObj), WINDOW_SHOWN);
        mceObj->clear();
        QDBusPendingCall cancel = callAgent(member, {});
        QTRY_VERIFY(cancel.isFinished());
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
        QVERIFY(!agent.windowVisible());
        QVERIFY(!agent.m_windowTimeout.isActive());
        QTRY_COMPARE(mceRequests(mceObj), WINDOW_HIDDEN);
    }

    // nobody answers: the backstop rejects the request and closes the window (and its display-on)
    void windowTimeoutRejectsPendingRequest()
    {
        BluetoothAgent agent;
        QCOMPARE(agent.m_windowTimeout.interval(), 120000);
        QVERIFY(agent.m_windowTimeout.isSingleShot());
        agent.m_windowTimeout.setInterval(100);
        QDBusPendingCall call = callAgent(QStringLiteral("RequestConfirmation"), { path(DEVICE), QVariant::fromValue(quint32(4)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqConfirmation);
        mceObj->clear();
        QTRY_VERIFY_WITH_TIMEOUT(call.isFinished(), 3000);
        QCOMPARE(call.error().name(), QStringLiteral("org.bluez.Error.Rejected"));
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
        QVERIFY(!agent.windowVisible());
        QTRY_COMPARE(mceRequests(mceObj), WINDOW_HIDDEN);
    }

    void windowTimeoutClosesDisplayOnlyWindow()
    {
        BluetoothAgent agent;
        agent.m_windowTimeout.setInterval(100);
        callAgent(QStringLiteral("DisplayPasskey"), { path(DEVICE), QVariant::fromValue(quint32(5)), QVariant::fromValue(quint16(0)) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::DispPasskey);
        QTRY_VERIFY_WITH_TIMEOUT(!agent.windowVisible(), 3000);
        QCOMPARE(agent.getState(), BluetoothAgent::Idle);
    }

    void bluezGoingAwayClosesWindow()
    {
        BluetoothAgent agent;
        callAgent(QStringLiteral("RequestAuthorization"), { path(DEVICE) });
        QTRY_COMPARE(agent.getState(), BluetoothAgent::ReqAuthorization);
        QVERIFY(bluez->unregisterName());
        QTRY_COMPARE(agent.getState(), BluetoothAgent::Idle);
        QVERIFY(!agent.windowVisible());

        // and registers again when it is back
        bluezObj->clear();
        QTRY_VERIFY(!QDBusConnection::systemBus().interface()->isServiceRegistered(QStringLiteral("org.bluez")).value());
        QVERIFY(bluez->registerName());
        QTRY_COMPARE(bluezObj->callsTo(QStringLiteral("RegisterAgent")).size(), 1);
    }

    void propertiesSetters()
    {
        BluetoothAgent agent;
        QSignalSpy stateSpy(&agent, &BluetoothAgent::stateChanged);
        QSignalSpy pinSpy(&agent, &BluetoothAgent::pinCodeChanged);
        QSignalSpy passkeySpy(&agent, &BluetoothAgent::passkeyChanged);
        agent.setState(BluetoothAgent::Idle);
        agent.setPinCode(QString());
        agent.setPasskey(0);
        QCOMPARE(stateSpy.count() + pinSpy.count() + passkeySpy.count(), 0);
        QVERIFY(agent.setProperty("windowVisible", true));
        QVERIFY(agent.property("windowVisible").toBool());
        QVERIFY(agent.setProperty("pinCode", QStringLiteral("1234")));
        QCOMPARE(pinSpy.count(), 1);
    }

    // The window of a display-only code (DisplayPasskey / DisplayPinCode) has a Cancel button. When no
    // request came before it since lipstick started, userCancels() sends an error reply to no message
    // and libdbus aborts lipstick ("dbus_message_set_reply_serial ... reply_serial != 0"). Run in a
    // child process (this binary, this function) so that the abort does not end the suite.
    void cancelOfFirstDisplayOnlyCode()
    {
        if (qEnvironmentVariableIsSet("TST_BT_CHILD")) {
            BluetoothAgent agent;
            callAgent(QStringLiteral("DisplayPasskey"), { path(DEVICE), QVariant::fromValue(quint32(6)), QVariant::fromValue(quint16(0)) });
            QTRY_COMPARE(agent.getState(), BluetoothAgent::DispPasskey);
            agent.userCancels();
            QCOMPARE(agent.getState(), BluetoothAgent::Idle);
            return;
        }
        QProcess child;
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("TST_BT_CHILD"), QStringLiteral("1"));
        child.setProcessEnvironment(env);
        child.setProcessChannelMode(QProcess::MergedChannels);
        child.start(QCoreApplication::applicationFilePath(), { QStringLiteral("cancelOfFirstDisplayOnlyCode") });
        QVERIFY(child.waitForFinished(60000));
        const QByteArray output = child.readAll();
        const bool survived = child.exitStatus() == QProcess::NormalExit && child.exitCode() == 0;
        if (!survived && !output.contains("reply_serial"))
            qWarning().noquote() << output; // not the known abort: show why
        QEXPECT_FAIL("", "BUG: userCancels() of a display-only code with no request before it aborts lipstick "
                         "in libdbus (patches/launcher/0001)", Continue);
        QVERIFY(survived);
    }
};

QTEST_GUILESS_MAIN(TestBluetoothAgent)
#include "tst_bluetoothagent.moc"
