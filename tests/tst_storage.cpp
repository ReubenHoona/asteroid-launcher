/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The low storage rule (connectivity-system-ux-20, lipstick/src/notifications/eosstorage.h) and the kind of
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
