/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The rules of the full screen celebrations (health-fitness-14 and -15; R5 E-05, E-06, E-18), as stock's Fitbit
 * CelebrationActivity shows them (celebration/display/CelebrationActivity.java, started by trj.java:115-185): the
 * main goal reached (one a day, of the main goal's type: tui.java:505-580 DailySteps / Calories / Distance / Floors
 * / Azm Celebration), every hour of the reminders' window met (DailyReminderToMoveCelebration), and the reminders to
 * move themselves (HourlyReminderToMoveMessage, HourlyReminderToMoveCelebration). asteroid-sensorlogd decides and
 * posts them (x-asteroid-category "celebration", the hint x-asteroid-health); lipstick hands them over as a full
 * screen category. Pure functions: tests tst_celebration.qml. */

// stock GoalAchievedCelebration.a(): dismisses after 10 s; the reminders' own time is a server flag
// (aaax.java:141, agga): the same 10 s (guess)
var SHOW_MS = 10000
// about 4 s of animation (the stock Lottie files run 3.8 to 5 s)
var ANIMATION_MS = 4000
// the vibration of a goal: two short confirmations 260 ms apart (a reminder's is its notification's)
var BUZZ_GAP_MS = 260
// stock's reminder goal: 250 steps an hour (RtmManager.java:613)
var HOURLY_STEPS = 250

/* The goals (stock PrimaryGoalType STEPS, CALORIES, DISTANCE, FLOORS, AZM) and the hourly activity: the icon (the
 * Health app's, installed in the icon theme), the name (stock 0x7f14019a, 0x7f140188, 0x7f14018a, 0x7f140191,
 * 0x7f140186, 0x7f140196) is the screen's qsTrId, by id. */
var METRICS = [
    { id: "steps", icon: "eos-health-steps" },
    { id: "calories", icon: "eos-health-energy" },
    { id: "distance", icon: "eos-health-distance" },
    { id: "floors", icon: "eos-health-floors" },
    { id: "azm", icon: "eos-health-azm" },
    { id: "hourly", icon: "eos-health-hourly" }
]

function metric(id) {
    for (var i = 0; i < METRICS.length; i++)
        if (METRICS[i].id === id)
            return METRICS[i]
    return null
}

/* A celebration from a notification's hints, or null (not one, a broken hint):
 *   { kind: "goal", metric, value, goal }        the main goal (type "goal")
 *   { kind: "goal", metric: "hourly", value }     every hour of the window met (type "hourly-activity": hours)
 *   { kind: "rtm", steps, goal, left }            a reminder to move ("reminder-to-move")
 *   { kind: "rtm-done", steps, goal }             its hour's goal reached ("reminder-to-move-complete") */
function parse(hints) {
    if (!hints || String(hints["x-asteroid-category"] || "") !== "celebration")
        return null
    var j
    try {
        j = JSON.parse(String(hints["x-asteroid-health"] || ""))
    } catch (e) {
        return null
    }
    if (!j || typeof j !== "object")
        return null
    var goal = Number(j.goal) > 0 ? Number(j.goal) : HOURLY_STEPS
    switch (String(j.type || "")) {
    case "goal":
        if (metric(String(j.metric || "")) === null || String(j.metric) === "hourly" || !(Number(j.value) >= 0))
            return null
        return { kind: "goal", metric: String(j.metric), value: Number(j.value), goal: Number(j.goal) || 0 }
    case "hourly-activity":
        if (!(Number(j.hours) >= 0))
            return null
        return { kind: "goal", metric: "hourly", value: Number(j.hours), goal: 0 }
    case "reminder-to-move":
        var steps = Math.max(0, Number(j.steps) || 0)
        return { kind: "rtm", steps: steps, goal: goal, left: Math.max(0, goal - steps) }
    case "reminder-to-move-complete":
        return { kind: "rtm-done", steps: Math.max(0, Number(j.steps) || 0), goal: goal }
    }
    return null
}

// the ring of a reminder: stock's displayProgress, (max - left) / max (aaax.java:150), full when its goal is met
function ringProgress(c) {
    if (!c)
        return 0
    if (c.kind === "rtm-done")
        return 1
    return Math.max(0, Math.min(1, (c.goal - c.left) / Math.max(1, c.goal)))
}

/* May it show now? stock trj.java:115-160 shows the full screen message only with the notification display criteria
 * met (zit.a: not in Do Not Disturb, Theater or Bedtime), not on the charger, not off the wrist, the celebrations
 * channel on; and not over a call, an alarm, setup or another system surface here (they would hide it). Anything
 * else drops it (stock does not show it later, but for an exercise: sensorlogd holds those until the workout ends). */
function mayShow(c) {
    return !(c.blocked || c.quiet || c.charging || c.offWrist || !c.enabled)
}

// a number as the screen writes it: thousands separated by the locale, `decimals` places
function number(n, locale, decimals) {
    return Number(n).toLocaleString(locale, "f", decimals || 0)
}

// at most two decimals and none that are not needed, as stock's uhz.a(n, 0, 2): 8.05, 8.1, 10
function shortNumber(n, locale) {
    var r = Math.round(Number(n) * 100) / 100
    var places = r === Math.round(r) ? 0 : Math.round(r * 10) === r * 10 ? 1 : 2
    return number(r, locale, places)
}

/* The value of a goal as stock's GoalAchievedCelebration.b() writes it (uhz.a: at most 2 decimals, none needed for
 * whole numbers): steps "10,000"; calories "%1$s cal" (0x7f140187); distance in the phone's unit system, else the locale's ("8.05 km", stock's
 * unit plural); floors "%1$s floors" (0x7f140190); AZM "%1$s Zone Mins" (0x7f140185); hours "%1$s hr" (0x7f140197).
 * `fmt` holds the screen's translated formats (cal, floors, azm, hours, km, mi), each with %1. */
function valueText(c, locale, imperial, fmt) {
    if (!c)
        return ""
    var v = c.value
    switch (c.metric) {
    case "steps":
        return number(v, locale, 0)
    case "calories":
        return fmt.cal.arg(number(Math.round(v), locale, 0))
    case "distance":
        return (imperial ? fmt.mi : fmt.km).arg(shortNumber(imperial ? v / 1609.344 : v / 1000, locale))
    case "floors":
        return fmt.floors.arg(number(Math.round(v), locale, 0))
    case "azm":
        return fmt.azm.arg(number(Math.round(v), locale, 0))
    case "hourly":
        return fmt.hours.arg(number(Math.round(v), locale, 0))
    }
    return number(v, locale, 0)
}

/* The pieces of the confetti: a fixed pattern (no randomness, so the same every time), `count` pieces
 * over the screen's width. Each: x (0..1 of the width), delay (ms), duration (ms), size (px), turns
 * (full turns), colour index. */
function confetti(count) {
    var out = []
    for (var i = 0; i < count; i++) {
        var a = (i * 0.61803398875) % 1
        var b = (i * 0.41421356237) % 1
        out.push({ x: 0.04 + 0.92 * a, delay: Math.round(b * 900), duration: 2000 + Math.round(((i * 7) % 11) / 10 * 1000),
                   size: 8 + (i * 5) % 9, turns: 1 + (i % 3), color: i % 5 })
    }
    return out
}
