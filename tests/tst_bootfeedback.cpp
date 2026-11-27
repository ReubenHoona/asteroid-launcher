/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * R5 B-09: when the boot-complete feedback is due (src/eosbootfeedback.h), as stock's
 * BootCompletedFeedbackProvider: once per boot, the setup finished, not the first boot of an update (eos-update's
 * trial boot, PHASE=trial in its state file). Plain C++.
 */

#include "eosbootfeedback.h"

#include <cstdio>

using namespace EosBootFeedback;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main()
{
    const std::string boot = "00000000-0000-4000-8000-000000000001\n";
    const std::string other = "00000000-0000-4000-8000-000000000002";

    // eos-update's state file: the last PHASE= line
    CHECK(updatePhase("") == "");
    CHECK(updatePhase("VERSION=72\nPHASE=trial\nRESULT=\n") == "trial");
    CHECK(updatePhase("PHASE=staged\nPHASE=confirmed\n") == "confirmed");
    CHECK(updatePhase("PHASE=trial") == "trial");
    CHECK(updatePhase("PHASE=trial \r\n") == "trial");
    CHECK(updatePhase("XPHASE=trial\nNOTPHASE=x\n") == "");
    CHECK(updatePhase("VERSION=72\n") == "");

    // a new boot, setup done, no update: it plays
    CHECK(due(boot, "", true, ""));
    CHECK(due(boot, other, true, "idle"));
    CHECK(due(boot, other, true, "confirmed"));
    CHECK(due(boot, other, true, "staged"));
    // the same boot again (the launcher restarted): no
    CHECK(!due(boot, "00000000-0000-4000-8000-000000000001", true, ""));
    CHECK(!due(boot, " 00000000-0000-4000-8000-000000000001\n", true, ""));
    // the setup not finished: no (stock: unless setup is not finished)
    CHECK(!due(boot, other, false, ""));
    // the first boot of an update (the trial boot): no (stock: unless the boot follows an OTA update)
    CHECK(!due(boot, other, true, "trial"));
    // no boot id: no
    CHECK(!due("", other, true, ""));
    CHECK(!due(" \n", "", true, ""));

    // the boot is remembered whenever it was asked, played or not, so a later restart in that boot is quiet
    CHECK(remember(boot, ""));
    CHECK(remember(boot, other));
    CHECK(!remember(boot, "00000000-0000-4000-8000-000000000001"));
    CHECK(!remember("", other));
    CHECK(trim(boot) == "00000000-0000-4000-8000-000000000001");

    if (failures)
        fprintf(stderr, "tst_bootfeedback: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_bootfeedback: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
