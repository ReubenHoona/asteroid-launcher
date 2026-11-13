/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Key claims (src/keyclaims.h): the table by process and key, and the bus
 * object on a private session bus:
 *   dbus-run-session -- ./tst_keyclaims
 * A second connection claims the side button and the crown, the launcher
 * side offers presses to it (a targeted signal), Release and leaving the
 * bus end the claim.
 */

#include "keyclaims.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QEventLoop>
#include <QStringList>
#include <QTimer>
#include <unistd.h>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

class Receiver : public QObject
{
    Q_OBJECT
public:
    QStringList got;
public slots:
    void Key(const QString &key, int count) { got << QStringLiteral("%1:%2").arg(key).arg(count); }
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
    using namespace EosKeys;

    // ---- the table ----
    CHECK(keyFromName("side") == SideKey);
    CHECK(keyFromName(" Crown ") == CrownKey);
    CHECK(keyFromName("volume") == NoKey);
    CHECK(keysFromList("side,crown") == (SideKey | CrownKey));
    CHECK(keysFromList("side") == SideKey);
    CHECK(keysFromList("x,,crown") == CrownKey);
    CHECK(keysFromList("") == NoKey);
    ClaimTable t;
    CHECK(t.owner(100, SideKey).isEmpty());
    t.claim(":1.5", 100, SideKey);
    CHECK(t.owner(100, SideKey) == ":1.5");
    CHECK(t.owner(100, CrownKey).isEmpty());            // only the key claimed
    CHECK(t.owner(101, SideKey).isEmpty());             // only while its process is in front
    t.claim(":1.5", 100, CrownKey);                     // replaces the earlier claim of the service
    CHECK(t.owner(100, SideKey).isEmpty());
    CHECK(t.owner(100, CrownKey) == ":1.5");
    t.claim(":1.6", 100, SideKey | CrownKey);           // the newest claim of a process wins
    CHECK(t.owner(100, CrownKey) == ":1.6");
    t.release(":1.6");
    CHECK(t.owner(100, CrownKey) == ":1.5");
    t.claim(":1.7", 0, SideKey);                        // no process: no claim
    CHECK(t.count() == 1);
    t.release(":1.5");
    CHECK(t.count() == 0);

    // ---- the bus object ----
    QDBusConnection session = QDBusConnection::sessionBus();
    if (!session.isConnected()) {
        fprintf(stderr, "no session bus: run under dbus-run-session\n");
        return 2;
    }
    KeyClaims claims(nullptr, session);
    QDBusConnection client = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("claimant"));
    CHECK(client.isConnected());
    Receiver receiver;
    const QString path = QStringLiteral("/org/asteroidos/launcher/keys");
    const QString iface = QStringLiteral("org.asteroidos.launcher.Keys");
    CHECK(client.connect(session.baseService(), path, iface, QStringLiteral("Key"), &receiver, SLOT(Key(QString,int))));

    claims.setFrontPid(getpid());
    CHECK(!claims.claimed("side"));
    CHECK(!claims.offer("side", 1));

    // asynchronous: the object lives in this thread, a blocking call would wait for itself
    auto call = [&](const QString &method, const QVariantList &args) {
        QDBusMessage m = QDBusMessage::createMethodCall(session.baseService(), path, iface, method);
        m.setArguments(args);
        QDBusPendingCall pc = client.asyncCall(m, 3000);
        QDBusPendingCallWatcher w(pc);
        QEventLoop loop;
        QObject::connect(&w, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
        if (!pc.isFinished())
            loop.exec();
        return pc.reply();
    };
    CHECK(call("Claim", { QStringLiteral("side,crown") }).type() == QDBusMessage::ReplyMessage);
    CHECK(claims.claimed("side"));
    CHECK(claims.claimed("crown"));
    CHECK(claims.offer("side", 2));
    CHECK(claims.offer("crown", 1));
    spin(300);
    CHECK(receiver.got == QStringList({ "side:2", "crown:1" }));

    // another window in front: the claim does not hold
    claims.setFrontPid(getpid() + 1);
    CHECK(!claims.claimed("side"));
    CHECK(!claims.offer("side", 1));
    claims.setFrontPid(getpid());
    CHECK(claims.claimed("side"));

    // a new claim replaces the old
    CHECK(call("Claim", { QStringLiteral("crown") }).type() == QDBusMessage::ReplyMessage);
    CHECK(!claims.claimed("side"));
    CHECK(claims.claimed("crown"));

    // Release
    CHECK(call("Release", {}).type() == QDBusMessage::ReplyMessage);
    CHECK(!claims.claimed("crown"));

    // a claim ends when the claimant leaves the bus
    CHECK(call("Claim", { QStringLiteral("side") }).type() == QDBusMessage::ReplyMessage);
    CHECK(claims.claimed("side"));
    QDBusConnection::disconnectFromBus(QStringLiteral("claimant"));
    client = QDBusConnection(QStringLiteral("none"));   // the last reference closes it
    spin(500);
    CHECK(!claims.claimed("side"));

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_keyclaims.moc"
