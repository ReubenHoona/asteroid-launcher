/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The not-responding exchange (system-dialogs-misc-03): lipstick/src/compositor/eosanr.h. Plain C++.
 */

#include "eosanr.h"

#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

using namespace EosAnr;

int main()
{
    CHECK(TimeoutMs == 5000);

    // a touch pings once; touches while it is out do not ping again
    {
        Policy p;
        CHECK(!p.pending());
        CHECK(p.touched(4, 1000));
        CHECK(p.pending() && p.window() == 4 && p.sentAt() == 1000);
        CHECK(!p.touched(4, 1200));
        CHECK(!p.touched(4, 3000));
        CHECK(p.sentAt() == 1000);          // the 5 s count is of the first ping
    }
    // a pong: the app answered; the next touch pings again
    {
        Policy p;
        CHECK(p.touched(4, 0));
        p.ponged();
        CHECK(!p.pending());
        CHECK(!p.expired(true, 4));         // no dialog for an app that answered
        CHECK(p.touched(4, 9000));
    }
    // no pong: the timer fires and the dialog shows, for the app in front, display on
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(p.expired(true, 4));
        CHECK(p.shown());
        // the dialog is up: no new ping, no second dialog
        CHECK(!p.touched(4, 6000));
        CHECK(!p.expired(true, 4));
    }
    // background apps are silent: another window is in front when the timer fires
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(!p.expired(true, 7));
        CHECK(!p.shown() && !p.pending());
    }
    // never with the display off
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(!p.expired(false, 4));
        CHECK(!p.shown() && !p.pending());
        CHECK(p.touched(4, 10000));
    }
    // Wait: another ping and another 5 s; the app answering then ends it quietly
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(p.expired(true, 4));
        p.waited(5200);
        CHECK(!p.shown());
        CHECK(p.pending() && p.sentAt() == 5200);
        p.ponged();
        CHECK(!p.pending());
        // or it does not, and the dialog comes back
        p.waited(20000);
        CHECK(p.expired(true, 4));
        CHECK(p.shown());
    }
    // Close app (or the app went away): everything is forgotten
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(p.expired(true, 4));
        p.closed();
        CHECK(!p.shown() && !p.pending());
        CHECK(p.touched(5, 100));
        CHECK(p.window() == 5);
    }
    // a touch for another window while a ping is out for the first
    {
        Policy p;
        CHECK(p.touched(4, 0));
        CHECK(p.touched(5, 100));           // the old ping is forgotten
        CHECK(p.window() == 5);
        CHECK(!p.expired(true, 4));         // the first window is not the one waited for any more
    }
    if (failures)
        fprintf(stderr, "tst_anr: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_anr: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
