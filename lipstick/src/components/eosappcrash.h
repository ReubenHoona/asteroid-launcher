/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSAPPCRASH_H
#define EOSAPPCRASH_H

#include <csignal>
#include <map>
#include <string>

/*
 * When an app that died is a crash, and when a crash earns the "keeps
 * stopping" dialog (system-dialogs-misc-01, -02), as stock's ActivityManager:
 *
 *  - AppErrors.java:691-717 counts the crashes of each process;
 *  - a crash within MIN_CRASH_INTERVAL (ActivityManagerConstants.java:1111,
 *    120000 ms) of the process' previous one is a repeating crash: the first
 *    crash shows nothing, the app just closes (AppErrors.java:955-985);
 *  - the dialog is throttled to one per process per 120000 ms.
 *
 * An app that quits by itself (exit code, even non-zero), is closed by the
 * system (SIGTERM, SIGHUP, SIGINT, the launcher's own kill of an unresponsive
 * app) or is killed for memory (SIGKILL) is not a crash: only the signals a
 * program dies of on its own bug are (SIGSEGV, SIGABRT, SIGBUS, SIGILL,
 * SIGFPE, SIGSYS, SIGTRAP). Plain C++ (tests/tst_appcrash.cpp); the time is
 * a number of milliseconds the caller reads from CLOCK_BOOTTIME.
 */
namespace EosCrash {

const long long MinCrashIntervalMs = 120000;
const long long DialogThrottleMs = 120000;

inline bool isCrashSignal(int sig)
{
    switch (sig) {
    case SIGSEGV:
    case SIGABRT:
    case SIGBUS:
    case SIGILL:
    case SIGFPE:
    case SIGSYS:
    case SIGTRAP:
        return true;
    default:
        return false;
    }
}

/* QProcess::finished(code, status): crashExit is status == CrashExit, in
 * which case `code` is the number of the signal that ended the process.
 * `deliberate`: the launcher ended it itself. */
inline bool isCrash(bool crashExit, int code, bool deliberate)
{
    if (deliberate || !crashExit)
        return false;
    return isCrashSignal(code);
}

struct Verdict {
    bool repeating = false;   // the previous crash of this program was less than 120 s ago
    bool showDialog = false;  // and no dialog was shown for it in the last 120 s
};

class CrashTracker
{
public:
    /* A crash of `key` (a desktop id or program name) at `nowMs`. */
    Verdict record(const std::string &key, long long nowMs)
    {
        prune(nowMs);
        Verdict v;
        std::map<std::string, long long>::iterator last = mLast.find(key);
        v.repeating = last != mLast.end() && nowMs - last->second < MinCrashIntervalMs;
        mLast[key] = nowMs;
        if (v.repeating) {
            std::map<std::string, long long>::iterator shown = mDialog.find(key);
            if (shown == mDialog.end() || nowMs - shown->second >= DialogThrottleMs) {
                v.showDialog = true;
                mDialog[key] = nowMs;
            }
        }
        return v;
    }

    size_t tracked() const { return mLast.size() + mDialog.size(); }

private:
    // what is older than both windows cannot matter again
    void prune(long long nowMs)
    {
        const long long keep = MinCrashIntervalMs > DialogThrottleMs ? MinCrashIntervalMs : DialogThrottleMs;
        for (std::map<std::string, long long>::iterator i = mLast.begin(); i != mLast.end();) {
            if (nowMs - i->second >= keep)
                i = mLast.erase(i);
            else
                ++i;
        }
        for (std::map<std::string, long long>::iterator i = mDialog.begin(); i != mDialog.end();) {
            if (nowMs - i->second >= keep)
                i = mDialog.erase(i);
            else
                ++i;
        }
    }

    std::map<std::string, long long> mLast;
    std::map<std::string, long long> mDialog;
};

} // namespace EosCrash

#endif // EOSAPPCRASH_H
