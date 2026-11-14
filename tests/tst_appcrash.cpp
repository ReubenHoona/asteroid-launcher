/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * When an app that died is a crash, and when it earns the "keeps stopping" dialog (system-dialogs-misc-01,
 * -02): lipstick/src/components/eosappcrash.h. Plain C++.
 */

#include "eosappcrash.h"

#include <cstdio>
#include <csignal>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

using namespace EosCrash;

static void crashSignals()
{
    CHECK(isCrash(true, SIGSEGV, false));
    CHECK(isCrash(true, SIGABRT, false));
    CHECK(isCrash(true, SIGBUS, false));
    CHECK(isCrash(true, SIGILL, false));
    CHECK(isCrash(true, SIGFPE, false));
    CHECK(isCrash(true, SIGSYS, false));
    CHECK(isCrash(true, SIGTRAP, false));
    // closed by the system or the user, or killed for memory: not a crash
    CHECK(!isCrash(true, SIGTERM, false));
    CHECK(!isCrash(true, SIGHUP, false));
    CHECK(!isCrash(true, SIGINT, false));
    CHECK(!isCrash(true, SIGKILL, false));
    // an exit code is no crash, whatever it is
    CHECK(!isCrash(false, 0, false));
    CHECK(!isCrash(false, 1, false));
    CHECK(!isCrash(false, SIGSEGV, false));
    // the launcher's own kill is never one
    CHECK(!isCrash(true, SIGSEGV, true));
    CHECK(!isCrash(true, SIGABRT, true));
}

static void firstCrashShowsNothing()
{
    CrashTracker t;
    Verdict v = t.record("asteroid-weather", 1000);
    CHECK(!v.repeating);
    CHECK(!v.showDialog);
}

static void secondCrashWithin120sShowsTheDialog()
{
    CrashTracker t;
    t.record("asteroid-weather", 0);
    Verdict v = t.record("asteroid-weather", 119999);
    CHECK(v.repeating);
    CHECK(v.showDialog);
}

static void secondCrashAt120sIsNotRepeating()
{
    CrashTracker t;
    t.record("asteroid-weather", 0);
    Verdict v = t.record("asteroid-weather", 120000);
    CHECK(!v.repeating);
    CHECK(!v.showDialog);
    // and the third, a minute later, is repeating
    v = t.record("asteroid-weather", 180000);
    CHECK(v.repeating && v.showDialog);
}

static void oneDialogPerAppPer120s()
{
    CrashTracker t;
    t.record("a", 0);
    Verdict v = t.record("a", 60000);               // second: the dialog
    CHECK(v.repeating && v.showDialog);
    v = t.record("a", 90000);                       // third, 30 s on: repeating, throttled
    CHECK(v.repeating && !v.showDialog);
    v = t.record("a", 150000);                      // 90 s after the dialog: throttled
    CHECK(v.repeating && !v.showDialog);
    v = t.record("a", 180000);                      // 120 s after the dialog (60000 + 120000): shown again
    CHECK(v.repeating && v.showDialog);
}

static void appsAreCountedApart()
{
    CrashTracker t;
    t.record("a", 0);
    t.record("b", 1000);
    Verdict v = t.record("c", 2000);
    CHECK(!v.repeating);
    v = t.record("b", 3000);
    CHECK(v.repeating && v.showDialog);
    v = t.record("a", 4000);
    CHECK(v.repeating && v.showDialog);
}

static void oldEntriesAreForgotten()
{
    CrashTracker t;
    for (int i = 0; i < 50; i++)
        t.record(std::string("app") + char('a' + i % 26) + char('a' + i / 26), i * 1000);
    CHECK(t.tracked() > 0);
    t.record("late", 1000000);
    // everything older than both windows was dropped
    CHECK(t.tracked() == 1);
}

int main()
{
    crashSignals();
    firstCrashShowsNothing();
    secondCrashWithin120sShowsTheDialog();
    secondCrashAt120sIsNotRepeating();
    oneDialogPerAppPer120s();
    appsAreCountedApart();
    oldEntriesAreForgotten();
    CHECK(MinCrashIntervalMs == 120000);
    CHECK(DialogThrottleMs == 120000);
    if (failures)
        fprintf(stderr, "tst_appcrash: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_appcrash: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
