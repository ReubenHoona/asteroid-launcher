/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The notification server in Bedtime and Theater mode
 * (lipstick/src/notifications/eosquietpolicy.h): no ngfd event (vibration,
 * sound) and no banner for any poster's notification but an alarm's; the
 * feedback hints the watch's posters use (asteroid-btsyncd's
 * PostPlan::feedbackEvent, the ngfd events.d of the image). Plain C++:
 * cmake -DLAUNCHER_TESTS=ON, or g++ -std=c++17 -I../lipstick/src/notifications.
 */

#include "eosquietpolicy.h"

#include <cstdio>

using namespace EosQuiet;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main()
{
    // not quiet: every event plays, every banner shows
    for (const char *e : { "notif_strong", "notif_normal", "notif_silent", "eos_phone_ringing", "eos_phone_alarm",
                           "alarm", "ringtone", "find_my_watch", "general_warning", "" }) {
        CHECK(feedback(false, e) == e);
        CHECK(previewAllowed(false, e));
    }

    // quiet (Bedtime, Theater): a phone notification (btsyncd posts them notif_silent
    // already), a call ringing on the phone (its vibration, or with the ringtone), a local
    // notification with the stock-style vibration or none (eos-update has no feedback hint),
    // lipstick's battery warnings
    for (const char *e : { "notif_strong", "notif_normal", "notif_silent", "eos_phone_ringing", "ringtone",
                           "general_warning", "charging_started", "eos_charging_sound", "accessory_connected", "" }) {
        CHECK(feedback(true, e).empty());
        CHECK(!previewAllowed(true, e));
    }
    // ...but an alarm: the watch's own (the alarm presenter), one going off on the
    // phone, and the find-my-watch alert the user asked for
    for (const char *e : { "alarm", "eos_phone_alarm", "find_my_watch" }) {
        CHECK(feedback(true, e) == e);
        CHECK(previewAllowed(true, e));
    }
    // a list of events: only the alarm-class ones stay, in order
    CHECK(feedback(true, "notif_strong,alarm") == "alarm");
    CHECK(feedback(true, "alarm,notif_strong,find_my_watch") == "alarm,find_my_watch");
    CHECK(feedback(true, "alarm,ringtone,eos_phone_ringing") == "alarm");
    CHECK(feedback(true, ",notif_strong,,") == "");
    CHECK(previewAllowed(true, "notif_normal,eos_phone_alarm"));
    CHECK(!previewAllowed(true, "notif_normal,notif_strong"));
    // event names are exact: no prefix passes
    CHECK(feedback(true, "alarm2").empty());
    CHECK(feedback(true, "ringtone_x").empty());
    CHECK(feedback(true, "find_my_watch_x").empty());
    CHECK(!alertsWhileQuiet("Alarm"));
    // a call's ring: the vibration alone or with the ringtone (no longer the find-my-watch ring)
    CHECK(isCallRing("eos_phone_ringing") && isCallRing("ringtone"));
    CHECK(!isCallRing("find_my_watch") && !isCallRing("alarm") && !isCallRing("ringtone_x") && !isCallRing(""));
    CHECK(!alertsWhileQuiet("ringtone") && !alertsWhileQuiet("eos_phone_ringing"));

    // in a call (LipstickSettings::callState: 0 none, 1 ringing, 2 in progress)
    // none: everything plays
    for (const char *e : { "notif_strong", "notif_normal", "eos_phone_alarm", "alarm", "" })
        CHECK(feedbackInCall(0, e) == e);
    // in progress: no notification event, but an alarm's, a second call's ring and the find-my-watch ring
    for (const char *e : { "notif_strong", "notif_normal", "notif_silent", "general_warning", "charging_started" })
        CHECK(feedbackInCall(2, e).empty());
    for (const char *e : { "alarm", "eos_phone_alarm", "find_my_watch", "ringtone", "eos_phone_ringing" })
        CHECK(feedbackInCall(2, e) == e);
    CHECK(feedbackInCall(2, "notif_strong,alarm") == "alarm");
    CHECK(feedbackInCall(2, "notif_normal,eos_phone_ringing,notif_strong") == "eos_phone_ringing");
    CHECK(feedbackInCall(2, "notif_normal,ringtone") == "ringtone");
    CHECK(feedbackInCall(2, "notif_strong,find_my_watch") == "find_my_watch");
    // ringing: a phone alarm's vibration stops under the call, the rest plays
    CHECK(feedbackInCall(1, "eos_phone_alarm").empty());
    CHECK(feedbackInCall(1, "notif_strong") == "notif_strong");
    CHECK(feedbackInCall(1, "eos_phone_alarm,notif_strong") == "notif_strong");
    CHECK(feedbackInCall(1, "alarm") == "alarm");
    CHECK(feedbackInCall(1, "eos_phone_ringing") == "eos_phone_ringing");
    CHECK(feedbackInCall(1, "ringtone") == "ringtone");
    CHECK(feedbackInCall(1, "find_my_watch") == "find_my_watch");
    // it composes with the quiet policy: quiet and in a call
    CHECK(feedbackInCall(2, feedback(true, "notif_strong,alarm")) == "alarm");
    CHECK(feedbackInCall(1, feedback(true, "eos_phone_alarm")).empty());
    CHECK(playsInCall(2, "alarm") && !playsInCall(2, "notif_normal") && playsInCall(0, "x"));

    // alarms in the modes (Customize > Alarms and Timers; Theater: vibration only)
    CHECK(alarmFeedback(3, "alarm") == "alarm" && alarmFeedback(3, "eos_phone_alarm") == "eos_phone_alarm");
    CHECK(alarmFeedback(3, "notif_strong,alarm") == "notif_strong,alarm");
    // vibration only (mask 2): the watch's alarm is its vibration, the phone's stays
    CHECK(alarmFeedback(2, "alarm") == "alarm_vibra");
    CHECK(alarmFeedback(2, "eos_phone_alarm") == "eos_phone_alarm");
    CHECK(alarmFeedback(2, "alarm_sound").empty() && alarmFeedback(2, "alarm_vibra") == "alarm_vibra");
    // sound only (mask 1): no vibration of the phone's alarm
    CHECK(alarmFeedback(1, "alarm") == "alarm_sound");
    CHECK(alarmFeedback(1, "eos_phone_alarm").empty() && alarmFeedback(1, "alarm_sound") == "alarm_sound");
    // neither: nothing plays, other events untouched
    CHECK(alarmFeedback(0, "alarm").empty() && alarmFeedback(0, "eos_phone_alarm").empty());
    CHECK(alarmFeedback(2, "notif_strong,alarm,ringtone") == "notif_strong,alarm_vibra,ringtone");
    CHECK(alarmFeedback(0, "ringtone") == "ringtone" && alarmFeedback(0, "notif_normal") == "notif_normal");
    // the alarm switches of the modes do not hold the find-my-watch alert (loud whatever, find_my_watch.ini)
    CHECK(alarmFeedback(0, "find_my_watch") == "find_my_watch" && alarmFeedback(2, "find_my_watch") == "find_my_watch");
    // and the two policies together: Theater (quiet, vibration only) keeps an alarm as its vibration
    CHECK(alarmFeedback(2, feedback(true, "notif_strong,alarm")) == "alarm_vibra");
    CHECK(alarmFeedback(2, feedback(true, "alarm_vibra")) == "alarm_vibra");
    CHECK(alertsWhileQuiet("alarm_sound") && alertsWhileQuiet("alarm_vibra"));
    CHECK(previewAllowed(true, "alarm_vibra"));

    // 'Silence when off wrist' (wake-sleep-display-18): one switch for off the wrist and charging
    CHECK(!silenced(false, true, true));                  // the row off: never
    CHECK(!silenced(true, false, false));                 // worn, not charging: sounds
    CHECK(silenced(true, true, false));                   // off the wrist
    CHECK(silenced(true, false, true));                   // charging
    CHECK(silenced(true, true, true));
    // it keeps the banner (feedback only): quiet is what suppresses the preview
    CHECK(previewAllowed(false, "notif_strong"));
    CHECK(feedback(silenced(true, true, false), "notif_strong,alarm") == "alarm");
    CHECK(feedback(silenced(true, false, false), "notif_strong,alarm") == "notif_strong,alarm");
    // off the wrist the find-my-watch alert still rings (what it is for); a call's ring is held as before
    CHECK(feedback(silenced(true, true, false), "find_my_watch") == "find_my_watch");
    CHECK(feedback(silenced(true, true, false), "ringtone").empty());
    CHECK(feedback(silenced(true, true, false), "eos_phone_ringing").empty());
    // the old 'quiet on the charger' value carries over; never set (default on): on
    CHECK(silenceDefault(true, true) && !silenceDefault(true, false) && silenceDefault(false, false));

    // Do Not Disturb (heads-up-alerts-17): the watch's own posters hold to it too
    for (const char *e : { "notif_strong", "notif_normal", "notif_silent", "general_warning", "charging_started",
                           "accessory_connected", "battery_low", "" }) {
        CHECK(feedbackDnd(true, e).empty());
        CHECK(!previewAllowedDnd(true, e));
        CHECK(feedbackDnd(false, e) == e);
        CHECK(previewAllowedDnd(false, e));
    }
    // ...but an alarm, a call ringing, and the critical battery warning
    for (const char *e : { "alarm", "alarm_sound", "alarm_vibra", "eos_phone_alarm", "find_my_watch", "ringtone",
                           "eos_phone_ringing", "battery_empty" }) {
        CHECK(feedbackDnd(true, e) == e);
        CHECK(previewAllowedDnd(true, e));
    }
    CHECK(feedbackDnd(true, "notif_strong,battery_empty,alarm") == "battery_empty,alarm");
    CHECK(!previewAllowedDnd(true, "notif_strong,battery_low"));
    CHECK(previewAllowedDnd(true, "notif_strong,eos_phone_ringing"));
    CHECK(previewAllowedDnd(true, "notif_strong,ringtone"));
    CHECK(feedbackDnd(true, "notif_normal,ringtone,notif_strong") == "ringtone");
    // Bedtime and Theater stay stricter than DND: no call, no battery warning
    CHECK(feedback(true, "eos_phone_ringing").empty());
    CHECK(feedback(true, "ringtone").empty());
    CHECK(feedback(true, "battery_empty").empty());
    // both on: what is left is what both allow
    CHECK(feedbackDnd(true, feedback(true, "eos_phone_ringing,alarm")) == "alarm");
    CHECK(feedbackDnd(true, feedback(true, "ringtone,find_my_watch")) == "find_my_watch");

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
