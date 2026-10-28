/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import Nemo.DBus
import Nemo.Mce
import Amber.Mpris
import Connman
import org.nemomobile.calendar
import org.nemomobile.lipstick
import org.asteroid.controls
import org.asteroid.utils
import org.asteroid.settings
import org.asteroid.launcher
import "../desktop.js" as Desktop

/*
 * What the assistant does for an intent (asteroid-assistant's Result), the
 * way the launcher's own tiles and quick settings do it: countdown alarms
 * as the timer tile, nemo alarms as the alarm clock, a calendar event with a
 * reminder as the agenda, mce/dconf/connman/bluez as quick settings, MPRIS
 * as the media tile, asteroid-btsyncd for find my phone, the phone's
 * battery and replies, sensorlogd's logs as the health tiles, the weather
 * keys as the weather tile.
 *
 * run(intent, slots, transcript, done): done(card) with the card the
 * overlay shows: { title, text, icon, accent, chips: [{ label, icon, run }] },
 * or { close: true, then: function } for intents that open an application
 * (the overlay goes, then the app starts).
 */
Item {
    id: actions
    visible: false

    // strings: the translation if there is one, else the English text
    function L(id, en) {
        var s = qsTrId(id)
        return (s === id || s === "") ? en : s
    }

    ConfigurationValue { id: use12H; key: "/org/asteroidos/settings/use-12h-format"; defaultValue: false }
    ConfigurationValue { id: fahrenheit; key: "/org/asteroidos/settings/use-fahrenheit"; defaultValue: false }
    ConfigurationValue { id: doNotDisturb; key: "/org/asteroidos/notifications/do-not-disturb"; defaultValue: false }
    ConfigurationValue { id: lastTimer; key: "/org/asteroidos/timer/last-timer-duration"; defaultValue: 300 }
    ConfigurationValue { id: stepsGoal; key: "/org/asteroidos/ux/steps-goal"; defaultValue: 10000 }
    ConfigurationValue { id: city; key: "/org/asteroidos/weather/city-name"; defaultValue: "" }
    ConfigurationValue { id: day0Stamp; key: "/org/asteroidos/weather/timestamp-day0"; defaultValue: 0 }
    ConfigurationValue { id: currentTemp; key: "/org/asteroidos/weather/current-temp"; defaultValue: 0 }

    AlarmsModel { id: countdowns; onlyCountdown: true }
    AlarmsModel { id: alarms }
    MceBatteryLevel { id: battery }
    MceChargerType { id: charger }
    DisplaySettings { id: display }
    NetworkTechnology { id: wifi; path: "/net/connman/technology/wifi" }
    BluetoothStatus { id: bluetooth }
    MprisController { id: mpris }
    NotificationListModel { id: notifications }
    HealthLog { id: heartLog; sensor: "heartrateMonitor"; buckets: 24; active: false }
    HealthLog { id: stepLog; sensor: "stepCounter"; buckets: 24; active: false }

    DBusInterface {
        id: btsyncd
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/notifications"
        iface: "org.asteroidos.btsyncd.Notifications"
    }
    DBusInterface {
        id: phone
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
    }

    /* ---- helpers -------------------------------------------------------- */

    function clock(h, m) {
        var d = new Date(2000, 0, 1, h, m)
        return Qt.formatTime(d, use12H.value ? "h:mm AP" : "HH:mm")
    }
    function dayWord(when) {
        var now = new Date()
        var a = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var b = new Date(when.getFullYear(), when.getMonth(), when.getDate())
        var days = Math.round((b - a) / 86400000)
        if (days === 0) return L("id-asst-today", "today")
        if (days === 1) return L("id-asst-tomorrow", "tomorrow")
        return L("id-asst-on-day", "on %1").arg(Qt.locale("en_GB").dayName(b.getDay(), Locale.LongFormat))
    }
    function minutesText(s) {
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
        var p = []
        if (h) p.push(h === 1 ? L("id-asst-1-hour", "1 hour") : L("id-asst-n-hours", "%1 hours").arg(h))
        if (m) p.push(m === 1 ? L("id-asst-1-minute", "1 minute") : L("id-asst-n-minutes", "%1 minutes").arg(m))
        if (sec || p.length === 0) p.push(sec === 1 ? L("id-asst-1-second", "1 second") : L("id-asst-n-seconds", "%1 seconds").arg(sec))
        return p.join(" ")
    }
    function countdownClock(s) {
        var m = Math.floor(s / 60), sec = s % 60
        if (m >= 60)
            return Math.floor(m / 60) + ":" + ("0" + (m % 60)).slice(-2) + ":" + ("0" + sec).slice(-2)
        return m + ":" + ("0" + sec).slice(-2)
    }
    function temp(kelvin) {
        var c = kelvin - 273
        return Math.round(fahrenheit.value ? c * 9 / 5 + 32 : c) + "°"
    }
    function condition(id) {
        if (id >= 200 && id < 300) return L("id-asst-w-thunder", "thunderstorms")
        if (id >= 300 && id < 400) return L("id-asst-w-drizzle", "drizzle")
        if (id === 511) return L("id-asst-w-freezing", "freezing rain")
        if (id >= 520 && id < 600) return L("id-asst-w-showers", "showers")
        if (id >= 500 && id < 600) return L("id-asst-w-rain", "rain")
        if (id >= 600 && id < 700) return L("id-asst-w-snow", "snow")
        if (id >= 700 && id < 800) return L("id-asst-w-fog", "fog")
        if (id === 800) return L("id-asst-w-clear", "clear skies")
        if (id === 801 || id === 802) return L("id-asst-w-partly", "some clouds")
        if (id > 802 && id < 900) return L("id-asst-w-cloudy", "clouds")
        return ""
    }
    function card(icon, title, text, chips, accent) {
        return { icon: icon, title: title || "", text: text || "", chips: chips || [], accent: accent || "#a8c7fa" }
    }
    function openApp(name, onDone) {
        onDone({ close: true, then: function () {
            if (typeof Desktop !== "undefined" && Desktop.desktop)
                Desktop.desktop.launchByName(name, null)
        } })
    }
    function chipOpen(label, name) {
        return { label: label, icon: "", run: function (done) { openApp(name, done) } }
    }
    function forEachAlarm(model, f) {
        for (var i = 0; i < model.rowCount(); i++) {
            var a = model.data(model.index(i, 0), 0x0100)
            if (a) f(a)
        }
    }
    function nextTrigger(a) {
        var now = new Date()
        if (a.triggerTime > now / 1000)
            return new Date(a.triggerTime * 1000)
        var t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), a.hour, a.minute)
        if (t <= now) t.setDate(t.getDate() + 1)
        return t
    }

    /* ---- the intents ---------------------------------------------------- */

    function run(intent, slots, transcript, done) {
        var s = slots || {}
        switch (intent) {
        case "timer.set": return timerSet(s.seconds, s.label, done)
        case "timer.ask": return done(card("ios-timer-outline", "", L("id-asst-timer-how-long", "For how long?"),
                                       [60, 300, 600].map(function (sec) {
                                           return { label: minutesText(sec), run: function (d) { timerSet(sec, "", d) } }
                                       }), "#c58af9"))
        case "timer.cancel": return timerCancel(done)
        case "timer.query": return timerQuery(done)
        case "alarm.set": return alarmSet(s, done)
        case "alarm.ask": return done(card("ios-alarm-outline", "", L("id-asst-alarm-when", "For what time? Say, for example, \"Set an alarm for 7 AM\"."),
                                       [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
        case "alarm.cancel": return alarmCancel(s, done)
        case "alarm.query": return alarmQuery(done)
        case "stopwatch.start": return openApp("asteroid-stopwatch", done)
        case "reminder.set": return reminderSet(s.text, new Date(s.at * 1000), done)
        case "reminder.ask": return reminderAsk(s.text, done)
        case "app.open": return openApp(s.app, done)
        case "app.unknown": return done(card("ios-apps-outline", "", L("id-asst-no-app", "I can't find an app called %1 on your watch.").arg(s.name)))
        case "weather.query": return weather(s, done)
        case "battery.query": return batteryQuery(s.device, done)
        case "health.heartrate": return heartRate(s.measure, done)
        case "health.steps": return steps(done)
        case "dnd.set":
            doNotDisturb.value = !!s.on
            return done(card(s.on ? "ios-moon" : "ios-moon-outline", "",
                             s.on ? L("id-asst-dnd-on", "Do Not Disturb is on.") : L("id-asst-dnd-off", "Do Not Disturb is off.")))
        case "dnd.query":
            return done(card(doNotDisturb.value ? "ios-moon" : "ios-moon-outline", "",
                             doNotDisturb.value ? L("id-asst-dnd-on", "Do Not Disturb is on.") : L("id-asst-dnd-off", "Do Not Disturb is off.")))
        case "brightness.set": return brightness(s, done)
        case "flashlight.on": return openApp("asteroid-flashlight", done)
        case "phone.find": return findPhone(done)
        case "media.play": case "media.pause": case "media.next": case "media.previous": return media(intent, s, done)
        case "volume.set": return volume(s, done)
        case "wifi.set":
            wifi.powered = !!s.on
            return done(card(s.on ? "ios-wifi" : "ios-wifi-outline", "",
                             s.on ? L("id-asst-wifi-on", "Turning Wi-Fi on.") : L("id-asst-wifi-off", "Wi-Fi is off.")))
        case "wifi.query":
            return done(card(wifi.powered ? "ios-wifi" : "ios-wifi-outline", "",
                             !wifi.powered ? L("id-asst-wifi-is-off", "Wi-Fi is off.")
                             : wifi.connected ? L("id-asst-wifi-connected", "Wi-Fi is on and connected.")
                                              : L("id-asst-wifi-is-on", "Wi-Fi is on, not connected.")))
        case "bluetooth.set": return bluetoothSet(s.on, done)
        case "bluetooth.query":
            return done(card("ios-bluetooth", "",
                             !bluetooth.powered ? L("id-asst-bt-is-off", "Bluetooth is off.")
                             : bluetooth.connected ? L("id-asst-bt-connected", "Bluetooth is on and your phone is connected.")
                                                   : L("id-asst-bt-is-on", "Bluetooth is on.")))
        case "notification.reply": return reply(s.text, done)
        default:
            return done(card("ios-help-circle-outline", "", L("id-asst-cannot", "Sorry, I can't do that yet.")))
        }
    }

    function timerSet(seconds, label, done) {
        if (!seconds || seconds <= 0)
            return run("timer.ask", {}, "", done)
        // the same countdown alarm as the timer tile and asteroid-timer
        var a = countdowns.createAlarm()
        a.countdown = true
        a.second = seconds - 1
        a.title = label ? label.charAt(0).toUpperCase() + label.slice(1)
                        : new Date(seconds * 1000).toISOString().slice(11, 19)
        a.enabled = true
        a.save()
        lastTimer.value = seconds
        var ends = new Date(Date.now() + seconds * 1000)
        var text = (label ? L("id-asst-timer-label", "%1 timer, %2, starting now.").arg(label.charAt(0).toUpperCase() + label.slice(1))
                          : L("id-asst-timer-set", "%2, starting now.")).arg(minutesText(seconds))
        text = text.charAt(0).toUpperCase() + text.slice(1)
        done(card("ios-timer-outline", countdownClock(seconds), text + " " + L("id-asst-timer-ends", "It ends at %1.").arg(clock(ends.getHours(), ends.getMinutes())),
                  [chipOpen(L("id-asst-open-timer", "Open Timer"), "asteroid-timer")], "#c58af9"))
    }

    function runningCountdowns() {
        var list = []
        forEachAlarm(countdowns, function (a) { if (a.enabled && a.triggerTime > Date.now() / 1000) list.push(a) })
        return list
    }
    function timerCancel(done) {
        var list = runningCountdowns()
        if (list.length === 0)
            return done(card("ios-timer-outline", "", L("id-asst-no-timers", "You don't have any timers running.")))
        for (var i = 0; i < list.length; i++)
            list[i].deleteAlarm()
        done(card("ios-timer-outline", "", list.length === 1 ? L("id-asst-timer-cancelled", "Timer cancelled.")
                                                            : L("id-asst-timers-cancelled", "%1 timers cancelled.").arg(list.length)))
    }
    function timerQuery(done) {
        var list = runningCountdowns()
        if (list.length === 0)
            return done(card("ios-timer-outline", "", L("id-asst-no-timers", "You don't have any timers running.")))
        list.sort(function (x, y) { return x.triggerTime - y.triggerTime })
        var left = Math.max(0, Math.round(list[0].triggerTime - Date.now() / 1000))
        var text = left < 90 ? L("id-asst-left-s", "%1 left.").arg(minutesText(left))
                             : L("id-asst-left-m", "About %1 left.").arg(minutesText(Math.round(left / 60) * 60))
        done(card("ios-timer-outline", countdownClock(left), text, [chipOpen(L("id-asst-open-timer", "Open Timer"), "asteroid-timer")], "#c58af9"))
    }

    function alarmSet(s, done) {
        if (s.tooFar)
            return done(card("ios-alarm-outline", "", L("id-asst-alarm-24h", "I can set an alarm for the next 24 hours, or one that repeats. Open the alarm clock to choose a day."),
                             [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
        var a = alarms.createAlarm()
        a.hour = s.hour
        a.minute = s.minute
        a.daysOfWeek = s.repeat || ""
        if (s.label)
            a.title = s.label.charAt(0).toUpperCase() + s.label.slice(1)
        a.enabled = true
        a.save()
        var when = new Date(s.at * 1000)
        var t = clock(s.hour, s.minute)
        var text
        if (s.repeat === "mtwTfsS") text = L("id-asst-alarm-daily", "Alarm set for %1 every day.").arg(t)
        else if (s.repeat === "mtwTf") text = L("id-asst-alarm-weekdays", "Alarm set for %1 on weekdays.").arg(t)
        else if (s.repeat === "sS") text = L("id-asst-alarm-weekends", "Alarm set for %1 at weekends.").arg(t)
        else if (s.repeat) text = L("id-asst-alarm-repeat", "Repeating alarm set for %1.").arg(t)
        else if (s.relative) text = L("id-asst-alarm-in", "Alarm set for %1, %2 from now.").arg(t).arg(minutesText(s.relative))
        else text = L("id-asst-alarm-set", "Alarm set for %1 %2.").arg(t).arg(dayWord(when))
        done(card("ios-alarm-outline", t, text, [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
    }
    function alarmCancel(s, done) {
        var off = []
        forEachAlarm(alarms, function (a) {
            if (a.countdown || !a.enabled)
                return
            if (s.hour !== undefined) {
                var hourOk = a.hour === s.hour || (!s.ampmKnown && a.hour === (s.hour + 12) % 24)
                if (hourOk && a.minute === s.minute) off.push(a)
            } else {
                off.push(a)
            }
        })
        if (s.hour === undefined && !s.all && off.length > 1) {
            // "cancel my alarm": the next one
            off.sort(function (x, y) { return nextTrigger(x) - nextTrigger(y) })
            off = [off[0]]
        }
        if (off.length === 0)
            return done(card("ios-alarm-outline", "", s.hour !== undefined ? L("id-asst-no-alarm-at", "You don't have an alarm at %1.").arg(clock(s.hour, s.minute))
                                                                          : L("id-asst-no-alarms", "You don't have any alarms on.")))
        for (var i = 0; i < off.length; i++) {
            off[i].enabled = false
            off[i].save()
        }
        done(card("ios-alarm-outline", "", off.length === 1 ? L("id-asst-alarm-off", "Your %1 alarm is off.").arg(clock(off[0].hour, off[0].minute))
                                                           : L("id-asst-alarms-off", "%1 alarms are off.").arg(off.length),
                  [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
    }
    function alarmQuery(done) {
        var on = []
        forEachAlarm(alarms, function (a) { if (!a.countdown && a.enabled) on.push(a) })
        if (on.length === 0)
            return done(card("ios-alarm-outline", "", L("id-asst-no-alarms-set", "You don't have any alarms set."),
                             [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
        on.sort(function (x, y) { return nextTrigger(x) - nextTrigger(y) })
        var next = nextTrigger(on[0])
        var text = L("id-asst-next-alarm", "Your next alarm is at %1 %2.").arg(clock(on[0].hour, on[0].minute)).arg(dayWord(next))
        if (on.length > 1)
            text += " " + L("id-asst-alarms-count", "You have %1 alarms on.").arg(on.length)
        done(card("ios-alarm-outline", clock(on[0].hour, on[0].minute), text,
                  [chipOpen(L("id-asst-open-alarms", "Open Alarms"), "asteroid-alarmclock")], "#f6aea9"))
    }

    function reminderSet(text, when, done) {
        // a calendar event with a reminder at its start: the agenda shows it
        // and the alarm presenter rings it (timed, as Calendar alarms)
        var ev = Calendar.createNewEvent()
        ev.displayLabel = text
        ev.description = L("id-asst-reminder-desc", "Reminder from the assistant")
        ev.recur = CalendarEvent.RecurOnce
        ev.reminder = 0
        ev.setStartTime(when, CalendarEvent.SpecLocalZone)
        ev.setEndTime(new Date(when.getTime() + 15 * 60000), CalendarEvent.SpecLocalZone)
        ev.allDay = false
        ev.calendarUid = Calendar.defaultNotebook
        ev.save()
        done(card("ios-notifications-outline", clock(when.getHours(), when.getMinutes()),
                  L("id-asst-reminder-set", "OK, I'll remind you %1 at %2: %3.").arg(dayWord(when)).arg(clock(when.getHours(), when.getMinutes())).arg(text),
                  [chipOpen(L("id-asst-open-agenda", "Open Agenda"), "asteroid-calendar")], "#7fcfff"))
    }
    function reminderAsk(text, done) {
        if (!text)
            return done(card("ios-notifications-outline", "", L("id-asst-reminder-what", "What should I remind you about? Say, for example, \"Remind me to call Mum at 5 PM\".")))
        var now = new Date()
        var inHour = new Date(now.getTime() + 3600000)
        var evening = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 18, 0)
        if (evening <= now) evening.setDate(evening.getDate() + 1)
        var morning = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 9, 0)
        done(card("ios-notifications-outline", "", L("id-asst-reminder-when", "When should I remind you to %1?").arg(text.charAt(0).toLowerCase() + text.slice(1)),
                  [{ label: L("id-asst-in-1-hour", "In 1 hour"), run: function (d) { reminderSet(text, inHour, d) } },
                   { label: L("id-asst-at-6pm", "At %1").arg(clock(18, 0)), run: function (d) { reminderSet(text, evening, d) } },
                   { label: L("id-asst-tomorrow-9", "Tomorrow"), run: function (d) { reminderSet(text, morning, d) } }], "#7fcfff"))
    }

    function weather(s, done) {
        var day = s.day || 0
        if (!day0Stamp.value)
            return done(card("ios-cloudy-outline", "", L("id-asst-no-weather", "I don't have the weather yet. It comes from your phone, or over Wi-Fi."),
                             [chipOpen(L("id-asst-open-weather", "Open Weather"), "asteroid-weather")], "#8ab4f8"))
        // the forecast's day 0 may be yesterday's
        var d0 = new Date(day0Stamp.value * 1000)
        var today = new Date()
        var shift = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate())
                                - new Date(d0.getFullYear(), d0.getMonth(), d0.getDate())) / 86400000)
        var idx = day + Math.max(0, shift)
        if (idx > 4)
            return done(card("ios-cloudy-outline", "", L("id-asst-weather-far", "I only have the forecast for the next few days.")))
        weatherDay.index = idx
        var c = condition(weatherDay.owm)
        var place = city.value
        var other = s.place && place && s.place.toLowerCase() !== String(place).toLowerCase()
        var when = day === 0 ? L("id-asst-today-cap", "Today") : day === 1 ? L("id-asst-tomorrow-cap", "Tomorrow")
                             : Qt.locale("en_GB").dayName(new Date(today.getTime() + day * 86400000).getDay(), Locale.LongFormat)
        var text
        if (s.kind === "rain" || s.kind === "snow") {
            var wet = s.kind === "rain" ? (weatherDay.owm >= 200 && weatherDay.owm < 600) : (weatherDay.owm >= 600 && weatherDay.owm < 700)
            text = (wet ? (s.kind === "rain" ? L("id-asst-rain-yes", "Yes, %1 looks like %2.") : L("id-asst-snow-yes", "Yes, %1 looks like %2."))
                        : (s.kind === "rain" ? L("id-asst-rain-no", "No rain expected %1: %2.") : L("id-asst-snow-no", "No snow expected %1: %2.")))
                    .arg(day === 0 ? L("id-asst-today", "today") : day === 1 ? L("id-asst-tomorrow", "tomorrow") : when).arg(c)
        } else if (day === 0 && currentTemp.value > 0) {
            text = L("id-asst-weather-now", "It's %1 and %2. Today: %3 to %4.").arg(temp(currentTemp.value)).arg(c)
                   .arg(temp(weatherDay.lo)).arg(temp(weatherDay.hi))
        } else {
            text = L("id-asst-weather-day", "%1: %2, %3 to %4.").arg(when).arg(c).arg(temp(weatherDay.lo)).arg(temp(weatherDay.hi))
        }
        text = text.charAt(0).toUpperCase() + text.slice(1)
        if (other)
            text = L("id-asst-weather-only", "I only have the weather for %1.").arg(place) + " " + text
        done(card("ios-cloudy-outline", (day === 0 && currentTemp.value > 0) ? temp(currentTemp.value) : temp(weatherDay.hi),
                  (place && !other ? place + ". " : "") + text,
                  [chipOpen(L("id-asst-open-weather", "Open Weather"), "asteroid-weather")], "#8ab4f8"))
    }
    Item {
        id: weatherDay
        property int index: 0
        readonly property int owm: owmValue.value
        readonly property int lo: loValue.value
        readonly property int hi: hiValue.value
        ConfigurationValue { id: owmValue; key: "/org/asteroidos/weather/day" + weatherDay.index + "/id"; defaultValue: 0 }
        ConfigurationValue { id: loValue; key: "/org/asteroidos/weather/day" + weatherDay.index + "/min-temp"; defaultValue: 273 }
        ConfigurationValue { id: hiValue; key: "/org/asteroidos/weather/day" + weatherDay.index + "/max-temp"; defaultValue: 273 }
    }

    function batteryQuery(device, done) {
        if (device === "phone") {
            phone.typedCall("Connected", [], function (connected) {
                if (!connected)
                    return done(card("ios-phone-portrait", "", L("id-asst-phone-away", "Your phone isn't connected.")))
                phone.typedCall("BatteryLevel", [], function (level) {
                    phone.typedCall("Charging", [], function (charging) {
                        if (level < 0)
                            return done(card("ios-phone-portrait", "", L("id-asst-phone-battery-unknown", "Your phone hasn't said how charged it is.")))
                        done(card("ios-phone-portrait", level + "%", (charging ? L("id-asst-phone-battery-charging", "Your phone is at %1% and charging.")
                                                                             : L("id-asst-phone-battery", "Your phone is at %1%.")).arg(level)))
                    }, function () { done(card("ios-phone-portrait", level + "%", L("id-asst-phone-battery", "Your phone is at %1%.").arg(level))) })
                }, function () { done(card("ios-phone-portrait", "", L("id-asst-phone-away", "Your phone isn't connected."))) })
            }, function () { done(card("ios-phone-portrait", "", L("id-asst-phone-away", "Your phone isn't connected."))) })
            return
        }
        var p = battery.percent
        var charging = charger.type != MceChargerType.None
        done(card("ios-battery-full", p + "%", (charging ? L("id-asst-battery-charging", "Your watch is at %1% and charging.")
                                                         : L("id-asst-battery", "Your watch is at %1%.")).arg(p), [], "#9be89b"))
    }

    function ago(t) {
        var mins = Math.round((Date.now() - t.getTime()) / 60000)
        if (mins < 2) return L("id-asst-just-now", "just now")
        if (mins < 60) return L("id-asst-mins-ago", "%1 minutes ago").arg(mins)
        var h = Math.round(mins / 60)
        return h === 1 ? L("id-asst-hour-ago", "an hour ago") : L("id-asst-hours-ago", "%1 hours ago").arg(h)
    }
    // sensorlogd's day file is read in a worker thread: the result comes in
    // the log's "changed", or nothing after a while (no file yet)
    property var logWaits: []
    function readLog(log, cb) {
        var waits = logWaits.slice()
        waits.push({ log: log, cb: cb })
        logWaits = waits
        if (log.active)
            log.reload()
        else
            log.active = true
        logTimeout.restart()
    }
    function logRead(log) {
        var rest = []
        var todo = []
        for (var i = 0; i < logWaits.length; i++)
            (logWaits[i].log === log ? todo : rest).push(logWaits[i])
        logWaits = rest
        log.active = false
        for (var j = 0; j < todo.length; j++)
            todo[j].cb()
    }
    Connections { target: heartLog; function onChanged() { actions.logRead(heartLog) } }
    Connections { target: stepLog; function onChanged() { actions.logRead(stepLog) } }
    Timer { id: logTimeout; interval: 1500; onTriggered: { actions.logRead(heartLog); actions.logRead(stepLog) } }

    function heartRate(measure, done) {
        if (measure)
            return openApp("asteroid-hrm", done)
        readLog(heartLog, function () {
            var t = heartLog.lastTime
            var recent = heartLog.hasData && t && (Date.now() - t.getTime()) < 12 * 3600000
            if (!recent)
                return openApp("asteroid-hrm", done)
            done(card("ios-heart", heartLog.lastValue + " " + L("id-asst-bpm", "bpm"),
                      L("id-asst-heart-last", "Your heart rate was %1 beats per minute %2.").arg(heartLog.lastValue).arg(ago(t)),
                      [chipOpen(L("id-asst-measure", "Measure"), "asteroid-hrm")], "#f28b82"))
        })
    }
    function steps(done) {
        readLog(stepLog, function () {
            var n = stepLog.hasData ? stepLog.lastValue : 0
            var goal = stepsGoal.value
            var count = Number(n).toLocaleString(Qt.locale("en_GB"), "f", 0)
            var text = L("id-asst-steps", "You've taken %1 steps today.").arg(count)
            if (goal > 0)
                text += " " + (n >= goal ? L("id-asst-steps-goal-done", "You've reached your goal.")
                                         : L("id-asst-steps-goal", "That's %1% of your goal.").arg(Math.round(100 * n / goal)))
            done(card("ios-walk", count, text, [chipOpen(L("id-asst-open-health", "Open Health"), "asteroid-health")], "#81c995"))
        })
    }

    function brightness(s, done) {
        var v = s.level !== undefined ? s.level : display.brightness + (s.delta || 0)
        v = Math.max(10, Math.min(100, Math.round(v / 10) * 10))
        display.brightness = v
        done(card("ios-sunny", v + "%", L("id-asst-brightness", "Brightness is at %1%.").arg(v)))
    }

    function findPhone(done) {
        btsyncd.typedCall("FindPhone", [{ "type": "b", "value": true }], function (ok) {
            if (!ok)
                return done(card("ios-phone-portrait", "", L("id-asst-phone-away", "Your phone isn't connected.")))
            done(card("ios-phone-portrait", "", L("id-asst-ringing", "Ringing your phone."),
                      [{ label: L("id-asst-stop", "Stop"), run: function (d) {
                          btsyncd.typedCall("FindPhone", [{ "type": "b", "value": false }])
                          d({ close: true })
                      } }], "#a8c7fa"))
        }, function () { done(card("ios-phone-portrait", "", L("id-asst-phone-away", "Your phone isn't connected."))) })
    }

    readonly property bool mediaPresent: mpris.currentService !== "" && mpris.currentService !== undefined
    function media(intent, s, done) {
        if (!mediaPresent)
            return done(card("ios-musical-notes-outline", "", L("id-asst-no-media", "Nothing is playing on your phone."),
                             [chipOpen(L("id-asst-open-music", "Open Music"), "asteroid-music")], "#78d9ec"))
        var title = mpris.metaData && mpris.metaData.title ? mpris.metaData.title : ""
        if (intent === "media.play") {
            if (mpris.canPlay) mpris.play()
            done(card("ios-play", title, s.query ? L("id-asst-play-query", "I can only play what's on your phone, so I've resumed it.")
                                                 : L("id-asst-playing", "Playing."), [], "#78d9ec"))
        } else if (intent === "media.pause") {
            if (mpris.canPause) mpris.pause()
            done(card("ios-pause", title, L("id-asst-paused", "Paused."), [], "#78d9ec"))
        } else if (intent === "media.next") {
            if (mpris.canGoNext) mpris.next()
            done(card("ios-skip-forward", "", L("id-asst-next", "Next track."), [], "#78d9ec"))
        } else {
            if (mpris.canGoPrevious) mpris.previous()
            done(card("ios-skip-backward", "", L("id-asst-previous", "Previous track."), [], "#78d9ec"))
        }
    }
    property real premute: 0.5
    function volume(s, done) {
        if (mediaPresent) {
            // the phone's player, as the music app's crown does
            var v = mpris.volume
            if (s.mute === true) { premute = v; v = 0 }
            else if (s.mute === false) v = premute > 0 ? premute : 0.5
            else if (s.level !== undefined) v = s.level / 100
            else v = v + (s.delta || 0) / 100
            v = Math.max(0, Math.min(1, v))
            mpris.volume = v
            return done(card(v === 0 ? "ios-volume-off" : "ios-volume-high", Math.round(v * 100) + "%",
                             v === 0 ? L("id-asst-muted", "Muted.") : L("id-asst-volume", "Volume %1%.").arg(Math.round(v * 100)), [], "#78d9ec"))
        }
        if (typeof volumeControl === "undefined" || !volumeControl || !volumeControl.maximumVolume)
            return done(card("ios-volume-high", "", L("id-asst-no-media", "Nothing is playing on your phone.")))
        var cur = Math.round(volumeControl.volume / volumeControl.maximumVolume * 100)
        var w = s.mute === true ? 0 : s.mute === false ? 50 : s.level !== undefined ? s.level : cur + (s.delta || 0)
        w = Math.max(0, Math.min(100, w))
        volumeControl.volume = Math.round(w / 100 * volumeControl.maximumVolume)
        done(card(w === 0 ? "ios-volume-off" : "ios-volume-high", w + "%",
                  w === 0 ? L("id-asst-muted", "Muted.") : L("id-asst-volume", "Volume %1%.").arg(w)))
    }

    function bluetoothSet(on, done) {
        if (on) {
            bluetooth.powered = true
            return done(card("ios-bluetooth", "", L("id-asst-bt-on", "Bluetooth is on.")))
        }
        // Wear OS asks: this disconnects the phone (and this assistant's way to it)
        done(card("ios-bluetooth", "", L("id-asst-bt-confirm", "Turn Bluetooth off? Your phone will disconnect."),
                  [{ label: L("id-asst-turn-off", "Turn off"), run: function (d) {
                      bluetooth.powered = false
                      d(card("ios-bluetooth", "", L("id-asst-bt-off", "Bluetooth is off.")))
                  } }]))
    }

    // the newest notification from the phone that takes a reply
    function lastReplyable() {
        var best = null
        for (var i = 0; i < notifications.itemCount; i++) {
            var n = notifications.get(i)
            if (!n || !n.hints)
                continue
            var a = n.hints["x-asteroid-phone-actions"]
            if (!a || String(a).split(",").indexOf("reply") < 0)
                continue
            if (best === null || n.timestamp > best.timestamp)
                best = n
        }
        return best
    }
    function reply(text, done) {
        var n = lastReplyable()
        if (!n)
            return done(card("ios-chatbubbles-outline", "", L("id-asst-no-message", "There's no message to reply to.")))
        if (!text)
            return done(card("ios-chatbubbles-outline", n.summary, L("id-asst-reply-what", "What's the message?")))
        // Wear OS shows the message and sends it on a tap
        done(card("ios-chatbubbles-outline", L("id-asst-reply-to", "Reply to %1").arg(n.summary), text,
                  [{ label: L("id-asst-send", "Send"), icon: "ios-send", run: function (d) {
                      btsyncd.typedCall("Reply", [{ "type": "u", "value": n.replacesId }, { "type": "s", "value": text }],
                                        function (sent) {
                                            d(sent ? { close: true, confirm: L("id-asst-sent", "Sent") }
                                                   : card("ios-chatbubbles-outline", "", L("id-asst-not-sent", "Couldn't send it. Is your phone connected?")))
                                        },
                                        function () { d(card("ios-chatbubbles-outline", "", L("id-asst-not-sent", "Couldn't send it. Is your phone connected?"))) })
                  } },
                   { label: L("id-asst-cancel", "Cancel"), run: function (d) { d({ close: true }) } }], "#a8c7fa"))
    }
}
