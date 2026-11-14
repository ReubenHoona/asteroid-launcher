/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "ongoing.js" as Ongoing

/* The face chip of the ongoing activities, stock's Live Space ("At A Glance"; W2-launcher-status,
 * audit status-indicators-12, -13, alarms-timers-stopwatch-32, media-controls-17): a pill at the
 * bottom of the face for the first entry of the registry. Height 32 dp, 8 dp above the screen
 * edge (live_space_height, live_space_bottom_padding). Collapsed it is the 18 dp icon; expanded,
 * when the entry has text (a status, a timer part, a duration), the icon and one line of text.
 * Tap runs the entry's touch, a long press asks to turn the app's live updates off (the menu is
 * LiveSpaceMenu). Our own look: black at 70 % behind it (the stock geometry file is not in the
 * firmware we have), the expanded chip at most 70 % of the screen chord at its height.
 *
 * Battery (M1): interactive (the display on, not ambient): the animated icon loops, the
 * text's timer part ticks with one single-shot timer armed for the next change, the
 * transitions run (250 ms). Ambient: the static icon only, no text, no timer, no animation;
 * the sensor hub draws what the AP drew last (StatusSlot.ambientIconsKey says when that
 * changes). `entry` is the registry's top ({} none); nothing here polls it. */
Item {
    id: chip
    objectName: "liveSpaceRoot"

    // the registry's first entry ({key, app, title, category, icon, staticIcon, status, when, ...})
    property var entry: ({})
    property bool interactive: true
    // the clock, for the tests
    property var clock: function () { return Date.now() }
    property real now: 0

    signal tapped(string key, string app)
    signal menuRequested(string key, string app, string title)

    // what the chip holds while a change runs (the entry it fades away from)
    property var shown: ({})
    readonly property bool present: shown && shown.key !== undefined && shown.key !== ""
    readonly property bool wanted: entry && entry.key !== undefined && entry.key !== ""
    readonly property bool animated: interactive && Motion.animationScale > 0
    readonly property bool expanded: interactive && present && Ongoing.expanded(shown, now)
    readonly property string label: present ? Ongoing.text(shown, now) : ""
    readonly property string iconName: present ? Ongoing.staticIcon(shown) : ""
    //% "Ongoing %1 running in the background"
    readonly property string description: present ? qsTrId("id-ongoing-description").arg(shown.title || "") : ""
    // what the always-on layout needs: the entry and its icon, never the text
    readonly property string ambientKey: wanted ? Ongoing.chipKey(entry) : ""
    readonly property alias pill: pill
    readonly property alias ticker: tick
    readonly property alias introAnim: changeIn

    readonly property real pillHeight: Theme.dp(Ongoing.HEIGHT_DP)
    readonly property real bottomGap: Theme.dp(Ongoing.BOTTOM_DP)
    readonly property real iconSize: Theme.dp(Ongoing.ICON_DP)
    readonly property real maxPillWidth: Ongoing.maxWidth(parent ? parent.width : Theme.dp(192) * 2,
                                                          bottomGap + pillHeight / 2)

    // the tap target is at least 60 dp tall (overlay_icon_min_tap_target_height)
    width: Math.max(pill.width, Theme.dp(Ongoing.TAP_MIN_DP))
    height: Theme.dp(Ongoing.TAP_MIN_DP)
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    visible: present

    // ---- what is shown follows the entry: intro, replace, update, exit ----
    onEntryChanged: follow()
    // (read from the objects themselves: the bindings of wanted and present may not have run yet
    // when the change handler does)
    function isSet(e) { return e && e.key !== undefined && e.key !== "" }
    function follow() {
        var want = isSet(entry), have = isSet(shown)
        var next = want ? entry : ({})
        var same = have && want && shown.key === entry.key
        if (!animated || same) {
            changeOut.stop(); changeIn.stop(); exitOut.stop()
            shown = next
            fade = want ? 1 : 0
            return
        }
        if (!want) {
            // exit: fade away, then nothing
            changeIn.stop(); changeOut.stop()
            exitOut.restart()
        } else if (have) {
            // replace: the old fades out, the new fades in
            exitOut.stop(); changeIn.stop()
            changeOut.restart()
        } else {
            // intro: the first one fades in
            exitOut.stop(); changeOut.stop()
            shown = next
            fade = 0
            changeIn.restart()
        }
    }
    property real fade: 0
    SequentialAnimation {
        id: changeOut
        NumberAnimation { target: chip; property: "fade"; to: 0; duration: Motion.duration(Ongoing.TRANSITION_MS)
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard }
        ScriptAction { script: chip.shown = chip.isSet(chip.entry) ? chip.entry : ({}) }
        NumberAnimation { target: chip; property: "fade"; to: 1; duration: Motion.duration(Ongoing.TRANSITION_MS)
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard }
    }
    NumberAnimation {
        id: changeIn
        target: chip; property: "fade"; to: 1; duration: Motion.duration(Ongoing.TRANSITION_MS)
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard
    }
    SequentialAnimation {
        id: exitOut
        NumberAnimation { target: chip; property: "fade"; to: 0; duration: Motion.duration(Ongoing.TRANSITION_MS)
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard }
        ScriptAction { script: if (!chip.isSet(chip.entry)) chip.shown = ({}) }
    }
    // the display went off or ambient: a change running is over at once, the icon at full opacity
    onAnimatedChanged: if (!animated) follow()

    // ---- the text's timer part: one single-shot timer for the next change ----
    onShownChanged: { now = clock(); arm() }
    onInteractiveChanged: { if (interactive) now = clock(); arm() }
    onVisibleChanged: arm()
    function arm() {
        var ms = Ongoing.nextChangeMs(shown, now)
        if (interactive && visible && present && isFinite(ms)) {
            tick.interval = Math.max(1, Math.ceil(ms))
            tick.restart()
        } else {
            tick.stop()
        }
    }
    Timer {
        id: tick
        repeat: false
        onTriggered: { chip.now = chip.clock(); chip.arm() }
    }
    Component.onCompleted: { now = clock(); follow() }

    // ---- the pill ----
    Rectangle {
        id: pill
        objectName: "liveSpace"
        anchors.bottom: parent.bottom
        anchors.bottomMargin: chip.bottomGap
        anchors.horizontalCenter: parent.horizontalCenter
        height: chip.pillHeight
        radius: height / 2
        color: "#000000"
        opacity: Ongoing.BACKDROP_OPACITY * chip.fade
        // the content width: 12 dp, the icon, 4 dp, the text, 8 dp
        readonly property real contentWidth: Theme.dp(12) + chip.iconSize + Theme.dp(4) + liveText.implicitWidth + Theme.dp(8)
        width: chip.expanded ? Math.min(contentWidth, chip.maxPillWidth) : height
        Behavior on width {
            enabled: chip.animated
            NumberAnimation { duration: Motion.duration(Ongoing.TRANSITION_MS)
                              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard }
        }
        clip: true
    }

    // the icon and the text sit over the backdrop with the chip's own fade (not the 70 %)
    Item {
        id: content
        objectName: "liveContent"
        anchors.fill: pill
        opacity: chip.fade

        // 18 dp icon, centred when collapsed, 12 dp from the start when expanded
        Item {
            id: iconBox
            objectName: "liveIcon"
            width: chip.iconSize
            height: width
            anchors.verticalCenter: parent.verticalCenter
            x: chip.expanded ? Theme.dp(12) : (parent.width - width) / 2
            Behavior on x {
                enabled: chip.animated
                NumberAnimation { duration: Motion.duration(Ongoing.TRANSITION_MS)
                                  easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.standard }
            }

            // the animated icon plays only while the screen is on and the chip is seen
            readonly property bool animatedOn: chip.interactive && chip.present && Ongoing.isFile(chip.shown.icon)
            Icon {
                anchors.fill: parent
                visible: !iconBox.animatedOn && !Ongoing.isFile(chip.iconName)
                name: Ongoing.isFile(chip.iconName) ? "" : chip.iconName
                color: "#ffffff"
            }
            Image {
                anchors.fill: parent
                visible: !iconBox.animatedOn && Ongoing.isFile(chip.iconName)
                source: Ongoing.isFile(chip.iconName) ? chip.iconName : ""
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
            }
            AnimatedImage {
                objectName: "liveAnimatedIcon"
                anchors.fill: parent
                visible: iconBox.animatedOn
                source: iconBox.animatedOn ? chip.shown.icon : ""
                fillMode: Image.PreserveAspectFit
                playing: iconBox.animatedOn && chip.visible
            }
        }

        Label {
            id: liveText
            objectName: "liveText"
            visible: chip.expanded
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.dp(12) + chip.iconSize + Theme.dp(4)
            width: Math.max(0, content.width - x - Theme.dp(8))
            text: chip.label
            role: "titleSmall"
            color: "#ffffff"
            maximumLineCount: 1
            elide: Text.ElideRight
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        id: touch
        objectName: "liveTap"
        anchors.fill: parent
        enabled: chip.present && chip.wanted
        onClicked: chip.tapped(chip.shown.key, chip.shown.app || "")
        onPressAndHold: chip.menuRequested(chip.shown.key, chip.shown.app || "", chip.shown.title || "")
    }

    Accessible.role: Accessible.Button
    Accessible.name: description
}
