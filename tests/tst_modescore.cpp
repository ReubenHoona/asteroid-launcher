/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * What the modes change (src/modescore.h), on a fake store: each mode's
 * holds, a mode on and off putting the user's settings back exactly,
 * overlapping modes (the user's values come back only when the last one
 * ends, never a mode's), a setting changed while held, a restart with
 * saved values and the modes over, the names Settings shows; Battery saver
 * keeping tilt-to-wake and capping the screen timeout at 10 s, Bedtime's
 * brightness ceiling with the light sensor's curve left on, Bedtime's
 * Night light at 2596 K, the automatic Battery saver (on at 15 %, off above
 * 25 %, after charging), what alarms may play in each mode.
 * cmake -DLAUNCHER_TESTS=ON; runs anywhere (Qt Core only).
 */

#include "modescore.h"

#include <QHash>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

typedef ModesCore C;

class FakeStore : public ModesCore::Store
{
public:
    QHash<int, QVariant> values, saves;
    int writes = 0;
    QVariant value(C::Setting s) const override { return values.value(s); }
    void setValue(C::Setting s, const QVariant &v) override { values.insert(s, v); writes++; }
    QVariant saved(C::Setting s) const override { return saves.value(s); }
    void setSaved(C::Setting s, const QVariant &v) override
    {
        if (v.isValid())
            saves.insert(s, v);
        else
            saves.remove(s);
    }
    // the user's settings
    void user()
    {
        values.insert(C::TiltToWake, true);
        values.insert(C::TouchToWake, QStringLiteral("unblank"));
        values.insert(C::Brightness, 60);
        values.insert(C::AutoBrightness, true);
        values.insert(C::DimTimeout, 15);
        values.insert(C::FaceBlankTimeout, 15);
    }
    bool isUser() const
    {
        return values.value(C::TiltToWake).toBool() && values.value(C::TouchToWake).toString() == "unblank"
            && values.value(C::Brightness).toInt() == 60 && values.value(C::AutoBrightness).toBool()
            && values.value(C::DimTimeout).toInt() == 15 && values.value(C::FaceBlankTimeout).toInt() == 15 && saves.isEmpty();
    }
};

static void holds()
{
    // Bedtime: tilt, touch off, brightness at most 8 % (the light sensor's curve stays
    // on: modes-dnd-17); AOD blocked; silent
    CHECK(C::hold(C::TiltToWake, C::Bedtime) == QVariant(false));
    CHECK(C::hold(C::TouchToWake, C::Bedtime) == QVariant(QString()));
    CHECK(C::hold(C::Brightness, C::Bedtime).toInt() == 8);
    CHECK(!C::hold(C::AutoBrightness, C::Bedtime).isValid());
    CHECK(C::isCap(C::Brightness, C::Bedtime) && !C::isCap(C::Brightness, C::Bedtime | C::ExtraDim));
    CHECK(!C::hold(C::DimTimeout, C::Bedtime).isValid());
    CHECK(C::blocksAlwaysOn(C::Bedtime) && C::silencesNotifications(C::Bedtime));
    // Theater: tilt, touch; AOD; silent; the brightness is the user's
    CHECK(C::hold(C::TiltToWake, C::Theater) == QVariant(false));
    CHECK(C::hold(C::TouchToWake, C::Theater) == QVariant(QString()));
    CHECK(!C::hold(C::Brightness, C::Theater).isValid());
    CHECK(!C::hold(C::AutoBrightness, C::Theater).isValid());
    CHECK(C::blocksAlwaysOn(C::Theater) && C::silencesNotifications(C::Theater));
    // Battery saver: AOD blocked and the screen timeout at most 10 s; tilt-to-wake stays
    // (config_disableTiltToWakeInBatterySaverMode false; charging-battery-16, modes-dnd-10)
    CHECK(!C::hold(C::TiltToWake, C::BatterySaver).isValid());
    CHECK(C::hold(C::DimTimeout, C::BatterySaver).toInt() == 10 && C::hold(C::FaceBlankTimeout, C::BatterySaver).toInt() == 10);
    CHECK(C::isCap(C::DimTimeout, C::BatterySaver) && C::adoptsChange(C::DimTimeout) && !C::adoptsChange(C::Brightness));
    CHECK(!C::hold(C::TouchToWake, C::BatterySaver).isValid());
    CHECK(!C::hold(C::Brightness, C::BatterySaver).isValid());
    CHECK(C::blocksAlwaysOn(C::BatterySaver) && !C::silencesNotifications(C::BatterySaver));
    // Extra dim: the brightness under 10 %, adaptive off; nothing else
    CHECK(!C::hold(C::TiltToWake, C::ExtraDim).isValid());
    CHECK(!C::hold(C::TouchToWake, C::ExtraDim).isValid());
    CHECK(C::hold(C::Brightness, C::ExtraDim).toInt() == C::extraDimBrightness(C::DefaultIntensity));
    CHECK(C::hold(C::AutoBrightness, C::ExtraDim) == QVariant(false));
    CHECK(!C::blocksAlwaysOn(C::ExtraDim) && !C::silencesNotifications(C::ExtraDim));
    // no mode: nothing
    for (int s = 0; s < C::SettingCount; s++)
        CHECK(!C::hold(C::Setting(s), 0).isValid());
    CHECK(!C::blocksAlwaysOn(0) && !C::silencesNotifications(0));
    // Extra dim's levels: under the slider's 10 %, down to the panel's floor
    CHECK(C::extraDimBrightness(0) == 9);
    CHECK(C::extraDimBrightness(25) == 7);
    CHECK(C::extraDimBrightness(50) == 5);
    CHECK(C::extraDimBrightness(90) == 2);
    CHECK(C::extraDimBrightness(100) == 1);
    CHECK(C::extraDimBrightness(-5) == 9 && C::extraDimBrightness(500) == 1);
    for (int i = 0; i <= 100; i++)
        CHECK(C::extraDimBrightness(i) >= 1 && C::extraDimBrightness(i) < 10);
    // both caps: the lower
    CHECK(C::hold(C::Brightness, C::Bedtime | C::ExtraDim, 0).toInt() == 8);
    CHECK(C::hold(C::Brightness, C::Bedtime | C::ExtraDim, 90).toInt() == 2);
}

static void names()
{
    CHECK(C::name(C::Bedtime) == "bedtime" && C::name(C::Theater) == "theater");
    CHECK(C::name(C::BatterySaver) == "battery-saver" && C::name(C::ExtraDim) == "extra-dim");
    CHECK(C::name(0).isEmpty());
    for (int s = 0; s < C::SettingCount; s++)
        CHECK(C::settingFromName(C::settingName(C::Setting(s))) == s);
    CHECK(C::settingFromName("nothing") == -1);
    // who Settings names: theater, bedtime, battery saver, extra dim
    const int all = C::Bedtime | C::Theater | C::BatterySaver | C::ExtraDim;
    CHECK(C::holder(C::TiltToWake, all) == C::Theater);
    CHECK(C::holder(C::TiltToWake, C::Bedtime | C::BatterySaver) == C::Bedtime);
    CHECK(C::holder(C::TiltToWake, C::BatterySaver | C::ExtraDim) == 0);
    CHECK(C::holder(C::DimTimeout, all) == C::BatterySaver);
    CHECK(C::holder(C::TouchToWake, C::BatterySaver | C::ExtraDim) == 0);
    CHECK(C::holder(C::Brightness, all) == C::Bedtime);
    CHECK(C::holder(C::Brightness, C::Theater | C::ExtraDim) == C::ExtraDim);
    CHECK(C::alwaysOnHolder(C::BatterySaver | C::Theater) == C::Theater);
    CHECK(C::alwaysOnHolder(C::ExtraDim) == 0);
}

static void onAndOff()
{
    // each mode alone: on, then off; the user's settings exactly as before
    const int modes[] = { C::Bedtime, C::Theater, C::BatterySaver, C::ExtraDim };
    for (int m : modes) {
        FakeStore st;
        st.user();
        C::apply(st, m);
        for (int s = 0; s < C::SettingCount; s++) {
            const QVariant h = C::hold(C::Setting(s), m);
            if (h.isValid()) {
                CHECK(C::same(C::Setting(s), st.values.value(s), h));
                CHECK(st.saves.contains(s));
            } else {
                CHECK(!st.saves.contains(s));
            }
        }
        // applied again: nothing more to write
        const int writes = st.writes;
        CHECK(C::apply(st, m) == 0 && st.writes == writes);
        C::apply(st, 0);
        CHECK(st.isUser());
    }
    // the user's own odd values come back as they were
    FakeStore st;
    st.user();
    st.values.insert(C::TiltToWake, false);
    st.values.insert(C::TouchToWake, QStringLiteral("unblank,double"));
    st.values.insert(C::Brightness, 30);
    C::apply(st, C::Bedtime);
    C::apply(st, 0);
    CHECK(st.values.value(C::TiltToWake) == QVariant(false));
    CHECK(st.values.value(C::TouchToWake).toString() == "unblank,double");
    CHECK(st.values.value(C::Brightness).toInt() == 30);
    CHECK(st.saves.isEmpty());
}

static void overlapping()
{
    // Bedtime, then Battery saver; Bedtime ends: tilt, touch and brightness
    // back (the saver keeps tilt-to-wake), the timeouts stay at 10 s; the
    // saver ends: the user's timeouts
    FakeStore st;
    st.user();
    C::apply(st, C::Bedtime);
    C::apply(st, C::Bedtime | C::BatterySaver);
    CHECK(st.values.value(C::TiltToWake) == QVariant(false));
    CHECK(st.saves.value(C::TiltToWake) == QVariant(true));   // still the user's
    CHECK(st.values.value(C::DimTimeout).toInt() == 10);
    C::apply(st, C::BatterySaver);
    CHECK(st.values.value(C::TiltToWake) == QVariant(true));
    CHECK(st.values.value(C::TouchToWake).toString() == "unblank");
    CHECK(st.values.value(C::Brightness).toInt() == 60);
    CHECK(st.values.value(C::AutoBrightness) == QVariant(true));
    CHECK(st.values.value(C::DimTimeout).toInt() == 10 && st.values.value(C::FaceBlankTimeout).toInt() == 10);
    CHECK(st.saves.size() == 2 && st.saves.contains(C::DimTimeout) && st.saves.contains(C::FaceBlankTimeout));
    C::apply(st, 0);
    CHECK(st.isUser());

    // Extra dim, then Bedtime on top (8 % < Extra dim's 9 % at intensity 0):
    // Bedtime ends: Extra dim's level; Extra dim ends: the user's
    FakeStore b;
    b.user();
    C::apply(b, C::ExtraDim, 0);
    CHECK(b.values.value(C::Brightness).toInt() == 9);
    C::apply(b, C::ExtraDim | C::Bedtime, 0);
    CHECK(b.values.value(C::Brightness).toInt() == 8);
    CHECK(b.saves.value(C::Brightness).toInt() == 60);
    C::apply(b, C::ExtraDim, 0);
    CHECK(b.values.value(C::Brightness).toInt() == 9);
    CHECK(b.values.value(C::AutoBrightness) == QVariant(false));
    // a new intensity while on
    C::apply(b, C::ExtraDim, 90);
    CHECK(b.values.value(C::Brightness).toInt() == 2);
    C::apply(b, 0, 90);
    CHECK(b.isUser());

    // all four at once, then off in another order
    FakeStore all;
    all.user();
    C::apply(all, C::Bedtime | C::Theater | C::BatterySaver | C::ExtraDim);
    C::apply(all, C::Theater | C::ExtraDim);
    CHECK(all.values.value(C::TouchToWake).toString().isEmpty());
    CHECK(all.values.value(C::Brightness).toInt() == C::extraDimBrightness(C::DefaultIntensity));
    C::apply(all, C::ExtraDim);
    CHECK(all.values.value(C::TiltToWake) == QVariant(true));
    C::apply(all, 0);
    CHECK(all.isUser());
}

static void changedWhileHeld()
{
    // something sets tilt-to-wake on in Bedtime: back off; the user's value
    // kept is not touched (nor is the brightness ceiling's saved value)
    FakeStore st;
    st.user();
    C::apply(st, C::Bedtime);
    st.values.insert(C::TiltToWake, true);
    st.values.insert(C::Brightness, 100);
    CHECK(C::apply(st, C::Bedtime) == 2);
    CHECK(st.values.value(C::TiltToWake) == QVariant(false));
    CHECK(st.values.value(C::Brightness).toInt() == 8);
    CHECK(st.saves.value(C::TiltToWake) == QVariant(true));
    CHECK(st.saves.value(C::Brightness).toInt() == 60);
    // the nightstand puts back what it owes into the saved value
    st.setSaved(C::Brightness, 45);
    C::apply(st, 0);
    CHECK(st.values.value(C::Brightness).toInt() == 45);
}

static void restart()
{
    // the launcher went down in Bedtime and Bedtime ended meanwhile (the
    // phone): the saved values come back at the next start
    FakeStore st;
    st.values.insert(C::TiltToWake, false);
    st.values.insert(C::TouchToWake, QString());
    st.values.insert(C::Brightness, 8);
    st.values.insert(C::AutoBrightness, false);
    st.values.insert(C::DimTimeout, 10);
    st.values.insert(C::FaceBlankTimeout, 10);
    st.saves.insert(C::TiltToWake, true);
    st.saves.insert(C::TouchToWake, QStringLiteral("unblank"));
    st.saves.insert(C::Brightness, 60);
    st.saves.insert(C::AutoBrightness, true);
    st.saves.insert(C::DimTimeout, 15);
    st.saves.insert(C::FaceBlankTimeout, 15);
    C::apply(st, 0);
    CHECK(st.isUser());
    // ...or is still on: the saved values stay, nothing is saved over them
    FakeStore on;
    on.values = st.values;
    on.values.insert(C::TiltToWake, false);
    on.values.insert(C::Brightness, 8);
    on.saves.insert(C::TiltToWake, true);
    on.saves.insert(C::Brightness, 60);
    on.saves.insert(C::DimTimeout, 15);
    on.saves.insert(C::FaceBlankTimeout, 15);
    C::apply(on, C::Bedtime | C::BatterySaver);
    CHECK(on.saves.value(C::TiltToWake) == QVariant(true));
    CHECK(on.saves.value(C::Brightness).toInt() == 60 && on.saves.value(C::DimTimeout).toInt() == 15);
    CHECK(on.values.value(C::Brightness).toInt() == 8 && on.values.value(C::DimTimeout).toInt() == 10);
    // a value mce has not given yet is not saved
    FakeStore unknown;
    C::apply(unknown, C::Bedtime);
    CHECK(unknown.saves.isEmpty());
}

static void saverTimeout()
{
    // 15 s: capped to 10 s, the user's 15 kept; back when the saver ends
    FakeStore st;
    st.user();
    CHECK(C::apply(st, C::BatterySaver) == 2);
    CHECK(st.values.value(C::DimTimeout).toInt() == 10 && st.values.value(C::FaceBlankTimeout).toInt() == 10);
    CHECK(st.saves.value(C::DimTimeout).toInt() == 15 && st.saves.value(C::FaceBlankTimeout).toInt() == 15);
    CHECK(st.values.value(C::TiltToWake).toBool());   // tilt-to-wake kept
    CHECK(C::apply(st, C::BatterySaver) == 0);
    CHECK(C::apply(st, 0) == 2 && st.isUser());

    // 30 s the same
    FakeStore l;
    l.user();
    l.values.insert(C::DimTimeout, 30);
    l.values.insert(C::FaceBlankTimeout, 30);
    C::apply(l, C::BatterySaver);
    CHECK(l.values.value(C::DimTimeout).toInt() == 10 && l.saves.value(C::DimTimeout).toInt() == 30);
    C::apply(l, 0);
    CHECK(l.values.value(C::DimTimeout).toInt() == 30 && l.saves.isEmpty());

    // 10 s and 5 s are not above it: left alone, nothing saved
    for (int t : { 10, 5 }) {
        FakeStore a;
        a.user();
        a.values.insert(C::DimTimeout, t);
        a.values.insert(C::FaceBlankTimeout, t);
        CHECK(C::apply(a, C::BatterySaver) == 0);
        CHECK(a.values.value(C::DimTimeout).toInt() == t && a.saves.isEmpty());
        CHECK(C::apply(a, 0) == 0 && a.values.value(C::DimTimeout).toInt() == t);
    }

    // the user picks 30 s in Settings while the saver is on: the saver takes
    // it down to 10 s and 30 s is what comes back
    FakeStore c;
    c.user();
    C::apply(c, C::BatterySaver);
    c.values.insert(C::DimTimeout, 30);
    c.values.insert(C::FaceBlankTimeout, 30);
    CHECK(C::apply(c, C::BatterySaver) == 2);
    CHECK(c.values.value(C::DimTimeout).toInt() == 10 && c.saves.value(C::DimTimeout).toInt() == 30);
    C::apply(c, 0);
    CHECK(c.values.value(C::DimTimeout).toInt() == 30 && c.values.value(C::FaceBlankTimeout).toInt() == 30);

    // ...or 5 s: that is theirs and stays
    FakeStore d;
    d.user();
    C::apply(d, C::BatterySaver);
    d.values.insert(C::DimTimeout, 5);
    d.values.insert(C::FaceBlankTimeout, 5);
    CHECK(C::apply(d, C::BatterySaver) == 0);
    CHECK(!d.saves.contains(C::DimTimeout) && !d.saves.contains(C::FaceBlankTimeout));
    C::apply(d, 0);
    CHECK(d.values.value(C::DimTimeout).toInt() == 5);

    // a timeout mce has not given yet is neither saved nor written
    FakeStore u;
    CHECK(C::apply(u, C::BatterySaver) == 0 && u.saves.isEmpty());
}

static void bedtimeBrightness()
{
    // the user's 60 % comes down to 8 %, adaptive brightness stays on
    FakeStore st;
    st.user();
    C::apply(st, C::Bedtime);
    CHECK(st.values.value(C::Brightness).toInt() == 8 && st.saves.value(C::Brightness).toInt() == 60);
    CHECK(st.values.value(C::AutoBrightness) == QVariant(true) && !st.saves.contains(C::AutoBrightness));
    C::apply(st, 0);
    CHECK(st.isUser());

    // a user brightness under the cap stays (min(user, 8 %)), nothing saved
    FakeStore low;
    low.user();
    low.values.insert(C::Brightness, 5);
    CHECK(C::apply(low, C::Bedtime) == 2);   // tilt and touch, not the brightness
    CHECK(low.values.value(C::Brightness).toInt() == 5 && !low.saves.contains(C::Brightness));
    C::apply(low, 0);
    CHECK(low.values.value(C::Brightness).toInt() == 5);
    // exactly the cap
    FakeStore eq;
    eq.user();
    eq.values.insert(C::Brightness, 8);
    C::apply(eq, C::Bedtime);
    CHECK(!eq.saves.contains(C::Brightness));
    C::apply(eq, 0);
    CHECK(eq.values.value(C::Brightness).toInt() == 8);

    // Extra dim on top pins (its own level, adaptive off), whatever the user had
    FakeStore x;
    x.user();
    x.values.insert(C::Brightness, 5);
    C::apply(x, C::Bedtime | C::ExtraDim, 0);
    CHECK(x.values.value(C::Brightness).toInt() == 8 && x.saves.value(C::Brightness).toInt() == 5);
    CHECK(x.values.value(C::AutoBrightness) == QVariant(false));
    C::apply(x, 0);
    CHECK(x.values.value(C::Brightness).toInt() == 5 && x.values.value(C::AutoBrightness).toBool());
}

static void nightLight()
{
    // Bedtime on: Night light is the default, a stored choice picks another
    CHECK(C::displayFilter(C::Bedtime, QString()) == C::NightLight);
    CHECK(C::displayFilter(C::Bedtime, "nightlight") == C::NightLight);
    CHECK(C::displayFilter(C::Bedtime, "grayscale") == C::Grayscale);
    CHECK(C::displayFilter(C::Bedtime, "none") == C::NoFilter);
    CHECK(C::displayFilter(C::Bedtime, "something else") == C::NoFilter);
    CHECK(C::displayFilter(C::Bedtime | C::Theater, "nightlight") == C::NightLight);
    // no Bedtime, no filter
    CHECK(C::displayFilter(0, "nightlight") == C::NoFilter && C::displayFilter(C::Theater | C::BatterySaver, QString()) == C::NoFilter);
    CHECK(C::displayFilterName(C::NightLight) == "nightlight" && C::displayFilterName(C::Grayscale) == "grayscale"
          && C::displayFilterName(C::NoFilter).isEmpty());
    // 2596 K, the Pixel Watch's Night light (stock coefficients): red 1, green 0.7232, blue 0.4588
    CHECK(C::NightLightKelvin == 2596);
    const QVector<double> m = C::filterMatrix(C::NightLight);
    CHECK(m.size() == 9);
    CHECK(m[0] == 1.0 && m[1] == 0.0 && m[2] == 0.0 && m[3] == 0.0 && m[5] == 0.0 && m[6] == 0.0 && m[7] == 0.0);
    CHECK(qAbs(m[4] - 0.7232) < 0.0005);
    CHECK(qAbs(m[8] - 0.4588) < 0.0005);
    fprintf(stderr, "night light 2596 K: %.4f %.4f %.4f\n", m[0], m[4], m[8]);
    // warmer is darker in blue, cooler lighter: stock's range 2596-4082 K
    CHECK(C::filterMatrix(C::NightLight, 4082)[8] > m[8] && C::filterMatrix(C::NightLight, 4082)[4] > m[4]);
    CHECK(C::filterMatrix(C::NightLight, 6500)[8] <= 1.0);
    // grayscale: Rec. 709 luma in every row; none: identity
    const QVector<double> g = C::filterMatrix(C::Grayscale);
    for (int row = 0; row < 3; row++)
        CHECK(g[row * 3] == 0.2126 && g[row * 3 + 1] == 0.7152 && g[row * 3 + 2] == 0.0722);
    CHECK(C::filterMatrix(C::NoFilter) == (QVector<double>{ 1, 0, 0, 0, 1, 0, 0, 0, 1 }));
}

static void autoSaver()
{
    C::AutoSaver cfg;   // stock: on at 15 %, off at 25 %
    CHECK(cfg.autoOn && cfg.onLevel == 15 && cfg.autoOff && cfg.offLevel == 25);
    // on: falling to 15 %
    CHECK(C::autoSaver(cfg, 16, 15, false, false) == C::AutoTurnOn);
    CHECK(C::autoSaver(cfg, 15, 14, false, false) == C::AutoNone);   // already under: once
    CHECK(C::autoSaver(cfg, 17, 14, false, false) == C::AutoTurnOn); // a jump over 15
    CHECK(C::autoSaver(cfg, 30, 16, false, false) == C::AutoNone);
    CHECK(C::autoSaver(cfg, -1, 12, false, false) == C::AutoTurnOn); // the first reading, already low
    CHECK(C::autoSaver(cfg, -1, 40, false, false) == C::AutoNone);
    // ...not on the charger, not when it is on, not without the setting
    CHECK(C::autoSaver(cfg, 16, 15, true, false) == C::AutoNone);
    CHECK(C::autoSaver(cfg, 16, 15, false, true) == C::AutoNone);
    cfg.autoOn = false;
    CHECK(C::autoSaver(cfg, 16, 15, false, false) == C::AutoNone);
    cfg.autoOn = true;
    // off: rising through 25 % (not on the charger)
    CHECK(C::autoSaver(cfg, 24, 25, false, true) == C::AutoTurnOff);
    CHECK(C::autoSaver(cfg, 22, 27, false, true) == C::AutoTurnOff);
    CHECK(C::autoSaver(cfg, 25, 26, false, true) == C::AutoNone);
    CHECK(C::autoSaver(cfg, 24, 25, true, true) == C::AutoNone);
    CHECK(C::autoSaver(cfg, 24, 25, false, false) == C::AutoNone);   // nothing to turn off
    CHECK(C::autoSaver(cfg, -1, 60, false, true) == C::AutoNone);    // a restart does not undo the user's saver
    cfg.autoOff = false;
    CHECK(C::autoSaver(cfg, 24, 25, false, true) == C::AutoNone);
    cfg.autoOff = true;
    // another level
    cfg.onLevel = 20;
    cfg.offLevel = 30;
    CHECK(C::autoSaver(cfg, 21, 20, false, false) == C::AutoTurnOn && C::autoSaver(cfg, 16, 15, false, false) == C::AutoNone);
    CHECK(C::autoSaver(cfg, 29, 30, false, true) == C::AutoTurnOff);
    // out of range readings do nothing
    CHECK(C::autoSaver(cfg, 30, -1, false, false) == C::AutoNone && C::autoSaver(cfg, 30, 101, false, false) == C::AutoNone);

    // off the charger: the saver comes back, unless "Turn off when charged" is on
    // and the watch is at the off level or above
    C::AutoSaver s;
    CHECK(C::afterCharging(s, true, 24) == C::ResumeSaver);
    CHECK(C::afterCharging(s, true, 25) == C::ResumeDropped);
    CHECK(C::afterCharging(s, true, 100) == C::ResumeDropped);
    CHECK(C::afterCharging(s, true, -1) == C::ResumeSaver);
    CHECK(C::afterCharging(s, false, 100) == C::ResumeNone);
    s.autoOff = false;
    CHECK(C::afterCharging(s, true, 100) == C::ResumeSaver);
    s.autoOff = true;
    s.offLevel = 50;
    CHECK(C::afterCharging(s, true, 49) == C::ResumeSaver && C::afterCharging(s, true, 50) == C::ResumeDropped);
}

static void alarms()
{
    typedef QHash<QString, QVariant> Prefs;
    // stock defaults: every mode lets an alarm sound and vibrate but Theater (vibration only)
    CHECK(C::alarmDefault("do-not-disturb") == C::AlarmAllowed());
    CHECK(C::alarmDefault("bedtime") == C::AlarmAllowed());
    CHECK(!C::alarmDefault("theater").sound && C::alarmDefault("theater").vibrate);
    CHECK(C::alarmAllowed(0, false, Prefs()) == C::AlarmAllowed());
    CHECK(C::alarmEvent(C::alarmAllowed(0, false, Prefs())) == "alarm");
    CHECK(C::alarmEvent(C::alarmAllowed(C::Bedtime, false, Prefs())) == "alarm");
    C::AlarmAllowed t = C::alarmAllowed(C::Theater, false, Prefs());
    CHECK(!t.sound && t.vibrate);
    CHECK(C::alarmEvent(t) == "alarm_vibra" && C::alarmMask(t) == 2);
    // the Theater page's Sound switch on: both
    Prefs on;
    on.insert("theater/alarm-sound", true);
    CHECK(C::alarmEvent(C::alarmAllowed(C::Theater, false, on)) == "alarm");
    // Vibrate off in Theater: silent
    Prefs off;
    off.insert("theater/alarm-vibrate", false);
    CHECK(C::alarmEvent(C::alarmAllowed(C::Theater, false, off)).isEmpty() && C::alarmMask(C::alarmAllowed(C::Theater, false, off)) == 0);
    // Sound only in Bedtime
    Prefs b;
    b.insert("bedtime/alarm-vibrate", false);
    CHECK(C::alarmEvent(C::alarmAllowed(C::Bedtime, false, b)) == "alarm_sound" && C::alarmMask(C::alarmAllowed(C::Bedtime, false, b)) == 1);
    // modes that are off do not count: Bedtime's switches with only Theater on
    CHECK(C::alarmAllowed(C::Theater, false, b) == t);
    // two modes: each one's limits apply (Theater's no sound, Bedtime's no vibration: silent)
    CHECK(C::alarmEvent(C::alarmAllowed(C::Theater | C::Bedtime, false, b)).isEmpty());
    // Do Not Disturb counts too
    Prefs d;
    d.insert("do-not-disturb/alarm-sound", false);
    CHECK(C::alarmEvent(C::alarmAllowed(0, true, d)) == "alarm_vibra");
    CHECK(C::alarmEvent(C::alarmAllowed(0, false, d)) == "alarm");
    // other modes (battery saver, extra dim) never limit alarms
    CHECK(C::alarmEvent(C::alarmAllowed(C::BatterySaver | C::ExtraDim, false, Prefs())) == "alarm");
    CHECK(C::alarmEvent({ true, false }) == "alarm_sound" && C::alarmEvent({ false, false }).isEmpty());
}

int main()
{
    holds();
    saverTimeout();
    bedtimeBrightness();
    nightLight();
    autoSaver();
    alarms();
    names();
    onAndOff();
    overlapping();
    changedWhileHeld();
    restart();
    if (failures)
        fprintf(stderr, "tst_modescore: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_modescore: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
