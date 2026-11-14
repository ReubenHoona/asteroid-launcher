/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "modescore.h"

#include <QStringList>
#include <QtGlobal>

int ModesCore::extraDimBrightness(int intensity)
{
    const int i = qBound(0, intensity, 100);
    return qBound(1, 9 - (8 * i + 50) / 100, 9);
}

QVariant ModesCore::hold(Setting s, int modes, int intensity)
{
    switch (s) {
    case TiltToWake:
        // Battery saver keeps it (config_disableTiltToWakeInBatterySaverMode false)
        if (modes & (Bedtime | Theater))
            return false;
        break;
    case TouchToWake:
        // Touch lock turns the touch screen off in every display state: a touch does not wake
        // it either (tilt and the crown still do)
        if (modes & (Bedtime | Theater | TouchLock))
            return QStringLiteral("");
        break;
    case Brightness: {
        // the lowest of the caps of the modes that are on
        int level = 101;
        if (modes & Bedtime)
            level = BedtimeBrightness;
        if (modes & ExtraDim)
            level = qMin(level, extraDimBrightness(intensity));
        if (level <= 100)
            return level;
        break;
    }
    case AutoBrightness:
        // Extra dim sets the level itself; Bedtime's cap keeps the light
        // sensor's curve on (it lowers the curve, mce scales it)
        if (modes & ExtraDim)
            return false;
        break;
    case DimTimeout:
    case FaceBlankTimeout:
        if (modes & BatterySaver)
            return SaverTimeoutSeconds;
        break;
    case SettingCount:
        break;
    }
    return QVariant();
}

bool ModesCore::isCap(Setting s, int modes)
{
    switch (s) {
    case Brightness:
        return (modes & Bedtime) && !(modes & ExtraDim);
    case DimTimeout:
    case FaceBlankTimeout:
        return true;
    case TiltToWake:
    case TouchToWake:
    case AutoBrightness:
    case SettingCount:
        break;
    }
    return false;
}

bool ModesCore::adoptsChange(Setting s)
{
    return s == DimTimeout || s == FaceBlankTimeout;
}

bool ModesCore::blocksAlwaysOn(int modes)
{
    return modes & (Bedtime | Theater | BatterySaver);
}

bool ModesCore::silencesNotifications(int modes)
{
    return modes & (Bedtime | Theater);
}

static const int Precedence[] = { ModesCore::Theater, ModesCore::Bedtime, ModesCore::BatterySaver, ModesCore::ExtraDim, ModesCore::TouchLock };

int ModesCore::holder(Setting s, int modes)
{
    for (int m : Precedence) {
        if ((modes & m) && hold(s, m).isValid())
            return m;
    }
    return 0;
}

int ModesCore::alwaysOnHolder(int modes)
{
    for (int m : Precedence) {
        if ((modes & m) && blocksAlwaysOn(m))
            return m;
    }
    return 0;
}

QString ModesCore::name(int mode)
{
    switch (mode) {
    case Bedtime: return QStringLiteral("bedtime");
    case Theater: return QStringLiteral("theater");
    case BatterySaver: return QStringLiteral("battery-saver");
    case ExtraDim: return QStringLiteral("extra-dim");
    case TouchLock: return QStringLiteral("touch-lock");
    }
    return QString();
}

QString ModesCore::settingName(Setting s)
{
    switch (s) {
    case TiltToWake: return QStringLiteral("tilt-to-wake");
    case TouchToWake: return QStringLiteral("touch-to-wake");
    case Brightness: return QStringLiteral("brightness");
    case AutoBrightness: return QStringLiteral("auto-brightness");
    case DimTimeout: return QStringLiteral("dim-timeout");
    case FaceBlankTimeout: return QStringLiteral("face-blank-timeout");
    case SettingCount: break;
    }
    return QString();
}

int ModesCore::settingFromName(const QString &name)
{
    for (int i = 0; i < SettingCount; i++) {
        if (settingName(Setting(i)) == name)
            return i;
    }
    return -1;
}

bool ModesCore::same(Setting s, const QVariant &a, const QVariant &b)
{
    if (a.isValid() != b.isValid())
        return false;
    switch (s) {
    case TiltToWake:
    case AutoBrightness:
        return a.toBool() == b.toBool();
    case Brightness:
    case DimTimeout:
    case FaceBlankTimeout:
        return a.toInt() == b.toInt();
    case TouchToWake:
    case SettingCount:
        break;
    }
    return a.toString() == b.toString();
}

int ModesCore::apply(Store &store, int modes, int intensity)
{
    int writes = 0;
    for (int i = 0; i < SettingCount; i++) {
        const Setting s = Setting(i);
        const QVariant held = hold(s, modes, intensity);
        const QVariant value = store.value(s);
        const QVariant saved = store.saved(s);
        if (held.isValid() && isCap(s, modes)) {
            // a ceiling: only a value above it comes down; a value at or
            // under it is left alone (and not saved: nothing changed)
            if (!value.isValid())
                continue;
            if (value.toInt() > held.toInt()) {
                // the first mode to hold it keeps the user's value; a
                // change of the user's meanwhile is their new value
                if (!saved.isValid() || (adoptsChange(s) && !same(s, saved, value)))
                    store.setSaved(s, value);
                store.setValue(s, held);
                writes++;
            } else if (adoptsChange(s) && saved.isValid() && value.toInt() < held.toInt()) {
                // the user chose less than the ceiling: theirs stays
                store.setSaved(s, QVariant());
            }
        } else if (held.isValid()) {
            // the first mode to hold it keeps the user's value
            if (!saved.isValid() && value.isValid())
                store.setSaved(s, value);
            if (!same(s, value, held)) {
                store.setValue(s, held);
                writes++;
            }
        } else if (saved.isValid()) {
            // the last one let go: the user's value back
            if (!same(s, value, saved)) {
                store.setValue(s, saved);
                writes++;
            }
            store.setSaved(s, QVariant());
        }
    }
    return writes;
}

ModesCore::DisplayFilter ModesCore::displayFilter(int modes, const QString &choice)
{
    if (!(modes & Bedtime))
        return NoFilter;
    if (choice.isEmpty() || choice == QLatin1String("nightlight"))
        return NightLight;
    if (choice == QLatin1String("grayscale"))
        return Grayscale;
    return NoFilter;
}

QString ModesCore::displayFilterName(DisplayFilter f)
{
    switch (f) {
    case NightLight: return QStringLiteral("nightlight");
    case Grayscale: return QStringLiteral("grayscale");
    case NoFilter: break;
    }
    return QString();
}

QVector<double> ModesCore::filterMatrix(DisplayFilter f, int kelvin)
{
    switch (f) {
    case NightLight: {
        // android config_nightDisplayColorTemperatureCoefficients:
        // r 0 0 1, g -9.62353339e-9 1.53045476e-4 0.390782778,
        // b -1.89359041e-8 3.02412211e-4 -0.198650895
        const double k = qBound(1000, kelvin, 6500);
        const double sq = k * k;
        const double r = 0.0 * sq + 0.0 * k + 1.0;
        const double g = -0.00000000962353339 * sq + 0.000153045476 * k + 0.390782778;
        const double b = -0.0000000189359041 * sq + 0.000302412211 * k - 0.198650895;
        return { qBound(0.0, r, 1.0), 0, 0,
                 0, qBound(0.0, g, 1.0), 0,
                 0, 0, qBound(0.0, b, 1.0) };
    }
    case Grayscale:
        // Rec. 709 luma, as Android's grayscale matrix
        return { 0.2126, 0.7152, 0.0722,
                 0.2126, 0.7152, 0.0722,
                 0.2126, 0.7152, 0.0722 };
    case NoFilter:
        break;
    }
    return { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
}

ModesCore::AutoAction ModesCore::autoSaver(const AutoSaver &cfg, int prev, int level, bool charging, bool saverOn)
{
    if (level < 0 || level > 100 || charging)
        return AutoNone;
    if (!cfg.autoOn && !cfg.autoOff)
        return AutoNone;
    // falls to the on level (or the first reading is under it)
    if (cfg.autoOn && !saverOn && level <= cfg.onLevel && (prev < 0 || prev > cfg.onLevel))
        return AutoTurnOn;
    // rises through the off level
    if (cfg.autoOff && saverOn && prev >= 0 && prev < cfg.offLevel && level >= cfg.offLevel)
        return AutoTurnOff;
    return AutoNone;
}

ModesCore::ResumeAction ModesCore::afterCharging(const AutoSaver &cfg, bool resume, int level)
{
    if (!resume)
        return ResumeNone;
    if (cfg.autoOff && level >= 0 && level >= cfg.offLevel)
        return ResumeDropped;
    return ResumeSaver;
}

ModesCore::AlarmAllowed ModesCore::alarmDefault(const QString &mode)
{
    AlarmAllowed a;
    if (mode == QLatin1String("theater"))
        a.sound = false;   // allowAlarms(false, true)
    return a;
}

ModesCore::AlarmAllowed ModesCore::alarmAllowed(int modes, bool dnd, const QHash<QString, QVariant> &prefs)
{
    AlarmAllowed out;
    QStringList on;
    if (dnd)
        on << QStringLiteral("do-not-disturb");
    if (modes & Bedtime)
        on << name(Bedtime);
    if (modes & Theater)
        on << name(Theater);
    for (const QString &mode : on) {
        const AlarmAllowed d = alarmDefault(mode);
        const QVariant sound = prefs.value(mode + QStringLiteral("/alarm-sound"));
        const QVariant vibrate = prefs.value(mode + QStringLiteral("/alarm-vibrate"));
        if (!(sound.isValid() ? sound.toBool() : d.sound))
            out.sound = false;
        if (!(vibrate.isValid() ? vibrate.toBool() : d.vibrate))
            out.vibrate = false;
    }
    return out;
}

QString ModesCore::alarmEvent(const AlarmAllowed &a)
{
    if (a.sound && a.vibrate)
        return QStringLiteral("alarm");
    if (a.sound)
        return QStringLiteral("alarm_sound");
    if (a.vibrate)
        return QStringLiteral("alarm_vibra");
    return QString();
}
