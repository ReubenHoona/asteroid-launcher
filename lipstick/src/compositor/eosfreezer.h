/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSFREEZER_H
#define EOSFREEZER_H

#include <csignal>
#include <functional>
#include <set>
#include <unistd.h>

/*
 * Freezing the process of an application that left the screen, as stock
 * Wear OS freezes cached apps (config_defaultFreezerDebounceTimeout 5000,
 * audit buttons-navigation-04): the process gets SIGSTOP and uses no CPU,
 * sensors or timers until SIGCONT. A signal and not a cgroup.freeze: the
 * applications share the user session's cgroup with lipstick, and freezing
 * that cgroup would freeze the compositor too.
 *
 * Never freezes pid <= 1, the compositor itself or a pid it did not get
 * from a window. A stopped process cannot hear a quit or a SIGTERM, so the
 * compositor thaws before it closes a window (LipstickCompositor), and
 * thawAll() runs when the compositor ends. Plain C++, the signal sender is
 * injectable: tests/tst_freezer.cpp (fake sender and a real child).
 */
namespace EosFreeze {

class Table
{
public:
    typedef std::function<bool(long long pid, int sig)> Sender;

    Table() : mSend(&Table::kill_) {}
    explicit Table(Sender send) : mSend(send) {}

    bool freeze(long long pid)
    {
        if (!allowed(pid))
            return false;
        if (mFrozen.count(pid))
            return true;
        if (!mSend(pid, SIGSTOP))
            return false;
        mFrozen.insert(pid);
        return true;
    }

    // Always sends SIGCONT for a pid it froze, also when it thinks it was
    // thawed already (a SIGCONT to a running process does nothing)
    bool thaw(long long pid)
    {
        if (!allowed(pid))
            return false;
        const bool was = mFrozen.erase(pid) > 0;
        if (!was)
            return true;
        mSend(pid, SIGCONT);
        return true;
    }

    void thawAll()
    {
        std::set<long long> all;
        all.swap(mFrozen);
        for (long long pid : all)
            mSend(pid, SIGCONT);
    }

    bool isFrozen(long long pid) const { return mFrozen.count(pid) > 0; }
    size_t count() const { return mFrozen.size(); }

private:
    static bool allowed(long long pid)
    {
        return pid > 1 && pid != static_cast<long long>(getpid());
    }
    static bool kill_(long long pid, int sig)
    {
        return ::kill(static_cast<pid_t>(pid), sig) == 0;
    }

    Sender mSend;
    std::set<long long> mFrozen;
};

} // namespace EosFreeze

#endif // EOSFREEZER_H
