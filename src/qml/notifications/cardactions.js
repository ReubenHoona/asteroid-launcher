/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library
.import "tiles/exercisetypes.js" as Types

/*
 * What the launcher's own buttons on a notification card do (CardActions.qml). Plain functions of the card's
 * hints; the dconf writes and the app start are CardActions'.
 *
 *  - exercise-detect (CR-38): sensorlogd's "Activity detected / Start tracking?" and "Finished working out?"
 *    cards carry x-asteroid-category=exercise-detect and the JSON hint x-asteroid-exercise
 *    {"action":"start"|"stop","activity":s,"since":ms}. The button "Start" writes
 *    /org/asteroidos/exercise/start-request = "<exercise key>@<ms>" (a key of exercisetypes.js; the activity is
 *    matched without case, an unknown one is Walk), "End" writes /org/asteroidos/exercise/stop-request = "<ms>";
 *    then asteroid-exercise is started. health-alert and celebration cards have no button of ours.
 *  - open page (health-fitness-26): a card with the hint x-eos-open-page and x-eos-app asteroid-health ("Start your
 *    day") gets the button "Open": it writes "<page>@<ms>" to /org/asteroidos/health/ui/open and starts Health.
 */

var EXERCISE_APP = "asteroid-exercise"
var START_KEY = "/org/asteroidos/exercise/start-request"
var STOP_KEY = "/org/asteroidos/exercise/stop-request"
var HEALTH_APP = "asteroid-health"
var HEALTH_OPEN_KEY = "/org/asteroidos/health/ui/open"

// what sensorlogd calls an activity (healthMonitor.h: "walking" / "running") and the other usual names, by exercise key
var ACTIVITY_ALIASES = {
    walking: "Walk", walk: "Walk",
    running: "Run", jogging: "Run",
    cycling: "Bike", biking: "Bike",
    hiking: "Hike",
    swimming: "Swim"
}

var _byLower = null

function _keys() {
    if (_byLower === null) {
        _byLower = {}
        var list = Types.all()
        for (var i = 0; i < list.length; i++)
            _byLower[list[i].key.toLowerCase()] = list[i].key
    }
    return _byLower
}

// the offer a card carries, or null: { action: "start" | "stop", activity, since }
function exerciseOffer(hints) {
    if (!hints || hints["x-asteroid-category"] !== "exercise-detect")
        return null
    var raw = hints["x-asteroid-exercise"]
    if (raw === undefined || raw === null || raw === "")
        return null
    var o
    try {
        o = typeof raw === "object" ? raw : JSON.parse(String(raw))
    } catch (e) {
        return null
    }
    if (!o || (o.action !== "start" && o.action !== "stop"))
        return null
    return { action: o.action, activity: o.activity === undefined || o.activity === null ? "" : String(o.activity),
             since: Number(o.since) || 0 }
}

// the exercise type of sensorlogd's activity: its key without case, else the usual names, else Walk
function exerciseKey(activity) {
    var a = String(activity === undefined || activity === null ? "" : activity).toLowerCase().replace(/[^a-z]/g, "")
    var keys = _keys()
    if (keys.hasOwnProperty(a))
        return keys[a]
    if (ACTIVITY_ALIASES.hasOwnProperty(a))
        return ACTIVITY_ALIASES[a]
    return "Walk"
}

// the dconf write of an offer's button: { key, value }
function exerciseRequest(offer, nowMs) {
    if (offer.action === "stop")
        return { key: STOP_KEY, value: String(nowMs) }
    return { key: START_KEY, value: exerciseKey(offer.activity) + "@" + nowMs }
}

// the page a card asks Health to open, or ""
function openPage(hints) {
    if (!hints)
        return ""
    var app = String(hints["x-eos-app"] || "").replace(/\.desktop$/, "")
    var page = hints["x-eos-open-page"]
    if (app !== HEALTH_APP || page === undefined || page === null)
        return ""
    return String(page)
}

function openRequest(page, nowMs) {
    return { key: HEALTH_OPEN_KEY, value: page + "@" + nowMs }
}
