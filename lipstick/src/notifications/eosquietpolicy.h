/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSQUIETPOLICY_H
#define EOSQUIETPOLICY_H

#include <string>

/*
 * What the notification server does while Bedtime or Theater mode is on
 * (the launcher's modes engine, ModesCore::silencesNotifications, set on
 * the NotificationManager by main.cpp): a notification plays no ngfd event
 * (no vibration, no sound) and shows no banner (which would turn the screen
 * on): it joins the stream quietly, as stock's priority interruption filter
 * lets nothing but alarms (and calls from starred contacts, which this
 * watch cannot tell) alert in Bedtime, and Theater mutes alerting.
 * asteroid-btsyncd posts the phone's notifications quietly then already;
 * this holds every poster to it (eos-update, lipstick's battery warnings,
 * the launcher itself). Plain C++: tests/tst_quietpolicy.cpp.
 *
 * Alarm-class events still play and show: the watch's own alarms and
 * timers ("alarm"), an alarm going off on the phone ("eos_phone_alarm"),
 * and the find-my-watch ring ("ringtone": the user asked for it).
 */
namespace EosQuiet {

inline bool alertsWhileQuiet(const std::string &event)
{
    return event == "alarm" || event == "alarm_sound" || event == "alarm_vibra"
        || event == "eos_phone_alarm" || event == "ringtone";
}

// The events of a notification's x-nemo-feedback hint (a comma-separated
// list) that play: all of them when not quiet
inline std::string feedback(bool quiet, const std::string &hint)
{
    if (!quiet)
        return hint;
    std::string out;
    size_t start = 0;
    while (start <= hint.size()) {
        size_t end = hint.find(',', start);
        if (end == std::string::npos)
            end = hint.size();
        const std::string item = hint.substr(start, end - start);
        if (!item.empty() && alertsWhileQuiet(item)) {
            if (!out.empty())
                out += ',';
            out += item;
        }
        start = end + 1;
    }
    return out;
}

/*
 * What plays during a call (LipstickSettings::callState: 0 none, 1 ringing,
 * 2 in progress), as stock (NotificationAttentionHelper.java:1168-1171,
 * 778-800, 843-846: in a call a notification does not vibrate; ringing is
 * not in-call) and calls win over alarms (DeskClock hob.java:68-96):
 *  - in progress: no event but an alarm's, a ringing call's (a second call)
 *    and the find-my-watch ring;
 *  - ringing: a phone alarm's vibration stops (the alarm view is under the
 *    call view), every other event plays.
 * Audit interruptions-07, interruptions-15.
 */
inline bool playsInCall(int callState, const std::string &event)
{
    if (callState == 2)
        return alertsWhileQuiet(event) || event == "eos_phone_ringing";
    if (callState == 1)
        return event != "eos_phone_alarm";
    return true;
}

// The events of an x-nemo-feedback hint that play in this call state
inline std::string feedbackInCall(int callState, const std::string &hint)
{
    if (callState == 0)
        return hint;
    std::string out;
    size_t start = 0;
    while (start <= hint.size()) {
        size_t end = hint.find(',', start);
        if (end == std::string::npos)
            end = hint.size();
        const std::string item = hint.substr(start, end - start);
        if (!item.empty() && playsInCall(callState, item)) {
            if (!out.empty())
                out += ',';
            out += item;
        }
        start = end + 1;
    }
    return out;
}

/*
 * What an alarm may play in the modes that are on (Settings > <mode> >
 * Customize > Alarms and Timers, Sound and Vibrate; stock FocusModeConstants
 * allowAlarms(sound, vibrate), Theater: no sound): mask 1 sound, 2
 * vibration, 3 both (nothing changes). The watch's own alarm "alarm" has
 * both (the presenter chooses the event itself from the engine's
 * alarm-feedback; here it is held to the mask for any poster): sound only
 * "alarm_sound", vibration only "alarm_vibra", neither none; the phone's
 * alarm "eos_phone_alarm" is a vibration. Audit modes-dnd-05.
 */
inline std::string alarmFeedback(int mask, const std::string &hint)
{
    if ((mask & 3) == 3)
        return hint;
    const bool sound = mask & 1;
    const bool vibra = mask & 2;
    std::string out;
    size_t start = 0;
    while (start <= hint.size()) {
        size_t end = hint.find(',', start);
        if (end == std::string::npos)
            end = hint.size();
        std::string item = hint.substr(start, end - start);
        if (item == "alarm")
            item = sound ? "alarm_sound" : vibra ? "alarm_vibra" : "";
        else if (item == "alarm_sound" && !sound)
            item = "";
        else if ((item == "alarm_vibra" || item == "eos_phone_alarm") && !vibra)
            item = "";
        if (!item.empty()) {
            if (!out.empty())
                out += ',';
            out += item;
        }
        start = end + 1;
    }
    return out;
}

/*
 * Settings > Vibration > 'Silence when off wrist' (wake-sleep-display-18):
 * "Notifications won't sound or vibrate when watch is off wrist or charging".
 * One switch for both (stock SilenceWhenNotWornSwitchPreference; the hub's
 * off-body sensor, the charger). Feedback only: the cards and banners stay,
 * unlike Bedtime and Theater (quiet). Alarms still sound, as in the modes.
 */
inline bool silenced(bool setting, bool offBody, bool charging)
{
    return setting && (offBody || charging);
}

// The key's value when it was never set: the old 'quiet on the charger' value
// carries over (default on, as asteroid-btsyncd and Settings had it), so what
// the user has today is kept
inline bool silenceDefault(bool oldKeySet, bool oldKeyValue)
{
    return oldKeySet ? oldKeyValue : true;
}

// Whether the banner shows (and the screen may turn on for it)
inline bool previewAllowed(bool quiet, const std::string &hint)
{
    return !quiet || !feedback(true, hint).empty();
}

} // namespace EosQuiet

#endif // EOSQUIETPOLICY_H
