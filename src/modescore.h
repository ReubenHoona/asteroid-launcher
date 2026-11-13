/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef MODESCORE_H
#define MODESCORE_H

#include <QHash>
#include <QString>
#include <QVariant>
#include <QVector>

/*
 * What the watch's modes change, as the stock Pixel Watch 2 (Wear OS 4's
 * Mode Manager, ~/mainline/agents/modes/STOCK-MODES.md), without D-Bus or
 * dconf: the tests drive it with a fake store.
 *
 * A mode never forgets what the user chose. Stock computes each setting
 * from the user's value and the modes that override it; mce only knows
 * one value per setting, so a setting a mode overrides is held: the first
 * mode to hold it keeps the user's value (the store's saved value, which
 * outlives the launcher and a reboot, as stock's PersistentStorage cache),
 * the setting stays at the mode's value while any mode holds it, and the
 * last one to let go puts the user's value back. The always-on screen is
 * only blocked: the user's choice (dconf always-on-display) is not
 * touched, the launcher keeps mce's low power mode off meanwhile.
 *
 *                 tilt  touch  brightness            auto  AOD   timeout  phone notifications
 *   Bedtime       off   off    at most 8 % (DBV 20)  -     off   -        silent
 *   Theater       off   off    -                     -     off   -        silent
 *   Battery saver -     -      -                     -     off   at most 10 s  -
 *   Extra dim     -     -      1-9 % (DBV 2-22)      off   -     -        -
 *
 * Battery saver keeps tilt-to-wake (stock overlays
 * config_disableTiltToWakeInBatterySaverMode = false; charging-battery-16)
 * and caps the screen timeout at 10 s (config_batterySaverScreenTimeoutMs,
 * ScreenTimeoutController.java:99,105; charging-battery-17). Bedtime caps
 * the brightness (config_screenBrightnessCapForWearBedtimeMode = 20 of 255)
 * and leaves the light sensor's curve on: mce scales the curve with the
 * brightness setting, so the cap lowers the curve and a lower user value
 * stays (modes-dnd-17). A cap holds only a value above it: a setting that
 * is under it is left as it is. Bedtime also turns a colour filter on
 * (Night light 2596 K by default, config_defaultEnableNightLightForBedtimeMode
 * on the Pixel Watch; modes-dnd-09).
 *
 * (touch: the wake taps of a screen that is off; a screen that is on
 * takes touches as ever). Alarms come through in every mode, with the
 * sound and vibration the mode's Customize page allows (Theater: vibration
 * only, stock allowAlarms(false, true)) and a button press turns the
 * screen on. Extra dim is not on stock Wear OS: the watch's own
 * mode below the lowest brightness (Android's Extra dim cannot be read by
 * an app since Android 12).
 */
class ModesCore
{
public:
    enum Mode {
        Bedtime = 1,
        Theater = 2,
        BatterySaver = 4,
        ExtraDim = 8,
    };
    enum Setting {
        TiltToWake,     // bool, mce wrist_sensor_enabled
        TouchToWake,    // string, mce powerkey actions_gesture4: "unblank" or ""
        Brightness,     // int percent, mce display_brightness (DBV = 255 * % / 100)
        AutoBrightness, // bool, mce als_enabled
        DimTimeout,     // int seconds, mce display_dim_timeout (Settings > Display > Screen timeout)
        FaceBlankTimeout, // int seconds, mce display_blank_from_locksreen_timeout (the same on the watch face)
        SettingCount
    };

    // Stock's bedtime cap, 20 of 255 (config_screenBrightnessCapForWearBedtimeMode)
    static constexpr int BedtimeBrightness = 8;
    // The screen timeout Battery saver caps (config_batterySaverScreenTimeoutMs = 10000)
    static constexpr int SaverTimeoutSeconds = 10;
    // Extra dim's brightness at an intensity of 0..100 (Android's Extra
    // dim strength): 9 % (under the slider's lowest step, 10 %) to 1 %
    // (DBV 2, the panel's floor)
    static int extraDimBrightness(int intensity);
    static constexpr int DefaultIntensity = 50;
    // The always-on screen's highest panel step in Extra dim (the "low"
    // choice is 6)
    static constexpr int ExtraDimAodStep = 4;

    // What a setting is held at while these modes are on; invalid: not held
    static QVariant hold(Setting s, int modes, int intensity = DefaultIntensity);
    // The hold is a ceiling (a number above it comes down to it, one under
    // it stays) rather than a value: the screen timeouts and Bedtime's
    // brightness. Extra dim's brightness is a value (it dims whatever the
    // brightness is), so with it on the brightness is not a ceiling.
    static bool isCap(Setting s, int modes);
    // A change of the user's, while a ceiling holds, is the user's new
    // value to put back later (the screen timeouts; stock keeps the user's
    // choice when it is changed meanwhile) rather than something to undo
    static bool adoptsChange(Setting s);
    static bool blocksAlwaysOn(int modes);
    // Phone notifications come without a banner or vibration (alarms and
    // the find-my-watch alert still come through), as Do Not Disturb;
    // asteroid-btsyncd applies it
    static bool silencesNotifications(int modes);
    // The mode the settings name for a held setting ("Bedtime mode is
    // on"): the first of theater, bedtime, battery saver and extra dim
    // that holds it, 0 if none
    static int holder(Setting s, int modes);
    static int alwaysOnHolder(int modes);
    // The dconf names: bedtime, theater, battery-saver, extra-dim
    static QString name(int mode);
    static QString settingName(Setting s);
    static int settingFromName(const QString &name);   // -1 if unknown

    // The watch's settings, and the user's values kept while held
    class Store
    {
    public:
        virtual ~Store() {}
        virtual QVariant value(Setting s) const = 0;   // invalid: not known yet
        virtual void setValue(Setting s, const QVariant &v) = 0;
        virtual QVariant saved(Setting s) const = 0;   // invalid: none
        virtual void setSaved(Setting s, const QVariant &v) = 0;
    };

    // Brings every setting in line with the modes that are on: a setting
    // newly held is saved, then set; one still held but changed meanwhile
    // goes back to the mode's value; one no mode holds any more gets the
    // saved value back. Returns the number of settings written.
    static int apply(Store &store, int modes, int intensity = DefaultIntensity);

    static bool same(Setting s, const QVariant &a, const QVariant &b);

    /*
     * Bedtime's colour filter (modes-dnd-09). Stock's Night light on the
     * Pixel Watch is 2596 K (config_nightDisplayColorTemperatureDefault,
     * overlay AndroidOverlayPixelWatch; Min is 2596, Max 4082), turned on by
     * Bedtime by default (config_defaultEnableNightLightForBedtimeMode),
     * and Settings > Bedtime > Customize > Display options picks Nightlight,
     * Grayscale or No color filter (dconf /org/asteroidos/modes/bedtime/
     * display-filter = nightlight | grayscale | none).
     */
    enum DisplayFilter {
        NoFilter = 0,
        Grayscale = 1,
        NightLight = 2,
    };
    static constexpr int NightLightKelvin = 2596;
    // The filter the modes put on the screen: Bedtime's choice ("" or
    // "nightlight" the stock default, "grayscale", anything else none),
    // none with Bedtime off
    static DisplayFilter displayFilter(int modes, const QString &choice);
    static QString displayFilterName(DisplayFilter f);   // "", "grayscale", "nightlight"
    // The colour matrix of a filter: rows R, G, B of the output over the
    // input R, G, B (9 numbers, row-major). Night light is Android's
    // ColorDisplayService.computeMatrixForCct with the stock coefficients
    // (android config_nightDisplayColorTemperatureCoefficients): a diagonal
    // matrix of the quadratic c2 * K^2 + c1 * K + c0 per channel (red 1);
    // grayscale is the Rec. 709 luma in every row, as Android's.
    static QVector<double> filterMatrix(DisplayFilter f, int kelvin = NightLightKelvin);

    /*
     * The automatic Battery saver (Wear OS AutomaticBatterySaverControllerV2,
     * ScheduleManager; charging-battery-18, -19). Fed by mce's battery level
     * signal, never polled. Settings > Battery > Battery Saver: "Turn on at
     * 15%" (default on) and "Turn off when charged" (default on, "above
     * 25%"); dconf /org/asteroidos/modes/battery-saver-auto-on, -auto-on-level,
     * -auto-off, -auto-off-level.
     */
    struct AutoSaver {
        bool autoOn = true;
        int onLevel = 15;
        bool autoOff = true;
        int offLevel = 25;
    };
    enum AutoAction {
        AutoNone = 0,
        AutoTurnOn,
        AutoTurnOff,
    };
    // A new battery level (prev: the one before, -1 if none): the saver
    // turns on when the level falls to the on level (the first reading
    // under it counts), off when it rises through the off level; never on
    // the charger, where the saver is off anyway, and an off needs a
    // reading to cross from (a launcher that restarts must not undo the
    // user's saver)
    static AutoAction autoSaver(const AutoSaver &cfg, int prev, int level, bool charging, bool saverOn);
    enum ResumeAction {
        ResumeNone = 0,
        ResumeSaver,     // back on: the user's saver, as before the charger
        ResumeDropped,   // charged above the off level: it stays off, with a notice
    };
    // The watch came off the charger with the saver on before it (resume):
    // it comes back unless "Turn off when charged" is on and the level is
    // at the off level or above
    static ResumeAction afterCharging(const AutoSaver &cfg, bool resume, int level);

    /*
     * Alarms in a mode (modes-dnd-05; Settings > <mode> > Customize >
     * Alarms and Timers, Sound and Vibrate; stock AlarmsCategory,
     * FocusModeConstants.createZenPolicyFor). Alarms are never silenced
     * entirely by a mode, only as that page says; Theater defaults to
     * vibration only (allowAlarms(false, true)). With several modes on, each
     * one's limits apply.
     */
    struct AlarmAllowed {
        bool sound = true;
        bool vibrate = true;
        bool operator==(const AlarmAllowed &o) const { return sound == o.sound && vibrate == o.vibrate; }
    };
    static AlarmAllowed alarmDefault(const QString &mode);   // "do-not-disturb", "bedtime", "theater"
    // prefs: "<mode>/alarm-sound" and "<mode>/alarm-vibrate" (bool) where set
    static AlarmAllowed alarmAllowed(int modes, bool dnd, const QHash<QString, QVariant> &prefs);
    // The ngfd event an alarm may play: "alarm" (both), "alarm_sound",
    // "alarm_vibra", "" (neither: the alarm still shows, silently)
    static QString alarmEvent(const AlarmAllowed &a);
    // 1 sound, 2 vibration (what NotificationManager and eosquietpolicy.h take)
    static int alarmMask(const AlarmAllowed &a) { return (a.sound ? 1 : 0) | (a.vibrate ? 2 : 0); }
};

#endif // MODESCORE_H
