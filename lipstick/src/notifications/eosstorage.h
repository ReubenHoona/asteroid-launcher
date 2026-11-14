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

} // namespace EosStorage

#endif // EOSSTORAGE_H
