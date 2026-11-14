/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSONGOING_H
#define EOSONGOING_H

#include <string>

/*
 * What an ongoing activity is, as a notification says it (W2-launcher-status,
 * audit status-indicators-11). Plain C++, no Qt: the notification server uses
 * it to keep such a notification quiet (no banner, no vibration: stock shows
 * an ongoing activity on the face, it never alerts), the launcher's registry
 * (src/ongoingregistry.h) to turn it into an entry. tests/tst_ongoing.cpp
 * checks every rule.
 *
 * The hints (all optional but the first):
 *   x-eos-ongoing            true: this notification is an ongoing activity
 *                            (x-nemo-ongoing, the category x-eos.ongoing /
 *                            x-nemo.ongoing and x-asteroid-category=ongoing
 *                            say the same: compositor/lifecycle.js ongoingKey)
 *   x-eos-ongoing-category   call | navigation | transport | alarm | workout |
 *                            stopwatch | location_sharing | other
 *   x-eos-ongoing-icon       an animated icon (an image file, played while the
 *                            screen is on)
 *   x-eos-ongoing-static-icon  the static icon (an icon name or an image file),
 *                            the only one in the always-on screen
 *   x-eos-ongoing-status     the status text; "%t" stands for the timer part
 *   x-eos-ongoing-when       ms since the epoch of a count-up start or a
 *                            countdown end
 *   x-eos-ongoing-countdown  true: counts down to `when`, false: up from it
 *   x-eos-ongoing-paused     true: the timer part stands still at ...-frozen
 *   x-eos-ongoing-frozen     the milliseconds a paused timer shows
 *   x-eos-ongoing-duration   true: `when` is shown as "5 min" / "1 hr" /
 *                            "Now" (a Live Update's time), not as a timer
 *   x-eos-ongoing-app        the desktop file id the touch opens (else
 *                            x-eos-app, else the notification's app name)
 * Stock: androidx.wear.ongoing OngoingActivity (jpd.java:71-140), ranks
 * jri.java / ini.java:411-416.
 */
namespace EosOngoing {

inline bool isTrue(const std::string &v)
{
    return v == "true" || v == "1";
}

// The same rule as compositor/lifecycle.js ongoingKey
inline bool isOngoing(const std::string &eosHint, const std::string &nemoHint,
                      const std::string &category, const std::string &asteroidCategory)
{
    return isTrue(eosHint) || isTrue(nemoHint)
           || category == "x-eos.ongoing" || category == "x-nemo.ongoing"
           || asteroidCategory == "ongoing";
}

enum Rank { CallRank = 0, OtherRank = 1, TransportRank = 2 };

// A call first, media (transport) last, everything else between (jri.java)
inline int rankOf(const std::string &category)
{
    if (category == "call")
        return CallRank;
    if (category == "transport")
        return TransportRank;
    return OtherRank;
}

inline bool knownCategory(const std::string &c)
{
    return c == "call" || c == "navigation" || c == "transport" || c == "alarm"
           || c == "workout" || c == "stopwatch" || c == "location_sharing" || c == "other";
}

} // namespace EosOngoing

#endif // EOSONGOING_H
