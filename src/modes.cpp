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
#include <QDBusVariant>
#include <QDebug>
#include <QFile>
#include <QTimer>
#include <MDConfItem>

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

static const int Modes[] = { ModesCore::Bedtime, ModesCore::Theater, ModesCore::BatterySaver, ModesCore::ExtraDim };

// the time the tile's press shows before the screen goes off in Theater
// mode, and "Starting Bedtime mode…" stays before it goes off in bedtime
static const int TheaterScreenOffMs = 300;
static const int BedtimeScreenOffMs = 2500;

static QString mceKey(ModesCore::Setting s)
{
    switch (s) {
    case ModesCore::TiltToWake: return QLatin1String(KEY_TILT);
    case ModesCore::TouchToWake: return QLatin1String(KEY_TOUCH);
    case ModesCore::Brightness: return QLatin1String(KEY_BRIGHTNESS);
    case ModesCore::AutoBrightness: return QLatin1String(KEY_ALS);
    case ModesCore::SettingCount: break;
    }
    return QString();
}

static QString confKey(const QString &name)
{
    return QLatin1String(ModesEngine::ModesPath) + QLatin1Char('/') + name;
}

ModesEngine::ModesEngine(QObject *parent) : QObject(parent)
{
    for (int i = 0; i < 4; i++) {
        mModeConf[i] = new MDConfItem(confKey(ModesCore::name(Modes[i])), this);
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

    mTheaterTimer = new QTimer(this);
    mTheaterTimer->setSingleShot(true);
    connect(mTheaterTimer, &QTimer::timeout, this, &ModesEngine::checkTheater);
    mScreenOffTimer = new QTimer(this);
    mScreenOffTimer->setSingleShot(true);
    connect(mScreenOffTimer, &QTimer::timeout, this, &ModesEngine::displayOff);

    for (int i = 0; i < 4; i++) {
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
    loadMce();
    // after the notification server is up: the "Theater mode off" card of
    // a theater mode that ran out while the watch was off
    QTimer::singleShot(5000, this, &ModesEngine::checkTheater);
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
    for (int i = 0; i < 4; i++) {
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
    for (int i = 0; i < 4; i++) {
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
        // the screen goes off now; only a button turns it on
        if (mDisplayOn)
            mScreenOffTimer->start(TheaterScreenOffMs);
    }
    if (off & ModesCore::Theater) {
        mTheaterSince->unset();
        mTheaterTimer->stop();
    }
    if ((on & ModesCore::Bedtime) && mDisplayOn) {
        emit bedtimeStarting();
        mScreenOffTimer->start(BedtimeScreenOffMs);
    }
    if (on & ModesCore::ExtraDim)
        mExtraDimBoot->set(bootId());
    if (!(mModes & (ModesCore::Theater | ModesCore::Bedtime)))
        mScreenOffTimer->stop();
    mEnforced = 0;
    apply();
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
    const QStringList keys = { KEY_TILT, KEY_TOUCH, KEY_BRIGHTNESS, KEY_ALS, KEY_LPM };
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
            && key != QLatin1String(KEY_ALS) && key != QLatin1String(KEY_LPM))
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
    mDisplayOn = status != QLatin1String("off");
    if (mDisplayOn && theater())
        checkTheater();
}

void ModesEngine::chargerTypeChanged(const QString &type)
{
    const bool plugged = !type.isEmpty() && type != QLatin1String("none");
    if (plugged == mCharging)
        return;
    mCharging = plugged;
    emit chargingChanged();
    if (plugged && batterySaver()) {
        qInfo() << "Modes: on the charger: battery saver off until unplugged";
        mSaverResume->set(true);
        setMode(ModesCore::BatterySaver, false);
    } else if (!plugged && mSaverResume->value(false).toBool()) {
        qInfo() << "Modes: unplugged: battery saver back on";
        mSaverResume->unset();
        setMode(ModesCore::BatterySaver, true);
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
    // the launcher is the notification server: never wait for it here
    QVariantMap hints;
    hints.insert(QStringLiteral("x-asteroid-modes"), QStringLiteral("theater"));
    hints.insert(QStringLiteral("x-nemo-feedback"), QStringLiteral("notif_silent"));
    hints.insert(QStringLiteral("urgency"), 1);
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("/org/freedesktop/Notifications"),
                                                       QStringLiteral("org.freedesktop.Notifications"),
                                                       QStringLiteral("Notify"));
    //% "Theater mode off"
    const QString title = qtTrId("id-theater-expired");
    //% "Theater mode is turned off after 24 hours"
    const QString body = qtTrId("id-theater-expired-body");
    call << QStringLiteral("asteroid-launcher") << 0u << QStringLiteral("ios-film-outline") << title << body
         << QStringList() << hints << -1;
    QDBusConnection::sessionBus().call(call, QDBus::NoBlock);
}

void ModesEngine::displayOff()
{
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
