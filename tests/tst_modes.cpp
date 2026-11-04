/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The modes engine (src/modes.h) against a fake mce and notification
 * server on a private D-Bus, with a dconf database of its own:
 *   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS tst_modes'
 *   - Bedtime: mce's settings held (the user's saved in dconf), the
 *     always-on screen off, Do Not Disturb off (the latest wins), "Starting
 *     Bedtime mode…" then the screen off; a setting changed meanwhile goes
 *     back; Battery saver on top keeps tilt-to-wake off after Bedtime ends
 *   - Do Not Disturb on ends Bedtime
 *   - Battery saver off on the charger, back when unplugged
 *   - Theater: the screen off at once; 24 hours later off with its card
 *   - a launcher restart: Bedtime ended meanwhile puts the user's settings
 *     back; Extra dim ends after a reboot
 * cmake -DLAUNCHER_TESTS=ON.
 */

#include "modes.h"

#include <MDConfItem>
#include <QCoreApplication>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QElapsedTimer>
#include <QMutex>
#include <QMutexLocker>
#include <QThread>
#include <cstdio>
#include <functional>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static const char TILT[] = "/system/osso/dsm/display/wrist_sensor_enabled";
static const char TOUCH[] = "/system/osso/dsm/powerkey/actions_gesture4";
static const char BRIGHTNESS[] = "/system/osso/dsm/display/display_brightness";
static const char ALS[] = "/system/osso/dsm/display/als_enabled";
static const char LPM[] = "/system/osso/dsm/display/use_low_power_mode";

// mce: its settings, display and charger, and what was asked of it
class FakeMce : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.nokia.mce.request")
public:
    QMutex lock;
    QHash<QString, QVariant> config;
    QString display = QStringLiteral("on");
    QString charger = QStringLiteral("none");
    QStringList sets;
    int offRequests = 0;
    QDBusConnection *conn = nullptr;

    QVariant get(const QString &key) { QMutexLocker l(&lock); return config.value(key); }
    // a change made elsewhere (Settings, the nightstand)
    void change(const QString &key, const QVariant &v)
    {
        {
            QMutexLocker l(&lock);
            config.insert(key, v);
        }
        QMetaObject::invokeMethod(this, [this, key, v] { emitChange(key, v); });
    }
    void signal(const char *name, const QString &arg)
    {
        QMetaObject::invokeMethod(this, [this, name, arg] {
            QDBusMessage m = QDBusMessage::createSignal("/com/nokia/mce/signal", "com.nokia.mce.signal", name);
            m << arg;
            conn->send(m);
        });
    }

public slots:
    QDBusVariant get_config(const QDBusObjectPath &key)
    {
        QMutexLocker l(&lock);
        return QDBusVariant(config.value(key.path()));
    }
    bool set_config(const QDBusObjectPath &key, const QDBusVariant &value)
    {
        {
            QMutexLocker l(&lock);
            config.insert(key.path(), value.variant());
            sets << key.path();
        }
        emitChange(key.path(), value.variant());
        return true;
    }
    QString get_display_status() { QMutexLocker l(&lock); return display; }
    QString get_charger_type() { QMutexLocker l(&lock); return charger; }
    void req_display_state_off() { QMutexLocker l(&lock); offRequests++; }

private:
    void emitChange(const QString &key, const QVariant &v)
    {
        QDBusMessage m = QDBusMessage::createSignal("/com/nokia/mce/signal", "com.nokia.mce.signal", "config_change_ind");
        m << QVariant::fromValue(QDBusObjectPath(key)) << QVariant::fromValue(QDBusVariant(v));
        conn->send(m);
    }
};

class FakeNotifications : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
public:
    QMutex lock;
    QStringList summaries;
public slots:
    uint Notify(const QString &, uint, const QString &, const QString &summary, const QString &,
                const QStringList &, const QVariantMap &, int)
    {
        QMutexLocker l(&lock);
        summaries << summary;
        return 1;
    }
};

static bool waitFor(const std::function<bool()> &cond, int ms = 6000)
{
    QElapsedTimer t;
    t.start();
    while (!cond() && t.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return cond();
}

static void spin(int ms) { waitFor([] { return false; }, ms); }

// a write of the engine reaches a reader through the dconf service, which
// can take seconds on a busy disk
static const int ConfMs = 30000;

static MDConfItem *conf(const QString &key) { return new MDConfItem(key); }
static void setConf(const QString &key, const QVariant &v)
{
    MDConfItem item(key);
    if (v.isValid())
        item.set(v);
    else
        item.unset();
    item.sync();
}
static QVariant confValue(const QString &key) { return MDConfItem(key).value(); }

static const QString M = QStringLiteral("/org/asteroidos/modes/");
static const QString DND = QStringLiteral("/org/asteroidos/notifications/do-not-disturb");

static bool userSettings(FakeMce &mce)
{
    return mce.get(TILT).toBool() && mce.get(TOUCH).toString() == "unblank" && mce.get(BRIGHTNESS).toInt() == 60
        && mce.get(ALS).toBool();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS") || qEnvironmentVariableIsEmpty("DBUS_SYSTEM_BUS_ADDRESS")) {
        fprintf(stderr, "needs a private bus as session and system bus (see the top of the source)\n");
        return 2;
    }

    QThread fakeThread;
    fakeThread.start();
    FakeMce mce;
    mce.config.insert(TILT, true);
    mce.config.insert(TOUCH, QStringLiteral("unblank"));
    mce.config.insert(BRIGHTNESS, 60);
    mce.config.insert(ALS, true);
    mce.config.insert(LPM, true);
    FakeNotifications notes;
    mce.moveToThread(&fakeThread);
    notes.moveToThread(&fakeThread);
    QDBusConnection mceConn = QDBusConnection::connectToBus(QDBusConnection::SystemBus, "fake-mce");
    mce.conn = &mceConn;
    CHECK(mceConn.registerObject("/com/nokia/mce/request", &mce, QDBusConnection::ExportAllSlots));
    CHECK(mceConn.registerService("com.nokia.mce"));
    QDBusConnection notesConn = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "fake-notifications");
    CHECK(notesConn.registerObject("/org/freedesktop/Notifications", &notes, QDBusConnection::ExportAllSlots));
    CHECK(notesConn.registerService("org.freedesktop.Notifications"));

    for (const char *k : { "bedtime", "theater", "battery-saver", "extra-dim", "theater-since", "extra-dim-boot",
                           "battery-saver-resume", "extra-dim-intensity" })
        setConf(M + k, QVariant());
    setConf(DND, false);

    auto *engine = new ModesEngine;
    int starting = 0;
    QObject::connect(engine, &ModesEngine::bedtimeStarting, [&] { starting++; });
    spin(500);
    // nothing on: nothing written
    CHECK(mce.sets.isEmpty());
    CHECK(!engine->alwaysOnBlocked() && engine->tiltHolder().isEmpty());
    CHECK(!engine->quiet());

    // --- Bedtime from Do Not Disturb (the quick panel): the latest wins
    engine->setDoNotDisturb(true);
    CHECK(waitFor([&] { return engine->doNotDisturb(); }));
    engine->setBedtime(true);
    CHECK(waitFor([&] { return !mce.get(TILT).toBool() && mce.get(BRIGHTNESS).toInt() == 8; }));
    CHECK(waitFor([&] { return mce.get(TOUCH).toString().isEmpty(); }));
    CHECK(waitFor([&] { return !mce.get(ALS).toBool(); }));
    CHECK(waitFor([&] { return !mce.get(LPM).toBool(); }));
    CHECK(waitFor([&] { return !confValue(DND).toBool(); }, ConfMs));
    CHECK(!engine->doNotDisturb());
    CHECK(engine->alwaysOnBlocked() && engine->alwaysOnHolder() == "bedtime");
    CHECK(engine->tiltHolder() == "bedtime" && engine->touchHolder() == "bedtime" && engine->brightnessHolder() == "bedtime");
    // the notification server goes quiet with it (main.cpp)
    CHECK(engine->quiet());
    // the user's values, kept in dconf
    CHECK(waitFor([&] { return confValue(M + "saved/tilt-to-wake") == QVariant(true); }, ConfMs));
    CHECK(waitFor([&] { return confValue(M + "saved/touch-to-wake").toString() == "unblank"; }, ConfMs));
    CHECK(waitFor([&] { return confValue(M + "saved/brightness").toInt() == 60; }, ConfMs));
    CHECK(waitFor([&] { return confValue(M + "saved/auto-brightness") == QVariant(true); }, ConfMs));
    // the screen was on: "Starting Bedtime mode…", then off
    CHECK(starting == 1);
    CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.offRequests == 1; }, 4000));

    // --- changed elsewhere while held: back
    mce.change(TILT, true);
    CHECK(waitFor([&] { return mce.get(TILT) == QVariant(false); }));
    mce.change(LPM, true);
    CHECK(waitFor([&] { return mce.get(LPM) == QVariant(false); }));

    // --- Battery saver on top; Bedtime ends: tilt stays off, the rest back
    engine->setBatterySaver(true);
    spin(300);
    engine->setBedtime(false);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 60 && mce.get(TOUCH).toString() == "unblank" && mce.get(ALS).toBool(); }));
    CHECK(waitFor([&] { return !mce.get(TILT).toBool(); }));
    CHECK(engine->alwaysOnBlocked() && engine->alwaysOnHolder() == "battery-saver");
    CHECK(engine->tiltHolder() == "battery-saver" && engine->touchHolder().isEmpty() && engine->brightnessHolder().isEmpty());
    CHECK(!engine->quiet());   // Battery saver alerts as ever
    CHECK(waitFor([&] { return confValue(M + "saved/tilt-to-wake") == QVariant(true); }, ConfMs));
    CHECK(waitFor([&] { return !confValue(M + "saved/brightness").isValid(); }, ConfMs));

    // --- on the charger: Battery saver off, back when unplugged
    {
        QMutexLocker l(&mce.lock);
        mce.charger = "usb";
    }
    mce.signal("charger_type_ind", "usb");
    CHECK(waitFor([&] { return !engine->batterySaver() && engine->charging(); }));
    CHECK(waitFor([&] { return mce.get(TILT).toBool(); }));
    CHECK(userSettings(mce));
    CHECK(!engine->alwaysOnBlocked());
    CHECK(waitFor([&] { return confValue(M + "battery-saver-resume") == QVariant(true); }, ConfMs));
    // turned on while charging: waits for the unplugging too
    mce.signal("charger_type_ind", "none");
    CHECK(waitFor([&] { return engine->batterySaver() && !engine->charging(); }));
    CHECK(waitFor([&] { return !mce.get(TILT).toBool(); }));
    CHECK(waitFor([&] { return !confValue(M + "battery-saver-resume").isValid(); }, ConfMs));
    engine->setBatterySaver(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(waitFor([&] { return !confValue(M + "saved/tilt-to-wake").isValid(); }, ConfMs));

    // --- Do Not Disturb on in Bedtime: Bedtime off
    engine->setBedtime(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 8; }));
    engine->setDoNotDisturb(true);
    CHECK(waitFor([&] { return !confValue(M + "bedtime").toBool(); }, ConfMs));
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(engine->doNotDisturb() && !engine->bedtime());
    engine->setDoNotDisturb(false);

    // --- Extra dim: under the slider's lowest; the intensity follows
    engine->setExtraDim(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 5 && !mce.get(ALS).toBool(); }));
    CHECK(engine->brightnessHolder() == "extra-dim" && !engine->alwaysOnBlocked());
    engine->setExtraDimIntensity(90);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 2; }));
    CHECK(waitFor([&] { return !confValue(M + "extra-dim-boot").toString().isEmpty(); }, ConfMs));
    engine->setExtraDim(false);
    CHECK(waitFor([&] { return userSettings(mce); }));

    // --- Theater: the screen off at once
    int offs = mce.offRequests;
    engine->setTheater(true);
    CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.offRequests == offs + 1; }));
    CHECK(waitFor([&] { return !mce.get(TILT).toBool() && mce.get(TOUCH).toString().isEmpty(); }));
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 60; }));
    CHECK(waitFor([&] { return confValue(M + "theater-since").toDouble() > 0; }, ConfMs));

    // --- the launcher goes down in Theater; Theater ends meanwhile (by hand
    // here); a new start puts the user's settings back
    delete engine;
    setConf(M + "theater", false);
    engine = new ModesEngine;
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(waitFor([&] { return !confValue(M + "saved/tilt-to-wake").isValid(); }, ConfMs));

    // --- Theater for 24 hours (started a day ago): off at the next screen on,
    // with its card
    engine->setTheater(true);
    CHECK(waitFor([&] { return !mce.get(TILT).toBool(); }));
    setConf(M + "theater-since", double(QDateTime::currentMSecsSinceEpoch() - ModesEngine::TheaterMaxMs - 60000) / 1000.0);
    mce.signal("display_status_ind", "on");
    CHECK(waitFor([&] { return !engine->theater(); }));
    CHECK(waitFor([&] { QMutexLocker l(&notes.lock); return notes.summaries.contains("id-theater-expired")
                                                          || notes.summaries.contains("Theater mode off"); }));
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(waitFor([&] { return !confValue(M + "theater-since").isValid(); }, ConfMs));

    // --- Extra dim after a reboot (another boot id): off at the start
    engine->setExtraDim(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 2; }));
    delete engine;
    setConf(M + "extra-dim-boot", QStringLiteral("an-earlier-boot"));
    engine = new ModesEngine;
    CHECK(!engine->extraDim());
    CHECK(waitFor([&] { return userSettings(mce); }));

    // --- the screen off when Bedtime comes on: no "Starting Bedtime mode…"
    {
        QMutexLocker l(&mce.lock);
        mce.display = "off";
    }
    mce.signal("display_status_ind", "off");
    spin(300);
    starting = 0;
    QObject::connect(engine, &ModesEngine::bedtimeStarting, [&] { starting++; });
    offs = mce.offRequests;
    engine->setBedtime(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 8; }));
    spin(3000);
    CHECK(starting == 0);
    CHECK(mce.offRequests == offs);
    engine->setBedtime(false);
    CHECK(waitFor([&] { return userSettings(mce); }));

    delete engine;
    fakeThread.quit();
    fakeThread.wait();
    if (failures)
        fprintf(stderr, "tst_modes: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_modes: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}

#include "tst_modes.moc"
