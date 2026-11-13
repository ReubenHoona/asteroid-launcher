/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The program name behind a window (lipstick/src/compositor/eosappkey.h),
 * how a launch of a running application finds its hidden window again. Plain
 * C++: g++ -std=c++17 -I../lipstick/src/compositor tst_appkey.cpp
 */

#include "eosappkey.h"

#include <cstdio>
#include <initializer_list>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static std::string cmd(std::initializer_list<const char *> args)
{
    std::string s;
    for (const char *a : args) { s += a; s += '\0'; }
    return s;
}

int main()
{
    using namespace EosAppKey;
    CHECK(fromCmdline(cmd({ "/usr/bin/asteroid-settings" })) == "asteroid-settings");
    CHECK(fromCmdline(cmd({ "asteroid-timer", "--icon", "x" })) == "asteroid-timer");
    CHECK(fromCmdline(cmd({ "/usr/bin/Asteroid-Music" })) == "asteroid-music");
    // through a launcher or interpreter: the first argument that is a program
    CHECK(fromCmdline(cmd({ "/usr/bin/invoker", "--type=qt6", "--no-wait", "/usr/bin/asteroid-alarmclock" })) == "asteroid-alarmclock");
    CHECK(fromCmdline(cmd({ "/usr/bin/env", "QT_X=1", "/usr/bin/asteroid-hrm" })) == "asteroid-hrm");
    CHECK(fromCmdline(cmd({ "/usr/bin/booster-qt6", "/usr/bin/asteroid-map" })) == "asteroid-map");
    // nothing better than the launcher itself
    CHECK(fromCmdline(cmd({ "/bin/sh", "-c", "x" })) == "x");
    CHECK(fromCmdline(cmd({ "/bin/sh" })) == "sh");
    // .desktop is dropped
    CHECK(base("/usr/share/applications/asteroid-weather.desktop") == "asteroid-weather");
    // empty
    CHECK(fromCmdline("").empty());
    CHECK(fromCmdline(std::string(3, '\0')).empty());
    // the same name lifecycle.js gives an Exec line
    CHECK(fromCmdline(cmd({ "/usr/bin/asteroid-flashlight" })) == "asteroid-flashlight");

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
