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

/*
 * The watch face complications, as Wear OS's: a face names its slots (an
 * Item with objectName "eosComplication", its slotId, shape and default
 * data source; see ComplicationView.qml) and the launcher draws the data
 * source chosen for each slot in it, the same on every face. The choice
 * is per face and slot, in dconf
 * /org/asteroidos/watchface/complications/<face file name> as a list of
 * "slotId=source" strings (missing: the face's default; "empty": nothing).
 *
 * Power, as the tiles: the sources read and follow their data only while
 * "active" (the face, or the face editor, on the awake screen) and only
 * the sources a slot shows; nothing here has a timer. While inactive every
 * value stays as it was, so nothing on the face changes with the screen
 * off. In always-on only the date shows (ComplicationView): the sensor
 * hub's layout keeps the always-on picture until the next midnight, and
 * the date is the one complication that does not change before then.
 */
Item {
    id: sources
    visible: false

    property bool active: false
    // from the home screen: always-on, nightstand, 12 h
    property bool ambient: false
    property bool nightstand: false
    property bool use12h: false
    // the wall clock of the faces (the date, the next event's end)
    property date now: new Date()

    // the data sources, in the order of the face editor's list
    readonly property var all: ["empty", "date", "steps", "heartrate", "battery", "phonebattery", "weather", "nextevent"]
    function name(id) {
        switch (id) {
        //% "Empty"
        case "empty": return qsTrId("id-comp-empty")
        //% "Day and date"
        case "date": return qsTrId("id-comp-date")
        //% "Steps"
        case "steps": return qsTrId("id-tile-steps")
        //% "Heart rate"
        case "heartrate": return qsTrId("id-tile-heart-rate")
        //% "Watch battery"
        case "battery": return qsTrId("id-comp-battery")
        //% "Phone battery"
        case "phonebattery": return qsTrId("id-comp-phone-battery")
        //% "Weather"
        case "weather": return qsTrId("id-tile-weather")
        //% "Next event"
        case "nextevent": return qsTrId("id-comp-next-event")
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
                return all.indexOf(src) >= 0 ? src : fallback
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

    // which sources the views show: only those read
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
                d[views[i].source] = true
        if (JSON.stringify(d) !== JSON.stringify(demand))
            demand = d
    }
    function wants(s) { return active && demand[s] === true }

    // what a source shows: text (a line's text), short (what fits in a round
    // slot), icon, progress (0..1 for a ring, -1 none), title (a long slot's
    // first line), known (false: no data, shown as "--")
    function info(id) {
        switch (id) {
        case "date": {
            var d = sources.now
            return { text: d.toLocaleString(Qt.locale(), "ddd d"), short: String(d.getDate()),
                     title: d.toLocaleString(Qt.locale(), "dddd"), icon: "ios-calendar-outline", progress: -1, known: true }
        }
        case "steps":
            var count = steps.known ? steps.count.toLocaleString(Qt.locale(), "f", 0) : "--"
            return { text: count, short: count,
                     //% "Steps"
                     title: qsTrId("id-tile-steps"), icon: "ios-walk",
                     progress: steps.known && steps.goal > 0 ? Math.min(1, steps.count / steps.goal) : -1,
                     known: steps.known }
        case "heartrate":
            var bpm = heart.known ? String(heart.bpm) : "--"
            return { text: bpm, short: bpm, title: qsTrId("id-tile-heart-rate"),
                     icon: "ios-heart", progress: -1, known: heart.known }
        case "battery":
            var pc = battery.percent >= 0 ? battery.percent + "%" : "--"
            return { text: pc, short: pc, title: name("battery"),
                     icon: battery.charging ? "ios-battery-charging" : battery.percent >= 0 && battery.percent <= 15 ? "ios-battery-dead" : "ios-battery-full",
                     progress: battery.percent >= 0 ? battery.percent / 100 : -1, known: battery.percent >= 0 }
        case "phonebattery":
            var lv = phone.known ? phone.level + "%" : "--"
            return { text: lv, short: lv, title: name("phonebattery"),
                     icon: "ios-phone-portrait", progress: phone.known ? phone.level / 100 : -1, known: phone.known }
        case "weather":
            var tp = weather.known ? weather.temp : "--"
            return { text: tp, short: tp, title: weather.city, icon: weather.known ? weather.icon : "ios-cloud-outline",
                     progress: -1, known: weather.known }
        case "nextevent":
            return { text: agenda.known ? agenda.when + " " + agenda.label : "--",
                     // a round slot: when only, as stock's short next event
                     short: agenda.known ? agenda.when : "--",
                     //% "No events"
                     title: agenda.known ? agenda.when : qsTrId("id-comp-no-events"),
                     long: agenda.known ? agenda.label : "",
                     icon: "ios-calendar-outline", progress: -1, known: agenda.known }
        }
        return { text: "", short: "", title: "", icon: "", progress: -1, known: false }
    }

    // where a tap on a slot goes, as the stock complications open their app
    function open(id, fromItem) {
        switch (id) {
        case "steps":
            desktop.launchByName("asteroid-health", fromItem)
            break
        case "heartrate":
            openRequest.value = "heartrate@" + Date.now()
            desktop.launchByName("asteroid-health", fromItem)
            break
        case "weather":
            desktop.launchByName("asteroid-weather", fromItem)
            break
        case "date":
        case "nextevent":
            desktop.launchByName("asteroid-calendar", fromItem)
            break
        case "battery":
        case "phonebattery":
            desktop.launchByName("asteroid-settings", fromItem)
            break
        }
    }
    ConfigurationValue { id: openRequest; key: "/org/asteroidos/health/ui/open"; defaultValue: "" }

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

    // today's forecast the phone sent (asteroid-btsyncd / eos-weather in
    // dconf /org/asteroidos/weather): its high, as the weather tile
    QtObject {
        id: weather
        property bool known: false
        property string temp: ""
        property string icon: ""
        property string city: ""
        readonly property bool on: sources.wants("weather")
        onOnChanged: if (on) take()
        function take() {
            // the phone sends five days from the day of its last update
            var d0 = new Date(day0Stamp.value * 1000)
            d0.setHours(0, 0, 0, 0)
            var today = new Date()
            today.setHours(0, 0, 0, 0)
            var offset = Math.round((today - d0) / 86400000)
            var day = offset >= 0 && offset < 5 ? weatherDays.itemAt(offset) : null
            known = day0Stamp.value > 0 && day !== null
            if (!known)
                return
            var c = day.high - 273
            temp = (fahrenheit.value ? Math.round(c * 9 / 5 + 32) : Math.round(c)) + "°"
            icon = IconTools.getIconName(day.owm)
            city = cityName.value
        }
    }
    Repeater {
        id: weatherDays
        model: 5
        delegate: Item {
            readonly property int high: highValue.value
            readonly property int owm: idValue.value
            ConfigurationValue { id: highValue; key: "/org/asteroidos/weather/day" + index + "/max-temp"; defaultValue: 273; onValueChanged: if (weather.on) weather.take() }
            ConfigurationValue { id: idValue; key: "/org/asteroidos/weather/day" + index + "/id"; defaultValue: 0; onValueChanged: if (weather.on) weather.take() }
        }
    }
    ConfigurationValue { id: day0Stamp; key: "/org/asteroidos/weather/timestamp-day0"; defaultValue: 0; onValueChanged: if (weather.on) weather.take() }
    ConfigurationValue { id: fahrenheit; key: "/org/asteroidos/settings/use-fahrenheit"; defaultValue: false; onValueChanged: if (weather.on) weather.take() }
    ConfigurationValue { id: cityName; key: "/org/asteroidos/weather/city-name"; defaultValue: "" }

    // the next event of today and tomorrow that has not ended (the phone's
    // calendar, which asteroid-btsyncd keeps in the calendar database), as
    // the agenda tile
    QtObject {
        id: agenda
        property bool known: false
        property string when: ""
        property string label: ""
        property var endsAt: null
        readonly property bool on: sources.wants("nextevent")
        onOnChanged: if (on) take()
        function take() {
            var m = agendaLoader.item
            var now = new Date()
            var found = null
            for (var i = 0; m && i < m.count; i++) {
                var o = m.occurrence(i)
                if (o && o.end > now && (found === null || o.start < found.start))
                    found = o
            }
            known = found !== null
            endsAt = found ? found.end : null
            if (!found)
                return
            label = found.title
            var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
            //% "All day"
            when = found.allDay ? qsTrId("id-tile-all-day")
                                : found.start.toLocaleString(Qt.locale(), (found.start >= tomorrow ? "ddd " : "")
                                                             + (sources.use12h ? "h:mm AP" : "HH:mm"))
        }
    }
    // the agenda is kept while a slot shows the next event (a query at every
    // screen on would be slower); read only while active
    Loader {
        id: agendaLoader
        active: sources.demand.nextevent === true
        source: "AgendaSource.qml"
        onLoaded: if (agenda.on) agenda.take()
    }
    Connections {
        target: agendaLoader.item
        function onUpdated() { if (agenda.on) agenda.take() }
    }
    // an event that ended, a new day: looked at once a minute, when the face
    // draws its minute anyway (the wall clock may tick every second)
    readonly property real minute: Math.floor(now.getTime() / 60000)
    onMinuteChanged: {
        if (agenda.on && agenda.endsAt !== null && now >= agenda.endsAt)
            agenda.take()
        if (weather.on)
            weather.take()
    }
}
