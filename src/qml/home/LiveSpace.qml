/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "ongoing.js" as Ongoing
import "status.js" as Status

/* The face's ongoing activity indicator, stock's Live Space (W2-launcher-status, audit
 * status-indicators-12, -13, alarms-timers-stopwatch-32, media-controls-17), for the first entry of
 * the registry: since N61-17 the first slot of the face's bottom row (FaceOverlayRow), as the Wear OS
 * 6 emulator draws it (X-face-ongoing-stopwatch, -6s, X-face-ongoing-plus-unread,
 * X-ambient-ongoing-plus-unread): the bare white 18 dp static icon (stopwatch 28 x 32 px), never
 * expanded: no pill, no text, also while a stopwatch runs. The row's band is its only backdrop, the
 * row brings the slot in and out. Tap runs the entry's touch, a long press opens the live update's
 * menu (LiveMenu); the tap target is at least 60 dp square, centred on the icon.
 *
 * Battery (M1): interactive (the display on, not ambient): an animated icon loops; nothing else runs,
 * no timer. Ambient: the static icon only; the sensor hub draws what the AP drew last
 * (StatusSlot.ambientIconsKey says when that changes). `entry` is the registry's top ({} none);
 * nothing here polls it. */
Item {
    id: chip
    objectName: "liveSpaceRoot"

    // the registry's first entry ({key, app, title, category, icon, staticIcon, ...})
    property var entry: ({})
    property bool interactive: true
    // the row's slot of this icon is shown (its appear above 0): a change of entry then gives way in
    // ROW_MS; else it is at once
    property bool present: false

    signal tapped(string key, string app)
    signal menuRequested(string key, string app, string title)

    // the entry drawn: it stays while the row takes the slot out
    property var shown: ({})
    readonly property bool wanted: isSet(entry)
    readonly property bool animated: interactive && Motion.animationScale > 0
    readonly property string iconName: isSet(shown) ? Ongoing.staticIcon(shown) : ""
    //% "Ongoing %1 running in the background"
    readonly property string description: isSet(shown) ? qsTrId("id-ongoing-description").arg(shown.title || "") : ""
    // what the always-on layout needs: the entry and its icon, never the text
    readonly property string ambientKey: wanted ? Ongoing.chipKey(entry) : ""
    // where an app launched from the icon grows from (OngoingFeed.launchFrom)
    readonly property alias pill: iconBox
    readonly property alias replaceAnim: replace

    width: Theme.dp(Status.ROW_SLOT_DP)
    height: width

    function isSet(e) { return e !== undefined && e !== null && e.key !== undefined && e.key !== "" }

    // ---- what is drawn follows the entry ----
    onEntryChanged: follow()
    function follow() {
        // no entry: the row takes the slot out, the last icon stays drawn meanwhile (nothing to keep
        // when nothing of the slot is drawn)
        if (!isSet(entry)) {
            if (!present) {
                replace.stop()
                _p = 1
                shown = ({})
            }
            return
        }
        var swap = isSet(shown) && shown.key !== entry.key
        if (swap && animated && present) {
            old.entry = shown
            shown = entry
            replace.restart()
            return
        }
        if (swap) {
            replace.stop()
            _p = 1
        }
        // a new entry, or the same one updated: at once
        shown = entry
    }
    // the display went off or ambient with a change running: it is over, at once
    onAnimatedChanged: if (!animated) {
        replace.stop()
        _p = 1
    }
    // the row has taken the slot out: the entry it kept drawn for that goes too
    onPresentChanged: if (!present && !isSet(entry)) {
        replace.stop()
        _p = 1
        shown = ({})
    }
    Component.onCompleted: follow()

    // the replacement's progress: the old icon goes (opacity and scale 1 -> 0), the new one comes
    property real _p: 1
    NumberAnimation {
        id: replace
        target: chip
        property: "_p"
        from: 0
        to: 1
        duration: Motion.duration(Status.ROW_MS)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Status.ROW_CURVE
    }

    // one entry's icon: its static icon by name or file, or its animated file while animatedOn
    component LiveIcon: Item {
        id: li
        property var entry: ({})
        property bool animatedOn: false
        readonly property string name: entry && entry.key ? Ongoing.staticIcon(entry) : ""
        anchors.fill: parent
        Icon {
            anchors.fill: parent
            visible: !li.animatedOn && li.name !== "" && !Ongoing.isFile(li.name)
            name: Ongoing.isFile(li.name) ? "" : li.name
            color: "#ffffff"
        }
        Image {
            anchors.fill: parent
            visible: !li.animatedOn && Ongoing.isFile(li.name)
            source: Ongoing.isFile(li.name) ? li.name : ""
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
        }
        AnimatedImage {
            objectName: "liveAnimatedIcon"
            anchors.fill: parent
            visible: li.animatedOn
            source: li.animatedOn ? li.entry.icon : ""
            fillMode: Image.PreserveAspectFit
            playing: li.animatedOn && li.visible
        }
    }

    // the icon, 18 dp, white
    Item {
        id: iconBox
        objectName: "liveIcon"
        anchors.fill: parent
        opacity: chip._p
        scale: chip._p
        // the animated icon plays only while the screen is on
        LiveIcon {
            entry: chip.shown
            animatedOn: chip.interactive && chip.isSet(chip.shown) && Ongoing.isFile(chip.shown.icon)
        }
    }
    // the icon it gives way to (only while a replacement runs)
    Item {
        id: old
        objectName: "liveIconFading"
        property var entry: ({})
        anchors.fill: parent
        visible: replace.running
        opacity: 1 - chip._p
        scale: 1 - chip._p
        LiveIcon { entry: old.entry }
    }

    MouseArea {
        id: touch
        objectName: "liveTap"
        anchors.centerIn: parent
        width: Math.max(parent.width, Theme.dp(Status.ROW_TAP_MIN_DP))
        height: Math.max(parent.height, Theme.dp(Status.ROW_TAP_MIN_DP))
        enabled: chip.wanted && chip.isSet(chip.shown)
        onClicked: chip.tapped(chip.shown.key, chip.shown.app || "")
        onPressAndHold: chip.menuRequested(chip.shown.key, chip.shown.app || "", chip.shown.title || "")
    }

    Accessible.role: Accessible.Button
    Accessible.name: description
}
