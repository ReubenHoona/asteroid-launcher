/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "ongoing.js" as Ongoing

/* The ongoing activities as status chips at the top of the notification stream (W2-launcher-status,
 * audit status-indicators-21): stock shows Live Updates there with tap and long press (kpp.java:
 * 110-125, 227-241). One compact chip per entry of the registry the user has not turned off: the
 * icon and one line, the entry's status or its app's name. Tap runs the entry's touch (the app
 * opens, the call screen comes back); a long press asks to turn the app's live updates off (the
 * home screen's menu). Used as the header of the stream's list: no entries, no height.
 *
 * Battery: the timer parts tick with one single-shot timer armed for the earliest next change, only
 * while the chips are on a screen that is on; nothing is polled. */
Item {
    id: chips

    // the registry (ongoingRegistry.entries, in order); a list of the entries of the registry
    property var entries: typeof ongoingRegistry !== "undefined" && ongoingRegistry !== null ? ongoingRegistry.entries : []
    // the screen is on and showing
    property bool interactive: true
    property var clock: function () { return Date.now() }
    property real now: 0
    // the side margin of the cards above, and the chip's height (our design: the chip rows of
    // the lists, 40 dp)
    property real sideMargin: Theme.dp(10)
    readonly property real chipHeight: Theme.dp(40)
    readonly property real gap: Theme.dp(4)

    signal tapped(string key)
    signal menuRequested(string key, string app, string title)

    readonly property var shownEntries: {
        var l = []
        for (var i = 0; entries && i < entries.length; i++)
            if (entries[i] && entries[i].muted !== true)
                l.push(entries[i])
        return l
    }
    readonly property int count: shownEntries.length

    width: parent ? parent.width : Theme.dp(192) * 2
    height: count > 0 ? column.height + gap : 0
    visible: count > 0

    onShownEntriesChanged: { now = clock(); arm() }
    onInteractiveChanged: { if (interactive) now = clock(); arm() }
    onVisibleChanged: arm()
    function arm() {
        var best = Infinity
        for (var i = 0; i < shownEntries.length; i++)
            best = Math.min(best, Ongoing.nextChangeMs(shownEntries[i], now))
        if (interactive && visible && isFinite(best)) {
            tick.interval = Math.max(1, Math.ceil(best))
            tick.restart()
        } else {
            tick.stop()
        }
    }
    readonly property alias ticker: tick
    Timer {
        id: tick
        repeat: false
        onTriggered: { chips.now = chips.clock(); chips.arm() }
    }
    Component.onCompleted: { now = clock(); arm() }

    Column {
        id: column
        x: chips.sideMargin
        width: chips.width - 2 * chips.sideMargin
        spacing: chips.gap

        Repeater {
            model: chips.shownEntries
            delegate: Rectangle {
                id: chip
                objectName: "liveChip"
                readonly property var e: modelData
                readonly property string label: {
                    var t = Ongoing.text(e, chips.now)
                    return t !== "" ? t : (e.title || "")
                }
                width: column.width
                height: chips.chipHeight
                radius: height / 2
                color: Theme.color.surfaceContainer

                Icon {
                    id: chipIcon
                    x: Theme.dp(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.dp(Ongoing.ICON_DP)
                    height: width
                    name: Ongoing.isFile(Ongoing.staticIcon(chip.e)) ? "" : Ongoing.staticIcon(chip.e)
                    color: Theme.color.onSurface
                }
                Label {
                    objectName: "liveChipText"
                    anchors.verticalCenter: parent.verticalCenter
                    x: chipIcon.x + chipIcon.width + Theme.dp(8)
                    width: parent.width - x - Theme.dp(12)
                    text: chip.label
                    role: "titleSmall"
                    color: Theme.color.onSurface
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    font.features: { "tnum": 1 }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: chips.tapped(chip.e.key)
                    onPressAndHold: chips.menuRequested(chip.e.key, chip.e.app || "", chip.e.title || "")
                }
                Accessible.role: Accessible.Button
                Accessible.name: chip.label
            }
        }
    }
}
