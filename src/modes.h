/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef MODES_H
#define MODES_H

#include <QHash>
#include <QObject>
#include <QVariant>

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
 *   - Theater mode turns the screen off at once and ends by itself after
 *     24 hours ("Theater mode off" card), also across a reboot;
 *   - Bedtime turned on while the screen is on shows "Starting Bedtime
 *     mode…" (bedtimeStarting), then the screen goes off;
 *   - Battery saver goes off on the charger and comes back when unplugged;
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
    Q_PROPERTY(QString tiltHolder READ tiltHolder NOTIFY changed)
    Q_PROPERTY(QString touchHolder READ touchHolder NOTIFY changed)
    Q_PROPERTY(QString brightnessHolder READ brightnessHolder NOTIFY changed)

public:
    explicit ModesEngine(QObject *parent = nullptr);

    static constexpr const char *ModesPath = "/org/asteroidos/modes";
    static constexpr const char *DndKey = "/org/asteroidos/notifications/do-not-disturb";
    static const qint64 TheaterMaxMs = 24LL * 3600 * 1000;

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
    QString tiltHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::TiltToWake, mModes)); }
    QString touchHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::TouchToWake, mModes)); }
    QString brightnessHolder() const { return ModesCore::name(ModesCore::holder(ModesCore::Brightness, mModes)); }

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
    // Bedtime came on with the screen on: "Starting Bedtime mode…", the
    // watch face, then the screen goes off (after BedtimeScreenOffMs)
    void bedtimeStarting();

private slots:
    void modeConfChanged();
    void mceConfigChanged(const QDBusObjectPath &key, const QDBusVariant &value);
    void displayStatusChanged(const QString &status);
    void chargerTypeChanged(const QString &type);
    void checkTheater();

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
    static QString bootId();

    MDConfItem *mModeConf[4];
    MDConfItem *mDndConf;
    MDConfItem *mSavedConf[ModesCore::SettingCount];
    MDConfItem *mIntensityConf;
    MDConfItem *mTheaterSince;
    MDConfItem *mExtraDimBoot;
    MDConfItem *mSaverResume;
    int mModes = 0;
    bool mDnd = false;
    bool mCharging = false;
    bool mDisplayOn = true;
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
};

#endif // MODES_H
