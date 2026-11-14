/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The navigation tutorial's script (setup-wizard-01, choice-settings-12), after stock CP3A's tutorial coach
 * (SysUI jvu.java:43-330, hjw.java:2720-3790). The tutorial waits for each gesture on the real home screen
 * instead of showing a demo: `snap` is what the home screen is doing right now. Pure functions. */

// stock integers (VALUES.tsv, com.google.android.wearable.sysui)
var welcome = { animationMs: 2500, textDelayMs: 2000, buttonDelayMs: 2800, buttonDp: 59, textOffsetDp: 10 }
var holdMs = 3000             // a section's gesture is shown 3000 ms after it is done
var confirmMs = 1000          // "All set" with the 96 dp check (tutorial_confirmation_lottie_duration)
var completionMs = 1000       // the final check animation (tutorial_completion_screen_lottie_duration_ms)
var autoCloseMs = 5000        // the final screen closes by itself
var timeoutMs = 900000        // 15 minutes per step
var firstTimeoutMs = 3600000  // 1 hour for the first two
var hints = {
    vertical: { widthDp: 40, heightDp: 96 }, horizontal: { widthDp: 140, heightDp: 40 },
    crown: { widthDp: 60, heightDp: 44, loopMs: 750 }, loopMs: 2000, checkDp: 96, edgeButtonDp: 59,
    splash: { top: 0.079, side: 0.052, gapDp: 4 }
}
var dim = { face: 0.88, panel: 0.55 }     // tutorial_overlay_transparent_background e0000000, lighter over a panel

var steps = ["welcome", "splash", "notifications", "quicksettings", "tilesSwipe", "keepLeft", "keepRight", "tilesInfo",
             "allSet", "crownFace", "crownApps", "sideButton", "done"]

function indexOf(id) { return steps.indexOf(id) }

/* 15 minutes per step, an hour for the two first ones */
function stepTimeout(id) {
    var i = indexOf(id)
    return i >= 0 && i < 2 ? firstTimeoutMs : timeoutMs
}

/* The step after `id`; "" after the last one */
function next(id) {
    var i = indexOf(id)
    return i >= 0 && i + 1 < steps.length ? steps[i + 1] : ""
}

/* The gesture steps wait for the user: the snapshot of the home screen decides.
 *   snap.vpos          the grid's vertical position: 1 the notifications, -1 quick settings
 *   snap.hpos          the horizontal position: not 0 on a tile
 *   snap.drawerOpen    the app list is open
 *   snap.recentsOpen   recent apps are open
 *   snap.assistantShown the assistant is up
 * Returns true when the gesture of the step has been done. */
function done(id, snap) {
    switch (id) {
    case "notifications": return snap.vpos === 1
    case "quicksettings": return snap.vpos === -1
    case "tilesSwipe": return snap.hpos !== 0
    case "crownFace": return isFace(snap)
    case "crownApps": return snap.drawerOpen === true
    case "sideButton": return sideDone(snap.side, snap)
    default: return false
    }
}

/* the face with nothing over it */
function isFace(snap) {
    return snap.vpos === 0 && snap.hpos === 0 && snap.drawerOpen !== true && snap.recentsOpen !== true
           && snap.assistantShown !== true
}

/* The steps that run by themselves for `hold` ms once they are shown (no gesture to wait for) */
function timed(id) { return id === "keepLeft" || id === "keepRight" || id === "allSet" }

/* How long a step shows its result once the gesture is done (ms; 0 = move on at once) */
function hold(id) {
    switch (id) {
    case "allSet": return confirmMs
    case "notifications":
    case "quicksettings":
    case "keepLeft":
    case "keepRight":
    case "crownFace":
    case "crownApps": return holdMs
    default: return 0
    }
}

/* The side button step follows the side-button option (choice-settings-12): the assistant (the default) opens on
 * a press and hold and that ends the step, `recents` opens the recent apps on a press. */
function sideMode(value) { return value === "recents" ? "recents" : "assistant" }

function sideDone(value, snap) {
    return sideMode(value) === "recents" ? snap.recentsOpen === true : snap.assistantShown === true
}

/* the steps' stock hints */
function hintFor(id) {
    switch (id) {
    case "notifications": return { kind: "vertical", dir: "up" }
    case "quicksettings": return { kind: "vertical", dir: "down" }
    case "tilesSwipe": return { kind: "horizontal", dir: "both" }
    case "keepLeft": return { kind: "horizontal", dir: "left" }
    case "keepRight": return { kind: "horizontal", dir: "right" }
    case "crownFace":
    case "crownApps": return { kind: "crown" }
    case "sideButton": return { kind: "side" }
    default: return { kind: "none" }
    }
}

/* The steps that show the dim layer over the home screen (everything between the splash and the end, but the
 * "All set" and the final screens, which are black) */
function dimmed(id) {
    var i = indexOf(id)
    return i >= indexOf("notifications") && id !== "done" && id !== "allSet"
}

/* The opacity of the dim: less over a panel, so the panel can be seen */
function dimAlpha(snap) { return isFace(snap) ? dim.face : dim.panel }

/* The example notification's title (stock tutorial_notification_primary) goes through the notification
 * service; its app is the setup's own and it is removed at the end. */
var exampleApp = "eos-setup"
