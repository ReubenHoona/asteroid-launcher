/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The rules of the heart rate alert screen (HrAlert.qml, M4 WO-12) as pure functions, tested in
 * tests/qml/tst_hralert.qml. Stock: Fitbit 4.01.1 on CP3A, HeartRateAlertInfoActivity and HrAlertService.
 */

// the screen opened with the notification closes itself a minute after it came or was last scrolled (stock:
// aabb.java:557-567 'delay(60000)' then finish(); apx.java starts it again at each scroll of the list); opened from
// the card it stays (extraShouldAutoDismiss false, HrAlertService.java:60-62)
var AUTO_DISMISS_MS = 60000

// the screen's colours: stock draws the icon, the title and the bpm in the HEALTH palette's colour (qbd.a(
// ColorPalette.HEALTH), tul.aY(..).D.u: not resolved in the sources); the Fitbit HEALTH tone of the tiles
// (flex_lite_tile_heartrate_preview.xml #94D6FF) and its deep tone for what sits on it (ColorPaletteCompat #001F2D)
var ACCENT = "#94D6FF"
var ON_ACCENT = "#001F2D"

/* asteroid-sensorlogd's alert in a notification's hints (x-asteroid-category health-alert, the JSON hint
 * x-asteroid-health: type hr-high / hr-low, bpm, threshold, start, end in ms): { kind: "high" | "low", bpm,
 * threshold, start, end }; null for any other notification */
function parse(hints) {
    if (!hints || hints["x-asteroid-category"] !== "health-alert")
        return null
    var j = null
    try {
        j = JSON.parse(String(hints["x-asteroid-health"] || ""))
    } catch (e) {
        j = null
    }
    if (!j || (j.type !== "hr-high" && j.type !== "hr-low"))
        return null
    return { kind: j.type === "hr-high" ? "high" : "low", bpm: Math.round(Number(j.bpm) || 0),
             threshold: Math.round(Number(j.threshold) || 0), start: Number(j.start) || 0, end: Number(j.end) || 0 }
}

/* how long an auto-dismissing screen has left at nowMs, last touched at sinceMs (0: it is over) */
function remainingMs(sinceMs, nowMs) {
    var left = AUTO_DISMISS_MS - (nowMs - sinceMs)
    return left > 0 && nowMs >= sinceMs ? left : 0
}
