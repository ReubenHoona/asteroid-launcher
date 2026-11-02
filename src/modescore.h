/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef MODESCORE_H
#define MODESCORE_H

#include <QString>
#include <QVariant>

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
 *                 tilt  touch  brightness            auto  AOD   phone notifications
 *   Bedtime       off   off    at most 8 % (DBV 20)  off   off   silent
 *   Theater       off   off    -                     -     off   silent
 *   Battery saver off   -      -                     -     off   -
 *   Extra dim     -     -      1-9 % (DBV 2-22)      off   -     -
 *
 * (touch: the wake taps of a screen that is off; a screen that is on
 * takes touches as ever). Alarms ring in every mode and a button press
 * turns the screen on. Extra dim is not on stock Wear OS: the watch's own
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
        SettingCount
    };

    // Stock's bedtime cap, 20 of 255 (config_screenBrightnessCapForWearBedtimeMode)
    static constexpr int BedtimeBrightness = 8;
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
};

#endif // MODESCORE_H
