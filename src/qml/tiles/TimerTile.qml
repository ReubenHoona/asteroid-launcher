/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import org.asteroid.controls
import "clocklogic.js" as Clock

/*
 * The Timer tile, as stock Clock's (ezv.java:90-125, dwf.java:109-258,
 * ibk.java) in the Wear OS 6 look (the emulator's S13): start a timer in
 * one tap, or the running one. An expressive tile (TileBase): no app icon
 * at rest, it fades in only while the pager moves (M08).
 *  - idle: no title, a circle for each of the user's saved timers, shortest
 *    first (dconf /org/asteroidos/timer/recents, the Timer app's list; 5,
 *    10, 15, 20, 30 min when it has none), as CircleGrid lays them out (two
 *    over three). Each circle is #182B2F with the number alone in white
 *    titleMedium ('05', '10', '1:30' for 90 min, '0:30' for 30 s; the unit
 *    is for the screen reader); a tap starts that timer. The cyan pill
 *    "New" (#78D9EC, #202124 label) opens the Timer app's picker.
 *  - running or paused: the title "Timer", MIN margins (3 %), one stadium
 *    data card with a ring of the time left (static while paused), the time
 *    left in tabular figures over the total, and the cyan pill "Open". No
 *    Cancel on the tile, no next-alarm line.
 * The colours are the Clock tiles' own, not the theme's. N61-27
 * The timer is a countdown alarm of timed, the same the Timer app sets, so
 * the alarm presenter rings it and the app shows it.
 *
 * Battery: the time left is re-drawn by ONE single shot per whole second,
 * only while the tile is on screen and awake (TileBase.awake: not in
 * ambient, not behind an app) and the timer runs; nothing otherwise.
 *
 * The Timer app's picker is asked for as the alarm clock's is: dconf
 * /org/asteroidos/timer/open as "picker@<ms>" before the program starts.
 */
TileBase {
    id: tile
    //% "Timer"
    title: tile.mode === "idle" ? "" : qsTrId("id-tile-timer") + localeManager.changesObserver
    backgroundTap: false
    expressive: true
    sideMarginFraction: tile.mode === "idle" ? 0.052 : 0.03
    pillColor: tile.cyan
    pillContentColor: tile.ink
    pillText: (tile.mode === "idle"
               //% "New"
               ? qsTrId("id-tile-new")
               //% "Open"
               : qsTrId("id-tile-open")) + localeManager.changesObserver
    onPillClicked: tile.openApp(tile.mode === "idle" ? "picker" : "")

    // the Clock tiles' colours (S13): circle, pill and its label
    readonly property color circle: "#182B2F"
    readonly property color cyan: "#78D9EC"
    readonly property color ink: "#202124"

    ConfigurationValue { id: recents; key: "/org/asteroidos/timer/recents"; defaultValue: Clock.recentsToStore(Clock.DEFAULT_RECENTS) }
    ConfigurationValue { id: lastDuration; key: "/org/asteroidos/timer/last-timer-duration"; defaultValue: 300 }
    ConfigurationValue { id: openRequest; key: "/org/asteroidos/timer/open"; defaultValue: "" }

    AlarmsModel {
        id: countdowns
        onlyCountdown: true
        onPopulatedChanged: if (tile.live) tile.findCountdown()
        onRowsInserted: if (tile.live) tile.findCountdown()
        onRowsRemoved: if (tile.live) tile.findCountdown()
        onDataChanged: if (tile.live) tile.findCountdown()
        onModelReset: if (tile.live) tile.findCountdown()
    }

    // the timer of the tile: Clock.classify of the countdown alarm
    property var info: ({ state: "expired", durationSec: 0, endMs: 0, frozenMs: 0 })
    property real remainingMs: 0
    readonly property string mode: info.state === "running" || info.state === "paused" ? info.state : "idle"
    readonly property bool running: mode === "running"
    onLiveChanged: if (live) findCountdown()
    onAwakeChanged: if (awake) update()
    Component.onCompleted: findCountdown()

    // the circles: the saved durations (<= 5); the units for the screen reader's name of each
    readonly property var units: ({
        //% "Hr"
        hour: qsTrId("id-tile-hr") + localeManager.changesObserver,
        //% "Min"
        minute: qsTrId("id-tile-min-short") + localeManager.changesObserver,
        //% "Sec"
        second: qsTrId("id-tile-sec") + localeManager.changesObserver,
        sep: ":"
    })
    readonly property var durations: Clock.buttons(recents.value)

    function findCountdown() {
        var now = Date.now()
        var best = null
        for (var i = 0; i < countdowns.rowCount(); i++) {
            var a = countdowns.data(countdowns.index(i, 0), 0x0100)
            if (!a)
                continue
            var c = Clock.classify(a, now)
            if (c.state === "expired")
                continue
            // a running timer wins over a paused one, the one ending first over another
            if (best === null || (c.state === "running" && (best.state !== "running" || c.endMs < best.endMs)))
                best = c
        }
        info = best !== null ? best : ({ state: "expired", durationSec: 0, endMs: 0, frozenMs: 0 })
        update()
    }

    function update() {
        remainingMs = info.state === "running" ? Math.max(0, info.endMs - Date.now())
                    : info.state === "paused" ? info.frozenMs : 0
        // it ran out: the alarm presenter rings it, the tile is idle again
        if (info.state === "running" && remainingMs === 0)
            info = ({ state: "expired", durationSec: 0, endMs: 0, frozenMs: 0 })
    }

    // One timer at a time, the Timer app's rule (alarms-timers-stopwatch-31): the circles show only
    // while none runs or is paused (stock's tile has no start then either). A timer the model had
    // not shown yet when a circle was tapped is not doubled: the tile shows it instead.
    function start(seconds) {
        findCountdown()
        if (mode !== "idle")
            return false
        var a = countdowns.createAlarm()
        if (!a)
            return false
        a.countdown = true
        a.hour = Math.floor(seconds / 3600)
        a.minute = Math.floor(seconds / 60) % 60
        a.second = seconds % 60
        a.title = ""
        a.enabled = true
        a.save()
        lastDuration.value = seconds
        // the saved list: the Timer app's, one entry per duration
        recents.value = Clock.recentsToStore(Clock.addRecent(Clock.parseRecents(recents.value), seconds))
        findCountdown()
        return true
    }

    function openApp(route) {
        if (route !== "")
            openRequest.value = route + "@" + Date.now()
        desktop.launchByName("asteroid-timer", null)
    }

    readonly property alias tick: ticker
    // one single shot for the next whole second of the time left
    Timer {
        id: ticker
        repeat: false
        interval: Math.min(Clock.nextTickMs(tile.remainingMs), 1001)
        running: tile.awake && tile.running && tile.remainingMs > 0
        onTriggered: {
            tile.update()
            if (tile.awake && tile.running && tile.remainingMs > 0)
                ticker.restart()
        }
    }

    // ---- idle: the circles ------------------------------------------------
    CircleGrid {
        id: buttonGrid
        objectName: "timerGrid"
        visible: tile.mode === "idle"
        anchors.fill: parent
        model: tile.durations
        delegate: TileCard {
            id: button
            objectName: "timerButton" + index
            readonly property int seconds: modelData
            readonly property var parts: Clock.label(seconds, tile.units)
            containerColor: tile.circle
            contentColor: "#FFFFFF"
            accessibleName: parts.number + " " + parts.unit
            preview: tile.preview
            onClicked: tile.start(seconds)

            // the number alone (S13: '05', 22 px digits)
            Label {
                objectName: "timerNumber"
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.dp(4)
                horizontalAlignment: Text.AlignHCenter
                text: Clock.circleText(button.seconds)
                role: "titleMedium"
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: "#FFFFFF"
                maximumLineCount: 1
            }
        }
    }

    // ---- running: the data card ---------------------------------------------
    TileCard {
        id: runCard
        objectName: "timerCard"
        visible: tile.mode !== "idle"
        width: tile.body.width
        height: Math.min(Theme.dp(60), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        onClicked: tile.openApp("")

        CircularProgressIndicator {
            id: ring
            objectName: "timerRing"
            x: Theme.dp(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.dp(48)
            height: width
            displayOn: tile.awake
            color: Theme.color.primary
            trackColor: Theme.color.surfaceContainerHigh
            progress: Clock.ringProgress(tile.remainingMs, tile.info.durationSec)
        }
        Column {
            x: ring.x + ring.width + Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - Theme.dp(14)
            Label {
                objectName: "timerLeft"
                width: parent.width
                text: Clock.countdownText(tile.remainingMs)
                role: "displaySmall"
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurface
                maximumLineCount: 1
            }
            Label {
                objectName: "timerTotal"
                width: parent.width
                text: Clock.totalText(tile.info.durationSec)
                role: "bodyMedium"
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
        }
    }
}
