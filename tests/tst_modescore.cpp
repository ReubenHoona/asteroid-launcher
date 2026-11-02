/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * What the modes change (src/modescore.h), on a fake store: each mode's
 * holds, a mode on and off putting the user's settings back exactly,
 * overlapping modes (the user's values come back only when the last one
 * ends, never a mode's), a setting changed while held, a restart with
 * saved values and the modes over, the names Settings shows.
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
    }
    bool isUser() const
    {
        return values.value(C::TiltToWake).toBool() && values.value(C::TouchToWake).toString() == "unblank"
            && values.value(C::Brightness).toInt() == 60 && values.value(C::AutoBrightness).toBool() && saves.isEmpty();
    }
};

static void holds()
{
    // Bedtime: tilt, touch off, brightness 8 %, adaptive off; AOD blocked; silent
    CHECK(C::hold(C::TiltToWake, C::Bedtime) == QVariant(false));
    CHECK(C::hold(C::TouchToWake, C::Bedtime) == QVariant(QString()));
    CHECK(C::hold(C::Brightness, C::Bedtime).toInt() == 8);
    CHECK(C::hold(C::AutoBrightness, C::Bedtime) == QVariant(false));
    CHECK(C::blocksAlwaysOn(C::Bedtime) && C::silencesNotifications(C::Bedtime));
    // Theater: tilt, touch; AOD; silent; the brightness is the user's
    CHECK(C::hold(C::TiltToWake, C::Theater) == QVariant(false));
    CHECK(C::hold(C::TouchToWake, C::Theater) == QVariant(QString()));
    CHECK(!C::hold(C::Brightness, C::Theater).isValid());
    CHECK(!C::hold(C::AutoBrightness, C::Theater).isValid());
    CHECK(C::blocksAlwaysOn(C::Theater) && C::silencesNotifications(C::Theater));
    // Battery saver: tilt and AOD only
    CHECK(C::hold(C::TiltToWake, C::BatterySaver) == QVariant(false));
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
    CHECK(C::holder(C::TiltToWake, C::BatterySaver | C::ExtraDim) == C::BatterySaver);
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
    // Bedtime, then Battery saver; Bedtime ends: tilt stays off (the
    // saver's), touch and brightness back; the saver ends: the user's tilt
    FakeStore st;
    st.user();
    C::apply(st, C::Bedtime);
    C::apply(st, C::Bedtime | C::BatterySaver);
    CHECK(st.values.value(C::TiltToWake) == QVariant(false));
    CHECK(st.saves.value(C::TiltToWake) == QVariant(true));   // still the user's
    C::apply(st, C::BatterySaver);
    CHECK(st.values.value(C::TiltToWake) == QVariant(false));
    CHECK(st.values.value(C::TouchToWake).toString() == "unblank");
    CHECK(st.values.value(C::Brightness).toInt() == 60);
    CHECK(st.values.value(C::AutoBrightness) == QVariant(true));
    CHECK(st.saves.keys() == QList<int>() << C::TiltToWake);
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
    // kept is not touched
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
    st.saves.insert(C::TiltToWake, true);
    st.saves.insert(C::TouchToWake, QStringLiteral("unblank"));
    st.saves.insert(C::Brightness, 60);
    st.saves.insert(C::AutoBrightness, true);
    C::apply(st, 0);
    CHECK(st.isUser());
    // ...or is still on: the saved values stay, nothing is saved over them
    FakeStore on;
    on.values = st.values;
    on.values.insert(C::TiltToWake, false);
    on.saves.insert(C::TiltToWake, true);
    C::apply(on, C::BatterySaver);
    CHECK(on.saves.value(C::TiltToWake) == QVariant(true));
    // a value mce has not given yet is not saved
    FakeStore unknown;
    C::apply(unknown, C::Bedtime);
    CHECK(unknown.saves.isEmpty());
}

int main()
{
    holds();
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
