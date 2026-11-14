/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The crown's triggers (src/crownbutton.h) against a fake mce on a private bus (power-boot-warnings-01,
 * wake-sleep-display-03, system-dialogs-misc-08): each power_button_trigger argument makes its signal,
 * and only its own:
 *   asteroid-crown        pressed        asteroid-crown-wake  wakePressed
 *   asteroid-crown-long   longPressed    asteroid-crown-down  pressStarted
 *   asteroid-crown-up     released       screenshot           screenshotRequested
 *   anything else         triggered(action)
 * Run it as: dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS ./tst_crownbutton'
 */

#include "crownbutton.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QStringList>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

struct Counts {
    int pressed = 0, wake = 0, longp = 0, down = 0, up = 0, shot = 0;
    QStringList other;
    QString text() const
    {
        return QStringLiteral("%1 %2 %3 %4 %5 %6 [%7]").arg(pressed).arg(wake).arg(longp).arg(down).arg(up).arg(shot)
            .arg(other.join(QLatin1Char(',')));
    }
};

static void send(const QString &arg)
{
    QDBusMessage m = QDBusMessage::createSignal(QStringLiteral("/com/nokia/mce/signal"),
                                                QStringLiteral("com.nokia.mce.signal"),
                                                QStringLiteral("power_button_trigger"));
    m << arg;
    QDBusConnection::systemBus().send(m);
}

// the signals reach the object through the bus: let the loop run until nothing more comes
static void settle()
{
    QElapsedTimer t;
    t.start();
    while (t.elapsed() < 250)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    CrownButton crown;
    Counts c;
    QObject::connect(&crown, &CrownButton::pressed, [&] { c.pressed++; });
    QObject::connect(&crown, &CrownButton::wakePressed, [&] { c.wake++; });
    QObject::connect(&crown, &CrownButton::longPressed, [&] { c.longp++; });
    QObject::connect(&crown, &CrownButton::pressStarted, [&] { c.down++; });
    QObject::connect(&crown, &CrownButton::released, [&] { c.up++; });
    QObject::connect(&crown, &CrownButton::screenshotRequested, [&] { c.shot++; });
    QObject::connect(&crown, &CrownButton::triggered, [&](const QString &a) { c.other << a; });

    struct Case { const char *arg; const char *expect; };
    const Case cases[] = {
        { "asteroid-crown",      "1 0 0 0 0 0 []" },
        { "asteroid-crown-wake", "0 1 0 0 0 0 []" },
        { "asteroid-crown-long", "0 0 1 0 0 0 []" },
        { "asteroid-crown-down", "0 0 0 1 0 0 []" },
        { "asteroid-crown-up",   "0 0 0 0 1 0 []" },
        { "screenshot",          "0 0 0 0 0 1 []" },
        { "side-key",            "0 0 0 0 0 0 [side-key]" },
        { "side-key-long",       "0 0 0 0 0 0 [side-key-long]" },
        { "asteroid-crown-x",    "0 0 0 0 0 0 [asteroid-crown-x]" },
    };
    for (const Case &k : cases) {
        c = Counts();
        send(QString::fromLatin1(k.arg));
        settle();
        const QString got = c.text();
        if (got != QLatin1String(k.expect))
            fprintf(stderr, "case %s: got %s expected %s\n", k.arg, qPrintable(got), k.expect);
        CHECK(got == QLatin1String(k.expect));
    }

    // a hold as mce sends it with the edge triggers: down, (3 s) long, up
    c = Counts();
    send(QStringLiteral("asteroid-crown-down"));
    send(QStringLiteral("asteroid-crown-long"));
    send(QStringLiteral("asteroid-crown-up"));
    settle();
    CHECK(c.text() == QLatin1String("0 0 1 1 1 0 []"));

    if (failures)
        fprintf(stderr, "tst_crownbutton: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_crownbutton: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
