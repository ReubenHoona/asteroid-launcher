/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSALERTPOLICY_H
#define EOSALERTPOLICY_H

#include <algorithm>
#include <string>
#include <vector>
#include <time.h>

/*
 * When and how a new notification alerts (W2-launcher-heads-up; audit
 * heads-up-alerts-03, -05, -07, -09, -10, -15). Plain C++, no Qt: the
 * NotificationPreviewPresenter feeds it the clock and the state it reads,
 * tests/tst_alertpolicy.cpp checks every number.
 *
 * Stock (CP3A SysUI, kfl.java:117-141, kfk.java:43-83, okj.java, icp.java:29,
 * kgf.java:52-60, juh.java:403-478):
 *  - a notification vibrates on arrival, not when its card is up; at most one
 *    notification vibration per 2000 ms;
 *  - 'Show new notifications' = On wrist raise (default): with the screen off
 *    or ambient the watch vibrates, does not wake, and keeps the alert pending
 *    10000 ms; if the screen turns on in that window the alert shows with no
 *    second vibration (the newest only; the others stay in the stream);
 *    pending queue 5, the oldest dropped;
 *  - 'Immediately': a display-on request, the vibration 500 ms after it, the
 *    alert shown after 750 ms; the user's screen timeout governs from there;
 *  - an alert on the face is the full screen glanceable, anywhere else the
 *    icon bubble (3000 ms), which Battery Saver turns off;
 *  - no overlay (vibration only) over the keyboard, an immersive app or the
 *    open notification list;
 *  - the glanceable or the full view that the display leaving ON hides comes
 *    back if the display is ON again within 10000 ms (auto-resume).
 *
 * Nothing here is a timer: the windows are compared with timestamps when the
 * display turns on. The clock is CLOCK_BOOTTIME (bootTimeMs()): it keeps
 * counting in suspend, so an alert that arrived an hour ago is not "pending".
 */
namespace EosAlert {

constexpr long long PendingMax = 5;
constexpr long long PendingWindowMs = 10000;
constexpr long long ResumeWindowMs = 10000;
constexpr long long VibrationGapMs = 2000;
// Immediately: wake request, vibration, show
constexpr long long ImmediateVibrateMs = 500;
constexpr long long ImmediateShowMs = 750;
// the glanceable turns into the full view after this (On wrist raise / Immediately)
constexpr long long GlanceHoldMs = 1000;
constexpr long long GlanceHoldImmediateMs = 1500;
// the bubble in an app
constexpr long long BubbleStayMs = 3000;

// What the presenter hands to the overlay
enum Kind { NoKind = 0, Glanceable = 1, Bubble = 2 };

inline long long bootTimeMs()
{
    struct timespec ts;
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return static_cast<long long>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

/* What a new alert does, given the display and the settings:
 *  ShowNow       the display is on: queue it for the overlay
 *  VibrateOnly   the display is on but a keyboard, an immersive app or the
 *                open notification list is in front: it goes to the stream
 *  KeepPending   display off or ambient, On wrist raise: vibrate, keep it
 *                10 s, never wake
 *  WakeThenShow  display off or ambient, Immediately: wake, vibrate after
 *                500 ms, show after 750 ms
 * With the display off the surface is judged when the alert is shown (the
 * list may have closed by then), not on arrival. */
enum Arrival { ShowNow, VibrateOnly, KeepPending, WakeThenShow };

inline Arrival onArrival(bool screenOn, bool showImmediately, bool surfaceBusy)
{
    if (!screenOn)
        return showImmediately ? WakeThenShow : KeepPending;
    return surfaceBusy ? VibrateOnly : ShowNow;
}

/* The overlay for an alert: the glanceable when the face is the current
 * panel, else the bubble, which Battery Saver does not show (the HUN service
 * stops itself in power save mode, HeadsUpNotificationService.java:117-123) */
inline Kind kindFor(bool faceCurrent, bool batterySaver)
{
    if (faceCurrent)
        return Glanceable;
    return batterySaver ? NoKind : Bubble;
}

// How long the glanceable stays before it becomes the full view
inline long long glanceHoldMs(bool showImmediately)
{
    return showImmediately ? GlanceHoldImmediateMs : GlanceHoldMs;
}

/* A new alert while one is up: on the face the newest replaces a glanceable
 * (stock shows it at once and extends the screen; inferred), but not the full
 * view the user is reading or answering; in an app the bubbles come one at a
 * time. */
inline bool replacesCurrent(Kind current, Kind incoming, bool detailOpen)
{
    return current == Glanceable && incoming == Glanceable && !detailOpen;
}

// The alerts the queue has to give up when it is over its cap (the oldest)
inline int overflow(int size)
{
    return size > PendingMax ? size - static_cast<int>(PendingMax) : 0;
}

/* One conversation: the app and the title of a message notification (a plain
 * notification is its own). A bubble for a conversation that is already the one
 * shown is skipped (ktr.java:300-306). */
inline std::string threadKey(const std::string &app, const std::string &summary, bool conversation)
{
    return conversation ? app + '\n' + summary : std::string();
}

/* The notification vibrations are the ones the 2000 ms rule counts; alarms, a
 * ringing call, the find-my-watch ring and the battery warnings are never
 * limited. x-nemo-feedback is a comma separated list of ngfd events. */
inline bool isNotificationVibration(const std::string &hint)
{
    bool any = false;
    size_t start = 0;
    while (start <= hint.size()) {
        size_t end = hint.find(',', start);
        if (end == std::string::npos)
            end = hint.size();
        const std::string item = hint.substr(start, end - start);
        if (!item.empty()) {
            if (item.compare(0, 6, "notif_") != 0)
                return false;
            any = true;
        }
        start = end + 1;
    }
    return any;
}

/* At most one notification vibration per 2000 ms, from the start of the last
 * one (icp.java:29). */
class VibrationLimiter
{
public:
    // true: play it now (and count it)
    bool allow(long long now)
    {
        if (m_last >= 0 && now - m_last < VibrationGapMs && now >= m_last)
            return false;
        m_last = now;
        return true;
    }
    void reset() { m_last = -1; }
private:
    long long m_last = -1;
};

/* The alerts that arrived with the screen off (On wrist raise): at most 5, the
 * oldest dropped; the newest not older than 10000 ms shows when the display
 * turns on, the rest are dropped. */
class Pending
{
public:
    struct Item { unsigned id; long long at; };

    // an alert again with the same id (an update) takes the new place and time
    void add(unsigned id, long long at)
    {
        remove(id);
        m_items.push_back({ id, at });
        while (static_cast<long long>(m_items.size()) > PendingMax)
            m_items.erase(m_items.begin());
    }
    void remove(unsigned id)
    {
        m_items.erase(std::remove_if(m_items.begin(), m_items.end(),
                                     [id](const Item &i) { return i.id == id; }), m_items.end());
    }
    bool contains(unsigned id) const
    {
        return std::any_of(m_items.begin(), m_items.end(), [id](const Item &i) { return i.id == id; });
    }
    int size() const { return static_cast<int>(m_items.size()); }
    const std::vector<Item> &items() const { return m_items; }
    void clear() { m_items.clear(); }

    // the id to show now (0: none); every alert of the list is gone after it
    unsigned takeNewest(long long now)
    {
        unsigned id = 0;
        if (!m_items.empty() && now - m_items.back().at <= PendingWindowMs && now >= m_items.back().at)
            id = m_items.back().id;
        m_items.clear();
        return id;
    }
private:
    std::vector<Item> m_items;
};

/* The alert the glanceable or the full view was showing when the display left
 * ON: it shows again if the display is ON again within 10000 ms, else it is
 * dropped (juh.java:403-478; the stream keeps it either way). */
class Resume
{
public:
    void left(unsigned id, long long now) { m_id = id; m_at = now; }
    void forget(unsigned id) { if (m_id == id) m_id = 0; }
    unsigned id() const { return m_id; }
    // the id to show again (0: none); one use
    unsigned take(long long now)
    {
        const unsigned id = (m_id != 0 && now >= m_at && now - m_at <= ResumeWindowMs) ? m_id : 0;
        m_id = 0;
        return id;
    }
    void clear() { m_id = 0; }
private:
    unsigned m_id = 0;
    long long m_at = 0;
};

} // namespace EosAlert

#endif // EOSALERTPOLICY_H
