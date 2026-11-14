/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// OffBody (src/offbody.h) against a fake sensor service on a private bus, with a stand-in for mlite's
// MDConfItem (tests/stubs/MDConfItem) for the dconf mirror (CR-44):
//   dbus-run-session -- ./tst_offbody

#include "offbody.h"

#include <MDConfItem>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QEventLoop>
#include <QTimer>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// the sensor service: GetOffBody() and the OffBodyChanged signal
class Fake : public QObject
{
    Q_OBJECT
public:
    int state = -1;
    int calls = 0;
public slots:
    int GetOffBody() { calls++; return state; }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        fprintf(stderr, "no session bus (run under dbus-run-session)\n");
        return 2;
    }

    // an earlier launcher left both keys true
    const QString keyOff = QString::fromLatin1(OffBody::OffBodyKey);
    const QString keyAvail = QString::fromLatin1(OffBody::AvailableKey);
    CHECK(keyOff == "/org/asteroidos/sensors/off-body" && keyAvail == "/org/asteroidos/sensors/off-body-available");
    MDConfItem::store().insert(keyOff, true);
    MDConfItem::store().insert(keyAvail, true);
    auto mirrorOff = [&] { return MDConfItem::store().value(keyOff); };
    auto mirrorAvail = [&] { return MDConfItem::store().value(keyAvail); };

    // ---- no service: unknown, the rule treats it as on the wrist ----
    OffBody ob(nullptr, bus);
    spin(200);
    CHECK(ob.state() == -1);
    CHECK(!ob.known());
    CHECK(!ob.offBody());
    // dconf: unknown too, what was left behind is overwritten (written once, at start)
    CHECK(mirrorOff().isValid() && !mirrorOff().toBool());
    CHECK(mirrorAvail().isValid() && !mirrorAvail().toBool());
    CHECK(MDConfItem::writes() == 2);
    int changes = 0;
    QObject::connect(&ob, &OffBody::changed, [&] { changes++; });

    // ---- the service appears: the state is read once ----
    Fake fake;
    fake.state = 1;
    CHECK(bus.registerObject(QString::fromLatin1(OffBody::Path), QString::fromLatin1(OffBody::Interface), &fake,
                             QDBusConnection::ExportAllSlots));
    CHECK(bus.registerService(QString::fromLatin1(OffBody::Service)));
    spin(300);
    CHECK(fake.calls == 1);
    CHECK(ob.known());
    CHECK(ob.offBody());
    CHECK(ob.state() == 1);
    CHECK(changes == 1);
    // off the wrist, and the sensor is there
    CHECK(mirrorOff().toBool());
    CHECK(mirrorAvail().toBool());
    CHECK(MDConfItem::writes() == 4);

    // ---- on change only: the signal moves it, nothing polls ----
    auto emitState = [&](int v) {
        QDBusMessage m = QDBusMessage::createSignal(QString::fromLatin1(OffBody::Path),
                                                    QString::fromLatin1(OffBody::Interface), QStringLiteral("OffBodyChanged"));
        m << v;
        bus.send(m);
        spin(150);
    };
    emitState(0);
    CHECK(ob.state() == 0);
    CHECK(!ob.offBody());
    CHECK(ob.known());
    CHECK(changes == 2);
    CHECK(!mirrorOff().toBool() && mirrorAvail().toBool());   // on the wrist
    CHECK(MDConfItem::writes() == 5);                         // only off-body changed
    emitState(0);                  // the same again: no change, no write
    CHECK(changes == 2);
    CHECK(MDConfItem::writes() == 5);
    emitState(1);
    CHECK(ob.offBody());
    CHECK(changes == 3);
    CHECK(mirrorOff().toBool() && mirrorAvail().toBool());
    CHECK(MDConfItem::writes() == 6);
    emitState(7);                  // out of range: unknown
    CHECK(ob.state() == -1);
    CHECK(changes == 4);
    CHECK(!mirrorOff().toBool() && !mirrorAvail().toBool());  // unknown: not available
    CHECK(MDConfItem::writes() == 8);
    spin(1500);
    CHECK(fake.calls == 1);        // no polling at all
    CHECK(MDConfItem::writes() == 8);

    // ---- the service goes: unknown; it comes back: read again ----
    bus.unregisterService(QString::fromLatin1(OffBody::Service));
    spin(300);
    CHECK(ob.state() == -1);
    CHECK(!mirrorAvail().toBool());
    fake.state = 0;
    CHECK(bus.registerService(QString::fromLatin1(OffBody::Service)));
    spin(300);
    CHECK(fake.calls == 2);
    CHECK(ob.state() == 0);
    CHECK(mirrorAvail().toBool() && !mirrorOff().toBool());

    printf("tst_offbody: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_offbody.moc"
