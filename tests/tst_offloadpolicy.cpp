/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * When the always-on screen is redrawn and the hub's layout dropped
 * (lipstick/src/compositor/eosoffloadpolicy.h), as stock: one handover per
 * display off, a layout sent only when it changes, expires or the burn-in
 * protection moves the face. The display-off sequences of 2026-11-02/03
 * (battery4: a second "ambient" handover 3.8 s after every display off with a
 * 290 KB resend) and the stale-layout cases. Plain C++ (no Qt):
 * cmake -DLAUNCHER_TESTS=ON, or g++ -std=c++17 -I../lipstick/src/compositor.
 */

#include "eosoffloadpolicy.h"

#include <cstdio>

using namespace EosOffload;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

// A display off as compositor.qml and lipstick do it, counting the
// handovers to the hub and the layouts sent
struct Watch {
    bool daemonLayout = false;      // the daemon holds a layout
    bool unknown = false;           // left by an earlier launcher
    bool offloaded = false;
    int64_t validUntil = 0, moveAfter = 0;
    int handovers = 0, sends = 0, drops = 0;
    int moveMinutes = 60;           // burn-in protection on

    void suspend(int64_t now)       // setUpdatesEnabled(false): offloadSuspend
    {
        if (dropAtSuspend(unknown, daemonLayout, validUntil, moveAfter, now)) {
            daemonLayout = unknown = false;
            drops++;
        }
        offloaded = daemonLayout;
        if (offloaded)
            handovers++;
    }
    void ambientUpdate(int64_t now, int64_t until)  // the AP draws, HubOffload sends, offloadSuspend
    {
        offloaded = false;          // offloadResume("ambient")
        sends++;
        daemonLayout = true;
        validUntil = until;
        moveAfter = moveMinutes ? now + moveMinutes * 60 : 0;
        suspend(now);
    }
    void displayOff(int64_t now, int64_t until)     // the blank, then delayTimer 5 s later
    {
        suspend(now);
        if (ambientUpdateWanted(offloaded, validUntil, now + 5))
            ambientUpdate(now + 5, until);
    }
    void displayOn() { offloaded = false; }         // offloadResume("unblank")
};

int main()
{
    const int64_t t0 = 1793000000, midnight = t0 + 6 * 3600;

    // expired()
    CHECK(!expired(0, t0));
    CHECK(!expired(t0 + 1, t0));
    CHECK(expired(t0, t0));

    // the first display off of a boot: no layout yet, the AP builds one: one handover
    {
        Watch w;
        w.displayOff(t0, midnight);
        CHECK(w.handovers == 1 && w.sends == 1);
    }
    // a launcher restart left the daemon a layout: dropped, then rebuilt: one handover
    {
        Watch w;
        w.daemonLayout = w.unknown = true;
        w.displayOff(t0, midnight);
        CHECK(w.drops == 1 && w.handovers == 1 && w.sends == 1);
    }
    // the evening of 2026-11-02: 16 display ons in 1.5 h with a current layout. Before:
    // 2 handovers and a 290 KB send each; now one handover, and a send only for the
    // hourly burn-in move
    {
        Watch w;
        w.displayOff(t0, midnight);
        int h = w.handovers, s = w.sends;
        for (int i = 1; i <= 16; i++) {
            w.displayOn();
            w.displayOff(t0 + i * 340, midnight);
        }
        CHECK(w.handovers - h == 16);
        CHECK(w.sends - s == 1);     // t0 + 3740 s: the move after 60 min
    }
    // burn-in protection off: no sends at all while the layout is current
    {
        Watch w;
        w.moveMinutes = 0;
        w.displayOff(t0, midnight);
        for (int i = 1; i <= 30; i++) {
            w.displayOn();
            w.displayOff(t0 + i * 600, midnight);
        }
        CHECK(w.handovers == 31 && w.sends == 1);
    }
    // the burn-in move: dropped at the blank, so still one handover for that display off
    {
        Watch w;
        w.displayOff(t0, midnight);
        w.displayOn();
        int h = w.handovers;
        w.displayOff(t0 + 3700, midnight);
        CHECK(w.drops == 1 && w.handovers - h == 1 && w.sends == 2);
    }
    // the date changes at midnight with the display off: the AP's wakeup at validUntil
    // redraws (the minute timer asks), with the display on/off after it as well
    {
        Watch w;
        w.displayOff(midnight - 600, midnight);
        CHECK(!ambientUpdateWanted(w.offloaded, w.validUntil, midnight - 1));
        CHECK(ambientUpdateWanted(w.offloaded, w.validUntil, midnight));
        w.ambientUpdate(midnight, midnight + 86400);
        CHECK(w.sends == 2 && w.handovers == 2 && w.validUntil == midnight + 86400);
        CHECK(!ambientUpdateWanted(w.offloaded, w.validUntil, midnight + 60));
    }
    // a display off after the expiry the AP slept through: never hand over the stale
    // date: dropped at the blank, rebuilt 5 s later
    {
        Watch w;
        w.displayOff(midnight - 600, midnight);
        w.displayOn();
        int h = w.handovers;
        w.displayOff(midnight + 120, midnight + 86400);
        CHECK(w.drops == 1 && w.handovers - h == 1 && w.sends == 2 && w.validUntil == midnight + 86400);
    }
    // the face, 12 h or the date option changed (HubOffload::invalidate: the daemon has none):
    // rebuilt at the next display off, one handover
    {
        Watch w;
        w.displayOff(t0, midnight);
        w.displayOn();
        w.daemonLayout = false;      // invalidate() -> clear
        int h = w.handovers;
        w.displayOff(t0 + 60, midnight);
        CHECK(w.handovers - h == 1 && w.sends == 2);
    }
    // a face the hub cannot draw: the AP draws every minute, as before
    CHECK(ambientUpdateWanted(false, 0, t0));

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
