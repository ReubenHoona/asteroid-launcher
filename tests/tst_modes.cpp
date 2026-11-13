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
 *   - Battery saver off on the charger, back when unplugged (unless charged
 *     to 25 %: it stays off, with a notice); it keeps tilt-to-wake and caps
 *     the screen timeout at 10 s; on by itself at 15 % off the charger, off
 *     again on rising through 25 % (mce's battery level signal)
 *   - Bedtime: brightness ceiling with the light sensor on, the colour filter
 *     (Night light 2596 K, Grayscale, none), "Starting Bedtime mode…" 5 s,
 *     the exit screen, a screen going off meanwhile, the screen off
 *   - Theater: the overlay and the screen off at 450 ms; 24 hours later off
 *     with its card and the screen on, also by the timed event's dconf key
 *   - alarms: the event they may play follows the modes and Customize
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
static const char DIM[] = "/system/osso/dsm/display/display_dim_timeout";
static const char FACE_BLANK[] = "/system/osso/dsm/display/display_blank_from_locksreen_timeout";

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
    int onRequests = 0;
    int level = 80;
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
    void batteryLevel(int percent)
    {
        {
            QMutexLocker l(&lock);
            level = percent;
        }
        QMetaObject::invokeMethod(this, [this, percent] {
            QDBusMessage m = QDBusMessage::createSignal("/com/nokia/mce/signal", "com.nokia.mce.signal", "battery_level_ind");
            m << percent;
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
    int get_battery_level() { QMutexLocker l(&lock); return level; }
    void req_display_state_off() { QMutexLocker l(&lock); offRequests++; }
    void req_display_state_on() { QMutexLocker l(&lock); onRequests++; }

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
        && mce.get(ALS).toBool() && mce.get(DIM).toInt() == 15 && mce.get(FACE_BLANK).toInt() == 15;
}

static bool hasNotice(FakeNotifications &notes, const char *id, const char *text)
{
    QMutexLocker l(&notes.lock);
    return notes.summaries.contains(id) || notes.summaries.contains(text);
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
    mce.config.insert(DIM, 15);
    mce.config.insert(FACE_BLANK, 15);
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
                           "battery-saver-resume", "extra-dim-intensity", "theater-expired", "theater-wake-cookie",
                           "alarm-feedback", "bedtime/display-filter", "theater/alarm-sound", "theater/alarm-vibrate",
                           "bedtime/alarm-sound", "bedtime/alarm-vibrate", "do-not-disturb/alarm-sound",
                           "do-not-disturb/alarm-vibrate", "battery-saver-auto-on", "battery-saver-auto-off",
                           "battery-saver-auto-on-level", "battery-saver-auto-off-level" })
        setConf(M + k, QVariant());
    setConf(DND, false);

    auto *engine = new ModesEngine;
    int starting = 0, skipped = 0, ending = 0, cancelled = 0, theaterStarting = 0;
    QObject::connect(engine, &ModesEngine::bedtimeStarting, [&] { starting++; });
    QObject::connect(engine, &ModesEngine::bedtimeSkipped, [&] { skipped++; });
    QObject::connect(engine, &ModesEngine::bedtimeEnding, [&] { ending++; });
    QObject::connect(engine, &ModesEngine::transitionCancelled, [&] { cancelled++; });
    QObject::connect(engine, &ModesEngine::theaterStarting, [&] { theaterStarting++; });
    spin(500);
    // nothing on: nothing written
    CHECK(mce.sets.isEmpty());
    CHECK(!engine->alwaysOnBlocked() && engine->tiltHolder().isEmpty());
    CHECK(!engine->quiet());
    // the battery at 80 %: nothing happens; alarms play as ever
    CHECK(engine->batteryLevel() == 80 && !engine->batterySaver());
    CHECK(engine->alarmFeedback() == "alarm" && engine->alarmMask() == 3);
    CHECK(waitFor([&] { return confValue(M + "alarm-feedback").toString() == "alarm"; }, ConfMs));
    CHECK(engine->displayFilter().isEmpty());

    // --- Bedtime from Do Not Disturb (the quick panel): the latest wins
    engine->setDoNotDisturb(true);
    CHECK(waitFor([&] { return engine->doNotDisturb(); }));
    engine->setBedtime(true);
    CHECK(waitFor([&] { return !mce.get(TILT).toBool() && mce.get(BRIGHTNESS).toInt() == 8; }));
    CHECK(waitFor([&] { return mce.get(TOUCH).toString().isEmpty(); }));
    // the light sensor's curve stays on (the brightness is the ceiling, modes-dnd-17)
    spin(300);
    CHECK(mce.get(ALS).toBool());
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
    CHECK(!confValue(M + "saved/auto-brightness").isValid());
    // Bedtime's colour filter: Night light at 2596 K by default, then the choice
    CHECK(engine->displayFilter() == "nightlight");
    {
        const QVariantList m = engine->filterMatrix();
        CHECK(m.size() == 9 && m[0].toDouble() == 1.0 && qAbs(m[4].toDouble() - 0.7232) < 0.0005 && qAbs(m[8].toDouble() - 0.4588) < 0.0005);
    }
    setConf(M + "bedtime/display-filter", QStringLiteral("grayscale"));
    CHECK(waitFor([&] { return engine->displayFilter() == "grayscale"; }, ConfMs));
    CHECK(engine->filterMatrix().at(0).toDouble() == 0.2126);
    setConf(M + "bedtime/display-filter", QStringLiteral("none"));
    CHECK(waitFor([&] { return engine->displayFilter().isEmpty(); }, ConfMs));
    CHECK(engine->filterMatrix().at(4).toDouble() == 1.0);
    setConf(M + "bedtime/display-filter", QVariant());
    CHECK(waitFor([&] { return engine->displayFilter() == "nightlight"; }, ConfMs));
    // the screen was on: "Starting Bedtime mode…", then the face and off (at 5000 ms)
    CHECK(starting == 1);
    CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.offRequests == 1; }, 8000));


    // --- changed elsewhere while held: back
    mce.change(TILT, true);
    CHECK(waitFor([&] { return mce.get(TILT) == QVariant(false); }));
    mce.change(LPM, true);
    CHECK(waitFor([&] { return mce.get(LPM) == QVariant(false); }));

    // --- Battery saver on top: the screen timeout at 10 s; Bedtime ends: the
    // settings back, tilt-to-wake with them (the saver keeps it on)
    engine->setBatterySaver(true);
    CHECK(waitFor([&] { return mce.get(DIM).toInt() == 10 && mce.get(FACE_BLANK).toInt() == 10; }));
    CHECK(waitFor([&] { return confValue(M + "saved/dim-timeout").toInt() == 15; }, ConfMs));
    engine->setBedtime(false);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 60 && mce.get(TOUCH).toString() == "unblank" && mce.get(ALS).toBool(); }));
    CHECK(waitFor([&] { return mce.get(TILT).toBool(); }));
    CHECK(engine->alwaysOnBlocked() && engine->alwaysOnHolder() == "battery-saver");
    CHECK(engine->tiltHolder().isEmpty() && engine->touchHolder().isEmpty() && engine->brightnessHolder().isEmpty());
    CHECK(mce.get(DIM).toInt() == 10 && mce.get(FACE_BLANK).toInt() == 10);
    CHECK(!engine->quiet());   // Battery saver alerts as ever
    CHECK(waitFor([&] { return !confValue(M + "saved/tilt-to-wake").isValid(); }, ConfMs));
    CHECK(waitFor([&] { return !confValue(M + "saved/brightness").isValid(); }, ConfMs));
    // Bedtime off with the screen on: "Turning off Bedtime mode…"
    CHECK(ending == 1);
    // the user picks 30 s meanwhile: back to 10 s, the 30 s is theirs for later
    mce.change(DIM, 30);
    mce.change(FACE_BLANK, 30);
    CHECK(waitFor([&] { return mce.get(DIM).toInt() == 10 && mce.get(FACE_BLANK).toInt() == 10; }));
    CHECK(waitFor([&] { return confValue(M + "saved/dim-timeout").toInt() == 30; }, ConfMs));
    mce.change(DIM, 15);
    mce.change(FACE_BLANK, 15);
    CHECK(waitFor([&] { return mce.get(DIM).toInt() == 10 && confValue(M + "saved/dim-timeout").toInt() == 15; }, ConfMs));
    mce.batteryLevel(20);
    CHECK(waitFor([&] { return engine->batteryLevel() == 20; }));

    // --- on the charger: Battery saver off, back when unplugged
    {
        QMutexLocker l(&mce.lock);
        mce.charger = "usb";
    }
    mce.signal("charger_type_ind", "usb");
    CHECK(waitFor([&] { return !engine->batterySaver() && engine->charging(); }));
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(!engine->alwaysOnBlocked());
    CHECK(waitFor([&] { return confValue(M + "battery-saver-resume") == QVariant(true); }, ConfMs));
    // unplugged at 20 %: the saver is back (under the 25 % of "Turn off when charged")
    mce.signal("charger_type_ind", "none");
    CHECK(waitFor([&] { return engine->batterySaver() && !engine->charging(); }));
    CHECK(waitFor([&] { return mce.get(DIM).toInt() == 10; }));
    CHECK(waitFor([&] { return !confValue(M + "battery-saver-resume").isValid(); }, ConfMs));
    CHECK(!hasNotice(notes, "id-saver-auto-off", "Battery Saver turned off"));
    // plugged again, charged to 90 %, unplugged: the saver stays off and a notice says so
    mce.signal("charger_type_ind", "usb");
    CHECK(waitFor([&] { return !engine->batterySaver() && engine->charging(); }));
    mce.batteryLevel(90);
    CHECK(waitFor([&] { return engine->batteryLevel() == 90; }));
    CHECK(!engine->batterySaver());   // not turned on by the level (on the charger)
    mce.signal("charger_type_ind", "none");
    CHECK(waitFor([&] { return !engine->charging(); }));
    CHECK(waitFor([&] { return hasNotice(notes, "id-saver-auto-off", "Battery Saver turned off"); }));
    spin(300);
    CHECK(!engine->batterySaver() && userSettings(mce));
    CHECK(waitFor([&] { return !confValue(M + "battery-saver-resume").isValid(); }, ConfMs));
    CHECK(waitFor([&] { return !confValue(M + "saved/dim-timeout").isValid(); }, ConfMs));

    // --- the automatic Battery saver: 15 % off the charger, off again at 25 %
    mce.batteryLevel(16);
    CHECK(waitFor([&] { return engine->batteryLevel() == 16; }));
    spin(200);
    CHECK(!engine->batterySaver());
    mce.batteryLevel(15);
    CHECK(waitFor([&] { return engine->batterySaver(); }));
    CHECK(waitFor([&] { return hasNotice(notes, "id-saver-auto-on", "Low battery"); }));
    CHECK(waitFor([&] { return mce.get(DIM).toInt() == 10; }));
    // the user turns it off at 14 %: it stays off (the level did not cross 15 again)
    mce.batteryLevel(14);
    CHECK(waitFor([&] { return engine->batteryLevel() == 14; }));
    engine->setBatterySaver(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    mce.batteryLevel(13);
    CHECK(waitFor([&] { return engine->batteryLevel() == 13; }));
    spin(300);
    CHECK(!engine->batterySaver());
    // on again by hand, the level rises through 25 %: off, with its notice
    engine->setBatterySaver(true);
    CHECK(waitFor([&] { return engine->batterySaver() && mce.get(DIM).toInt() == 10; }));
    mce.batteryLevel(24);
    CHECK(waitFor([&] { return engine->batteryLevel() == 24; }));
    spin(200);
    CHECK(engine->batterySaver());
    mce.batteryLevel(25);
    CHECK(waitFor([&] { return !engine->batterySaver(); }));
    CHECK(waitFor([&] { return userSettings(mce); }));
    // settings: "Turn on at" off: nothing at 15 %
    setConf(M + "battery-saver-auto-on", false);
    CHECK(waitFor([&] { return !engine->autoSaverOn(); }, ConfMs));
    mce.batteryLevel(16);
    CHECK(waitFor([&] { return engine->batteryLevel() == 16; }));
    mce.batteryLevel(10);
    CHECK(waitFor([&] { return engine->batteryLevel() == 10; }));
    spin(300);
    CHECK(!engine->batterySaver());
    setConf(M + "battery-saver-auto-on", QVariant());
    CHECK(waitFor([&] { return engine->autoSaverOn() && engine->autoSaverOnLevel() == 15; }, ConfMs));
    mce.batteryLevel(80);
    CHECK(waitFor([&] { return engine->batteryLevel() == 80; }));

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

    // --- Theater: the overlay, and the screen off at 450 ms; alarms vibrate only
    int offs = mce.offRequests;
    engine->setTheater(true);
    CHECK(theaterStarting == 1);
    CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.offRequests == offs + 1; }));
    CHECK(waitFor([&] { return !mce.get(TILT).toBool() && mce.get(TOUCH).toString().isEmpty(); }));
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 60; }));
    CHECK(waitFor([&] { return confValue(M + "theater-since").toDouble() > 0; }, ConfMs));
    CHECK(engine->alarmFeedback() == "alarm_vibra" && engine->alarmMask() == 2);
    CHECK(waitFor([&] { return confValue(M + "alarm-feedback").toString() == "alarm_vibra"; }, ConfMs));
    // Settings > Theater > Customize > Alarms and Timers > Sound on: both; off again: vibration
    setConf(M + "theater/alarm-sound", true);
    CHECK(waitFor([&] { return engine->alarmFeedback() == "alarm"; }, ConfMs));
    setConf(M + "theater/alarm-sound", QVariant());
    CHECK(waitFor([&] { return engine->alarmFeedback() == "alarm_vibra"; }, ConfMs));
    setConf(M + "theater/alarm-vibrate", false);
    CHECK(waitFor([&] { return engine->alarmFeedback().isEmpty() && engine->alarmMask() == 0; }, ConfMs));
    setConf(M + "theater/alarm-vibrate", QVariant());
    CHECK(waitFor([&] { return engine->alarmFeedback() == "alarm_vibra"; }, ConfMs));
    // Do Not Disturb with its Sound off adds its limit while on
    setConf(M + "do-not-disturb/alarm-vibrate", false);
    CHECK(waitFor([&] { return engine->alarmFeedback() == "alarm_vibra"; }, ConfMs));   // not on yet
    setConf(M + "do-not-disturb/alarm-vibrate", QVariant());

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
    CHECK(waitFor([&] { return hasNotice(notes, "id-theater-expired", "Theater mode off"); }));
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(waitFor([&] { return !confValue(M + "theater-since").isValid(); }, ConfMs));
    // the screen comes on for it
    { QMutexLocker l(&mce.lock); CHECK(mce.onRequests >= 1); }

    // --- the same with the watch asleep: the timed event's command writes
    // theater-expired (a dconf key): off, the screen on, the card, and the key cleared
    notes.summaries.clear();
    int ons = mce.onRequests;
    engine->setTheater(true);
    CHECK(waitFor([&] { return !mce.get(TILT).toBool(); }));
    setConf(M + "theater-since", double(QDateTime::currentMSecsSinceEpoch() - ModesEngine::TheaterMaxMs - 60000) / 1000.0);
    spin(1500);   // the engine reads the start it was given before the event's key arrives
    setConf(M + "theater-expired", true);
    CHECK(waitFor([&] { return !engine->theater(); }, ConfMs));
    CHECK(waitFor([&] { return hasNotice(notes, "id-theater-expired", "Theater mode off"); }));
    CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.onRequests > ons; }));
    CHECK(waitFor([&] { return !confValue(M + "theater-expired").isValid(); }, ConfMs));
    CHECK(waitFor([&] { return userSettings(mce); }));
    // a stale event (Theater began a moment ago): nothing
    engine->setTheater(true);
    CHECK(waitFor([&] { return !mce.get(TILT).toBool(); }));
    setConf(M + "theater-expired", true);
    CHECK(waitFor([&] { return !confValue(M + "theater-expired").isValid(); }, ConfMs));
    spin(300);
    CHECK(engine->theater());
    engine->setTheater(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    // the command timed runs: the launcher's own session, the key above
    {
        const QString cmd = ModesEngine::theaterWakeCommand("/run/user/1000", "unix:path=/run/user/1000/bus");
        CHECK(cmd.contains("/usr/bin/dconf write /org/asteroidos/modes/theater-expired true"));
        CHECK(cmd.contains("XDG_RUNTIME_DIR='/run/user/1000'") && cmd.contains("DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus'"));
    }

    // --- Extra dim after a reboot (another boot id): off at the start
    engine->setExtraDim(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 2; }));
    delete engine;
    setConf(M + "extra-dim-boot", QStringLiteral("an-earlier-boot"));
    engine = new ModesEngine;
    CHECK(!engine->extraDim());
    CHECK(waitFor([&] { return userSettings(mce); }));

    // --- the screen off when Bedtime comes on: no "Starting Bedtime mode…";
    // the face goes on top after 2500 ms (bedtimeSkipped); no sleep request, no exit screen
    {
        QMutexLocker l(&mce.lock);
        mce.display = "off";
    }
    mce.signal("display_status_ind", "off");
    spin(300);
    starting = skipped = ending = cancelled = 0;
    QObject::connect(engine, &ModesEngine::bedtimeStarting, [&] { starting++; });
    QObject::connect(engine, &ModesEngine::bedtimeSkipped, [&] { skipped++; });
    QObject::connect(engine, &ModesEngine::bedtimeEnding, [&] { ending++; });
    QObject::connect(engine, &ModesEngine::transitionCancelled, [&] { cancelled++; });
    offs = mce.offRequests;
    engine->setBedtime(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 8; }));
    spin(2000);
    CHECK(skipped == 0);
    spin(1000);
    CHECK(starting == 0);
    CHECK(skipped == 1);
    CHECK(mce.offRequests == offs);
    engine->setBedtime(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(ending == 0);   // the screen is off: no exit screen

    // --- the screen comes on within the 2500 ms: the transition plays then
    skipped = 0;
    engine->setBedtime(true);
    CHECK(waitFor([&] { return mce.get(BRIGHTNESS).toInt() == 8; }));
    spin(500);
    { QMutexLocker l(&mce.lock); mce.display = "on"; }
    mce.signal("display_status_ind", "on");
    CHECK(waitFor([&] { return starting == 1; }));
    {
        // 5000 ms from the screen coming on: nothing before 4 s, the screen off request by 6.5 s
        QElapsedTimer t0;
        t0.start();
        offs = mce.offRequests;
        spin(4000);
        CHECK(mce.offRequests == offs);
        CHECK(waitFor([&] { QMutexLocker l(&mce.lock); return mce.offRequests == offs + 1; }, 2500));
        const qint64 ms = t0.elapsed();
        fprintf(stderr, "bedtime: screen off request %lld ms after the screen came on (stock 5000)\n", ms);
        CHECK(ms >= 4800 && ms <= 6500);   // exact timer (QTimer::PreciseTimer)
    }
    CHECK(skipped == 0);
    // off with the screen on (the fake keeps it on): the exit screen
    ending = 0;
    engine->setBedtime(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(ending == 1);
    ending = 0;
    // the screen goes off during the entry (the side button): the transition ends and
    // the engine's own screen off does not come
    { QMutexLocker l(&mce.lock); mce.display = "on"; }
    mce.signal("display_status_ind", "on");
    spin(300);
    starting = cancelled = 0;
    engine->setBedtime(true);
    CHECK(waitFor([&] { return starting == 1; }));
    spin(1000);
    offs = mce.offRequests;
    { QMutexLocker l(&mce.lock); mce.display = "off"; }
    mce.signal("display_status_ind", "off");
    CHECK(waitFor([&] { return cancelled == 1; }));
    spin(5000);
    CHECK(mce.offRequests == offs);
    engine->setBedtime(false);
    CHECK(waitFor([&] { return userSettings(mce); }));
    CHECK(ending == 0);
    // Bedtime turned off during its own entry screen (screen on): the entry ends, no exit screen
    { QMutexLocker l(&mce.lock); mce.display = "on"; }
    mce.signal("display_status_ind", "on");
    spin(300);
    starting = cancelled = 0;
    engine->setBedtime(true);
    CHECK(waitFor([&] { return starting == 1; }));
    engine->setBedtime(false);
    CHECK(waitFor([&] { return cancelled == 1; }));
    CHECK(ending == 0);
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
