/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/*
 * The window transitions of Wear OS (CP3A) as numbers and pure functions
 * (W2-launcher-window-motion). The QML (AppOpen, WatchfaceReveal,
 * WindowTransitions) only feeds them spring values; the tests check every
 * number here against the stock sources named beside it.
 *
 * Stock evidence (SysUI = com.google.android.apps.wearable.systemui,
 * clockwork/systemui/):
 *  - launch: transition/mixed/WearAppLaunchMixinTransition.java:63-64 and its
 *    ExternalSyntheticLambda0/2 (scale, alpha, dim), transition/shelltransition/
 *    WearMixedTransitionHandler.java:110-131,214-235
 *  - back to the face: transition/mixed/WearOpenWatchfaceMixinTransition.java:104-106
 *    and its lambdas 0-2
 *  - back swipe: wmshell/back/CrossTaskBackAnimation.java:25-34,37-80,84-87,95-160
 */

/* ---- app launch from the face or the app list (motion-transitions-02, -05) ---- */
var LAUNCH = {
    // the opening window or list: scale 0.45 -> 1.0 about the centre on the
    // baseline spring (damping 1.0, stiffness 260, the last 2 % skipped)
    startScale: 0.45,
    baseline: { stiffness: 260, dampingRatio: 1.0, stopAtFraction: 0.98 },
    // its alpha 0 -> 1 on damping 1.0 / stiffness 5000 (~83 ms)
    fade: { stiffness: 5000, dampingRatio: 1.0, stopAtFraction: 0.98 },
    // the closing task (the app list, or the face): scale 1.0 -> 0.70 on the
    // same baseline spring, a black dim 0 -> 0.5 over it
    behindDrop: 0.30,
    behindDim: 0.5
}

/* ---- back to the watch face: the crown in an app, the app list closing
 *      (motion-transitions-04, -06) ---- */
var HOME = {
    // the closing app or list: scale 1 -> 0.60 on damping 1.0 / stiffness 500
    // (98 % at ~261 ms)
    top: { stiffness: 500, dampingRatio: 1.0, stopAtFraction: 0.98 },
    topDrop: 0.40,
    // its alpha 1 -> 0 linearly over 50 ms, starting at 100 ms
    fadeDelayMs: 100,
    fadeMs: 50,
    // the face (home + wallpaper): scale and alpha 0.5 -> 1 on damping 1.0 /
    // stiffness 260 (98 % at ~362 ms), over black
    face: { stiffness: 260, dampingRatio: 1.0, stopAtFraction: 0.98 },
    faceStart: 0.5
}

/* ---- the back swipe at the root of an app (motion-transitions-11) ---- */
var BACK = {
    // e = CubicBezier(0, 0.20, 0.80, 1.00)(p)
    bezier: [0, 0.20, 0.80, 1.00],
    closingMin: 0.70,           // scale_front_min
    openingMin: 0.85,           // scale_back_min
    openingBeforeCommit: 0.93,  // scale_back_commit
    dimBackMin: 0,              // dimming_back_min
    dimBackBeforeCommit: 0.25,  // dimming_back_commit
    dimBackMax: 0.50,           // dimming_back_max
    dimFrontMin: 0,             // dimming_front_min
    dimFrontBeforeCommit: 0.25, // dimming_front_commit
    dimFrontMax: 0.30,          // dimming_front_max
    // the commit: the app's left edge springs to the screen width
    commit: { stiffness: 600, dampingRatio: 1.0, stopAtFraction: 0.98, visibleChange: 0.5 },
    // the cancel: the progress springs back
    cancel: { stiffness: 1500, dampingRatio: 1.0 },
    // the progress follows the finger smoothed by the same spring
    // (BackProgressAnimator, Motion.backGesture.progress)
    smooth: { stiffness: 1500, dampingRatio: 1.0 }
}

/* ---- the app list's intro slide (app-launcher-08) ---- */
var INTRO = {
    // the top spacer 0.33 -> 0.13 of the height (127 -> 50 px), 400 ms,
    // CubicBezier(0, 0, 0, 1); launcher_scroll_to_top_anim_duration_ms,
    // compose_list_launcher_scroll_to_top_screen_height_percent = 0.2
    fromFraction: 0.33,
    toFraction: 0.13,
    durationMs: 400,
    bezier: [0, 0, 0, 1, 1, 1]
}

/* ---- the face leaving and entering the always-on screen
 *      (ambient-aod-19, motion-transitions-32) ---- */
var AMBIENT = {
    // the face animates its own change in 500 ms (WFF runtime_ambient_transition_ms)
    // with the standard easing, before the sensor hub draws the panel
    entryMs: 500,
    entryBezier: [0.2, 0, 0, 1, 1, 1],
    faceLook: 0.55,
    // no ramp at screen on (config_skipScreenOnBrightnessRamp): the wake is at once
    wakeMs: 0
}

// the starting window (motion-transitions-03)
var SPLASH = {
    minShownMs: 400,
    iconFadeMs: 50,           // starting_window_app_reveal_icon_fade_out_duration
    revealDelayMs: 50,        // starting_window_app_reveal_anim_delay
    revealMs: 200,            // starting_window_app_reveal_anim_duration
    bareIconScale: 1.25,      // splash_icon_no_background_scale_factor
    iconDp: 48,               // starting_surface_icon_size 48dp (values-watch/dimens.xml:41; VALUES.tsv:6034) = 96 px
    background: "#000000"     // splash_window_background_default
}

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
function lerp(a, b, t) { return a + (b - a) * t }

/* The y of a cubic Bezier with control points (x1, y1), (x2, y2) and the ends
 * (0, 0), (1, 1) at x = t (Android's CubicBezierEasing / PathInterpolator). */
function bezier(x1, y1, x2, y2, t) {
    if (t <= 0) return 0
    if (t >= 1) return 1
    function bx(s) { var u = 1 - s; return 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s }
    function by(s) { var u = 1 - s; return 3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s }
    function dbx(s) { var u = 1 - s; return 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2) }
    var s = t
    for (var i = 0; i < 8; i++) {
        var d = dbx(s)
        if (Math.abs(d) < 1e-6) break
        var ns = s - (bx(s) - t) / d
        s = ns < 0 ? 0 : (ns > 1 ? 1 : ns)
    }
    // bisection when Newton did not land
    if (Math.abs(bx(s) - t) > 1e-5) {
        var lo = 0, hi = 1
        for (var j = 0; j < 40; j++) {
            s = (lo + hi) / 2
            if (bx(s) < t) lo = s; else hi = s
        }
    }
    return by(s)
}

/* The values of the launch at the baseline spring value p and the fade
 * spring value f (both 0 -> 1). */
function launch(p, f) {
    return {
        scale: LAUNCH.startScale + (1 - LAUNCH.startScale) * p,
        alpha: f,
        behindScale: 1 - LAUNCH.behindDrop * p,
        behindDim: LAUNCH.behindDim * p
    }
}

/* The values of the way back to the face at the top spring value a (the
 * closing app or list) and the face spring value q (both 0 -> 1) and ms since
 * the start (for the linear fade). */
function home(a, q, ms) {
    return {
        topScale: 1 - HOME.topDrop * a,
        topAlpha: 1 - clamp01((ms - HOME.fadeDelayMs) / HOME.fadeMs),
        faceScale: HOME.faceStart + (1 - HOME.faceStart) * q,
        faceAlpha: HOME.faceStart + (1 - HOME.faceStart) * q
    }
}

/* The back swipe at the finger's progress p (0..1 of the screen width, smoothed)
 * on a screen w px wide (onGestureProgress). */
function back(p, w) {
    var e = clamp01(bezier(BACK.bezier[0], BACK.bezier[1], BACK.bezier[2], BACK.bezier[3], clamp01(p)))
    var s = lerp(1, BACK.closingMin, e)
    var left = w * (1 - s)
    var t = clamp01(left / w)
    return {
        e: e,
        appScale: s,
        // the app's right edge stays on the screen's right edge
        appLeft: left,
        homeScale: lerp(BACK.openingMin, BACK.openingBeforeCommit, e),
        homeDim: lerp(BACK.dimBackMax, BACK.dimBackBeforeCommit, t),
        appDim: lerp(BACK.dimFrontMin, BACK.dimFrontBeforeCommit, t)
    }
}

/* The commit with the app's left edge at `left` px (springing from left0 to w):
 * the dims start from where the swipe left them (homeDim0, appDim0)
 * (CrossTaskDismissalAnimation.onDismissalAnimationProgressChanged$1). */
function commit(left, left0, homeDim0, appDim0, w) {
    var c = clamp01(left / w)
    var c2 = clamp01(c - left0 / w)
    var s = Math.max(BACK.closingMin, Math.min(1 - c, 1))
    return {
        appScale: s,
        appLeft: left,
        homeScale: lerp(BACK.openingBeforeCommit, 1, c),
        homeDim: lerp(homeDim0, BACK.dimBackMin, c2),
        appDim: lerp(appDim0, BACK.dimFrontMax, c2)
    }
}

/* The offset of the app list's content while the intro slide runs, at the
 * eased fraction e (0 -> 1) of the slide, on a screen h px high. */
function introShift(h, e) {
    return h * (INTRO.fromFraction - INTRO.toFraction) * (1 - e)
}
