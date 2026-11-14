/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The call state service (src/callstate.h, CR-03 and CR-09) on a private session bus:
 *   dbus-run-session -- ./tst_callstate
 * CallState() answers 0, 1, 2 as the state is set; CallStateChanged(i) is sent on each change
 * (and is in the introspection, which is all Nemo.DBus connects: handler rcCallStateChanged);
 * the dconf key /org/asteroidos/phone/call-active (an MDConfItem stand-in) is false at start,
 * true while the state is above 0.
 */

#include "callstate.h"
#include "dbusintrospect.h"

#include <MDConfItem>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QEventLoop>
#include <QTimer>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

class Receiver : public QObject
{
    Q_OBJECT
public:
    QList<int> got;
public slots:
    // what the QML handler rcCallStateChanged(state) is
    void rcCallStateChanged(int state) { got << state; }
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
    QDBusConnection session = QDBusConnection::sessionBus();
    if (!session.isConnected()) {
        fprintf(stderr, "no session bus: run under dbus-run-session\n");
        return 2;
    }
    const QString key = QStringLiteral("/org/asteroidos/phone/call-active");
    // an earlier launcher left "a call is on" behind
    MDConfItem::store().insert(key, true);

    CallStateService svc(nullptr, session);
    CHECK(svc.state() == 0);
    CHECK(MDConfItem::store().contains(key));
    CHECK(MDConfItem::store().value(key).toBool() == false);   // CR-09: false at start

    QDBusConnection client = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("cs-client"));
    CHECK(client.isConnected());
    const QString svcName = session.baseService();
    const QString path = QStringLiteral("/org/asteroidos/launcher/call");
    const QString iface = QStringLiteral("org.asteroidos.launcher.Call");

    // what Nemo.DBus sees (CR-03)
    const Introspected intro = introspect(client, svcName, path);
    CHECK(intro.hasMethod(iface + ".CallState"));
    CHECK(intro.methodsOf.value(iface + ".CallState").isEmpty());
    CHECK(intro.hasSignal(iface + ".CallStateChanged"));
    CHECK(intro.signalsOf.value(iface + ".CallStateChanged") == QStringList({ "i" }));
    // the old spellings are not offered beside the contract's
    CHECK(!intro.hasSignal(iface + ".StateChanged"));
    CHECK(!intro.hasMethod(iface + ".State"));

    Receiver rx;
    CHECK(intro.hasSignal(iface + ".CallStateChanged")
          && client.connect(svcName, path, iface, QStringLiteral("CallStateChanged"), &rx, SLOT(rcCallStateChanged(int))));

    auto answer = [&]() {
        const QDBusMessage r = busCall(client, svcName, path, iface, QStringLiteral("CallState"));
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty() ? r.arguments().at(0).toInt() : -1;
    };
    CHECK(answer() == 0);

    const int writes0 = MDConfItem::writes();
    svc.setState(1);                                    // ringing
    CHECK(answer() == 1);
    CHECK(MDConfItem::store().value(key).toBool() == true);
    CHECK(MDConfItem::writes() == writes0 + 1);
    svc.setState(2);                                    // answered: still a call, no second write
    CHECK(answer() == 2);
    CHECK(MDConfItem::store().value(key).toBool() == true);
    CHECK(MDConfItem::writes() == writes0 + 1);
    svc.setState(2);                                    // the same again: nothing
    svc.setState(0);                                    // over
    CHECK(answer() == 0);
    CHECK(MDConfItem::store().value(key).toBool() == false);
    CHECK(MDConfItem::writes() == writes0 + 2);
    svc.setState(9);                                    // not a state: counts as none, no change
    svc.setState(-3);
    CHECK(answer() == 0);
    spin(300);
    CHECK(rx.got == QList<int>({ 1, 2, 0 }));

    // without a dconf key nothing is written
    {
        const int w = MDConfItem::writes();
        CallStateService bare(nullptr, QDBusConnection(QStringLiteral("none")), QString());
        bare.setState(1);
        CHECK(MDConfItem::writes() == w && bare.state() == 1);
    }

    QDBusConnection::disconnectFromBus(QStringLiteral("cs-client"));
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_callstate.moc"
