/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSDISABLEDAPPS_H
#define EOSDISABLEDAPPS_H

#include "eosongoing.h"
#include "eosquietpolicy.h"

#include <string>
#include <vector>

/*
 * Settings > Apps & notifications > Notifications > App notifications, the
 * switch of a watch app or system service (CR-18, FP-L3): the dconf list
 * /org/asteroidos/notifications/disabled-apps holds the apps whose
 * notifications are off. The notification server drops a post of such an app
 * before it is stored: no card, no banner, no sound or vibration, no wake of
 * the screen. Plain C++: tests/tst_disabledapps.cpp.
 *
 * The list holds the desktop id without the suffix ("asteroid-timer"), or the
 * id of a system service ("battery", "bluetooth", "eos-update"). A post names
 * its app by the first of these hints that is not empty (CR-18 order):
 *   x-eos-app             what every poster of this watch sets
 *   x-nemo-origin-package the package of the sender (lipstick's own hint)
 *   category              a lipstick category, last resort
 * A ".desktop" suffix on either side is ignored.
 *
 * Never dropped, whatever the list says:
 *  - an alarm: category x-nemo.alarm, or an x-nemo-feedback event of the alarm
 *    class (eosquietpolicy.h alertsWhileQuiet: the alarm, a phone alarm, the
 *    find-my-watch alert), as stock's alarm channel cannot be turned off;
 *  - an ongoing activity (eosongoing.h): it is no card, it is the face chip
 *    and what keeps its app alive in the background.
 */
namespace EosDisabledApps {

// "asteroid-timer.desktop" -> "asteroid-timer", blanks trimmed
inline std::string normalize(const std::string &id)
{
    size_t b = id.find_first_not_of(" \t");
    if (b == std::string::npos)
        return std::string();
    size_t e = id.find_last_not_of(" \t");
    std::string out = id.substr(b, e - b + 1);
    static const std::string suffix = ".desktop";
    if (out.size() > suffix.size() && out.compare(out.size() - suffix.size(), suffix.size(), suffix) == 0)
        out.erase(out.size() - suffix.size());
    return out;
}

// The app a notification belongs to: the first of the three hints that is not empty ("" when none is)
inline std::string matchKey(const std::string &eosApp, const std::string &originPackage, const std::string &category)
{
    for (const std::string *hint : { &eosApp, &originPackage, &category }) {
        const std::string key = normalize(*hint);
        if (!key.empty())
            return key;
    }
    return std::string();
}

// Whether an x-nemo-feedback hint (comma separated ngfd events) holds an event of the alarm class
inline bool feedbackIsAlarm(const std::string &feedback)
{
    size_t start = 0;
    while (start <= feedback.size()) {
        size_t end = feedback.find(',', start);
        if (end == std::string::npos)
            end = feedback.size();
        if (EosQuiet::alertsWhileQuiet(feedback.substr(start, end - start)))
            return true;
        start = end + 1;
    }
    return false;
}

// An alarm (never dropped)
inline bool isAlarm(const std::string &category, const std::string &feedback)
{
    return category == "x-nemo.alarm" || feedbackIsAlarm(feedback);
}

struct Post {
    std::string eosApp;           // hint x-eos-app
    std::string originPackage;    // hint x-nemo-origin-package
    std::string category;         // hint category
    std::string feedback;         // hint x-nemo-feedback
    std::string eosOngoing;       // hint x-eos-ongoing
    std::string nemoOngoing;      // hint x-nemo-ongoing
    std::string asteroidCategory; // hint x-asteroid-category
};

// Whether the notification server drops this post
inline bool dropped(const std::vector<std::string> &disabled, const Post &post)
{
    if (disabled.empty())
        return false;
    if (isAlarm(post.category, post.feedback))
        return false;
    if (EosOngoing::isOngoing(post.eosOngoing, post.nemoOngoing, post.category, post.asteroidCategory))
        return false;
    const std::string key = matchKey(post.eosApp, post.originPackage, post.category);
    if (key.empty())
        return false;
    for (const std::string &entry : disabled) {
        if (normalize(entry) == key)
            return true;
    }
    return false;
}

} // namespace EosDisabledApps

#endif // EOSDISABLEDAPPS_H
