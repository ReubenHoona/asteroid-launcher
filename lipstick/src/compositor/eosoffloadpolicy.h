/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSOFFLOADPOLICY_H
#define EOSOFFLOADPOLICY_H

#include <cstdint>

/*
 * eos display offload: when the AP redraws the always-on screen and when the
 * layout the hub holds is dropped. Stock Wear OS hands the display to the hub
 * once per display off and sends a layout only when it changes (the watch
 * face, its options) or at its minutes_valid. No I/O; host tested by
 * tests/tst_offloadpolicy.cpp. Times are seconds since the epoch, 0 = none.
 */
namespace EosOffload {

// The layout's background (the date, AM/PM) is past its validity
inline bool expired(int64_t validUntil, int64_t now)
{
    return validUntil > 0 && validUntil <= now;
}

// An ambient update (the AP draws the face, builds and sends its layout):
// with the hub drawing a current layout the hub's picture is right, and an
// update would only take the display back, resend the same layout and hand
// it over again. Asked by compositor.qml's display-off timer (after it closed
// the application) and MainScreen's ambient minute timer (which then rebuilds
// an expired layout at the AP wakeup lipstick schedules for validUntil).
inline bool ambientUpdateWanted(bool offloaded, int64_t validUntil, int64_t now)
{
    return !offloaded || expired(validUntil, now);
}

// At a suspend (the AP stopped drawing): drop the layout the daemon holds
// instead of handing it over when it may be stale or wrong (one an earlier
// launcher left: unknown; past validUntil) or when the burn-in protection is
// due to move the face (moveAfter): the AP then draws and sends the next one
// at the ambient update that follows, the only handover of that display off.
inline bool dropAtSuspend(bool unknown, bool set, int64_t validUntil,
                          int64_t moveAfter, int64_t now)
{
    return unknown || (set && (expired(validUntil, now) ||
                               (moveAfter > 0 && moveAfter <= now)));
}

// The modes (Bedtime, Theater, Battery saver: ModesCore::blocksAlwaysOn in
// the launcher's modes engine) keep the always-on screen off. The hub's
// picture is that screen too: while a mode blocks it, a display off tells
// the daemon the display is not ready (a "resume": the panel stays the AP's,
// which has it blank) instead of ready, whatever an earlier launcher told
// it; and a mode starting while the hub draws releases the panel at once.
// The layout the daemon holds stays for when the last mode ends: the user's
// always-on setting then has the next display off hand over as before.
enum Handover { NoRequest, Suspend, Release };

inline Handover atDisplayOff(bool ambientEnabled, bool blocked)
{
    if (blocked)
        return Release;
    return ambientEnabled ? Suspend : NoRequest;
}

inline Handover atBlockChange(bool blocked)
{
    return blocked ? Release : NoRequest;
}

} // namespace EosOffload

#endif // EOSOFFLOADPOLICY_H
