/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "eosbatterypolicy.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

using namespace EosBattery;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static std::string slurp(const char *path)
{
    std::ifstream f(path);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static bool has(const std::string &s, const char *what)
{
    return s.find(what) != std::string::npos;
}

int main()
{
    // stock posts none of the battery notices: not one is wanted
    for (int n = First; n <= Last; ++n) {
        CHECK(!wanted(static_cast<Notice>(n)));
        CHECK(!wakesDisplay(static_cast<Notice>(n)));
    }
    CHECK(!anyWanted());
    CHECK(First == Charging && Last == NotEnoughPower);
    // 'Low battery' (mce LOW, <= 10 %), 'Recharge battery' (EMPTY, <= 2 %) and 'Charging complete' (which
    // turned the display on for 6 s) in particular
    CHECK(!wanted(LowBattery));
    CHECK(!wanted(RechargeBattery));
    CHECK(!wanted(ChargingComplete));
    CHECK(!wanted(Charging));
    CHECK(!wanted(RemoveCharger));
    CHECK(!wanted(ChargingNotStarted));
    CHECK(!wanted(EnteringPSM) && !wanted(ExitingPSM));
    CHECK(!wanted(NotEnoughPower));
    // nothing repeats
    CHECK(lowBatteryRepeatSeconds() == 0);

#ifdef NOTIFIER_SRC
    // the source of BatteryNotifier: no keepalive activity, so nothing is scheduled from suspend
    const std::string cpp = slurp(NOTIFIER_SRC "/batterynotifier.cpp");
    const std::string h = slurp(NOTIFIER_SRC "/batterynotifier.h");
    CHECK(cpp.size() > 1000 && h.size() > 500);
    for (const char *bad : { "BackgroundActivity", "keepalive", "setWakeupRange", "LOW_BATTERY_INTERVAL",
                             "HEARTBEAT_INTERVAL", "startLowBatteryNotifier", "stopLowBatteryNotifier",
                             "updateLowBatteryNotifier", "onBatteryLowTimeout", "m_lowBatteryRepeat" }) {
        CHECK(!has(cpp, bad));
        CHECK(!has(h, bad));
    }
    // the policy is what the notifier asks, before it creates any mce object or posts anything
    CHECK(has(cpp, "EosBattery::anyWanted()"));
    CHECK(has(cpp, "EosBattery::wanted("));
    CHECK(cpp.find("EosBattery::anyWanted()") < cpp.find("new QMceChargerType"));
    CHECK(cpp.find("EosBattery::wanted(") < cpp.find("evaluateNotificationLevel(type, previousState)"));
    // the table still has its nine notices, in the policy's order
    CHECK(has(cpp, "x-nemo.battery\", // NotificationCharging"));
    CHECK(has(cpp, "x-nemo.battery.notenoughpower\", // NotificationNotEnoughPower"));
#endif

    printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
