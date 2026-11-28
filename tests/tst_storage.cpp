/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The low storage rule (connectivity-system-ux-20, lipstick/src/notifications/eosstorage.h), when the notifier
 * looks and what it does with the notification (C-17: a fake df and a fake boot clock), and the kind of
 * shutdown (power-boot-warnings-03, lipstick/src/eosshutdown.h). Plain C++.
 */

#include "eosstorage.h"
#include "eosshutdown.h"

#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static const int64_t MiB = 1024 * 1024;
static const int64_t GiB = 1024 * MiB;

int main()
{
    using namespace EosStorage;
    // min(5 %, 250 MiB)
    CHECK(MaxLowBytes == uint64_t(250 * MiB));
    CHECK(lowBytes(2 * GiB) == uint64_t(2 * GiB / 20));          // 5 % = 102 MiB: under the cap
    CHECK(lowBytes(4 * GiB) == uint64_t(4 * GiB) / 20);   // 204.8 MiB
    CHECK(lowBytes(5 * GiB) == MaxLowBytes);                     // 5 % = 256 MiB: the cap
    CHECK(lowBytes(100 * GiB) == MaxLowBytes);
    CHECK(lowBytes(0) == 0);

    // a 2 GiB partition: low under 102.4 MiB free
    CHECK(isLow(100 * MiB, 2 * GiB));
    CHECK(!isLow(103 * MiB, 2 * GiB));
    // a 16 GiB one: low under 250 MiB free, not at 5 % (819 MiB)
    CHECK(isLow(249 * MiB, 16 * GiB));
    CHECK(!isLow(251 * MiB, 16 * GiB));
    CHECK(!isLow(800 * MiB, 16 * GiB));
    // exactly at the limit is not low (free < low)
    CHECK(!isLow(250 * MiB, 16 * GiB));
    CHECK(isLow(250 * MiB - 1, 16 * GiB));
    // nothing known: not low
    CHECK(!isLow(0, 0));
    CHECK(!isLow(-1, 16 * GiB));
    CHECK(isLow(0, 16 * GiB));

    // ---- when the notifier looks (C-17), on a fake df and a fake CLOCK_BOOTTIME ----
    {
        int64_t freeB = 10 * GiB, totalB = 16 * GiB;
        bool known = true;
        int stats = 0;
        auto df = [&](int64_t &f, int64_t &t) {
            stats++;
            if (!known)
                return false;
            f = freeB;
            t = totalB;
            return true;
        };
        Monitor m;
        CHECK(!m.shown && m.last < 0);
        // the launcher starts: a look at once; plenty of room
        CHECK(m.look(Start, 100, df) == None && stats == 1 && !m.shown);
        // the screen on within the hour: no look at all (no statvfs)
        CHECK(!m.due(DisplayOn, 100 + 3599));
        CHECK(m.look(DisplayOn, 100 + 3599, df) == None && stats == 1);
        // an hour after the last look (the time asleep counts): a look; 200 MiB free of 16 GiB is low
        freeB = 200 * MiB;
        CHECK(m.look(DisplayOn, 100 + 3600, df) == Show && stats == 2 && m.shown);
        // still low: no second notification
        CHECK(m.look(Update, 4000, df) == None && stats == 3 && m.shown);
        // eos-update's state and dsme look whatever the time; above the limit the notification goes
        // (stock cancels it on leaving LEVEL_LOW)
        freeB = 260 * MiB;
        CHECK(m.look(Dsme, 4001, df) == Clear && !m.shown && stats == 4);
        CHECK(m.look(Update, 4002, df) == None && !m.shown);
        // the screen right after a look: not due
        freeB = 100 * MiB;
        CHECK(m.look(DisplayOn, 4003, df) == None && !m.shown && stats == 5);
        CHECK(m.look(DisplayOn, 4002 + 3600, df) == Show && m.shown);
        // df failing: nothing changes (no Clear for an unknown)
        known = false;
        CHECK(m.look(Start, 9000, df) == None && m.shown);
        known = true;
        CHECK(m.look(Start, 9001, df) == None && m.shown);
        freeB = 5 * GiB;
        CHECK(m.look(Start, 9002, df) == Clear && !m.shown);
        // a small partition: 5 % rules (2 GiB: under 102.4 MiB)
        Monitor s;
        totalB = 2 * GiB;
        freeB = 150 * MiB;
        CHECK(s.look(Start, 0, df) == None);
        freeB = 100 * MiB;
        CHECK(s.look(Update, 1, df) == Show && s.shown);
        // a size of 0 is not known
        totalB = 0;
        CHECK(s.look(Update, 2, df) == None && s.shown);
    }

    using namespace EosShutdown;
    CHECK(!isRestart("poweroff"));
    CHECK(!isRestart("halt"));
    CHECK(!isRestart(""));
    CHECK(!isRestart("something-new"));
    CHECK(isRestart("reboot"));
    CHECK(isRestart("kexec"));
    CHECK(isRestart("soft-reboot"));

    if (failures)
        fprintf(stderr, "tst_storage: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_storage: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
