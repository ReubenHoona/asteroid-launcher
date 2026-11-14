/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef MODES_H
#define MODES_H

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QVariant>
#include <QVariantList>

#include "modescore.h"

class MDConfItem;
class QDBusObjectPath;
class QDBusVariant;
class QTimer;

/*
 * The watch's modes, as the stock Pixel Watch 2 (STOCK-MODES.md): Bedtime,
 * Theater, Battery saver, and Extra dim (this watch's own), next to Do Not
 * Disturb. Each is a dconf key (/org/asteroidos/modes/bedtime, theater,
 * battery-saver, extra-dim; DND stays /org/asteroidos/notifications/
 * do-not-disturb) that the quick panel, Settings, the assistant and
 * asteroid-btsyncd (the phone) switch; this engine, in the launcher,
 * does what a mode changes (ModesCore) and keeps what the user chose:
 *   - tilt-to-wake, touch-to-wake, the brightness and adaptive brightness
 *     (mce settings) are held while a mode needs them off or low, with the
 *     user's values in /org/asteroidos/modes/saved/<setting> until the
 *     last mode ends;
 *   - the always-on screen is blocked (mce's low power mode kept off; the
 *     launcher's MainScreen puts it back from the user's choice);
 *   - Do Not Disturb and Bedtime exclude each other, the latest wins (the
 *     other goes off after the new one is on, so the phone sees no gap);
 *   - Theater mode: the screen fades to black (theaterStarting), the face
 *     shows and the screen goes off after 450 ms; it ends by itself after
 *     24 hours, also across a reboot: a timed event wakes the watch for it
 *     (dconf theater-expired, written by the event's command), Theater is
 *     off, the screen on and the "Theater mode off" card posted;
 *   - Bedtime turned on while the screen is on shows "Starting Bedtime
 *     mode…" (bedtimeStarting: 1000 ms in, 2000 ms held, 1000 ms out, 1000
 *     ms black), then the face and the screen off at 5000 ms; with the
 *     screen off the face shows after 2500 ms (bedtimeSkipped); the screen
 *     going off meanwhile ends it (transitionCancelled). Bedtime turned
 *     off with the screen on: "Turning off Bedtime mode…" (bedtimeEnding;
 *     the screen shows it only with the home screen on top);
 *   - Bedtime puts a colour filter on the screen (displayFilter,
 *     filterMatrix: Night light 2596 K by default);
 *   - alarms and timers come through with the sound and vibration the
 *     modes' Customize pages allow: the event they may play is published
 *     as dconf /org/asteroidos/modes/alarm-feedback and alarmFeedback
 *     (the notification server's feedback follows it too);
 *   - Battery saver goes off on the charger and comes back when unplugged
 *     (unless "Turn off when charged" is on and the level is 25 % or more:
 *     a notice says so); it turns on by itself at 15 % off the charger and
 *     off on rising through 25 % (mce's battery level signal; notices
 *     "Low battery" / "Battery Saver turned off"); it caps the screen
 *     timeout at 10 s and keeps tilt-to-wake;
 *   - Extra dim ends at a reboot (as Android's), its intensity in
 *     /org/asteroidos/modes/extra-dim-intensity.
 * Phone notifications are silenced by btsyncd, which reads the same keys;
 * the notification server (main.cpp sets NotificationManager::setQuiet from
 * quiet) silences every other poster's the same way, alarms excepted.
 */
class ModesEngine : public QObject, private ModesCore::Store
{
    Q_OBJECT
    Q_PROPERTY(bool bedtime READ bedtime WRITE setBedtime NOTIFY changed)
    Q_PROPERTY(bool theater READ theater WRITE setTheater NOTIFY changed)
    Q_PROPERTY(bool batterySaver READ batterySaver WRITE setBatterySaver NOTIFY changed)
    Q_PROPERTY(bool extraDim READ extraDim WRITE setExtraDim NOTIFY changed)
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY changed)
    Q_PROPERTY(int extraDimIntensity READ extraDimIntensity WRITE setExtraDimIntensity NOTIFY changed)
    Q_PROPERTY(bool charging READ charging NOTIFY chargingChanged)
    Q_PROPERTY(bool alwaysOnBlocked READ alwaysOnBlocked NOTIFY changed)
    // Bedtime and Theater: notifications without banner, vibration or sound
    // (alarms still come through); asteroid-btsyncd posts the phone's so,
    // the notification server (lipstick eosquietpolicy.h) holds every poster to it
    Q_PROPERTY(bool quiet READ quiet NOTIFY changed)
    // the mode that holds a setting ("bedtime", "theater", "battery-saver",
    // "extra-dim"), "" if none: Settings and the quick panel name it
    Q_PROPERTY(QString alwaysOnHolder READ alwaysOnHolder NOTIFY changed)
    // Settings > Gestures as mce has them now (stock default: both on): the
    // crown's Home action from the always-on display needs both
    Q_PROPERTY(bool tiltToWake READ tiltToWake NOTIFY changed)
    Q_PROPERTY(bool touchToWake READ touchToWake NOTIFY changed)
    Q_PROPERTY(QString tiltHolder READ tiltHolder NOTIFY changed)
    Q_PROPERTY(QString touchHolder READ touchHolder NOTIFY changed)
    Q_PROPERTY(QString brightnessHolder READ brightnessHolder NOTIFY changed)
    // Bedtime's colour filter: "" (none), "nightlight" or "grayscale", and
    // its 3x3 colour matrix (9 numbers, row-major; identity with none)
    Q_PROPERTY(QString displayFilter READ displayFilter NOTIFY changed)
    Q_PROPERTY(QVariantList filterMatrix READ filterMatrix NOTIFY changed)
    // the ngfd event an alarm may play now: "alarm", "alarm_sound",
    // "alarm_vibra" or "" (modes-dnd-05)
    Q_PROPERTY(QString alarmFeedback READ alarmFeedback NOTIFY changed)
    // Settings > Battery > Battery Saver: "Turn on at N%"
    Q_PROPERTY(bool autoSaverOn READ autoSaverOn NOTIFY changed)
    Q_PROPERTY(int autoSaverOnLevel READ autoSaverOnLevel NOTIFY changed)
    // mce's battery level, -1 until known (its own signal: changed() stays quiet at each percent)
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY levelChanged)

public:
    explicit ModesEngine(QObject *parent = nullptr);

    static constexpr const char *ModesPath = "/org/asteroidos/modes";
    static constexpr const char *DndKey = "/org/asteroidos/notifications/do-not-disturb";
    static const qint64 TheaterMaxMs = 24LL * 3600 * 1000;
    // Stock's timings: "Starting Bedtime mode…" 1000 ms in, 2000 ms held,
    // 1000 ms out and 1000 ms black, then the face and the screen off
    // (modes-dnd-08); with the screen off the face shows after 2500 ms;
    // Theater's overlay fades in 225 ms after 225 ms, then the screen goes off
    // (modes-dnd-16)
    static const int BedtimeScreenOffMs = 5000;
    static const int BedtimeSkipMs = 2500;
    static const int TheaterScreenOffMs = 450;
    // The command timed runs when Theater's 24 hours are over
    static QString theaterWakeCommand(const QByteArray &runtimeDir, const QByteArray &busAddress);

    bool bedtime() const { return mModes & ModesCore::Bedtime; }
    bool theater() const { return mModes & ModesCore::Theater; }
    bool batterySaver() const { return mModes & ModesCore::BatterySaver; }
    bool extraDim() const { return mModes & ModesCore::ExtraDim; }
    bool doNotDisturb() const { return mDnd; }
    int extraDimIntensity() const;
    bool charging() const { return mCharging; }
    bool alwaysOnBlocked() const { return ModesCore::blocksAlwaysOn(mModes); }
    bool quiet() const { return ModesCore::silencesNotifications(mModes); }
    QString alwaysOnHolder() const { return ModesCore::name(ModesCore::alwaysOnHolder(mModes)); }
    bool tiltToWake() const;
    bool touchToWake() const;
    QString tiltHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::TiltToWake, mModes)); }
    QString touchHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::TouchToWake, mModes)); }
    QString brightnessHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::Brightness, mModes)); }
    QString displayFilter() const;
    QVariantList filterMatrix() const;
    QString alarmFeedback() const;
    // 1 sound, 2 vibration (what an alarm may play now)
    int alarmMask() const { return mAlarmMask; }
    bool autoSaverOn() const { return autoSaverConfig().autoOn; }
    int autoSaverOnLevel() const { return autoSaverConfig().onLevel; }
    int batteryLevel() const { return mLevel; }

    void setBedtime(bool on) { setMode(ModesCore::Bedtime, on); }
    void setTheater(bool on) { setMode(ModesCore::Theater, on); }
    void setBatterySaver(bool on) { setMode(ModesCore::BatterySaver, on); }
    void setExtraDim(bool on) { setMode(ModesCore::ExtraDim, on); }
    void setDoNotDisturb(bool on);
    void setExtraDimIntensity(int intensity);

    // What a held setting goes back to when the last mode lets go (the
    // nightstand: unplugged while Extra dim held the brightness it had
    // changed); a setting no mode holds is set at once
    Q_INVOKABLE void setRestoreValue(const QString &setting, const QVariant &value);

signals:
    void changed();
    void chargingChanged();
    void levelChanged();
    // Bedtime came on with the screen on: "Starting Bedtime mode…", the
    // watch face, then the screen goes off (after BedtimeScreenOffMs)
    void bedtimeStarting();
    // Bedtime came on with the screen off and nothing was shown: the watch
    // face is put on top (stock waits 2500 ms for the screen)
    void bedtimeSkipped();
    // Bedtime went off with the screen on: "Turning off Bedtime mode…"
    // (the screen shows it with the home screen on top; no sleep after it)
    void bedtimeEnding();
    // the screen went off while a Bedtime transition played: it ends, the
    // face is put on top
    void transitionCancelled();
    // Theater came on with the screen on: a black overlay fades in (225
    // ms after 225 ms), the face, then the screen goes off at 450 ms
    void theaterStarting();

private slots:
    void modeConfChanged();
    void mceConfigChanged(const QDBusObjectPath &key, const QDBusVariant &value);
    void displayStatusChanged(const QString &status);
    void chargerTypeChanged(const QString &type);
    void mceBatteryLevel(int level);
    void checkTheater();
    void theaterExpiredByTimed();
    void alarmPrefsChanged();
    void bedtimeSkipTimeout();

private:
    QVariant value(ModesCore::Setting s) const override;
    void setValue(ModesCore::Setting s, const QVariant &v) override;
    QVariant saved(ModesCore::Setting s) const override;
    void setSaved(ModesCore::Setting s, const QVariant &v) override;

    void setMode(int mode, bool on);
    void modesChanged(int before, bool dndBefore);
    int apply();
    void loadMce();
    void setMce(const QString &key, const QVariant &value);
    void displayOff();
    void theaterExpired();
    void armTheaterWake();
    void cancelTheaterWake();
    void publishAlarmFeedback();
    void evaluateSaver();
    ModesCore::AutoSaver autoSaverConfig() const;
    void postNotice(const QString &title, const QString &body, const QString &mode, bool replaceLast);
    void closeSaverNotice();
    static QString bootId();

    MDConfItem *mModeConf[5];
    MDConfItem *mDndConf;
    MDConfItem *mSavedConf[ModesCore::SettingCount];
    MDConfItem *mIntensityConf;
    MDConfItem *mTheaterSince;
    MDConfItem *mExtraDimBoot;
    MDConfItem *mSaverResume;
    MDConfItem *mDisplayFilterConf;
    MDConfItem *mTheaterExpiredConf;
    MDConfItem *mTheaterCookie;
    MDConfItem *mAlarmFeedbackConf;
    // battery saver's settings and Customize > Alarms of each mode
    MDConfItem *mAutoOnConf;
    MDConfItem *mAutoOnLevelConf;
    MDConfItem *mAutoOffConf;
    MDConfItem *mAutoOffLevelConf;
    QHash<QString, MDConfItem *> mAlarmPrefs;
    QString mAlarmFeedback;
    int mAlarmMask = 3;
    int mModes = 0;
    bool mDnd = false;
    bool mCharging = false;
    bool mChargerKnown = false;
    bool mDisplayOn = true;
    // mce's battery level (-1 until known) and the one the saver last saw
    int mLevel = -1;
    int mLevelSeen = -1;
    // a Bedtime transition is playing (the screen goes off at its end)
    bool mBedtimeTransition = false;
    uint mSaverNoticeId = 0;
    // mce's values of the settings the modes hold, and its low power mode
    QHash<QString, QVariant> mMce;
    // what the engine wrote and mce has not signalled back yet, oldest
    // first, with the time: a change signal of an earlier write must not
    // undo a later one (nor pass for the user's)
    QHash<QString, QList<QPair<QVariant, qint64>>> mEchoes;
    static const int EchoMs = 5000;
    int mMcePending = 0;
    bool mReady = false;
    // writes that put a held setting back since the modes last changed
    int mEnforced = 0;
    static const int MaxEnforced = 8;
    QTimer *mTheaterTimer;
    QTimer *mScreenOffTimer;
    QTimer *mBedtimeSkipTimer;
};

#endif // MODES_H
