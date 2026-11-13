/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The freezer of hidden applications (lipstick/src/compositor/eosfreezer.h):
 * the table with a fake signal sender (which pids, in what order, never
 * pid <= 1 or itself) and with a real child process (SIGSTOP stops it,
 * SIGCONT runs it again, state 'T' in /proc). Plain C++:
 * g++ -std=c++17 -I../lipstick/src/compositor tst_freezer.cpp
 */

#include "eosfreezer.h"

#include <cstdio>
#include <fstream>
#include <string>
#include <vector>
#include <sys/wait.h>
#include <unistd.h>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static char stateOf(pid_t pid)
{
    std::ifstream f("/proc/" + std::to_string(pid) + "/stat");
    std::string line;
    std::getline(f, line);
    const size_t rp = line.rfind(')');
    return rp == std::string::npos || rp + 2 >= line.size() ? '?' : line[rp + 2];
}

int main()
{
    // fake sender
    std::vector<std::pair<long long, int>> sent;
    bool ok = true;
    EosFreeze::Table t([&](long long pid, int sig) { sent.push_back({ pid, sig }); return ok; });

    CHECK(t.freeze(1234));
    CHECK(sent.size() == 1 && sent[0].first == 1234 && sent[0].second == SIGSTOP);
    CHECK(t.isFrozen(1234) && t.count() == 1);
    // frozen twice: no second signal
    CHECK(t.freeze(1234));
    CHECK(sent.size() == 1);
    // thaw: SIGCONT once, then nothing
    CHECK(t.thaw(1234));
    CHECK(sent.size() == 2 && sent[1].second == SIGCONT);
    CHECK(!t.isFrozen(1234));
    CHECK(t.thaw(1234));
    CHECK(sent.size() == 2);

    // never pid 0, 1, negative or itself
    sent.clear();
    CHECK(!t.freeze(0)); CHECK(!t.freeze(1)); CHECK(!t.freeze(-5));
    CHECK(!t.freeze(static_cast<long long>(getpid())));
    CHECK(sent.empty() && t.count() == 0);

    // a failed signal does not leave it listed as frozen
    ok = false;
    CHECK(!t.freeze(99));
    CHECK(!t.isFrozen(99));
    ok = true;

    // thawAll: every frozen pid gets SIGCONT, the table is empty after
    t.freeze(10); t.freeze(11); t.freeze(12);
    sent.clear();
    t.thawAll();
    CHECK(sent.size() == 3);
    for (auto &s : sent) CHECK(s.second == SIGCONT);
    CHECK(t.count() == 0);

    // a real process
    const pid_t child = fork();
    if (child == 0) {
        for (;;) sleep(1);
    }
    usleep(100000);
    EosFreeze::Table real;
    CHECK(stateOf(child) == 'S');
    CHECK(real.freeze(child));
    usleep(100000);
    CHECK(stateOf(child) == 'T');
    CHECK(real.isFrozen(child));
    CHECK(real.thaw(child));
    usleep(100000);
    CHECK(stateOf(child) != 'T');
    // frozen at the end of the compositor: thawAll runs it again
    CHECK(real.freeze(child));
    usleep(50000);
    CHECK(stateOf(child) == 'T');
    real.thawAll();
    usleep(100000);
    CHECK(stateOf(child) != 'T');
    // a process that is gone: freezing fails, no crash
    kill(child, SIGKILL);
    waitpid(child, nullptr, 0);
    CHECK(!real.freeze(child));

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
