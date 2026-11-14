/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The launcher's session bus surface by its name (CR-01 to CR-06) on a private session bus:
 *   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS ./tst_launcherbus'
 * The objects the launcher exports (Keys, Ongoing, Assistant, Lock, Call) are created as main.cpp
 * creates them; the name org.asteroidos.launcher is registered as lipstick's HomeApplication does
 * (and a lint reads that source, as it cannot be built on the host). A second connection (an app)
 * calls every object by the NAME and introspects it; before the name is registered the same call
 * fails, which is today's fault (the objects hang under the unique name only).
 */

#include "assistantkey.h"
#include "callstate.h"
#include "dbusintrospect.h"
#include "keyclaims.h"
#include "lockservice.h"
#include "ongoingregistry.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QEventLoop>
#include <QFile>
#include <QTemporaryDir>
#include <QTimer>
#include <unistd.h>
#include <cstdio>

#ifndef SRC_ROOT
#error "SRC_ROOT: the asteroid-launcher tree"
#endif

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QString slurp(const QString &rel)
{
    QFile f(QStringLiteral(SRC_ROOT "/") + rel);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QDBusConnection session = QDBusConnection::sessionBus();
    if (!session.isConnected()) {
        fprintf(stderr, "no session bus: run under dbus-run-session\n");
        return 2;
    }
    const QString name = QStringLiteral("org.asteroidos.launcher");

    // ---- the registration in the launcher's source ----
    const QString home = slurp("lipstick/src/homeapplication.cpp");
    const QString dbusH = slurp("lipstick/src/lipstickdbus.h");
    CHECK(!home.isEmpty() && !dbusH.isEmpty());
    CHECK(dbusH.contains(QStringLiteral("#define LAUNCHER_SESSION_SERVICE_NAME \"org.asteroidos.launcher\"")));
    CHECK(home.contains(QStringLiteral("sessionBus.registerService(QLatin1String(LAUNCHER_SESSION_SERVICE_NAME))")));
    CHECK(home.contains(QStringLiteral("QDBusConnection sessionBus = QDBusConnection::sessionBus();")));
    // org.nemomobile.lipstick stays on the system bus only
    CHECK(home.contains(QStringLiteral("systemBus.registerService(LIPSTICK_DBUS_SERVICE_NAME)")));
    CHECK(!home.contains(QStringLiteral("sessionBus.registerService(LIPSTICK_DBUS_SERVICE_NAME)")));
    // the call state follows lipstickSettings.callState (main.cpp)
    const QString mainCpp = slurp("src/main.cpp");
    CHECK(mainCpp.contains(QStringLiteral("new CallStateService(&app)")));
    CHECK(mainCpp.contains(QStringLiteral("&LipstickSettings::callStateChanged")));
    CHECK(mainCpp.contains(QStringLiteral("callState->setState(LipstickSettings::instance()->callState())")));

    // ---- the objects, as main.cpp makes them ----
    QTemporaryDir dir;
    CHECK(dir.isValid());
    KeyClaims keys(nullptr, session);
    OngoingRegistry ongoing(nullptr, session);
    CallStateService call(nullptr, session);
    AssistantKey assistant;
    LockService lock(nullptr, session, dir.filePath(QStringLiteral("lock")));
    QStringList asked;
    QObject::connect(&assistant, &AssistantKey::openRequested, [&](const QString &t) { asked << t; });

    QDBusConnection client = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("app"));
    CHECK(client.isConnected());
    const QString kPath = QStringLiteral("/org/asteroidos/launcher/keys");
    const QString kIf = QStringLiteral("org.asteroidos.launcher.Keys");

    // ---- no name yet: an app cannot reach the object ----
    {
        const QDBusMessage r = busCall(client, name, kPath, kIf, QStringLiteral("Claim"), { QStringLiteral("side") });
        CHECK(r.type() == QDBusMessage::ErrorMessage);
        CHECK(!session.interface()->isServiceRegistered(name));
    }

    // ---- the name, as HomeApplication takes it ----
    CHECK(session.registerService(name));
    CHECK(session.interface()->isServiceRegistered(name));
    CHECK(session.interface()->serviceOwner(name).value() == session.baseService());

    // Keys by name (CR-02)
    keys.setFrontPid(getpid());
    CHECK(busCall(client, name, kPath, kIf, QStringLiteral("Claim"), { QStringLiteral("side") }).type() == QDBusMessage::ReplyMessage);
    CHECK(keys.claimed("side") && !keys.claimed("crown"));
    {
        const Introspected i = introspect(client, name, kPath);
        CHECK(i.signalsOf.value(kIf + ".Key") == QStringList({ "s", "i" }));
        CHECK(i.hasMethod(kIf + ".Claim") && i.hasMethod(kIf + ".Release"));
    }
    CHECK(busCall(client, name, kPath, kIf, QStringLiteral("Release")).type() == QDBusMessage::ReplyMessage);
    CHECK(!keys.claimed("side"));

    // Ongoing by name (CR-04)
    const QString oPath = QStringLiteral("/org/asteroidos/launcher/ongoing");
    const QString oIf = QStringLiteral("org.asteroidos.launcher.Ongoing");
    {
        QVariantMap p;
        p["category"] = QStringLiteral("stopwatch");
        p["app"] = QStringLiteral("asteroid-stopwatch");
        p["status"] = QStringLiteral("%t");
        p["title"] = QStringLiteral("asteroid-stopwatch");
        const int before = ongoing.count();
        CHECK(busCall(client, name, oPath, oIf, QStringLiteral("Publish"), { QStringLiteral("sw"), p }).type() == QDBusMessage::ReplyMessage);
        CHECK(ongoing.count() == before + 1);
        CHECK(busCall(client, name, oPath, oIf, QStringLiteral("SetInUse"), { QStringLiteral("mic"), true }).type() == QDBusMessage::ReplyMessage);
        CHECK(ongoing.micInUse());
        CHECK(busCall(client, name, oPath, oIf, QStringLiteral("Remove"), { QStringLiteral("sw") }).type() == QDBusMessage::ReplyMessage);
        CHECK(ongoing.count() == before);
        const Introspected i = introspect(client, name, oPath);
        CHECK(i.signalsOf.value(oIf + ".Activated") == QStringList({ "s" }));
    }

    // Call by name (CR-03)
    const QString cPath = QStringLiteral("/org/asteroidos/launcher/call");
    const QString cIf = QStringLiteral("org.asteroidos.launcher.Call");
    {
        QDBusMessage r = busCall(client, name, cPath, cIf, QStringLiteral("CallState"));
        CHECK(r.type() == QDBusMessage::ReplyMessage && r.arguments().value(0).toInt() == 0);
        call.setState(2);
        r = busCall(client, name, cPath, cIf, QStringLiteral("CallState"));
        CHECK(r.arguments().value(0).toInt() == 2);
        call.setState(0);
        const Introspected i = introspect(client, name, cPath);
        CHECK(i.signalsOf.value(cIf + ".CallStateChanged") == QStringList({ "i" }));
    }

    // Assistant by name (CR-05)
    const QString aPath = QStringLiteral("/org/asteroidos/launcher/assistant");
    const QString aIf = QStringLiteral("org.asteroidos.launcher.Assistant");
    CHECK(busCall(client, name, aPath, aIf, QStringLiteral("Open")).type() == QDBusMessage::ReplyMessage);
    CHECK(busCall(client, name, aPath, aIf, QStringLiteral("Ask"), { QStringLiteral("what time is it") }).type() == QDBusMessage::ReplyMessage);
    spin(100);
    CHECK(asked == QStringList({ QString(), QStringLiteral("what time is it") }));

    // Lock by name (CR-06)
    const QString lPath = QStringLiteral("/org/asteroidos/launcher/lock");
    const QString lIf = QStringLiteral("org.asteroidos.launcher.Lock");
    {
        QDBusMessage r = busCall(client, name, lPath, lIf, QStringLiteral("State"));
        CHECK(r.type() == QDBusMessage::ReplyMessage && r.arguments().value(0).toString() == "none");
        r = busCall(client, name, lPath, lIf, QStringLiteral("Locked"));
        CHECK(r.type() == QDBusMessage::ReplyMessage && r.arguments().value(0).toBool() == false);
        r = busCall(client, name, lPath, lIf, QStringLiteral("SetPin"), { QString(), QStringLiteral("1234") });
        CHECK(r.type() == QDBusMessage::ReplyMessage && r.arguments().value(0).toInt() == 0);
        r = busCall(client, name, lPath, lIf, QStringLiteral("State"));
        CHECK(r.arguments().value(0).toString() == "pin");
        const Introspected i = introspect(client, name, lPath);
        CHECK(i.signalsOf.value(lIf + ".LockedChanged") == QStringList({ "b" }));
        CHECK(i.signalsOf.value(lIf + ".StateChanged") == QStringList({ "s" }));
        for (const char *m : { "State", "Locked", "Verify", "SetPin", "SetPattern", "Clear", "Lock", "Remaining" })
            CHECK(i.hasMethod(lIf + "." + QLatin1String(m)));
        r = busCall(client, name, lPath, lIf, QStringLiteral("Clear"), { QStringLiteral("1234") });
        CHECK(r.arguments().value(0).toInt() == 0);
    }

    // the name has one owner, the launcher: the app's own connection is another
    CHECK(client.baseService() != session.baseService());

    QDBusConnection::disconnectFromBus(QStringLiteral("app"));
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
