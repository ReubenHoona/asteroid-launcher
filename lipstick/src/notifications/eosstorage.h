/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSSTORAGE_H
#define EOSSTORAGE_H

#include <stdint.h>

/*
 * When the storage is low (connectivity-system-ux-20), as stock's
 * DeviceStorageMonitorService (SVC/storage/DeviceStorageMonitorService.java:
 * 279-360): the data partition is low when its free space is under the
 * smaller of 5 % of its size (AOSP's default storage low percentage) and
 * 250 MiB (the default storage low maximum). Stock also frees app caches
 * below 1.5 times that; here nothing is trimmed in response (the user's rule:
 * logs are never limited). Plain C++ (tests/tst_storage.cpp).
 */
namespace EosStorage {

const uint64_t MaxLowBytes = 250ull * 1024 * 1024;

// min(5 % of the partition, 250 MiB)
inline uint64_t lowBytes(uint64_t total)
{
    const uint64_t five = total / 20;
    return five < MaxLowBytes ? five : MaxLowBytes;
}

// freeBytes: what an app may still use (statvfs f_bavail)
inline bool isLow(int64_t freeBytes, int64_t totalBytes)
{
    if (totalBytes <= 0 || freeBytes < 0)
        return false;
    return uint64_t(freeBytes) < lowBytes(uint64_t(totalBytes));
}

/*
 * When the launcher looks (C-17). Stock looks once a minute (its handler's
 * 60 s message); here a look costs nothing while the watch sleeps: it is
 * made on events the watch has anyway, never on a timer of its own:
 *   Start      the launcher starts (the boot, a launcher restart)
 *   DisplayOn  the screen comes on, when the last look is an hour old or
 *              more (CLOCK_BOOTTIME seconds: the time asleep counts)
 *   Update     eos-update's state changes (a download staged, an install)
 *   Dsme       dsme's diskmonitor signals a change (disk_space_state_ind)
 * The notification follows stock's levels: it is posted when the partition
 * becomes low and taken down when it is not low any more
 * (DeviceStorageMonitorService: notifyAsUser on entering LEVEL_LOW,
 * cancelAsUser on leaving it).
 */
enum Reason { Start, DisplayOn, Update, Dsme };
const int64_t DisplayLookSeconds = 3600;

enum Action { None, Show, Clear };

struct Monitor {
    // the notification is up
    bool shown = false;
    // CLOCK_BOOTTIME seconds of the last look, -1 none yet
    int64_t last = -1;

    bool due(Reason reason, int64_t now) const
    {
        return reason != DisplayOn || last < 0 || now - last >= DisplayLookSeconds;
    }

    // A look for `reason` at boot time `now` (seconds): stat(free, total) gives the data partition (false: not
    // known, nothing changes). What to do with the notification.
    template <typename Stat>
    Action look(Reason reason, int64_t now, Stat stat)
    {
        if (!due(reason, now))
            return None;
        last = now;
        int64_t freeBytes = -1, totalBytes = -1;
        if (!stat(freeBytes, totalBytes) || totalBytes <= 0 || freeBytes < 0)
            return None;
        const bool low = isLow(freeBytes, totalBytes);
        if (low && !shown) {
            shown = true;
            return Show;
        }
        if (!low && shown) {
            shown = false;
            return Clear;
        }
        return None;
    }
};

} // namespace EosStorage

#endif // EOSSTORAGE_H
