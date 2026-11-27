/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSCATEGORY_H
#define EOSCATEGORY_H

#include <string>
#include <vector>

#include "eosquietpolicy.h"

/*
 * What a notification's x-asteroid-category asks of the notification server beyond its feedback hint (M4 WO-12).
 * asteroid-sensorlogd's heart rate alerts ("health-alert": daemon/healthMonitor.cpp postAlert, "High heart rate" /
 * "Low heart rate") are stock's HrAlertService notification (Fitbit 4.01.1 on CP3A, HrAlertService.java:60-110):
 *  - category "alarm" (setCategory("alarm"): Notification.CATEGORY_ALARM, which Android's interruption filter lets
 *    through Do Not Disturb as it lets alarms): its feedback plays and it shows in Bedtime, Theater and Do Not
 *    Disturb, as the alarm class of eosquietpolicy.h;
 *  - one notification id for every alert (notify(87654321, ...)): one card, which a new alert replaces (and which
 *    alerts again, as a new post of stock's id does);
 *  - the HeartRateAlertInfoActivity started with it (acit.j: a full screen intent): the launcher's heart rate
 *    alert screen (src/qml/system/HrAlert.qml) instead of a banner.
 * asteroid-sensorlogd's celebrations ("celebration": the main goal reached, a reminder to move, its hour's goal and
 * every hour met; R5 E-05, E-06) are stock's CelebrationActivity, started directly (trj.java:115-185): full screen
 * (src/qml/system/GoalCelebration.qml), no banner; not an alarm (stock shows none in Do Not Disturb, Theater or
 * Bedtime: zit.a) and not one id (each is a transient post that leaves no card).
 * Plain C++: tests/tst_eoscategory.cpp.
 */
namespace EosCategory {

// plays and shows as the alarm class in Bedtime, Theater and Do Not Disturb (stock's category "alarm")
inline bool alarm(const std::string &category)
{
    return category == "health-alert";
}

/*
 * The events of a post's x-nemo-feedback hint that play in Bedtime or Theater, off the wrist or on the charger
 * (quiet: EosQuiet::feedback) and in Do Not Disturb (dnd: EosQuiet::feedbackDnd): an alarm category post's all of
 * them, as an alarm's; any other post's the alarm-class ones. A call and the modes' alarm switches still hold
 * them (EosQuiet::feedbackInCall, alarmFeedback, applied after this).
 */
inline std::string modeFeedback(const std::string &category, bool quiet, bool dnd, const std::string &hint)
{
    if (alarm(category))
        return hint;
    return EosQuiet::feedbackDnd(dnd, EosQuiet::feedback(quiet, hint));
}

// one card for the app's posts of the category (stock's one notification id)
inline bool oneId(const std::string &category)
{
    return category == "health-alert";
}

// shown full screen by the launcher, never as a banner (stock's full screen activity)
inline bool fullScreen(const std::string &category)
{
    return category == "health-alert" || category == "celebration";
}

// a card in the notification server
struct Card {
    unsigned id;
    std::string app;
    std::string category;
};

/*
 * The cards a post of a one-id category takes the place of: the app's cards of the category (the one the post names
 * and any other: the poster may have lost the id when it restarted). They go and the post is a new card, so it
 * alerts as a new one: lipstick plays the feedback and shows the alert only for a new id, and it refuses a post that
 * names a card that is gone (the user cleared it), which would leave a second alert unseen. Any other category: none.
 */
inline std::vector<unsigned> replacedCards(const std::string &app, const std::string &category, const std::vector<Card> &cards)
{
    std::vector<unsigned> out;
    if (!oneId(category))
        return out;
    for (const Card &c : cards)
        if (c.app == app && c.category == category)
            out.push_back(c.id);
    return out;
}

} // namespace EosCategory

#endif // EOSCATEGORY_H
