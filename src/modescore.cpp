/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "modescore.h"

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
        if (modes & (Bedtime | Theater | BatterySaver))
            return false;
        break;
    case TouchToWake:
        if (modes & (Bedtime | Theater))
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
        // a cap holds only with the light sensor's curve off
        if (modes & (Bedtime | ExtraDim))
            return false;
        break;
    case SettingCount:
        break;
    }
    return QVariant();
}

bool ModesCore::blocksAlwaysOn(int modes)
{
    return modes & (Bedtime | Theater | BatterySaver);
}

bool ModesCore::silencesNotifications(int modes)
{
    return modes & (Bedtime | Theater);
}

static const int Precedence[] = { ModesCore::Theater, ModesCore::Bedtime, ModesCore::BatterySaver, ModesCore::ExtraDim };

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
        if (held.isValid()) {
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
