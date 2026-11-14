/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "modes.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>
#include <QFile>
#include <QTimer>
#include <MDConfItem>
#include <timed-qt6/event>
#include <timed-qt6/interface>

#include <climits>

static const char MCE_SERVICE[] = "com.nokia.mce";
static const char MCE_REQUEST_PATH[] = "/com/nokia/mce/request";
static const char MCE_REQUEST_IF[] = "com.nokia.mce.request";
static const char MCE_SIGNAL_PATH[] = "/com/nokia/mce/signal";
static const char MCE_SIGNAL_IF[] = "com.nokia.mce.signal";

static const char KEY_TILT[] = "/system/osso/dsm/display/wrist_sensor_enabled";
static const char KEY_TOUCH[] = "/system/osso/dsm/powerkey/actions_gesture4";
static const char KEY_BRIGHTNESS[] = "/system/osso/dsm/display/display_brightness";
static const char KEY_ALS[] = "/system/osso/dsm/display/als_enabled";
static const char KEY_LPM[] = "/system/osso/dsm/display/use_low_power_mode";
// Settings > Display > Screen timeout writes these two (DisplayPage.qml);
// mce spells the second "locksreen"
static const char KEY_DIM[] = "/system/osso/dsm/display/display_dim_timeout";
static const char KEY_FACE_BLANK[] = "/system/osso/dsm/display/display_blank_from_locksreen_timeout";

static const int Modes[] = { ModesCore::Bedtime, ModesCore::Theater, ModesCore::BatterySaver, ModesCore::ExtraDim, ModesCore::TouchLock };
static const int ModeCount = int(sizeof(Modes) / sizeof(Modes[0]));

static const QStringList AlarmModes = { QStringLiteral("do-not-disturb"), QStringLiteral("bedtime"), QStringLiteral("theater") };

static QString mceKey(ModesCore::Setting s)
{
    switch (s) {
    case ModesCore::TiltToWake: return QLatin1String(KEY_TILT);
    case ModesCore::TouchToWake: return QLatin1String(KEY_TOUCH);
    case ModesCore::Brightness: return QLatin1String(KEY_BRIGHTNESS);
    case ModesCore::AutoBrightness: return QLatin1String(KEY_ALS);
    case ModesCore::DimTimeout: return QLatin1String(KEY_DIM);
    case ModesCore::FaceBlankTimeout: return QLatin1String(KEY_FACE_BLANK);
    case ModesCore::SettingCount: break;
    }
    return QString();
}

static QString confKey(const QString &name)
{
    return QLatin1String(ModesEngine::ModesPath) + QLatin1Char('/') + name;
}

// where a mode's switch is: Touch lock's is a Settings key (Settings > Display > Touch lock
// and the launcher's lock write it), the others' are under the modes' path
static QString modeKey(int mode)
{
    if (mode == ModesCore::TouchLock)
        return QStringLiteral("/org/asteroidos/settings/touch-lock");
    return confKey(ModesCore::name(mode));
}

ModesEngine::ModesEngine(QObject *parent) : QObject(parent)
{
    for (int i = 0; i < ModeCount; i++) {
        mModeConf[i] = new MDConfItem(modeKey(Modes[i]), this);
        connect(mModeConf[i], &MDConfItem::valueChanged, this, &ModesEngine::modeConfChanged);
    }
    mDndConf = new MDConfItem(QLatin1String(DndKey), this);
    connect(mDndConf, &MDConfItem::valueChanged, this, &ModesEngine::modeConfChanged);
    for (int i = 0; i < ModesCore::SettingCount; i++)
        mSavedConf[i] = new MDConfItem(confKey(QStringLiteral("saved/") + ModesCore::settingName(ModesCore::Setting(i))), this);
    mIntensityConf = new MDConfItem(confKey(QStringLiteral("extra-dim-intensity")), this);
    connect(mIntensityConf, &MDConfItem::valueChanged, this, &ModesEngine::modeConfChanged);
    mTheaterSince = new MDConfItem(confKey(QStringLiteral("theater-since")), this);
    mExtraDimBoot = new MDConfItem(confKey(QStringLiteral("extra-dim-boot")), this);
    mSaverResume = new MDConfItem(confKey(QStringLiteral("battery-saver-resume")), this);
    // Bedtime's colour filter (Settings > Bedtime > Customize > Display options)
    mDisplayFilterConf = new MDConfItem(confKey(QStringLiteral("bedtime/display-filter")), this);
    connect(mDisplayFilterConf, &MDConfItem::valueChanged, this, &ModesEngine::changed);
    // what the timed event at the end of Theater's 24 hours writes
    mTheaterExpiredConf = new MDConfItem(confKey(QStringLiteral("theater-expired")), this);
    connect(mTheaterExpiredConf, &MDConfItem::valueChanged, this, &ModesEngine::theaterExpiredByTimed);
    mTheaterCookie = new MDConfItem(confKey(QStringLiteral("theater-wake-cookie")), this);
    // what alarms may do now, for the presenter and the timer
    mAlarmFeedbackConf = new MDConfItem(confKey(QStringLiteral("alarm-feedback")), this);
    for (const QString &mode : AlarmModes) {
        for (const char *key : { "alarm-sound", "alarm-vibrate" }) {
            const QString name = mode + QLatin1Char('/') + QLatin1String(key);
            auto *item = new MDConfItem(confKey(name), this);
            connect(item, &MDConfItem::valueChanged, this, &ModesEngine::alarmPrefsChanged);
            mAlarmPrefs.insert(name, item);
        }
    }
    // Settings > Battery > Battery Saver (stock: on at 15 %, off when charged above 25 %)
    mAutoOnConf = new MDConfItem(confKey(QStringLiteral("battery-saver-auto-on")), this);
    mAutoOnLevelConf = new MDConfItem(confKey(QStringLiteral("battery-saver-auto-on-level")), this);
    mAutoOffConf = new MDConfItem(confKey(QStringLiteral("battery-saver-auto-off")), this);
    mAutoOffLevelConf = new MDConfItem(confKey(QStringLiteral("battery-saver-auto-off-level")), this);
    for (MDConfItem *item : { mAutoOnConf, mAutoOnLevelConf, mAutoOffConf, mAutoOffLevelConf })
        connect(item, &MDConfItem::valueChanged, this, &ModesEngine::changed);

    mTheaterTimer = new QTimer(this);
    mTheaterTimer->setSingleShot(true);
    connect(mTheaterTimer, &QTimer::timeout, this, &ModesEngine::checkTheater);
    mScreenOffTimer = new QTimer(this);
    mScreenOffTimer->setSingleShot(true);
    // exact: the screen goes off as the transition's last black ends (a coarse
    // timer fires up to 5 % early)
    mScreenOffTimer->setTimerType(Qt::PreciseTimer);
    connect(mScreenOffTimer, &QTimer::timeout, this, &ModesEngine::displayOff);
    // Bedtime came on with the screen off: if it stays off the face goes on
    // top after 2500 ms (stock's PLAY_ANIMATION_TIMEOUT_MS)
    mBedtimeSkipTimer = new QTimer(this);
    mBedtimeSkipTimer->setSingleShot(true);
    connect(mBedtimeSkipTimer, &QTimer::timeout, this, &ModesEngine::bedtimeSkipTimeout);

    for (int i = 0; i < ModeCount; i++) {
        if (mModeConf[i]->value(false).toBool())
            mModes |= Modes[i];
    }
    mDnd = mDndConf->value(false).toBool();
    // Extra dim lasts until a restart, as Android's
    if (extraDim() && mExtraDimBoot->value().toString() != bootId()) {
        qInfo() << "Modes: Extra dim off after a restart";
        mModes &= ~ModesCore::ExtraDim;
        mModeConf[3]->set(false);
    }
    // never both (an older image could leave them so): bedtime stays
    if (bedtime() && mDnd) {
        mDnd = false;
        mDndConf->set(false);
    }
    qInfo() << "Modes:" << (bedtime() ? "bedtime" : "") << (theater() ? "theater" : "") << (batterySaver() ? "battery-saver" : "")
            << (extraDim() ? "extra-dim" : "") << (mDnd ? "do-not-disturb" : "") << (mModes || mDnd ? "" : "none");

    QDBusConnection system = QDBusConnection::systemBus();
    system.connect(MCE_SERVICE, MCE_SIGNAL_PATH, MCE_SIGNAL_IF, "config_change_ind",
                   this, SLOT(mceConfigChanged(QDBusObjectPath, QDBusVariant)));
    system.connect(MCE_SERVICE, MCE_SIGNAL_PATH, MCE_SIGNAL_IF, "display_status_ind",
                   this, SLOT(displayStatusChanged(QString)));
    system.connect(MCE_SERVICE, MCE_SIGNAL_PATH, MCE_SIGNAL_IF, "charger_type_ind",
                   this, SLOT(chargerTypeChanged(QString)));
    // the automatic Battery saver: the level comes with mce's signal, never polled
    system.connect(MCE_SERVICE, MCE_SIGNAL_PATH, MCE_SIGNAL_IF, "battery_level_ind",
                   this, SLOT(mceBatteryLevel(int)));
    loadMce();
    publishAlarmFeedback();
    // after the notification server is up: the "Theater mode off" card of
    // a theater mode that ran out while the watch was off
    QTimer::singleShot(5000, this, &ModesEngine::checkTheater);
    if (theater() && !mTheaterCookie->value().isValid())
        QTimer::singleShot(5000, this, &ModesEngine::armTheaterWake);
}

QString ModesEngine::displayFilter() const
{
    return ModesCore::displayFilterName(ModesCore::displayFilter(mModes, mDisplayFilterConf->value(QString()).toString()));
}

QVariantList ModesEngine::filterMatrix() const
{
    QVariantList out;
    const QVector<double> m = ModesCore::filterMatrix(ModesCore::displayFilter(mModes, mDisplayFilterConf->value(QString()).toString()));
    for (double v : m)
        out << v;
    return out;
}

QString ModesEngine::alarmFeedback() const
{
    return mAlarmFeedback;
}

ModesCore::AutoSaver ModesEngine::autoSaverConfig() const
{
    ModesCore::AutoSaver cfg;
    cfg.autoOn = mAutoOnConf->value(true).toBool();
    cfg.onLevel = qBound(1, mAutoOnLevelConf->value(cfg.onLevel).toInt(), 99);
    cfg.autoOff = mAutoOffConf->value(true).toBool();
    cfg.offLevel = qBound(1, mAutoOffLevelConf->value(cfg.offLevel).toInt(), 100);
    return cfg;
}

// what an alarm may play with the modes that are on (Customize > Alarms and
// Timers), for the presenter and the timer to read; and the notification
// server holds its own alarm feedback to it
void ModesEngine::publishAlarmFeedback()
{
    QHash<QString, QVariant> prefs;
    for (auto it = mAlarmPrefs.constBegin(); it != mAlarmPrefs.constEnd(); ++it) {
        const QVariant v = it.value()->value();
        if (v.isValid())
            prefs.insert(it.key(), v);
    }
    const ModesCore::AlarmAllowed allowed = ModesCore::alarmAllowed(mModes, mDnd, prefs);
    const QString event = ModesCore::alarmEvent(allowed);
    mAlarmMask = ModesCore::alarmMask(allowed);
    if (event == mAlarmFeedback && mAlarmFeedbackConf->value().isValid())
        return;
    mAlarmFeedback = event;
    qInfo() << "Modes: alarms play" << (event.isEmpty() ? QStringLiteral("nothing") : event);
    mAlarmFeedbackConf->set(event);
}

void ModesEngine::alarmPrefsChanged()
{
    publishAlarmFeedback();
    emit changed();
}

int ModesEngine::extraDimIntensity() const
{
    return qBound(0, mIntensityConf->value(ModesCore::DefaultIntensity).toInt(), 100);
}

void ModesEngine::setExtraDimIntensity(int intensity)
{
    mIntensityConf->set(qBound(0, intensity, 100));
}

void ModesEngine::setDoNotDisturb(bool on)
{
    mDndConf->set(on);
}

void ModesEngine::setMode(int mode, bool on)
{
    for (int i = 0; i < ModeCount; i++) {
        if (Modes[i] == mode)
            mModeConf[i]->set(on);
    }
}

void ModesEngine::setRestoreValue(const QString &setting, const QVariant &value)
{
    const int s = ModesCore::settingFromName(setting);
    if (s < 0 || !value.isValid())
        return;
    if (saved(ModesCore::Setting(s)).isValid())
        setSaved(ModesCore::Setting(s), value);
    else
        setValue(ModesCore::Setting(s), value);
}

void ModesEngine::modeConfChanged()
{
    const int before = mModes;
    const bool dndBefore = mDnd;
    mModes = 0;
    for (int i = 0; i < ModeCount; i++) {
        if (mModeConf[i]->value(false).toBool())
            mModes |= Modes[i];
    }
    mDnd = mDndConf->value(false).toBool();
    if (before != mModes || dndBefore != mDnd)
        modesChanged(before, dndBefore);
    else
        apply();   // the intensity
    emit changed();
}

void ModesEngine::modesChanged(int before, bool dndBefore)
{
    const int on = mModes & ~before;
    const int off = before & ~mModes;
    for (int m : Modes) {
        if (on & m)
            qInfo() << "Modes:" << ModesCore::name(m) << "on";
        if (off & m)
            qInfo() << "Modes:" << ModesCore::name(m) << "off";
    }

    // Do Not Disturb and Bedtime: the latest wins (stock's Mode Manager);
    // the new one is on already, so the phone never sees a gap
    if ((on & ModesCore::Bedtime) && mDnd) {
        qInfo() << "Modes: Do Not Disturb off for bedtime";
        mDndConf->set(false);
    } else if (mDnd && !dndBefore && bedtime()) {
        qInfo() << "Modes: bedtime off for Do Not Disturb";
        setMode(ModesCore::Bedtime, false);
    }

    // Battery saver is off on the charger (and back when unplugged)
    if ((on & ModesCore::BatterySaver) && mCharging) {
        qInfo() << "Modes: on the charger: battery saver once unplugged";
        mSaverResume->set(true);
        setMode(ModesCore::BatterySaver, false);
    }
    if ((off & ModesCore::BatterySaver) && !mCharging)
        mSaverResume->unset();

    if (on & ModesCore::Theater) {
        mTheaterSince->set(double(QDateTime::currentMSecsSinceEpoch()) / 1000.0);
        checkTheater();
        armTheaterWake();
        // a black overlay fades in, then the face and the screen off; only a
        // button turns it on again
        if (mDisplayOn) {
            emit theaterStarting();
            mScreenOffTimer->start(TheaterScreenOffMs);
        }
    }
    if (off & ModesCore::Theater) {
        mTheaterSince->unset();
        mTheaterTimer->stop();
        cancelTheaterWake();
    }
    if (on & ModesCore::Bedtime) {
        mBedtimeTransition = false;
        if (mDisplayOn) {
            mBedtimeTransition = true;
            emit bedtimeStarting();
            mScreenOffTimer->start(BedtimeScreenOffMs);
        } else {
            mBedtimeSkipTimer->start(BedtimeSkipMs);
        }
    }
    if (off & ModesCore::Bedtime) {
        mBedtimeSkipTimer->stop();
        if (mBedtimeTransition) {
            // a transition into Bedtime still playing: it ends, no exit one
            mBedtimeTransition = false;
            emit transitionCancelled();
        } else if (mDisplayOn) {
            emit bedtimeEnding();
        }
    }
    if (on & ModesCore::ExtraDim)
        mExtraDimBoot->set(bootId());
    if (!(mModes & (ModesCore::Theater | ModesCore::Bedtime))) {
        mScreenOffTimer->stop();
        mBedtimeTransition = false;
    }
    mEnforced = 0;
    apply();
    publishAlarmFeedback();
}

int ModesEngine::apply()
{
    if (!mReady)
        return 0;
    int writes = ModesCore::apply(*this, mModes, extraDimIntensity());
    if (alwaysOnBlocked() && mMce.value(QLatin1String(KEY_LPM)).toBool()) {
        qInfo() << "Modes: always-on screen off for" << alwaysOnHolder();
        setMce(QLatin1String(KEY_LPM), false);
        writes++;
    }
    return writes;
}

void ModesEngine::loadMce()
{
    QDBusConnection system = QDBusConnection::systemBus();
    const QStringList keys = { KEY_TILT, KEY_TOUCH, KEY_BRIGHTNESS, KEY_ALS, KEY_LPM, KEY_DIM, KEY_FACE_BLANK };
    mMcePending = keys.size();
    for (const QString &key : keys) {
        QDBusMessage get = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "get_config");
        get << QVariant::fromValue(QDBusObjectPath(key));
        auto *watcher = new QDBusPendingCallWatcher(system.asyncCall(get), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, key](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<QDBusVariant> reply = *w;
            w->deleteLater();
            if (reply.isError())
                qWarning() << "Modes: no mce setting" << key << reply.error().message();
            else if (!mMce.contains(key))   // a change signal may have come first
                mMce.insert(key, reply.value().variant());
            if (--mMcePending == 0 && !mReady) {
                mReady = true;
                apply();
                emit changed();
            }
        });
    }
    QDBusMessage display = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "get_display_status");
    auto *dw = new QDBusPendingCallWatcher(system.asyncCall(display), this);
    connect(dw, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QString> reply = *w;
        w->deleteLater();
        if (!reply.isError())
            displayStatusChanged(reply.value());
    });
    QDBusMessage level = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "get_battery_level");
    auto *lw = new QDBusPendingCallWatcher(system.asyncCall(level), this);
    connect(lw, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<int> reply = *w;
        w->deleteLater();
        if (!reply.isError() && mLevel < 0)   // a change signal may have come first
            mceBatteryLevel(reply.value());
    });
    QDBusMessage charger = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "get_charger_type");
    auto *cw = new QDBusPendingCallWatcher(system.asyncCall(charger), this);
    connect(cw, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QString> reply = *w;
        w->deleteLater();
        chargerTypeChanged(reply.isError() ? QStringLiteral("none") : reply.value());
    });
}

void ModesEngine::setMce(const QString &key, const QVariant &value)
{
    mMce.insert(key, value);
    mEchoes[key].append(qMakePair(value, QDateTime::currentMSecsSinceEpoch()));
    QDBusMessage set = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "set_config");
    set << QVariant::fromValue(QDBusObjectPath(key)) << QVariant::fromValue(QDBusVariant(value));
    QDBusConnection::systemBus().call(set, QDBus::NoBlock);
}

bool ModesEngine::tiltToWake() const
{
    return mMce.contains(QLatin1String(KEY_TILT)) ? mMce.value(QLatin1String(KEY_TILT)).toBool() : true;
}

bool ModesEngine::touchToWake() const
{
    return mMce.contains(QLatin1String(KEY_TOUCH)) ? mMce.value(QLatin1String(KEY_TOUCH)).toBool() : true;
}

void ModesEngine::mceConfigChanged(const QDBusObjectPath &path, const QDBusVariant &value)
{
    const QString key = path.path();
    // whatever way this returns: the gestures changed, KeyRouter reads them
    struct Notify {
        ModesEngine *e; bool on;
        ~Notify() { if (on) emit e->changed(); }
    } notify { this, key == QLatin1String(KEY_TILT) || key == QLatin1String(KEY_TOUCH) };
    if (key != QLatin1String(KEY_TILT) && key != QLatin1String(KEY_TOUCH) && key != QLatin1String(KEY_BRIGHTNESS)
            && key != QLatin1String(KEY_ALS) && key != QLatin1String(KEY_LPM) && key != QLatin1String(KEY_DIM)
            && key != QLatin1String(KEY_FACE_BLANK))
        return;
    const QVariant v = value.variant();
    // the echo of a write of ours: the value stays the latest written
    auto &echoes = mEchoes[key];
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    while (!echoes.isEmpty() && now - echoes.first().second > EchoMs)
        echoes.removeFirst();
    for (int i = 0; i < echoes.size(); i++) {
        if (echoes.at(i).first == v) {
            echoes.erase(echoes.begin(), echoes.begin() + i + 1);
            if (echoes.isEmpty())
                mMce.insert(key, v);
            return;
        }
    }
    echoes.clear();
    const bool same = mMce.value(key) == v;
    mMce.insert(key, v);
    if (same || !mReady)
        return;
    // changed elsewhere while a mode holds it: back to the mode's value
    // (Settings and the quick panel offer no control meanwhile). Should
    // mce not keep a value, the engine gives up until the next change of
    // the modes rather than write it again and again
    if (mEnforced > MaxEnforced)
        return;
    mEnforced += apply();
    if (mEnforced > MaxEnforced)
        qWarning() << "Modes: mce does not keep" << key << "at the modes' value";
}

void ModesEngine::displayStatusChanged(const QString &status)
{
    const bool wasOn = mDisplayOn;
    mDisplayOn = status != QLatin1String("off");
    if (mDisplayOn && theater())
        checkTheater();
    if (mDisplayOn == wasOn)
        return;
    if (mDisplayOn && mBedtimeSkipTimer->isActive()) {
        // the screen came on while Bedtime started: the transition plays now
        mBedtimeSkipTimer->stop();
        mBedtimeTransition = true;
        emit bedtimeStarting();
        mScreenOffTimer->start(BedtimeScreenOffMs);
    } else if (!mDisplayOn && mBedtimeTransition) {
        // the screen went off (a button, the timeout) during the transition:
        // it stops and the face is put on top (stock finalizes it)
        mBedtimeTransition = false;
        mScreenOffTimer->stop();
        emit transitionCancelled();
    }
}

void ModesEngine::bedtimeSkipTimeout()
{
    if (!bedtime() || mDisplayOn)
        return;
    emit bedtimeSkipped();
}

void ModesEngine::chargerTypeChanged(const QString &type)
{
    const bool plugged = !type.isEmpty() && type != QLatin1String("none");
    const bool first = !mChargerKnown;
    mChargerKnown = true;
    if (plugged == mCharging) {
        if (first)
            evaluateSaver();
        return;
    }
    mCharging = plugged;
    emit chargingChanged();
    if (plugged) {
        // the saver's notice goes (stock cancels it when the watch is plugged)
        closeSaverNotice();
        if (batterySaver()) {
            qInfo() << "Modes: on the charger: battery saver off until unplugged";
            mSaverResume->set(true);
            setMode(ModesCore::BatterySaver, false);
        }
    } else if (mSaverResume->value(false).toBool()) {
        // back on after the charger, unless "Turn off when charged" is on and
        // the watch is charged to the off level
        const ModesCore::AutoSaver cfg = autoSaverConfig();
        mSaverResume->unset();
        if (ModesCore::afterCharging(cfg, true, mLevel) == ModesCore::ResumeDropped) {
            qInfo() << "Modes: unplugged at" << mLevel << "%: battery saver stays off";
            //% "Battery Saver turned off"
            const QString title = qtTrId("id-saver-auto-off");
            //% "Your watch is above %1%. Battery Saver is turned off."
            const QString body = qtTrId("id-saver-auto-off-body").arg(cfg.offLevel);
            postNotice(title, body, QStringLiteral("battery-saver"), true);
        } else {
            qInfo() << "Modes: unplugged: battery saver back on";
            setMode(ModesCore::BatterySaver, true);
        }
    }
    if (first)
        evaluateSaver();
}

// A level from mce (its battery_level_ind signal, or the first query): the
// automatic Battery saver decides on it. Event driven: nothing polls.
void ModesEngine::mceBatteryLevel(int level)
{
    if (level < 0 || level > 100)
        return;
    if (level == mLevel)
        return;
    mLevel = level;
    emit levelChanged();
    evaluateSaver();
}

void ModesEngine::evaluateSaver()
{
    // on the charger or not is known before the first level counts
    if (!mChargerKnown || mLevel < 0)
        return;
    const int prev = mLevelSeen;
    mLevelSeen = mLevel;
    const ModesCore::AutoSaver cfg = autoSaverConfig();
    switch (ModesCore::autoSaver(cfg, prev, mLevel, mCharging, batterySaver())) {
    case ModesCore::AutoTurnOn: {
        qInfo() << "Modes: battery" << mLevel << "%: battery saver on";
        setMode(ModesCore::BatterySaver, true);
        //% "Low battery"
        const QString title = qtTrId("id-saver-auto-on");
        //% "Battery Saver was automatically turned on at %1%. Connect watch to charger."
        const QString body = qtTrId("id-saver-auto-on-body").arg(cfg.onLevel);
        postNotice(title, body, QStringLiteral("battery-saver"), true);
        break;
    }
    case ModesCore::AutoTurnOff: {
        qInfo() << "Modes: battery" << mLevel << "%: battery saver off";
        setMode(ModesCore::BatterySaver, false);
        const QString title = qtTrId("id-saver-auto-off");
        const QString body = qtTrId("id-saver-auto-off-body").arg(cfg.offLevel);
        postNotice(title, body, QStringLiteral("battery-saver"), true);
        break;
    }
    case ModesCore::AutoNone:
        break;
    }
}

void ModesEngine::checkTheater()
{
    if (!theater())
        return;
    bool ok = false;
    const double since = mTheaterSince->value().toDouble(&ok);
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (!ok || since <= 0) {
        mTheaterSince->set(double(now) / 1000.0);
        mTheaterTimer->start(int(qMin<qint64>(TheaterMaxMs, INT_MAX)));
        return;
    }
    const qint64 left = qint64(since * 1000.0) + TheaterMaxMs - now;
    if (left <= 0) {
        theaterExpired();
        return;
    }
    // the timer stands still while the watch sleeps: a wake of the screen
    // checks again
    mTheaterTimer->start(int(qMin<qint64>(left, INT_MAX)));
}

void ModesEngine::theaterExpired()
{
    qInfo() << "Modes: theater mode off after 24 hours";
    setMode(ModesCore::Theater, false);
    // the screen comes on for it (stock: TheaterModeController wakes the
    // watch), with the card: the launcher is the notification server, so
    // never wait for it here
    QDBusMessage on = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "req_display_state_on");
    QDBusConnection::systemBus().call(on, QDBus::NoBlock);
    //% "Theater mode off"
    const QString title = qtTrId("id-theater-expired");
    //% "Theater mode is turned off after 24 hours"
    const QString body = qtTrId("id-theater-expired-body");
    postNotice(title, body, QStringLiteral("theater"), false);
}

// A card from the engine: the notification server is this process, so the
// call never waits. replaceLast: the battery saver's own notice replaces the
// one before (stock posts it once, auto-cancel, alert only once).
void ModesEngine::postNotice(const QString &title, const QString &body, const QString &mode, bool replaceLast)
{
    QVariantMap hints;
    hints.insert(QStringLiteral("x-asteroid-modes"), mode);
    hints.insert(QStringLiteral("urgency"), 1);
    if (replaceLast) {
        hints.insert(QStringLiteral("x-nemo-preview-summary"), title);
        hints.insert(QStringLiteral("x-nemo-preview-body"), body);
        hints.insert(QStringLiteral("x-nemo-feedback"), QStringLiteral("notif_normal"));
    } else {
        hints.insert(QStringLiteral("x-nemo-feedback"), QStringLiteral("notif_silent"));
    }
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("/org/freedesktop/Notifications"),
                                                       QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("Notify"));
    call << (replaceLast ? QStringLiteral("Battery") : QStringLiteral("asteroid-launcher"))
         << (replaceLast ? mSaverNoticeId : 0u)
         << (replaceLast ? QStringLiteral("ico-battery") : QStringLiteral("ios-film-outline")) << title << body
         << QStringList() << hints << -1;
    if (!replaceLast) {
        QDBusConnection::sessionBus().call(call, QDBus::NoBlock);
        return;
    }
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<uint> reply = *w;
        w->deleteLater();
        if (!reply.isError())
            mSaverNoticeId = reply.value();
    });
}

void ModesEngine::closeSaverNotice()
{
    if (!mSaverNoticeId)
        return;
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("/org/freedesktop/Notifications"),
                                                       QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("CloseNotification"));
    call << mSaverNoticeId;
    mSaverNoticeId = 0;
    QDBusConnection::sessionBus().call(call, QDBus::NoBlock);
}

// Theater's 24 hours end with the watch asleep: a timed event, due at
// since + 24 h, wakes it; its command writes dconf theater-expired, which
// theaterExpiredByTimed() answers. The command runs as the user with the
// session bus of the launcher's own environment. Without timed the 24 hours
// are still checked when the screen comes on (checkTheater).
QString ModesEngine::theaterWakeCommand(const QByteArray &runtimeDir, const QByteArray &busAddress)
{
    return QStringLiteral("/bin/sh -c \"XDG_RUNTIME_DIR='%1' DBUS_SESSION_BUS_ADDRESS='%2' /usr/bin/dconf write %3/theater-expired true\"")
            .arg(QString::fromLocal8Bit(runtimeDir), QString::fromLocal8Bit(busAddress), QLatin1String(ModesPath));
}

void ModesEngine::armTheaterWake()
{
    cancelTheaterWake();
    bool ok = false;
    const double since = mTheaterSince->value().toDouble(&ok);
    if (!theater() || !ok || since <= 0)
        return;
    Maemo::Timed::Interface interface;
    if (!interface.isValid()) {
        qInfo() << "Modes: no timed: theater mode's 24 hours are checked when the screen is on";
        return;
    }
    Maemo::Timed::Event event;
    Maemo::Timed::Event::Action &act = event.addAction();
    act.whenDue();
    act.runCommand(theaterWakeCommand(qgetenv("XDG_RUNTIME_DIR"), qgetenv("DBUS_SESSION_BUS_ADDRESS")), QStringLiteral("ceres"));
    event.setAttribute(QStringLiteral("APPLICATION"), QStringLiteral("launcher"));
    event.setAttribute(QStringLiteral("type"), QStringLiteral("theater-mode"));
    event.setTicker(time_t(since) + time_t(TheaterMaxMs / 1000));
    event.setTriggerIfMissedFlag();
    QDBusReply<uint> res = interface.add_event_sync(event);
    if (res.isValid() && res.value()) {
        mTheaterCookie->set(res.value());
        qInfo() << "Modes: timed wakes the watch at the end of theater mode (cookie" << res.value() << ")";
    } else {
        qWarning() << "Modes: timed would not take theater mode's wake";
    }
}

void ModesEngine::cancelTheaterWake()
{
    const QVariant cookie = mTheaterCookie->value();
    if (!cookie.isValid())
        return;
    mTheaterCookie->unset();
    Maemo::Timed::Interface interface;
    if (interface.isValid() && cookie.toUInt())
        interface.cancel_sync(cookie.toUInt());
}

// the event's command ran (or a test wrote the key)
void ModesEngine::theaterExpiredByTimed()
{
    if (!mTheaterExpiredConf->value(false).toBool())
        return;
    mTheaterExpiredConf->unset();
    mTheaterCookie->unset();   // the event is spent
    // a stale event (Theater was off and on again since) is told by the clock
    checkTheater();
}

void ModesEngine::displayOff()
{
    mBedtimeTransition = false;
    if (!(mModes & (ModesCore::Theater | ModesCore::Bedtime)))
        return;
    QDBusMessage off = QDBusMessage::createMethodCall(MCE_SERVICE, MCE_REQUEST_PATH, MCE_REQUEST_IF, "req_display_state_off");
    QDBusConnection::systemBus().call(off, QDBus::NoBlock);
}

QString ModesEngine::bootId()
{
    QFile f(QStringLiteral("/proc/sys/kernel/random/boot_id"));
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromLatin1(f.readAll().trimmed());
}

QVariant ModesEngine::value(ModesCore::Setting s) const
{
    return mMce.value(mceKey(s));
}

void ModesEngine::setValue(ModesCore::Setting s, const QVariant &v)
{
    qInfo() << "Modes:" << ModesCore::settingName(s) << "=" << v;
    setMce(mceKey(s), v);
}

QVariant ModesEngine::saved(ModesCore::Setting s) const
{
    return mSavedConf[s]->value();
}

void ModesEngine::setSaved(ModesCore::Setting s, const QVariant &v)
{
    if (v.isValid())
        mSavedConf[s]->set(v);
    else
        mSavedConf[s]->unset();
}
