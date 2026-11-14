/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop
import "liveupdate.js" as Live

/* The live update full view (system-dialogs-misc-12), as stock's LiveUpdateActivity: a tap on a live
 * update that has no app to open (an entry published on the bus without one) opens its full view:
 * the app's name with its icon, the title, the status the chip shows and the relative time of the
 * entry's `when`: "in 5m", "in 2h" or "Now". The long press menu with "Show on watch face" and
 * "Turn off" is LiveMenu (W2-launcher-status). The time moves on with ONE single-shot timer armed
 * for the next change, only while the view is on screen and the display is on (never in the
 * always-on screen: no wake-ups). Opened through Desktop.liveUpdate.open(entry) or .tap(key). */
Item {
    id: view
    objectName: "liveUpdate"
    anchors.fill: parent

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    readonly property alias timer: tick
    // the entry on screen: { key, app, title, status, when, countdown, ... }
    property var entry: ({})
    // the display is on (the arbiter's)
    property bool displayOn: true
    // the registry the keys are looked up in (a test replaces it)
    property QtObject registry: typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null
    // a clock in ms (the tests move it)
    property var clock: function () { return Date.now() }
    property real now: clock()

    readonly property var rel: Live.relative(entry.when || 0, now)
    readonly property string relativeText: {
        if (rel.kind === "h")
            //% "in %1h"
            return qsTrId("id-live-in-hours").arg(rel.n) + localeManager.changesObserver
        if (rel.kind === "m")
            //% "in %1m"
            return qsTrId("id-live-in-minutes").arg(rel.n) + localeManager.changesObserver
        if (rel.kind === "now")
            //% "Now"
            return qsTrId("id-live-now") + localeManager.changesObserver
        return ""
    }

    function open(e) {
        entry = e || ({})
        now = clock()
        dialog.open()
        arm()
    }
    // a tap on the live update with this key: only an entry without an app opens the view (the others
    // open their app, the registry's activate)
    function tap(key) {
        var e = Live.find(registry ? registry.entries : [], key)
        if (!e || e.app)
            return false
        open(e)
        return true
    }
    function close() { dialog.close() }

    function arm() {
        tick.stop()
        if (!dialog.shown || !displayOn)
            return
        var ms = Live.nextChangeMs(entry.when || 0, now)
        if (ms === Infinity)
            return
        tick.interval = Math.max(1, Math.min(ms, 2147483647))
        tick.restart()
    }
    onDisplayOnChanged: {
        if (displayOn && dialog.shown) {
            now = clock()
            arm()
        } else {
            tick.stop()
        }
    }

    Component.onCompleted: Desktop.liveUpdate = view
    Component.onDestruction: if (Desktop.liveUpdate === view) Desktop.liveUpdate = null

    Timer {
        id: tick
        repeat: false
        onTriggered: {
            view.now = view.clock()
            view.arm()
        }
    }

    Dialog {
        id: dialog
        objectName: "liveUpdateDialog"
        onClosed: tick.stop()

        Column {
            id: content
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: Theme.dp(4)

            // the app: its icon in a circle, its name
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.dp(6)
                Rectangle {
                    width: Theme.dp(24)
                    height: width
                    radius: width / 2
                    color: Theme.color.primary
                    Icon {
                        anchors.centerIn: parent
                        width: Theme.dp(18)
                        height: width
                        name: view.entry.staticIcon ? String(view.entry.staticIcon) : "ios-mail-outline"
                        color: Theme.color.onPrimary
                    }
                }
                Label {
                    objectName: "liveUpdateApp"
                    anchors.verticalCenter: parent.verticalCenter
                    role: "titleSmall"
                    color: Theme.color.onSurfaceVariant
                    text: view.entry.title ? String(view.entry.title) : ""
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, content.width - Theme.dp(30))
                }
            }
            // the status the chip shows
            Label {
                id: statusLabel
                objectName: "liveUpdateStatus"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                role: "titleMedium"
                color: Theme.color.tertiary
                text: view.entry.status ? String(view.entry.status).replace("%t", "").trim() : ""
                visible: text !== ""
            }
            // in 5m, in 2h, Now
            Label {
                id: relativeLabel
                objectName: "liveUpdateRelative"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "displaySmall"
                color: Theme.color.primary
                text: view.relativeText
                visible: text !== ""
            }
        }
    }
}
