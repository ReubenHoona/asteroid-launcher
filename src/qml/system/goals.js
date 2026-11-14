/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The rules of the daily goal celebration (health-fitness-14, stock's Fitbit GoalAchievedCelebration):
 * once per day and goal, when the day's total crosses the goal, a full screen "Goal complete!" shows
 * for 10 s. Pure functions: tests tst_celebration.qml. */

// stock GoalAchievedCelebration: dismisses after 10 s
var SHOW_MS = 10000
// about 4 s of animation (the stock Lottie files run 3.8 to 5 s)
var ANIMATION_MS = 4000
// the vibration: two short confirmations 260 ms apart
var BUZZ_GAP_MS = 260

// the goals the watch can measure today: steps (asteroid-sensorlogd's stepCounter, summed for the day);
// calories, distance, floors and active zone minutes need sensors that are not there
var METRICS = [
    { id: "steps", sensor: "stepCounter", goalKey: "/org/asteroidos/ux/steps-goal", defaultGoal: 10000, icon: "ms-directions_walk" }
]

function metric(id) {
    for (var i = 0; i < METRICS.length; i++)
        if (METRICS[i].id === id)
            return METRICS[i]
    return null
}

// "2026-11-14" from a Date (the local day)
function dayKey(d) {
    function p(n) { return (n < 10 ? "0" : "") + n }
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
}

/* "celebrate" when the total reached the goal today and today has not been celebrated; "none" else.
 * A goal of 0 (off) or a total that is not a number never celebrates. */
function decide(total, goal, celebratedDay, today) {
    var t = Number(total), g = Number(goal)
    if (!(g > 0) || !(t >= g))
        return "none"
    return celebratedDay === today ? "none" : "celebrate"
}

/* May it show now? Not while the display is off (it waits for the next screen on), not over a call,
 * an alarm, setup or another system surface, and not in Bedtime, Theater or Do Not Disturb (the quiet
 * rules of the notifications) */
function mayShow(c) {
    if (!c.displayOn || c.blocked || c.quiet)
        return false
    return true
}

// the value as the screen writes it: thousands separated by the locale
function valueText(n, locale) {
    return Number(n).toLocaleString(locale, "f", 0)
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
