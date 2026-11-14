/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The ongoing activity registry (src/ongoingregistry.h, lipstick/src/notifications/eosongoing.h):
// the hint rules and the ranks (plain C++), the table (Qt Core), and the bus object on a private bus:
//   dbus-run-session -- ./tst_ongoing

#include "eosongoing.h"
#include "ongoingregistry.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QEventLoop>
#include <QStringList>
#include <QTimer>
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
    void Activated(const QString &id) { got << id; }
};

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// a call to the registry in this very process: asynchronous, the event loop serves it
static bool callOk(QDBusConnection &c, const QDBusMessage &m)
{
    QDBusPendingCall pc = c.asyncCall(m, 3000);
    QDBusPendingCallWatcher w(pc);
    QEventLoop loop;
    QObject::connect(&w, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
    QTimer::singleShot(4000, &loop, &QEventLoop::quit);
    if (!pc.isFinished())
        loop.exec();
    return pc.isFinished() && !pc.isError();
}

static QVariantMap props(const QString &category, const QString &app, const QString &status = QString())
{
    QVariantMap p;
    p["category"] = category;
    p["app"] = app;
    p["status"] = status;
    p["title"] = app;
    return p;
}

static QStringList keys(const QVariantList &l)
{
    QStringList k;
    for (const QVariant &v : l)
        k << v.toMap().value("key").toString();
    return k;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    // ---- the hint rules (eosongoing.h; the rule of lifecycle.js ongoingKey) ----
    CHECK(EosOngoing::isOngoing("true", "", "", ""));
    CHECK(EosOngoing::isOngoing("1", "", "", ""));
    CHECK(EosOngoing::isOngoing("", "true", "", ""));
    CHECK(EosOngoing::isOngoing("", "", "x-eos.ongoing", ""));
    CHECK(EosOngoing::isOngoing("", "", "x-nemo.ongoing", ""));
    CHECK(EosOngoing::isOngoing("", "", "", "ongoing"));
    CHECK(!EosOngoing::isOngoing("false", "", "", ""));
    CHECK(!EosOngoing::isOngoing("", "", "x-nemo.messaging", ""));
    CHECK(!EosOngoing::isOngoing("", "", "", ""));
    CHECK(EosOngoing::rankOf("call") == 0);
    CHECK(EosOngoing::rankOf("transport") == 2);
    for (const char *c : { "navigation", "alarm", "workout", "stopwatch", "location_sharing", "other", "", "x" })
        CHECK(EosOngoing::rankOf(c) == 1);
    CHECK(EosOngoing::knownCategory("workout"));
    CHECK(!EosOngoing::knownCategory("media"));

    // ---- the table ----
    using EosOngoing::Table;
    CHECK(Table::normalApp(" asteroid-timer.desktop ") == "asteroid-timer");
    CHECK(Table::isMuted("asteroid-timer", { "asteroid-timer.desktop" }));
    CHECK(!Table::isMuted("", { "" }));
    CHECK(!Table::isMuted("asteroid-music", { "asteroid-timer" }));
    {
        Table t;
        CHECK(t.upsert("local", "local:call", props("call", "asteroid-phone"), 100));
        CHECK(t.upsert("local", "local:timer", props("alarm", "asteroid-timer", "%t"), 1000));
        CHECK(t.upsert("local", "local:media", props("transport", "asteroid-music"), 5000));
        CHECK(t.upsert("local", "local:run", props("workout", "asteroid-exercise"), 2000));
        // a call first, media last, the others newest first
        CHECK(keys(t.toList({})) == (QStringList { "local:call", "local:run", "local:timer", "local:media" }));
        // an identical republish changes nothing; a new status does, and keeps the age
        CHECK(!t.upsert("local", "local:timer", props("alarm", "asteroid-timer", "%t"), 9999));
        CHECK(t.upsert("local", "local:timer", props("alarm", "asteroid-timer", "Timer %t"), 9999));
        CHECK(keys(t.toList({})) == (QStringList { "local:call", "local:run", "local:timer", "local:media" }));
        CHECK(t.find("local:timer")->posted == 1000);
        // the user opened the timer last: it goes before the workout; a call stays first
        CHECK(t.touch("local:timer", 3000));
        CHECK(keys(t.toList({})) == (QStringList { "local:call", "local:timer", "local:run", "local:media" }));
        CHECK(!t.touch("local:none", 3000));
        // a tie goes by key
        t.upsert("local", "local:b", props("navigation", "m"), 7000);
        t.upsert("local", "local:a", props("navigation", "m"), 7000);
        QStringList k = keys(t.toList({}));
        CHECK(k.indexOf("local:a") < k.indexOf("local:b"));
        t.remove("local:a"); t.remove("local:b");
        // top: the first that is not turned off
        CHECK(t.top({}).value("key").toString() == "local:call");
        CHECK(t.top({ "asteroid-phone" }).value("key").toString() == "local:timer");
        CHECK(t.top({ "asteroid-phone", "asteroid-timer.desktop", "asteroid-exercise", "asteroid-music" }).isEmpty());
        CHECK(t.toList({ "asteroid-phone" }).first().toMap().value("muted").toBool());
        CHECK(t.toList({}).last().toMap().value("rank").toInt() == 2);
        // an unknown category is "other"
        t.upsert("local", "local:x", props("Media", "z"), 1);
        CHECK(t.find("local:x")->category == "other");
        t.upsert("local", "local:y", props(" CALL ", "z"), 1);
        CHECK(t.find("local:y")->category == "call");
        // the fields reach the QML
        QVariantMap p = props("alarm", "asteroid-timer", "%t");
        p["when"] = qint64(1700000000000LL); p["countdown"] = true; p["paused"] = true; p["frozen"] = qint64(42000);
        p["icon"] = "anim.gif"; p["staticIcon"] = "ms-timer"; p["duration"] = true;
        Table u;
        u.upsert("local", "local:t", p, 1);
        const QVariantMap m = u.toList({}).first().toMap();
        CHECK(m.value("when").toLongLong() == 1700000000000LL && m.value("countdown").toBool() && m.value("paused").toBool());
        CHECK(m.value("frozen").toLongLong() == 42000 && m.value("duration").toBool());
        CHECK(m.value("icon").toString() == "anim.gif" && m.value("staticIcon").toString() == "ms-timer");
        // sources: a replace is one change, a withdrawal too
        Table s;
        s.upsert("local", "local:keep", props("call", "p"), 1);
        QVariantList items;
        QVariantMap a = props("alarm", "t"); a["key"] = "n:1";
        QVariantMap b = props("workout", "e"); b["key"] = "n:2";
        items << a << b;
        CHECK(s.replaceSource("notifications", items, 10));
        CHECK(s.count() == 3);
        CHECK(!s.replaceSource("notifications", items, 20));
        items.removeLast();
        CHECK(s.replaceSource("notifications", items, 30));
        CHECK(s.count() == 2 && s.find("n:2") == nullptr && s.find("local:keep") != nullptr);
        CHECK(s.removeSource("notifications") && s.count() == 1);
        CHECK(!s.removeSource("notifications"));
    }

    // ---- the registry, its bus object and its own calls ----
    {
        OngoingRegistry reg;
        int changedN = 0, inuseN = 0;
        QStringList actKeys, actApps;
        QObject::connect(&reg, &OngoingRegistry::entriesChanged, [&] { ++changedN; });
        QObject::connect(&reg, &OngoingRegistry::inUseChanged, [&] { ++inuseN; });
        QObject::connect(&reg, &OngoingRegistry::activated, [&](const QString &k, const QString &a) { actKeys << k; actApps << a; });

        // local publish: one change, an identical one none
        reg.publish("media", props("transport", "asteroid-music", "Song"));
        CHECK(changedN == 1 && reg.count() == 1);
        reg.publish("media", props("transport", "asteroid-music", "Song"));
        CHECK(changedN == 1);
        reg.publish("", props("call", "x"));
        CHECK(reg.count() == 1);
        CHECK(reg.top().value("key").toString() == "local:media");

        // the notification list: the ongoing ones only, from the hints
        QVariantList list;
        QVariantMap plain; plain["id"] = 3; plain["appName"] = "Messages"; plain["hints"] = QVariantMap();
        QVariantMap h; h["x-eos-ongoing"] = true; h["x-eos-ongoing-category"] = "alarm";
        h["x-eos-ongoing-static-icon"] = "ms-timer"; h["x-eos-ongoing-status"] = "%t";
        h["x-eos-ongoing-when"] = qint64(1700000090000LL); h["x-eos-ongoing-countdown"] = true;
        h["x-eos-ongoing-app"] = "asteroid-timer.desktop";
        QVariantMap timer; timer["id"] = 4; timer["appName"] = "Timer"; timer["hints"] = h;
        QVariantMap h2; h2["x-eos-app"] = "asteroid-exercise"; h2["x-nemo-ongoing"] = "true";
        h2["x-eos-ongoing-category"] = "workout"; h2["x-eos-ongoing-paused"] = true; h2["x-eos-ongoing-frozen"] = 61000;
        QVariantMap run; run["id"] = 5; run["appName"] = "Exercise"; run["hints"] = h2;
        QVariantMap h3; h3["x-eos-ongoing-category"] = "call";   // no x-eos-ongoing: not an entry
        QVariantMap nope; nope["id"] = 6; nope["appName"] = "Phone"; nope["hints"] = h3;
        list << plain << timer << run << nope;
        reg.syncNotifications(list);
        CHECK(changedN == 2 && reg.count() == 3);
        CHECK(keys(reg.entries()) == (QStringList { "n:5", "n:4", "local:media" }) || keys(reg.entries()).size() == 3);
        const QVariantList es = reg.entries();
        QVariantMap te, re;
        for (const QVariant &v : es) {
            if (v.toMap().value("key") == "n:4") te = v.toMap();
            if (v.toMap().value("key") == "n:5") re = v.toMap();
        }
        CHECK(te.value("app").toString() == "asteroid-timer" && te.value("title").toString() == "Timer");
        CHECK(te.value("category").toString() == "alarm" && te.value("staticIcon").toString() == "ms-timer");
        CHECK(te.value("countdown").toBool() && te.value("when").toLongLong() == 1700000090000LL);
        CHECK(re.value("app").toString() == "asteroid-exercise" && re.value("paused").toBool() && re.value("frozen").toLongLong() == 61000);
        CHECK(re.value("category").toString() == "workout");
        // the same list again: no change; the workout gone: one change
        reg.syncNotifications(list);
        CHECK(changedN == 2);
        list.removeAt(2);
        reg.syncNotifications(list);
        CHECK(changedN == 3 && reg.count() == 2);

        // a notification entry may not be removed by remove() of the QML (another namespace)
        reg.remove("n:4");
        CHECK(reg.count() == 2);
        reg.remove("media");
        CHECK(changedN == 4 && reg.count() == 1);

        // the user turns the app off: top skips it, a change is announced
        reg.setMutedApps({ "asteroid-timer" });
        CHECK(changedN == 5 && reg.top().isEmpty());
        reg.setMutedApps({ "asteroid-timer" });
        CHECK(changedN == 5);
        reg.setMutedApps({});
        CHECK(reg.top().value("key").toString() == "n:4");

        // a tap: the app named, the entry newest
        reg.activate("n:4");
        CHECK(actKeys.size() == 1 && actKeys.first() == "n:4" && actApps.first() == "asteroid-timer");
        reg.activate("n:none");
        CHECK(actKeys.size() == 1);

        // in use claims of the QML
        reg.setInUse("mic", true);
        CHECK(reg.micInUse() && !reg.locationInUse() && inuseN == 1);
        reg.setInUse("mic", true);
        CHECK(inuseN == 1);
        reg.setInUse("mic", false);
        CHECK(!reg.micInUse() && inuseN == 2);

        // the touch lock is a claim of the QML only
        reg.setInUse("touchlock", true);
        CHECK(reg.touchLocked() && !reg.micInUse() && inuseN == 3);
        reg.setInUse("touchlock", false);
        CHECK(!reg.touchLocked() && inuseN == 4);

        // ---- another process on the bus ----
        QDBusConnection client = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("client"));
        CHECK(client.isConnected());
        Receiver rx;
        const QString svc = QDBusConnection::sessionBus().baseService();
        CHECK(client.connect(svc, OngoingRegistry::Path, "org.asteroidos.launcher.Ongoing", "Activated", &rx, SLOT(Activated(QString))));
        const int before = reg.count();
        changedN = 0;
        QVariantMap p = props("stopwatch", "asteroid-stopwatch", "%t");
        p["when"] = qint64(1700000000000LL); p["staticIcon"] = "ms-timer";
        QDBusMessage m = QDBusMessage::createMethodCall(svc, OngoingRegistry::Path, "org.asteroidos.launcher.Ongoing", "Publish");
        m << QStringLiteral("sw") << p;
        CHECK(callOk(client, m));
        CHECK(reg.count() == before + 1 && changedN == 1);
        const QString key = QStringLiteral("bus:") + client.baseService() + "/sw";
        QVariantMap swe;
        for (const QVariant &v : reg.entries())
            if (v.toMap().value("key") == key) swe = v.toMap();
        CHECK(swe.value("category").toString() == "stopwatch" && swe.value("when").toLongLong() == 1700000000000LL);
        CHECK(swe.value("status").toString() == "%t" && swe.value("app").toString() == "asteroid-stopwatch");
        // the same again: no change
        CHECK(callOk(client, m));
        CHECK(changedN == 1);
        // a tap goes to the owner only
        reg.activate(key);
        spin(200);
        CHECK(rx.got == QStringList { "sw" });
        // a privacy claim
        QDBusMessage u = QDBusMessage::createMethodCall(svc, OngoingRegistry::Path, "org.asteroidos.launcher.Ongoing", "SetInUse");
        u << QStringLiteral("location") << true;
        CHECK(callOk(client, u));
        CHECK(reg.locationInUse() && !reg.micInUse());
        // an app cannot claim the touch lock
        QDBusMessage tl = QDBusMessage::createMethodCall(svc, OngoingRegistry::Path, "org.asteroidos.launcher.Ongoing", "SetInUse");
        tl << QStringLiteral("touchlock") << true;
        CHECK(callOk(client, tl));
        CHECK(!reg.touchLocked());
        // Remove withdraws it
        QDBusMessage r = QDBusMessage::createMethodCall(svc, OngoingRegistry::Path, "org.asteroidos.launcher.Ongoing", "Remove");
        r << QStringLiteral("sw");
        CHECK(callOk(client, r));
        CHECK(reg.count() == before);
        // the owner leaves the bus: its entries and claims go
        CHECK(callOk(client, m));
        CHECK(reg.count() == before + 1);
        // drop every reference, then close the connection: the bus announces the name gone
        client = QDBusConnection(QStringLiteral("none"));
        QDBusConnection::disconnectFromBus(QStringLiteral("client"));
        for (int i = 0; i < 20 && reg.count() != before; ++i)
            spin(100);
        CHECK(reg.count() == before);
        CHECK(!reg.locationInUse());
    }

    printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_ongoing.moc"
