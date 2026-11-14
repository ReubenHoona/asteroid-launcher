/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The alert rules (lipstick/src/notifications/eosalertpolicy.h): On wrist
 * raise never wakes the display, the 10 s window, the 2 s vibration limit,
 * the queue of 5, the auto-resume window, the bubble and glanceable choice.
 * Plain C++: cmake -DLAUNCHER_TESTS=ON, or g++ -std=c++17 -I../lipstick/src/notifications.
 */

#include "eosalertpolicy.h"

#include <cstdio>

using namespace EosAlert;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main()
{
    // the numbers of the audit
    CHECK(PendingMax == 5);
    CHECK(PendingWindowMs == 10000);
    CHECK(ResumeWindowMs == 10000);
    CHECK(VibrationGapMs == 2000);
    CHECK(ImmediateVibrateMs == 500);
    CHECK(ImmediateShowMs == 750);
    CHECK(GlanceHoldMs == 1000);
    CHECK(GlanceHoldImmediateMs == 1500);
    CHECK(BubbleStayMs == 3000);
    CHECK(glanceHoldMs(false) == 1000);
    CHECK(glanceHoldMs(true) == 1500);

    // On wrist raise (the default): the display off or ambient never wakes,
    // whatever is in front
    CHECK(onArrival(false, false, false) == KeepPending);
    CHECK(onArrival(false, false, true) == KeepPending);
    // Immediately wakes, and judges the surface when it shows
    CHECK(onArrival(false, true, false) == WakeThenShow);
    CHECK(onArrival(false, true, true) == WakeThenShow);
    // the display on: shown, or vibrate only over the keyboard / immersive app / open list
    CHECK(onArrival(true, false, false) == ShowNow);
    CHECK(onArrival(true, true, false) == ShowNow);
    CHECK(onArrival(true, false, true) == VibrateOnly);
    CHECK(onArrival(true, true, true) == VibrateOnly);

    // glanceable on the face, bubble elsewhere, no bubble in Battery Saver
    CHECK(kindFor(true, false) == Glanceable);
    CHECK(kindFor(true, true) == Glanceable);
    CHECK(kindFor(false, false) == Bubble);
    CHECK(kindFor(false, true) == NoKind);

    // a new alert replaces a glanceable, not a bubble and not the full view
    CHECK(replacesCurrent(Glanceable, Glanceable, false));
    CHECK(!replacesCurrent(Glanceable, Glanceable, true));
    CHECK(!replacesCurrent(Bubble, Bubble, false));
    CHECK(!replacesCurrent(NoKind, Glanceable, false));
    CHECK(!replacesCurrent(Glanceable, Bubble, false));

    // the queue's cap
    CHECK(overflow(0) == 0);
    CHECK(overflow(5) == 0);
    CHECK(overflow(6) == 1);
    CHECK(overflow(9) == 4);

    // a conversation is one thread, a plain notification has none
    CHECK(threadKey("Chat", "Sam", true) == threadKey("Chat", "Sam", true));
    CHECK(threadKey("Chat", "Sam", true) != threadKey("Chat", "Alex", true));
    CHECK(threadKey("Chat", "Sam", true) != threadKey("Mail", "Sam", true));
    CHECK(threadKey("Chat", "Sam", false).empty());

    // only notification vibrations are counted
    CHECK(isNotificationVibration("notif_strong"));
    CHECK(isNotificationVibration("notif_silent"));
    CHECK(isNotificationVibration("notif_normal,notif_strong"));
    CHECK(!isNotificationVibration(""));
    CHECK(!isNotificationVibration("alarm"));
    CHECK(!isNotificationVibration("eos_phone_ringing"));
    CHECK(!isNotificationVibration("eos_phone_alarm"));
    CHECK(!isNotificationVibration("battery_empty"));
    CHECK(!isNotificationVibration("notif_strong,alarm"));
    CHECK(!isNotificationVibration("ringtone"));

    // at most one notification vibration per 2000 ms
    {
        VibrationLimiter v;
        CHECK(v.allow(5000));            // the first always plays
        CHECK(!v.allow(5001));
        CHECK(!v.allow(6999));
        CHECK(v.allow(7000));            // 2000 ms after the start of the last one
        CHECK(!v.allow(8999));
        CHECK(v.allow(9000));
        // five alerts in one second: one vibration
        v.reset();
        int played = 0;
        for (int i = 0; i < 5; i++)
            played += v.allow(100000 + i * 200) ? 1 : 0;
        CHECK(played == 1);
        // a blocked alert does not push the window out
        v.reset();
        CHECK(v.allow(0));
        CHECK(!v.allow(1900));
        CHECK(v.allow(2000));
    }

    // On wrist raise: the pending list
    {
        Pending p;
        CHECK(p.takeNewest(0) == 0);
        p.add(1, 1000);
        p.add(2, 2000);
        p.add(3, 3000);
        CHECK(p.size() == 3);
        // the display turns on 9999 ms after the newest: it shows; the rest is dropped
        CHECK(p.takeNewest(3000 + 9999) == 3);
        CHECK(p.size() == 0);
        CHECK(p.takeNewest(3000 + 9999) == 0);
    }
    {
        // 10000 ms exactly still shows, 10001 does not (and the rest is dropped all the same)
        Pending p;
        p.add(7, 500);
        CHECK(p.takeNewest(500 + 10000) == 7);
        p.add(7, 500);
        CHECK(p.takeNewest(500 + 10001) == 0);
        CHECK(p.size() == 0);
    }
    {
        // the newest is judged, not the oldest: an old one under a fresh one is dropped
        Pending p;
        p.add(1, 0);
        p.add(2, 20000);
        CHECK(p.takeNewest(25000) == 2);
        // only an expired one: nothing
        p.add(1, 0);
        CHECK(p.takeNewest(25000) == 0);
    }
    {
        // at most 5, the oldest dropped
        Pending p;
        for (unsigned i = 1; i <= 8; i++)
            p.add(i, i * 100);
        CHECK(p.size() == 5);
        CHECK(!p.contains(1));
        CHECK(!p.contains(3));
        CHECK(p.contains(4));
        CHECK(p.contains(8));
        CHECK(p.items().front().id == 4);
        CHECK(p.takeNewest(1000) == 8);
    }
    {
        // the same notification updated: one entry, the new time
        Pending p;
        p.add(1, 100);
        p.add(2, 200);
        p.add(1, 300);
        CHECK(p.size() == 2);
        CHECK(p.items().back().id == 1);
        CHECK(p.items().back().at == 300);
        // removed by the phone: gone
        p.remove(1);
        CHECK(!p.contains(1));
        CHECK(p.takeNewest(300) == 2);
        // a clock that went back never shows a "future" alert
        p.add(9, 5000);
        CHECK(p.takeNewest(4000) == 0);
    }

    // auto-resume: the alert that was up when the display left ON
    {
        Resume r;
        CHECK(r.take(0) == 0);
        r.left(4, 1000);
        CHECK(r.id() == 4);
        CHECK(r.take(1000 + 10000) == 4);       // within 10000 ms
        CHECK(r.take(1000 + 10000) == 0);       // one use
        r.left(4, 1000);
        CHECK(r.take(1000 + 10001) == 0);       // too late: dropped
        CHECK(r.id() == 0);
        r.left(5, 0);
        r.forget(6);
        CHECK(r.id() == 5);
        r.forget(5);                            // the phone removed it
        CHECK(r.take(100) == 0);
        r.left(5, 0);
        r.clear();
        CHECK(r.take(100) == 0);
    }

    // the clock counts in suspend (CLOCK_BOOTTIME) and goes forward
    {
        const long long a = bootTimeMs();
        const long long b = bootTimeMs();
        CHECK(a > 0);
        CHECK(b >= a);
    }

    fprintf(stderr, "%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
