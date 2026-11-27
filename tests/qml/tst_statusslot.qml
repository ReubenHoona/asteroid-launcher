// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
//
// The face's bottom row as the home screen builds it (N61-17): src/qml/home/StatusSlot.qml with
// FaceOverlayRow, StatusSources, NotificationIndicator, OngoingFeed and MediaOngoing, the home
// screen's shared ids mocked (grid, desktop, modes, mceChargerType, ongoingRegistry: the setup of the
// W2-launcher-status tst_slot.qml, on the repo mocks):
//  - touch lock to its glyph in the row (s:wet-touch), a status type to its slot, nothing at the top;
//  - a notification to the unread dot (dotWanted, unreadDotWanted), the dot in the middle;
//  - the registry's first entry to the ongoing slot, its tap (activate, launch) and long press (LiveMenu);
//  - ambientIconsKey, the key of the hub's always-on layout (status and ongoing icon, not the dot);
//  - the panel fade (1 - 3 * offset) and the static row of the always-on screen;
//  - a status on and off in one turn leaves nothing drawn (the independent check of L1);
//  - taps on the dot and the status icon never reach the ongoing entry.
// Run beside st/ (the tree as its qrc lays it out in st/qml) under qemu-aarch64 on the image rootfs,
// the icon folder holding the glyphs of WO-61-M1 (newlook-wt/l1h/run.sh, MODE=st).
import QtQuick
import QtTest
import Nemo.Mce
import org.nemomobile.lipstick
import org.asteroid.controls
import LauncherTest
import "st/qml/desktop.js" as Desktop
import "st/qml/home/status.js" as Status

Item {
    id: top
    width: 384; height: 384

    // ---- the home screen's shared ids ----
    QtObject { id: grid
        property int currentHorizontalPos: 0
        property int currentVerticalPos: 0
        property real normalizedHorOffset: 0
        property real normalizedVerOffset: 0
        // the dim a tray leaves on the face after its close cut (N61-24), fading to 0
        property real trayCloseDim: 0 }
    QtObject { id: desktop
        property bool wearLayout: true
        property bool displayAwake: true
        property bool displayAmbient: false
        property bool nightstand: false
        property var streamItem: null
        property var launched: []
        function launchByName(name, from) { var l = launched.slice(); l.push(name); launched = l; return true } }
    QtObject { id: modes
        property bool bedtime: false
        property bool theater: false
        property bool batterySaver: false
        property bool doNotDisturb: false
        property int batteryLevel: 57
        property bool autoSaverOn: false
        property int autoSaverOnLevel: 15 }
    QtObject { id: mceChargerType; property int type: MceChargerType.None }
    // the registry's contract (src/ongoingregistry.h), recorded
    QtObject { id: ongoingRegistry
        property var top: ({})
        property bool micInUse: false
        property bool locationInUse: false
        property bool touchLocked: false
        property var mutedApps: []
        property var published: ({})
        property var synced: []
        property var activatedKeys: []
        signal activated(string key, string app)
        function publish(id, p) { var m = {}; for (var k in published) m[k] = published[k]; m[id] = p; published = m }
        function remove(id) { var m = {}; for (var k in published) if (k !== id) m[k] = published[k]; published = m }
        function syncNotifications(items) { var l = synced.slice(); l.push(items); synced = l }
        function activate(key) { var l = activatedKeys.slice(); l.push(key); activatedKeys = l; activated(key, ongoingRegistry.top.app || "") }
    }

    Rectangle { anchors.fill: parent; color: "#404040" }
    Item { id: stage; anchors.fill: parent }
    SignalSpy { id: keySpy; signalName: "ambientIconsKeyChanged" }

    function entry(extra) {
        var e = { key: "n:4", app: "asteroid-timer", title: "Timer", category: "alarm", icon: "",
                  staticIcon: "ms-timer", status: "", when: 0, countdown: false, paused: false,
                  frozen: -1, duration: false, rank: 1, muted: false }
        for (var k in extra) e[k] = extra[k]
        return e
    }
    // a notification as lipstick's model holds it (what home/unread.js reads)
    Component {
        id: notificationC
        QtObject {
            property int replacesId
            property var timestamp
            property var hints: ({})
            property string summary
            property string body
            property string category
            property string icon
            property string appIcon
            property string appName: "Messages"
        }
    }
    property int nextId: 1
    function notification(summary) {
        var id = nextId++
        return notificationC.createObject(top, { replacesId: id, timestamp: new Date(1000 * id), summary: summary })
    }

    TestCase {
        name: "StatusSlotRow"
        when: windowShown
        property var slot: null
        property var row: null

        function near(a, b, eps, msg) { verify(Math.abs(a - b) <= eps, (msg || "") + ": " + a + " vs " + b) }
        // a slot is out once its appear is exactly 0: tryCompare matches numbers within 1e-5, so a wait for
        // "appear 0" could end on the fade's last frame, with the slot still present and its glyph held
        function slotOut(s) { tryVerify(function () { return s.appear === 0 }, 2000, (s.objectName || "the slot") + " out") }
        function findIn(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var d = item.data
            for (var i = 0; d && i < d.length; i++) {
                var r = findIn(d[i], name)
                if (r)
                    return r
            }
            return null
        }
        function centre(s) { return s.mapToItem(top, s.width / 2, s.height / 2) }
        // the unread indicator's own notification list (the mock keeps one list per model)
        function indicatorModel() {
            var d = slot.notificationIndicator.data
            for (var i = 0; i < d.length; i++)
                if (d[i] && typeof d[i].add === "function" && d[i].itemCount !== undefined)
                    return d[i]
            return null
        }

        function init() {
            Backend.reset()
            Lipstick.compositor.displayAmbient = false
            desktop.wearLayout = true; desktop.displayAwake = true; desktop.displayAmbient = false
            desktop.nightstand = false; desktop.launched = []
            Desktop.desktop = desktop
            modes.bedtime = false; modes.theater = false; modes.batterySaver = false; modes.doNotDisturb = false
            modes.batteryLevel = 57; modes.autoSaverOn = false
            mceChargerType.type = MceChargerType.None
            grid.normalizedHorOffset = 0; grid.normalizedVerOffset = 0; grid.trayCloseDim = 0
            grid.currentHorizontalPos = 0; grid.currentVerticalPos = 0
            ongoingRegistry.top = ({}); ongoingRegistry.published = ({}); ongoingRegistry.synced = []
            ongoingRegistry.activatedKeys = []; ongoingRegistry.touchLocked = false
            ongoingRegistry.micInUse = false; ongoingRegistry.locationInUse = false
            var c = Qt.createComponent(Qt.resolvedUrl("st/qml/home/StatusSlot.qml"))
            compare(c.status, Component.Ready, c.errorString())
            slot = c.createObject(stage)
            verify(slot !== null)
            // what the phone link and Bluetooth say: up and on
            slot.sources.btPowered = true
            slot.sources.wifiConnected = false
            slot.sources.phoneKnown = true
            slot.sources.phoneConnected = true
            row = slot.overlayRow
            keySpy.target = slot; keySpy.clear()
            wait(30)
            // the start is over: nothing wanted, nothing drawn
            tryCompare(row, "animating", false, 2000)
        }
        function cleanup() {
            slot.destroy()
            slot = null
            row = null
            wait(20)
        }

        // ---- the row is the slot's ----
        function test_01_the_row() {
            verify(row !== null)
            compare(row.objectName, "faceOverlayRow")
            compare(slot.statusIcon, row.statusIcon)
            compare(slot.liveSpace, row.liveSpace)
            compare(row.count, 0)
            compare(row.band.visible, false)
            compare(slot.ambientIconsKey, "")
            compare(row.interactive, true)
        }

        // ---- touch lock: its glyph in the row ----
        function test_02_touch_lock() {
            ongoingRegistry.touchLocked = true
            compare(slot.sources.slotKey, "wet-touch")
            compare(row.slots, ["status"])
            tryCompare(row.statusIconSlot, "appear", 1, 2000)
            verify(/eos-status-touchlock\.svg$/.test(String(slot.statusIcon.mainIcon.source)),
                   String(slot.statusIcon.mainIcon.source))
            compare(slot.statusIcon.description, "Touch lock on")
            compare(slot.ambientIconsKey, "s:wet-touch")
            var c = centre(row.statusIconSlot)
            near(c.x, 192, 0.01, "alone in the middle"); near(c.y, 361, 0.01, "at the bottom")
            ongoingRegistry.touchLocked = false
            slotOut(row.statusIconSlot)
            compare(slot.ambientIconsKey, "")
            compare(slot.statusIcon.shownKey, "")
            // a status type the same way (Bedtime), and the priority: touch lock first
            modes.bedtime = true
            ongoingRegistry.touchLocked = true
            compare(slot.ambientIconsKey, "s:wet-touch")
            ongoingRegistry.touchLocked = false
            compare(slot.ambientIconsKey, "s:bedtime")
            tryCompare(row, "animating", false, 2000)
            verify(/eos-status-bedtime\.svg$/.test(String(slot.statusIcon.mainIcon.source)))
            // a type without a glyph (safety) takes no slot and leaves the hub's key empty
            modes.bedtime = false
            slot.sources.safety = true
            compare(slot.sources.slotKey, "safety")
            compare(row.count, 0)
            compare(slot.ambientIconsKey, "")
        }

        // ---- a notification: the dot ----
        function test_03_dot_from_a_notification() {
            var m = indicatorModel()
            verify(m !== null, "the indicator's notification list")
            tryCompare(slot.notificationIndicator, "wearLayout", true, 2000)
            m.add(top.notification("Hello"))
            compare(slot.notificationIndicator.unreadCount, 1)
            verify(slot.notificationIndicator.dotWanted)
            verify(slot.unreadDotWanted)
            compare(row.slots, ["dot"])
            tryCompare(row.dotSlot, "appear", 1, 2000)
            var c = centre(row.dotSlot)
            near(c.x, 192, 0.01, "dot x"); near(c.y, 361, 0.01, "dot y")
            // the dot has its own flag in the hub's layout inputs, not the icons' key
            compare(slot.ambientIconsKey, "")
            // the setting off hides it
            Backend.confSet("/org/asteroidos/notifications/unread-dot", false)
            verify(!slot.notificationIndicator.dotWanted)
            slotOut(row.dotSlot)
            Backend.confSet("/org/asteroidos/notifications/unread-dot", true)
            tryCompare(row.dotSlot, "appear", 1, 2000)
            // the stream looked at: read, the dot goes
            slot.notificationIndicator.markAllRead()
            compare(slot.notificationIndicator.unreadCount, 0)
            slotOut(row.dotSlot)
            compare(row.band.visible, false)
        }

        // ---- the registry: the ongoing slot ----
        function test_04_registry_to_the_ongoing_slot() {
            ongoingRegistry.top = top.entry({ status: "%t", when: Date.now() - 42000 })
            compare(row.slots, ["ongoing"])
            tryCompare(row.ongoingSlot, "appear", 1, 2000)
            compare(slot.liveSpace.shown.key, "n:4")
            compare(slot.ambientIconsKey, "|c:n:4|ms-timer")
            var c = centre(row.ongoingSlot)
            near(c.x, 192, 0.01, "ongoing alone in the middle")
            // tap: the registry's touch, the app launches from the icon
            mouseClick(top, c.x, c.y)
            compare(ongoingRegistry.activatedKeys, ["n:4"])
            compare(desktop.launched, ["asteroid-timer"])
            // long press: the live update's menu for the app
            var menu = findIn(slot, "liveMenu")
            verify(menu !== null)
            compare(menu.app, "")
            mousePress(top, c.x, c.y)
            wait(1000)
            mouseRelease(top, c.x, c.y)
            compare(menu.app, "asteroid-timer")
            // with a status: both in the key, ongoing first
            modes.bedtime = true
            compare(slot.ambientIconsKey, "s:bedtime|c:n:4|ms-timer")
            compare(row.slots, ["ongoing", "status"])
            // the entry goes
            ongoingRegistry.top = ({})
            slotOut(row.ongoingSlot)
            compare(slot.ambientIconsKey, "s:bedtime")
            verify(!slot.liveSpace.isSet(slot.liveSpace.shown))
        }

        // ---- the panel fade and the always-on screen ----
        function test_05_panel_fade_and_always_on() {
            modes.bedtime = true
            tryCompare(row.statusIconSlot, "appear", 1, 2000)
            var part = findIn(slot, "overlayPart")
            verify(part !== null)
            compare(part.opacity, 1)
            grid.normalizedHorOffset = 0.1
            near(part.opacity, 0.7, 1e-9, "a panel a tenth over the face")
            grid.normalizedHorOffset = 0
            grid.normalizedVerOffset = -0.2
            near(part.opacity, 0.4, 1e-9, "a fifth up")
            grid.normalizedVerOffset = 0.4
            compare(part.opacity, 0)
            compare(part.visible, false)
            grid.normalizedVerOffset = 0
            compare(part.opacity, 1)
            // a tray's close cut (N61-24): the row comes up with the face from the tray's dim
            grid.trayCloseDim = 0.6
            near(part.opacity, 0.4, 1e-9, "under the dim of the cut")
            grid.trayCloseDim = 1
            compare(part.opacity, 0)
            grid.trayCloseDim = 0
            compare(part.opacity, 1)
            // always-on: the row is static, changes at once
            desktop.displayAmbient = true
            compare(slot.interactive, false)
            compare(row.interactive, false)
            ongoingRegistry.top = top.entry({})
            compare(row.ongoingSlot.appear, 1)
            compare(row.animating, false)
            near(centre(row.ongoingSlot).x, 174, 0.5, "ongoing left")
            near(centre(row.statusIconSlot).x, 210, 0.5, "status right")
            modes.bedtime = false
            compare(row.statusIconSlot.appear, 0)
            near(centre(row.ongoingSlot).x, 192, 0.01, "ongoing alone")
            compare(row.animating, false)
        }

        // ---- the independent check's case: a status on and off in one turn ----
        function test_06_on_and_off_in_one_turn() {
            ongoingRegistry.touchLocked = true
            ongoingRegistry.touchLocked = false
            slot.sources.btPowered = false
            slot.sources.btPowered = true
            wait(600)
            compare(row.slots.length, 0)
            compare(row.statusIconSlot.appear, 0, "status slot left shown with no status")
            compare(row.statusIconSlot.visible, false)
            compare(row.band.fade, 0, "band left shown with no slot")
            compare(slot.statusIcon.shownKey, "", "no glyph kept")
            compare(slot.ambientIconsKey, "")
        }

        // ---- the ongoing icon's tap area: never the dot's or the status icon's ----
        function test_07_tap_areas() {
            var m = indicatorModel()
            tryCompare(slot.notificationIndicator, "wearLayout", true, 2000)
            m.add(top.notification("Hello"))
            ongoingRegistry.top = top.entry({})
            modes.bedtime = true
            compare(row.slots, ["ongoing", "dot", "status"])
            tryCompare(row, "animating", false, 2000)
            var o = centre(row.ongoingSlot), d = centre(row.dotSlot), st = centre(row.statusIconSlot)
            var menu = findIn(slot, "liveMenu")
            mouseClick(top, d.x, d.y)
            mouseClick(top, d.x - 12, d.y)
            mouseClick(top, st.x, st.y)
            mouseClick(top, st.x - 12, st.y)
            compare(ongoingRegistry.activatedKeys, [], "taps on the dot and the status icon")
            mousePress(top, d.x, d.y)
            wait(1000)
            mouseRelease(top, d.x, d.y)
            compare(menu.app, "", "a long press on the dot")
            mouseClick(top, o.x, o.y)
            compare(ongoingRegistry.activatedKeys, ["n:4"])
            mouseClick(top, o.x, o.y - 50)
            compare(ongoingRegistry.activatedKeys, ["n:4", "n:4"], "50 px above the icon")
            var tap = findIn(row.liveSpace, "liveTap")
            near(tap.height, 120, 0.01, "120 px tall")
            verify(tap.mapToItem(top, tap.width, 0).x <= (o.x + d.x) / 2 + 0.01, "short of half way to the dot")
        }

        // ---- R5 K-06: thermal mode, from eos-thermal's dconf state ----
        // stock's THERMAL_MODE status is on for ThermalStatusEvent 5 only (jqf.java: EMERGENCY = the cooldown)
        function test_08_thermal_mode() {
            compare(slot.sources.thermal, false)
            Backend.confSet("/org/asteroidos/thermal/state", "warning")
            wait(30)
            compare(slot.sources.thermal, false, "the warning shows no icon")
            compare(slot.sources.slotKey, "")
            Backend.confSet("/org/asteroidos/thermal/state", "cooldown")
            tryCompare(slot.sources, "thermal", true, 1000)
            compare(slot.sources.slotKey, "thermal")
            compare(row.slots, ["status"])
            tryCompare(row.statusIconSlot, "appear", 1, 2000)
            verify(/eos-status-thermal\.svg$/.test(String(slot.statusIcon.mainIcon.source)),
                   String(slot.statusIcon.mainIcon.source))
            compare(slot.statusIcon.description, "Watch is warm")
            compare(slot.ambientIconsKey, "s:thermal")
            // the first of stock's priorities: over touch lock and Bedtime
            ongoingRegistry.touchLocked = true
            modes.bedtime = true
            compare(slot.sources.slotKey, "thermal")
            ongoingRegistry.touchLocked = false
            modes.bedtime = false
            // the cooldown over: gone
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(slot.sources, "thermal", false, 1000)
            slotOut(row.statusIconSlot)
            compare(slot.ambientIconsKey, "")
        }
    }
}
