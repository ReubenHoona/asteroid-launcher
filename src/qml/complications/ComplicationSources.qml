/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus
import Nemo.Mce
import org.asteroid.launcher
import "../weathericons.js" as IconTools
import "../desktop.js" as Desktop
import "complications.js" as C
import "../home/ambient.js" as Ambient

/*
 * The watch face complications, as Wear OS's: a face names its slots (an
 * Item with objectName "eosComplication", its slotId, shape and default
 * data source; see ComplicationView.qml) and the launcher draws the data
 * source chosen for each slot in it, the same on every face. The choice
 * is per face and slot, in dconf
 * /org/asteroidos/watchface/complications/<face file name> as a list of
 * "slotId=source" strings (missing: the face's default; "empty": nothing).
 * A source is one of `all`, or "kind:parameter" for the three that need a
 * choice (`parameterised`): "worldclock:+0530" (a UTC offset), "countdown:
 * 2026-12-25" and "app:asteroid-music" (a desktop file); the face editor
 * asks for the parameter.
 *
 * Power, as the tiles: the sources read and follow their data only while
 * "active" (the face, or the face editor, on the awake screen) and only
 * the sources a slot shows; nothing here has a timer. While inactive every
 * value stays as it was, so nothing on the face changes with the screen
 * off. In always-on only the date shows (ComplicationView): the sensor
 * hub's layout keeps the always-on picture until the next midnight, and
 * the date is the one complication that does not change before then.
 * The values that move with the clock (a countdown, the stopwatch, "in 45
 * min") are worked out from `now`, which the home screen ticks while the
 * face is awake; the rules are in complications.js.
 */
Item {
    id: sources
    visible: false

    property bool active: false
    // from the home screen: always-on, nightstand, 12 h
    property bool ambient: false
    // the sensor hub draws the always-on face (the AP sleeps through it): data
    // that changes in between is drawn '--' there (ambient-aod-11, ambient.js)
    property bool hubDrawn: false
    property bool nightstand: false
    property bool use12h: false
    // the wall clock of the faces (the date, the next event's end)
    property date now: new Date()
    // the unread notifications (the notification indicator's count) and the
    // launcher's apps (the app shortcut's name and icon)
    property int unread: 0
    property var apps: null

    // the data sources, in the order of the face editor's list
    readonly property var all: ["empty", "date", "daymonth", "datemonth", "weekday", "timedate", "steps", "heartrate",
                                "battery", "phonebattery", "notifications", "health", "weather", "uv", "precipitation",
                                "aqi", "sun", "moon", "nextevent", "alarm", "timer", "stopwatch", "media", "assistant"]
    // the sources that need a choice first (the face editor's second page)
    readonly property var parameterised: ["worldclock", "countdown", "app"]
    function kindOf(id) { return C.split(id).kind }
    function isSource(id) {
        var p = C.split(id)
        return all.indexOf(p.kind) >= 0 && p.param === "" || parameterised.indexOf(p.kind) >= 0 && p.param !== ""
    }
    function name(id) {
        var p = C.split(id)
        switch (p.kind) {
        //% "Empty"
        case "empty": return qsTrId("id-comp-empty")
        //% "Day and date"
        case "date": return qsTrId("id-comp-date")
        //% "Date"
        case "daymonth": return qsTrId("id-comp-day-month")
        //% "Date and month"
        case "datemonth": return qsTrId("id-comp-date-month")
        //% "Day of the week"
        case "weekday": return qsTrId("id-comp-weekday")
        //% "Time and date"
        case "timedate": return qsTrId("id-comp-time-date")
        //% "Steps"
        case "steps": return qsTrId("id-tile-steps")
        //% "Heart rate"
        case "heartrate": return qsTrId("id-tile-heart-rate")
        //% "Battery"
        case "battery": return qsTrId("id-comp-battery")
        //% "Phone battery"
        case "phonebattery": return qsTrId("id-comp-phone-battery")
        //% "Notifications"
        case "notifications": return qsTrId("id-comp-notifications")
        //% "Health"
        case "health": return qsTrId("id-comp-health")
        //% "Weather"
        case "weather": return qsTrId("id-tile-weather")
        //% "UV Index"
        case "uv": return qsTrId("id-comp-uv")
        //% "Precipitation"
        case "precipitation": return qsTrId("id-comp-precipitation")
        //% "Air quality index"
        case "aqi": return qsTrId("id-comp-aqi")
        //% "Sunrise and sunset"
        case "sun": return qsTrId("id-comp-sun")
        //% "Moon phase"
        case "moon": return qsTrId("id-comp-moon")
        //% "Next event"
        case "nextevent": return qsTrId("id-comp-next-event")
        //% "Alarm"
        case "alarm": return qsTrId("id-tile-alarm")
        //% "Timer"
        case "timer": return qsTrId("id-tile-timer")
        //% "Stopwatch"
        case "stopwatch": return qsTrId("id-comp-stopwatch")
        //% "Media controls"
        case "media": return qsTrId("id-comp-media")
        //% "Assistant"
        case "assistant": return qsTrId("id-comp-assistant")
        //% "World clock"
        case "worldclock": return qsTrId("id-comp-world-clock")
        //% "Countdown to date"
        case "countdown": return qsTrId("id-comp-countdown")
        //% "App shortcut"
        case "app": return qsTrId("id-comp-app-shortcut")
        }
        return id
    }

    // the source of a slot in a face's list ("slotId=source"), else its default
    function sourceOf(list, slotId, fallback) {
        var l = list || []
        for (var i = 0; i < l.length; i++) {
            var s = String(l[i])
            var at = s.indexOf("=")
            if (at > 0 && s.slice(0, at) === slotId) {
                var src = s.slice(at + 1)
                return isSource(src) ? src : fallback
            }
        }
        return fallback
    }
    // the list with slotId set to source
    function withSource(list, slotId, source) {
        var out = []
        var l = list || []
        for (var i = 0; i < l.length; i++)
            if (String(l[i]).indexOf(slotId + "=") !== 0)
                out.push(String(l[i]))
        out.push(slotId + "=" + source)
        out.sort()
        return out
    }
    function faceName(url) {
        return String(url).split("/").pop().replace(/\.qml$/, "")
    }
    function configKey(face) {
        return "/org/asteroidos/watchface/complications/" + face
    }

    // the slots of a face: its items named eosComplication, in tree order
    function slotsOf(item, out) {
        out = out || []
        if (!item)
            return out
        if (item.objectName === "eosComplication" && item.slotId !== undefined)
            out.push(item)
        for (var i = 0; i < item.children.length; i++)
            slotsOf(item.children[i], out)
        return out
    }

    // a face loaded: a view in each of its slots
    function attach(face, url) {
        var name = faceName(url)
        var slots = slotsOf(face)
        for (var i = 0; i < slots.length; i++) {
            var has = false
            for (var c = 0; c < slots[i].children.length; c++)
                if (slots[i].children[c].objectName === "eosComplicationView")
                    has = true
            if (!has)
                viewComponent.createObject(slots[i], { slotItem: slots[i], faceName: name, sources: sources })
        }
        return slots.length
    }
    Component {
        id: viewComponent
        ComplicationView { }
    }

    // which sources the views show: only those read (by kind: "app:x" is "app")
    property var views: []
    property var demand: ({})
    function register(v) {
        if (views.indexOf(v) < 0)
            views.push(v)
        Qt.callLater(refreshDemand)
    }
    function unregister(v) {
        var i = views.indexOf(v)
        if (i >= 0)
            views.splice(i, 1)
        Qt.callLater(refreshDemand)
    }
    function refreshDemand() {
        var d = {}
        for (var i = 0; i < views.length; i++)
            if (views[i] && views[i].source && views[i].source !== "empty")
                d[kindOf(views[i].source)] = true
        if (JSON.stringify(d) !== JSON.stringify(demand))
            demand = d
    }
    function wants(s) { return active && demand[s] === true }

    // the words of the next event, as the stock calendar complication says them
    function eventWords() {
        return {
            //% "None"
            none: qsTrId("id-comp-none"),
            //% "No events today"
            noEvents: qsTrId("id-comp-no-events-today"),
            //% "Now"
            now: qsTrId("id-comp-now"),
            //% "Today"
            today: qsTrId("id-comp-today"),
            //% "Tomorrow"
            tomorrow: qsTrId("id-comp-tomorrow"),
            //% "in %1 min"
            inMinutes: qsTrId("id-comp-in-minutes")
        }
    }

    // a source's data, as the view draws it. type: short (text), ranged (text and a ring: progress
    // 0..1), icon (an icon alone), weighted (elements: [{weight, color}]), smallimage (image: url).
    // text: a line's text; short: what fits in a round slot; caption: its small line above;
    // lead: the first part of text when a line draws it in the tint (the weekday); title and long: a
    // long slot's two lines; icon (iconTop: above the value, not in the ring's gap); color: the ring's
    // colour when it is not the face's tint; known false: no data (drawn "- -"); ambient: drawn in the
    // always-on screen (only the date)
    function base(o) {
        var d = { type: "short", text: "", short: "", caption: "", lead: "", title: "", long: "", icon: "", iconTop: false,
                  progress: -1, color: "", elements: [], image: "", known: true, ambient: false }
        for (var k in o)
            d[k] = o[k]
        return d
    }
    function dateInfo(kind) {
        var d = sources.now
        var loc = Qt.locale()
        var wd = C.upper(d.toLocaleString(loc, "ddd"))
        var mon = C.upper(d.toLocaleString(loc, "MMM"))
        switch (kind) {
        case "daymonth":
            return base({ text: wd + " " + C.pad2(d.getDate()), lead: wd, short: C.pad2(d.getDate()), caption: wd,
                          title: d.toLocaleString(loc, "dddd"), long: d.toLocaleString(loc, "d MMMM"),
                          icon: "ios-calendar-outline", iconTop: false, ambient: true })
        case "datemonth":
            return base({ text: mon + " " + C.pad2(d.getDate()), lead: mon, short: C.pad2(d.getDate()), caption: mon,
                          title: d.toLocaleString(loc, "MMMM"), long: d.toLocaleString(loc, "d MMMM"),
                          icon: "ios-calendar-outline", ambient: true })
        case "weekday":
            return base({ text: wd, short: wd, title: d.toLocaleString(loc, "dddd"), long: d.toLocaleString(loc, "d MMMM"),
                          icon: "ios-calendar-outline", ambient: true })
        }
        // date: the weekday in the tint, then the month and the day ("THU MAY 24"); a round slot has the
        // calendar icon, the month over the day
        return base({ text: wd + " " + mon + " " + d.getDate(), lead: wd, short: String(d.getDate()), caption: mon,
                      title: d.toLocaleString(loc, "dddd"), long: d.toLocaleString(loc, "d MMMM"),
                      icon: "ios-calendar-outline", iconTop: true, ambient: true })
    }

    // A source's data for the screen on screen: the always-on screen draws every
    // complication (stock: Pixel faces keep them in the AOD) in the face's dimmed
    // look, the ring's track only and no progress; where the sensor hub draws it,
    // what would go stale shows '--' (the developer guidance for ambient)
    function info(id) {
        var d = liveInfo(id)
        if (!sources.ambient)
            return d
        d.ambient = true
        if (Ambient.complicationStale(C.split(id).kind, sources.hubDrawn)) {
            d.text = "--"
            d.short = "--"
            d.caption = ""
            d.lead = ""
            d.long = "--"
            d.type = d.icon !== "" ? "short" : d.type
            d.progress = -1
            d.elements = []
            d.known = false
        }
        return d
    }
    function liveInfo(id) {
        var p = C.split(id)
        var nodata = "- -"
        switch (p.kind) {
        case "date":
        case "daymonth":
        case "datemonth":
        case "weekday":
            return dateInfo(p.kind)
        case "timedate": {
            var t = C.timeParts(sources.now, sources.use12h)
            return base({ text: C.fmtTime(sources.now, sources.use12h) + " " + sources.now.toLocaleString(Qt.locale(), "ddd d"),
                          short: t.time, caption: t.marker, title: name("timedate"),
                          long: sources.now.toLocaleString(Qt.locale(), "ddd d MMM"), icon: "ios-time-outline" })
        }
        case "worldclock": {
            var off = C.offsetMinutes(p.param)
            if (off === null)
                return base({ short: nodata, text: nodata, icon: "ios-globe-outline", title: name("worldclock"), known: false })
            var wc = C.inOffset(sources.now, off)
            var wp = C.timeParts(wc, sources.use12h)
            return base({ text: C.fmtTime(wc, sources.use12h), short: wp.time, caption: wp.marker, title: name("worldclock"),
                          long: C.fmtTime(wc, sources.use12h), icon: "ios-globe-outline" })
        }
        case "countdown": {
            var days = C.daysTo(sources.now, p.param)
            if (days === null)
                return base({ short: nodata, text: nodata, icon: "ios-calendar-outline", title: name("countdown"), known: false })
            //% "%1 d"
            var left = days < 0 ? nodata : qsTrId("id-comp-days-short").replace("%1", String(days))
            return base({ text: left, short: days < 0 ? nodata : String(days), caption: days < 0 ? "" : "d",
                          title: name("countdown"), long: p.param, icon: "ios-calendar-outline", known: days >= 0 })
        }
        case "steps":
            var count = steps.known ? steps.count.toLocaleString(Qt.locale(), "f", 0) : "--"
            return base({ type: steps.known && steps.goal > 0 ? "ranged" : "short", text: count, short: count,
                          //% "Steps"
                          title: qsTrId("id-tile-steps"), icon: "ios-walk",
                          progress: steps.known && steps.goal > 0 ? Math.min(1, steps.count / steps.goal) : -1,
                          known: steps.known })
        case "heartrate":
            // stock's ranged heart rate (the range is not in readable code: 40-200 bpm)
            var bpm = heart.known ? String(heart.bpm) : "--"
            return base({ type: heart.known ? "ranged" : "short", text: bpm, short: bpm, title: qsTrId("id-tile-heart-rate"),
                          icon: "ios-heart", progress: heart.known ? C.clamp01((heart.bpm - 40) / 160) : -1, known: heart.known })
        case "battery": {
            // stock: the number alone ('82'), 'Battery: 82' for a long slot, a battery icon in four steps
            var known = battery.percent >= 0
            var pc = known ? String(battery.percent) : "--"
            return base({ type: known ? "ranged" : "short", text: pc, short: pc,
                          title: name("battery") + ": " + pc, long: name("battery") + ": " + pc,
                          icon: C.batteryIcon(battery.percent, battery.charging),
                          progress: known ? battery.percent / 100 : -1, known: known })
        }
        case "phonebattery":
            var lv = phone.known ? phone.level + "%" : "--"
            return base({ type: phone.known ? "ranged" : "short", text: lv, short: lv, title: name("phonebattery"),
                          icon: "ios-phone-portrait", progress: phone.known ? phone.level / 100 : -1, known: phone.known })
        case "notifications": {
            var n = sources.unread
            return base({ type: n > 0 ? "short" : "icon", text: String(n), short: String(n), title: name("notifications"),
                          long: String(n), icon: n > 0 ? "ios-notifications" : "ios-notifications-outline" })
        }
        case "health":
            return base({ type: "icon", icon: "ios-heart", title: name("health"), text: name("health") })
        case "weather":
            return weatherInfo()
        case "uv": {
            if (!(wx.uv >= 0))
                return base({ short: nodata, text: nodata, title: name("uv"), icon: "ios-sunny", known: false })
            var u = String(Math.round(wx.uv))
            return base({ type: "ranged", text: "UV " + u, short: "UV " + u, title: "UV", long: uvWord(wx.uv),
                          icon: "ios-sunny", progress: C.clamp01(wx.uv / 11) })
        }
        case "precipitation": {
            if (!(wx.pop >= 0))
                return base({ short: nodata, text: nodata, title: name("precipitation"), icon: "ios-umbrella", known: false })
            return base({ type: "ranged", text: Math.round(wx.pop) + "%", short: Math.round(wx.pop) + "%",
                          title: name("precipitation"), long: precipWord(wx.pop), icon: "ios-umbrella",
                          progress: C.clamp01(wx.pop / 100) })
        }
        case "aqi": {
            if (!(wx.aqi >= 0))
                return base({ short: nodata, text: nodata, title: name("aqi"), icon: "ios-leaf", known: false })
            return base({ type: "ranged", text: String(Math.round(wx.aqi)), short: String(Math.round(wx.aqi)),
                          title: name("aqi"), long: aqiWord(wx.aqi), icon: "ios-leaf", progress: C.clamp01(wx.aqi / 500) })
        }
        case "sun": {
            var s = sunNext()
            if (s === null)
                return base({ short: nodata, text: nodata, title: name("sun"), icon: "ios-sunny-outline", known: false })
            var at = new Date(s.at)
            var sp = C.timeParts(at, sources.use12h)
            var rem = s.at - sources.now.getTime()
            //% "Sunrise"
            var label = s.rise ? qsTrId("id-comp-sunrise") : qsTrId("id-comp-sunset")
            // within the hour the countdown ('45m', 'Now') replaces the time, as the weather complication
            return base({ text: label + ": " + C.fmtTime(at, sources.use12h), short: rem <= 3600000 ? C.leftShort(rem) : sp.time,
                          caption: rem <= 3600000 ? "" : sp.marker, title: label, long: C.fmtTime(at, sources.use12h),
                          icon: s.rise ? "ios-sunny" : "ios-partly-sunny" })
        }
        case "moon": {
            var m = C.moonPhase(sources.now)
            var pct = Math.round(m.illumination * 100)
            return base({ text: pct + "%", short: pct + "%", title: name("moon"), long: moonWord(m.phase), icon: "ios-moon" })
        }
        case "nextevent": {
            var e = C.eventText(sources.now, agenda.ev, sources.use12h, eventWords())
            return base({ text: agenda.ev ? e.short + " " + e.long : e.short, short: e.short, title: e.title, long: e.long,
                          icon: "ios-calendar-outline", known: agenda.ev !== null })
        }
        case "alarm": {
            var ca = clockLoader.item
            var at2 = ca ? ca.nextAlarmMs : 0
            if (!at2)
                return base({ type: "icon", icon: "ios-alarm", title: name("alarm"), text: name("alarm"), known: false })
            var ad = new Date(at2)
            var ap = C.timeParts(ad, sources.use12h)
            return base({ text: C.fmtTime(ad, sources.use12h), short: ap.time, caption: ap.marker, title: name("alarm"),
                          long: C.fmtTime(ad, sources.use12h), icon: "ios-alarm" })
        }
        case "timer": {
            var ct = clockLoader.item
            var rest = ct && ct.countdownEnd > 0 ? ct.countdownEnd - sources.now.getTime() : 0
            if (rest <= 0)
                return base({ type: "icon", icon: "ios-timer", title: name("timer"), text: name("timer"), known: false })
            return base({ text: C.clockText(rest), short: C.clockText(rest), title: name("timer"), long: C.clockText(rest), icon: "ios-timer" })
        }
        case "stopwatch": {
            var ms = stopwatchMs()
            if (ms <= 0)
                return base({ type: "icon", icon: "ios-stopwatch", title: name("stopwatch"), text: name("stopwatch"), known: false })
            return base({ text: C.clockText(ms), short: C.clockText(ms), title: name("stopwatch"), long: C.clockText(ms), icon: "ios-stopwatch" })
        }
        case "media": {
            var md = mediaLoader.item
            //% "Nothing playing"
            var idle = qsTrId("id-comp-nothing-playing")
            var has = md && md.present
            return base({ type: "icon", icon: "ios-musical-notes", text: has ? md.title : idle, short: "",
                          title: has ? md.artist : name("media"), long: has ? md.title : idle, known: has })
        }
        case "assistant":
            return base({ type: "icon", icon: "ios-mic", title: name("assistant"), text: name("assistant"), long: name("assistant") })
        case "app": {
            var ap2 = appItem(p.param)
            return base({ type: "icon", icon: ap2 && ap2.iconId ? ap2.iconId : "ios-apps", title: ap2 && ap2.title ? ap2.title : name("app"),
                          text: ap2 && ap2.title ? ap2.title : name("app"), long: ap2 && ap2.title ? ap2.title : name("app"),
                          known: ap2 !== null })
        }
        }
        return base({ known: false })
    }

    // where a tap on a slot goes, as the stock complications open their app
    function open(id, fromItem) {
        var p = C.split(id)
        switch (p.kind) {
        case "steps":
            // Today at DETAILS for its own metric, as the heart rate one
            openRequest.value = "steps@" + Date.now()
            desktop.launchByName("asteroid-health", fromItem)
            break
        case "heartrate":
            openRequest.value = "heartrate@" + Date.now()
            desktop.launchByName("asteroid-health", fromItem)
            break
        case "health":
            desktop.launchByName("asteroid-health", fromItem)
            break
        case "weather":
        case "uv":
        case "precipitation":
        case "aqi":
        case "sun":
            desktop.launchByName("asteroid-weather", fromItem)
            break
        case "date":
        case "daymonth":
        case "datemonth":
        case "weekday":
        case "timedate":
        case "countdown":
            desktop.launchByName("asteroid-calendar", fromItem)
            break
        case "nextevent":
            // the calendar on that event (it reads the request as the health app's)
            if (agenda.ev)
                calendarRequest.value = "event:" + agenda.ev.start.getTime() + "@" + Date.now()
            desktop.launchByName("asteroid-calendar", fromItem)
            break
        case "battery":
            // Settings > Battery > Battery Saver (the page opens from this request)
            settingsRequest.value = "battery-saver"
            desktop.launchByName("asteroid-settings", fromItem)
            break
        case "phonebattery":
            desktop.launchByName("asteroid-settings", fromItem)
            break
        case "notifications":
            if (desktop.openNotificationStream)
                desktop.openNotificationStream()
            break
        case "alarm":
            desktop.launchByName("asteroid-alarmclock", fromItem)
            break
        case "timer":
            desktop.launchByName("asteroid-timer", fromItem)
            break
        case "stopwatch":
            desktop.launchByName("asteroid-stopwatch", fromItem)
            break
        case "media":
            desktop.launchByName("asteroid-music", fromItem)
            break
        case "assistant":
            if (Desktop.compositorRoot && Desktop.compositorRoot.openAssistant)
                Desktop.compositorRoot.openAssistant("")
            break
        case "app":
            desktop.launchByName(p.param, fromItem)
            break
        }
    }
    ConfigurationValue { id: openRequest; key: "/org/asteroidos/health/ui/open"; defaultValue: "" }
    ConfigurationValue { id: calendarRequest; key: "/org/asteroidos/calendar/ui/open"; defaultValue: "" }
    ConfigurationValue { id: settingsRequest; key: "/org/asteroidos/settings/ui/open"; defaultValue: "" }

    // ---- the sources ------------------------------------------------------

    // steps so far today (asteroid-sensorlogd's log), against the daily goal
    QtObject {
        id: steps
        readonly property bool known: stepsLog.hasData
        readonly property int count: stepsLog.lastValue
        readonly property int goal: stepsGoal.value
    }
    HealthLog { id: stepsLog; sensor: "stepCounter"; buckets: 1; active: sources.wants("steps") }
    ConfigurationValue { id: stepsGoal; key: "/org/asteroidos/ux/steps-goal"; defaultValue: 10000 }

    // the latest heart rate logged today
    QtObject {
        id: heart
        readonly property bool known: heartLog.hasData
        readonly property int bpm: heartLog.lastValue
    }
    HealthLog { id: heartLog; sensor: "heartrateMonitor"; buckets: 1; active: sources.wants("heartrate") }

    // the watch's battery (mce), taken while active
    QtObject {
        id: battery
        property int percent: -1
        property bool charging: false
        readonly property bool on: sources.wants("battery")
        function take() {
            percent = mceLevel.percent
            charging = mceState.value === MceBatteryState.Charging
        }
        onOnChanged: if (on) take()
    }
    MceBatteryLevel { id: mceLevel; onPercentChanged: if (battery.on) battery.take() }
    // (its value's change signal is stateChanged)
    MceBatteryState { id: mceState; onStateChanged: if (battery.on) battery.take() }

    // the phone's battery, as asteroid-btsyncd last heard it (the quick
    // settings' phone toggle shows the same)
    QtObject {
        id: phone
        property bool connected: false
        property int level: -1
        readonly property bool known: connected && level >= 0
        readonly property bool on: sources.wants("phonebattery")
        onOnChanged: if (on) ask()
        function ask() {
            phoneDBus.typedCall("Connected", [], function (c) { phone.connected = c }, function () { phone.connected = false })
            phoneDBus.typedCall("BatteryLevel", [], function (l) { phone.level = l }, function () { phone.level = -1 })
        }
    }
    DBusInterface {
        id: phoneDBus
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
        signalsEnabled: phone.on
        function rcConnectedChanged(connected: bool) {
            if (phone.on)
                phone.connected = connected
        }
        function rcBatteryChanged(level: int, charging: bool) {
            if (phone.on)
                phone.level = level
        }
    }

    // the weather the phone sent (asteroid-btsyncd / eos-weather in dconf
    // /org/asteroidos/weather): the extended forecast when there is one (the
    // current temperature, today's low and high, UV, chance of rain, air
    // quality, the sun times), else the five days of the old characteristics
    // (today's high stands for the temperature)
    QtObject {
        id: wx
        property bool known: false
        property real cur: 0
        property real lo: 0
        property real hi: 0
        property int code: 0
        property real uv: -1
        property real pop: -1
        property real aqi: -1
        property string city: ""
        property var today: null
        property var tomorrow: null
        readonly property bool on: sources.wants("weather") || sources.wants("uv") || sources.wants("precipitation")
                                   || sources.wants("aqi") || sources.wants("sun")
        onOnChanged: if (on) take()
        function take() {
            var ext = C.parseExtended(extended.value)
            var now = new Date(sources.now.getTime())
            var d0 = ext ? C.dayOf(ext, now) : null
            today = d0
            tomorrow = ext ? C.dayOf(ext, C.startOfDay(now, 1)) : null
            city = cityName.value
            uv = -1; pop = -1; aqi = -1
            if (ext && ext.now && ext.now.c !== undefined) {
                known = true
                cur = ext.now.c
                code = ext.now.code || 0
                lo = d0 && d0.lo !== undefined ? d0.lo : cur
                hi = d0 && d0.hi !== undefined ? d0.hi : cur
                uv = ext.now.uv !== undefined ? ext.now.uv : (d0 && d0.uv !== undefined ? d0.uv : -1)
                pop = ext.now.pop !== undefined ? ext.now.pop : (d0 && d0.pop !== undefined ? d0.pop : -1)
                aqi = ext.aqi && ext.aqi.index !== undefined ? ext.aqi.index : -1
                return
            }
            // the phone sends five days from the day of its last update
            var s0 = new Date(day0Stamp.value * 1000)
            s0.setHours(0, 0, 0, 0)
            var t0 = new Date(sources.now.getTime())
            t0.setHours(0, 0, 0, 0)
            var offset = Math.round((t0 - s0) / 86400000)
            var day = offset >= 0 && offset < 5 ? weatherDays.itemAt(offset) : null
            known = day0Stamp.value > 0 && day !== null
            if (!known)
                return
            hi = day.high - 273
            lo = day.low - 273
            cur = hi
            code = day.owm
        }
    }
    Repeater {
        id: weatherDays
        model: 5
        delegate: Item {
            readonly property int high: highValue.value
            readonly property int low: lowValue.value
            readonly property int owm: idValue.value
            ConfigurationValue { id: highValue; key: "/org/asteroidos/weather/day" + index + "/max-temp"; defaultValue: 273; onValueChanged: if (wx.on) wx.take() }
            ConfigurationValue { id: lowValue; key: "/org/asteroidos/weather/day" + index + "/min-temp"; defaultValue: 273; onValueChanged: if (wx.on) wx.take() }
            ConfigurationValue { id: idValue; key: "/org/asteroidos/weather/day" + index + "/id"; defaultValue: 0; onValueChanged: if (wx.on) wx.take() }
        }
    }
    ConfigurationValue { id: day0Stamp; key: "/org/asteroidos/weather/timestamp-day0"; defaultValue: 0; onValueChanged: if (wx.on) wx.take() }
    ConfigurationValue { id: extended; key: "/org/asteroidos/weather/extended"; defaultValue: ""; onValueChanged: if (wx.on) wx.take() }
    ConfigurationValue { id: fahrenheit; key: "/org/asteroidos/settings/use-fahrenheit"; defaultValue: false }
    ConfigurationValue { id: cityName; key: "/org/asteroidos/weather/city-name"; defaultValue: "" }
    // the phone's position (asteroid-btsyncd), for the sun when the forecast has no sun times; 999: unknown
    ConfigurationValue { id: latitude; key: "/org/asteroidos/weather/phone-location/latitude"; defaultValue: 999 }
    ConfigurationValue { id: longitude; key: "/org/asteroidos/weather/phone-location/longitude"; defaultValue: 999 }

    function weatherInfo() {
        var nodata = "- -"
        if (!wx.known)
            return base({ short: nodata, text: nodata, title: wx.city, icon: "ios-cloud-outline", known: false })
        // stock: the current temperature, the ring its place between today's low and high in the
        // ramp colours, 'N° Condition' for a long slot
        var tp = C.degrees(wx.cur, fahrenheit.value)
        var progress = wx.hi > wx.lo ? C.clamp01((wx.cur - wx.lo) / (wx.hi - wx.lo)) : -1
        var word = conditionWord(wx.code)
        return base({ type: progress >= 0 ? "ranged" : "short", text: tp, short: tp, title: wx.city,
                      long: word !== "" ? tp + " " + word : tp, icon: IconTools.getIconName(wx.code),
                      progress: progress, color: progress >= 0 ? C.ramp(progress) : "" })
    }
    function conditionWord(code) {
        switch (C.conditionKey(code)) {
        //% "Thunderstorm"
        case "thunderstorm": return qsTrId("id-comp-wx-thunderstorm")
        //% "Drizzle"
        case "drizzle": return qsTrId("id-comp-wx-drizzle")
        //% "Rain"
        case "rain": return qsTrId("id-comp-wx-rain")
        //% "Snow"
        case "snow": return qsTrId("id-comp-wx-snow")
        //% "Fog"
        case "fog": return qsTrId("id-comp-wx-fog")
        //% "Clear"
        case "clear": return qsTrId("id-comp-wx-clear")
        //% "Partly cloudy"
        case "partlycloudy": return qsTrId("id-comp-wx-partly-cloudy")
        //% "Cloudy"
        case "cloudy": return qsTrId("id-comp-wx-cloudy")
        }
        return ""
    }
    function uvWord(uv) {
        switch (C.uvLabel(uv)) {
        //% "Low"
        case "low": return qsTrId("id-comp-low")
        //% "Mod."
        case "moderate": return qsTrId("id-comp-mod")
        //% "High"
        case "high": return qsTrId("id-comp-high")
        }
        //% "Extreme"
        return qsTrId("id-comp-extreme")
    }
    function precipWord(pop) {
        switch (C.precipLabel(pop)) {
        //% "None"
        case "none": return qsTrId("id-comp-none")
        //% "Slight"
        case "slight": return qsTrId("id-comp-slight")
        //% "Chance"
        case "chance": return qsTrId("id-comp-chance")
        //% "Likely"
        case "likely": return qsTrId("id-comp-likely")
        }
        //% "Rain"
        return qsTrId("id-comp-wx-rain")
    }
    function aqiWord(index) {
        switch (C.aqiLabel(index)) {
        //% "Good"
        case "good": return qsTrId("id-comp-aqi-good")
        //% "Mod."
        case "moderate": return qsTrId("id-comp-mod")
        //% "Unhealthy"
        case "unhealthy": return qsTrId("id-comp-aqi-unhealthy")
        //% "V. Unhealthy"
        case "veryunhealthy": return qsTrId("id-comp-aqi-very-unhealthy")
        }
        //% "Hazardous"
        return qsTrId("id-comp-aqi-hazardous")
    }
    function moonWord(phase) {
        switch (phase) {
        //% "New moon"
        case 0: return qsTrId("id-comp-moon-new")
        //% "Waxing crescent"
        case 1: return qsTrId("id-comp-moon-waxing-crescent")
        //% "First quarter"
        case 2: return qsTrId("id-comp-moon-first-quarter")
        //% "Waxing gibbous"
        case 3: return qsTrId("id-comp-moon-waxing-gibbous")
        //% "Full moon"
        case 4: return qsTrId("id-comp-moon-full")
        //% "Waning gibbous"
        case 5: return qsTrId("id-comp-moon-waning-gibbous")
        //% "Last quarter"
        case 6: return qsTrId("id-comp-moon-last-quarter")
        }
        //% "Waning crescent"
        return qsTrId("id-comp-moon-waning-crescent")
    }
    // the next sunrise or sunset, from the forecast's times, else the formula at the phone's position
    function sunNext() {
        var lat = Math.abs(latitude.value) <= 90 ? latitude.value : null
        var lon = Math.abs(longitude.value) <= 180 ? longitude.value : null
        return C.nextSun(sources.now, lat, lon, wx.today, wx.tomorrow)
    }

    // the next event of the next 24 hours (the phone's calendar, which
    // asteroid-btsyncd keeps in the calendar database), as the agenda tile
    QtObject {
        id: agenda
        // the occurrence: { start, end, title, allDay }, null when there is none
        property var ev: null
        property var endsAt: null
        readonly property bool on: sources.wants("nextevent")
        onOnChanged: if (on) take()
        function take() {
            var m = agendaLoader.item
            var now = sources.now
            var list = []
            for (var i = 0; m && i < m.count; i++) {
                var o = m.occurrence(i)
                if (o)
                    list.push(o)
            }
            ev = C.pickNext(now, list)
            endsAt = ev ? ev.end : null
        }
    }
    // the agenda is kept while a slot shows the next event (a query at every
    // screen on would be slower); read only while active
    Loader {
        id: agendaLoader
        active: sources.demand.nextevent === true
        source: "AgendaSource.qml"
        onLoaded: {
            item.now = sources.now
            if (agenda.on)
                agenda.take()
        }
    }
    Binding { target: agendaLoader.item; property: "now"; value: sources.now; when: agendaLoader.item !== null }
    Connections {
        target: agendaLoader.item
        function onUpdated() { if (agenda.on) agenda.take() }
    }

    // the next alarm and the running countdown (timed's alarms, as the alarm
    // and timer tiles read them), kept while a slot shows one of them
    Loader {
        id: clockLoader
        active: sources.demand.alarm === true || sources.demand.timer === true
        source: "ClockSource.qml"
        onLoaded: {
            item.now = sources.now
            if (sources.active)
                item.refresh()
        }
    }
    Binding { target: clockLoader.item; property: "active"; value: sources.active; when: clockLoader.item !== null }
    Binding { target: clockLoader.item; property: "now"; value: sources.now; when: clockLoader.item !== null }

    // what plays (the phone's player or the watch's)
    Loader {
        id: mediaLoader
        active: sources.demand.media === true
        source: "MediaSource.qml"
    }
    Binding { target: mediaLoader.item; property: "active"; value: sources.active; when: mediaLoader.item !== null }

    // the stopwatch app's state in dconf (it writes these: since boot is not needed, the wall clock is
    // enough for a face): the time the running lap started (ms, 0 stopped) and what ran before it (ms)
    ConfigurationValue { id: swStarted; key: "/org/asteroidos/stopwatch/started-at"; defaultValue: 0 }
    ConfigurationValue { id: swElapsed; key: "/org/asteroidos/stopwatch/elapsed"; defaultValue: 0 }
    function stopwatchMs() {
        return Number(swElapsed.value) + (Number(swStarted.value) > 0 ? Math.max(0, sources.now.getTime() - Number(swStarted.value)) : 0)
    }

    // an app of the launcher by its desktop file name (without .desktop), or null
    function appItem(name) {
        var m = sources.apps
        for (var i = 0; m && i < m.itemCount; i++) {
            var it = m.get(i)
            if (it && it.object)
                it = it.object
            if (it && it.filePath && it.filePath.split("/").pop() === name + ".desktop")
                return it
        }
        return null
    }

    // an event that ended, a new day: looked at once a minute, when the face
    // draws its minute anyway (the wall clock may tick every second)
    readonly property real minute: Math.floor(now.getTime() / 60000)
    onMinuteChanged: {
        if (agenda.on)
            agenda.take()
        if (wx.on)
            wx.take()
        if (clockLoader.item && sources.active)
            clockLoader.item.refresh()
    }
}
