/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The app notification switches (CR-18, FP-L3): which posts the notification server drops
 * (lipstick/src/notifications/eosdisabledapps.h), and a lint of where the server and the launcher
 * use it. Plain C++: cmake -DLAUNCHER_TESTS=ON, or g++ -std=c++17 -I../lipstick/src/notifications.
 */

#include "eosdisabledapps.h"

#include <cstdio>
#include <fstream>
#include <sstream>

using namespace EosDisabledApps;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static std::string slurp(const std::string &path)
{
    std::ifstream f(path);
    std::stringstream s;
    s << f.rdbuf();
    return s.str();
}
static bool has(const std::string &text, const std::string &needle) { return text.find(needle) != std::string::npos; }

static Post post(const char *app, const char *origin = "", const char *category = "", const char *feedback = "")
{
    Post p;
    p.eosApp = app;
    p.originPackage = origin;
    p.category = category;
    p.feedback = feedback;
    return p;
}

int main()
{
    const std::vector<std::string> none;
    const std::vector<std::string> off = { "asteroid-timer", "battery", "bluetooth", "eos-update", "com.example.chat" };

    // the match key: x-eos-app, then x-nemo-origin-package, then category
    CHECK(matchKey("asteroid-timer", "com.example.chat", "x-nemo.email") == "asteroid-timer");
    CHECK(matchKey("", "com.example.chat", "x-nemo.email") == "com.example.chat");
    CHECK(matchKey("", "", "x-nemo.email") == "x-nemo.email");
    CHECK(matchKey("", "", "").empty());
    CHECK(matchKey("  ", "", "battery") == "battery");
    CHECK(normalize("asteroid-timer.desktop") == "asteroid-timer");
    CHECK(normalize(" asteroid-timer ") == "asteroid-timer");
    CHECK(normalize(".desktop") == ".desktop");

    // nothing disabled: nothing dropped
    CHECK(!dropped(none, post("asteroid-timer")));
    // by x-eos-app
    CHECK(dropped(off, post("asteroid-timer")));
    CHECK(dropped(off, post("asteroid-timer.desktop")));
    CHECK(!dropped(off, post("asteroid-calendar")));
    // the system notices set x-eos-app to battery, bluetooth, eos-update
    CHECK(dropped(off, post("battery", "", "x-nemo.battery.lowbattery")));
    CHECK(dropped(off, post("bluetooth")));
    CHECK(dropped(off, post("eos-update")));
    // by x-nemo-origin-package when x-eos-app is not set
    CHECK(dropped(off, post("", "com.example.chat")));
    CHECK(!dropped(off, post("", "com.example.other")));
    // by category when neither is set
    CHECK(dropped(std::vector<std::string>{ "x-nemo.email" }, post("", "", "x-nemo.email")));
    CHECK(!dropped(std::vector<std::string>{ "x-nemo.email" }, post("", "", "x-nemo.im")));
    // the order: a post that names its app by x-eos-app is not judged by a package or a category
    CHECK(!dropped(std::vector<std::string>{ "com.example.chat" }, post("asteroid-calendar", "com.example.chat")));
    CHECK(!dropped(std::vector<std::string>{ "x-nemo.email" }, post("", "com.example.chat", "x-nemo.email")));
    // a post with no app at all is never dropped, an entry of the list written with the suffix still matches
    CHECK(!dropped(off, post("")));
    CHECK(dropped(std::vector<std::string>{ "asteroid-timer.desktop" }, post("asteroid-timer")));

    // an alarm is never dropped, even from a disabled app
    CHECK(!dropped(off, post("asteroid-timer", "", "x-nemo.alarm")));
    CHECK(!dropped(off, post("asteroid-timer", "", "", "alarm")));
    CHECK(!dropped(off, post("asteroid-timer", "", "", "notif_normal,alarm_sound")));
    CHECK(!dropped(off, post("asteroid-timer", "", "", "eos_phone_alarm")));
    CHECK(!dropped(off, post("asteroid-alarmclock", "", "x-nemo.alarm", "alarm")) );
    CHECK(!dropped(std::vector<std::string>{ "asteroid-alarmclock" }, post("asteroid-alarmclock", "", "x-nemo.alarm", "alarm")));
    // other events of a disabled app are dropped
    CHECK(dropped(off, post("asteroid-timer", "", "", "notif_normal")));
    CHECK(isAlarm("x-nemo.alarm", "") && isAlarm("", "find_my_watch") && !isAlarm("x-nemo.email", "notif_strong"));
    // the find-my-watch alert is of the alarm class; a call's ring (eosquietpolicy.h isCallRing) is not
    CHECK(!dropped(off, post("asteroid-timer", "", "", "find_my_watch")));
    CHECK(!isAlarm("", "ringtone") && !isAlarm("", "eos_phone_ringing"));
    // an ongoing activity (the face chip, what keeps its app alive) is not a card
    {
        Post p = post("asteroid-timer");
        p.eosOngoing = "true";
        CHECK(!dropped(off, p));
        p.eosOngoing = "";
        p.nemoOngoing = "true";
        CHECK(!dropped(off, p));
        p.nemoOngoing = "";
        p.asteroidCategory = "ongoing";
        CHECK(!dropped(off, p));
        p.asteroidCategory = "";
        p.eosOngoing = "false";
        CHECK(dropped(off, p));
    }

#ifdef NOTIFIER_SRC
    // where the rule is used: the server checks the list before it stores a post, the launcher keeps the list
    // current from dconf, and lipstick's battery notices name their app
    const std::string mgr = slurp(NOTIFIER_SRC "/notificationmanager.cpp");
    const std::string mgrh = slurp(NOTIFIER_SRC "/notificationmanager.h");
    const std::string bat = slurp(NOTIFIER_SRC "/batterynotifier.cpp");
    const std::string mainCpp = slurp(SRC_ROOT "/src/main.cpp");
    CHECK(mgr.size() > 5000 && mgrh.size() > 1000 && bat.size() > 1000 && mainCpp.size() > 1000);
    CHECK(has(mgr, "#include \"eosdisabledapps.h\""));
    CHECK(has(mgr, "EosDisabledApps::dropped("));
    CHECK(mgr.find("EosDisabledApps::dropped(") < mgr.find("new LipstickNotification(appName, id"));
    CHECK(has(mgr, "x-eos-app") && has(mgr, "x-nemo-origin-package") && has(mgr, "HINT_CATEGORY"));
    CHECK(has(mgrh, "setDisabledApps") && has(mgrh, "isDisabledAppPost"));
    // a post is checked by the same rule as the cards that are in the stream when the list changes
    CHECK(has(mgr, "if (isDisabledAppPost(hints))"));
    CHECK(has(mgr, "if (n && isDisabledAppPost(n->hints()))"));
    CHECK(has(mainCpp, "/org/asteroidos/notifications/disabled-apps"));
    CHECK(has(mainCpp, "setDisabledApps("));
    CHECK(has(bat, "\"x-eos-app\"") && has(bat, "\"battery\""));
#endif

    printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
