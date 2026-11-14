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
 * ibk.java): start a timer in one tap, or the running one.
 *  - idle: no title (a screen under 225 dp has none), buttons for the
 *    user's saved timers, shortest first (dconf /org/asteroidos/timer/recents,
 *    the Timer app's list; 5, 10, 15, 30 min when it has none): fewer than
 *    four in one row, four as 2 x 2, five as 3 + 2 (2 + 3 when a label of
 *    the first three is wide). Each button is a filled stadium (primary /
 *    onPrimary) with the number over the unit ("Min", "Hr", "Sec"); a tap
 *    starts that timer. The green edge button "+" (Add timer) opens the
 *    Timer app's picker.
 *  - running or paused: the title "Timer", MIN margins (3 %), one stadium
 *    data card with a ring of the time left (static while paused), the time
 *    left in tabular figures over the total, and the text edge button
 *    "Open". No Cancel on the tile, no next-alarm line.
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
    sideMarginFraction: tile.mode === "idle" ? 0.052 : 0.03
    chipColor: Theme.color.tertiary
    chipContentColor: Theme.color.onTertiary
    chipIcon: tile.mode === "idle" ? "ios-add" : ""
    //% "Open"
    chipText: tile.mode === "idle" ? "" : qsTrId("id-tile-open") + localeManager.changesObserver
    onChipClicked: tile.openApp(tile.mode === "idle" ? "picker" : "")

    ConfigurationValue { id: recents; key: "/org/asteroidos/timer/recents"; defaultValue: ["300", "600", "900", "1800"] }
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

    // the buttons: the saved durations (<= 5), each with its label
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
    readonly property var rowCounts: Clock.rows(durations, units)
    readonly property real gap: Theme.dp(4)

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

    function start(seconds) {
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

    // ---- idle: the buttons ------------------------------------------------
    Item {
        id: buttonGrid
        objectName: "timerGrid"
        visible: tile.mode === "idle"
        anchors.fill: parent

        readonly property int rowCount: tile.rowCounts.length
        // one row is a standard button high (52 dp); two fill the slot
        readonly property real rowHeight: rowCount <= 1 ? Math.min(Theme.dp(52), height)
                                                        : (height - (rowCount - 1) * tile.gap) / rowCount

        Repeater {
            model: tile.durations
            delegate: TileCard {
                id: button
                objectName: "timerButton" + index
                readonly property int seconds: modelData
                readonly property var rowInfo: {
                    var counts = tile.rowCounts
                    var left = index
                    for (var r = 0; r < counts.length; r++) {
                        if (left < counts[r])
                            return { row: r, col: left, n: counts[r] }
                        left -= counts[r]
                    }
                    return { row: 0, col: 0, n: 1 }
                }
                readonly property var parts: Clock.label(seconds, tile.units)
                width: (buttonGrid.width - (rowInfo.n - 1) * tile.gap) / rowInfo.n
                height: buttonGrid.rowHeight
                x: rowInfo.col * (width + tile.gap)
                y: (buttonGrid.height - (buttonGrid.rowCount * buttonGrid.rowHeight + (buttonGrid.rowCount - 1) * tile.gap)) / 2
                   + rowInfo.row * (buttonGrid.rowHeight + tile.gap)
                containerColor: Theme.color.primary
                contentColor: Theme.color.onPrimary
                accessibleName: parts.number + " " + parts.unit
                onClicked: tile.start(seconds)

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.dp(4)
                    Label {
                        objectName: "timerNumber"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: button.parts.number
                        role: "displaySmall"
                        font.weight: Font.Medium
                        font.features: Theme.tabularNumerals
                        color: Theme.color.onPrimary
                        maximumLineCount: 1
                    }
                    Label {
                        objectName: "timerUnit"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: button.parts.unit
                        role: "labelSmall"
                        color: Theme.color.onPrimary
                        maximumLineCount: 1
                    }
                }
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
