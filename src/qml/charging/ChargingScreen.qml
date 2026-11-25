/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Mce
import org.nemomobile.lipstick
import org.asteroid.controls
import org.asteroid.utils
import "../complications"
import "charging.js" as Charging
import "../compositor/windowmotion.js" as WM

/* The charging screen (W2-launcher-charging; audit charging-battery-01, -06, -07, -08):
 * full screen on the charger, as stock's ChargingComposeActivity (ini.java).
 * 192 dp, in the Wear OS 6 emulator's look (N61-18, S03-c): black; the battery
 * ring round the edge (8 dp stroke, 2 dp inset, gap 8/3 dp, 12 o'clock start,
 * indicator primaryDim); '91%' top centre in tertiaryDim (arcSmall, weight 500,
 * glyph top 38 px); the bolt 24 dp in tertiaryDim at 96 %, 6 dp above the clock;
 * the clock in two surfaceContainerLow pills 78 x 70 dp 4 dp apart (hours
 * corner 40 dp, minutes 26 dp; digits onSurface, Noto Sans ExtraBold 53 sp,
 * 'hh' zero-padded in 12 h, 'HH' in 24 h, no AM/PM); under it a 16 sp tall
 * pill chip (surfaceContainerLow, tertiaryDim text) with the date (ICU's
 * 'EEE d' in the locale: '23 Mon' in en_US, 'Mon 23' in en_GB) or, when the
 * next alarm rings within 24 h, the alarm icon and its time, centred between
 * the clock and the bottom slot 14 dp above the edge, which holds the 5 dp
 * primary unread dot while notifications are unread. At 15 % and below the
 * whole screen turns red (300 ms; CP3A's colours).
 *
 * The plug-in plays the intro (Charging.introAt: our own bolt traced, filled
 * and scaled 2.83 -> 1.06 in 1 s, then the ring, the bolt move and the rise of
 * the clock and the chip on the springs of stock); a relaunch at the next
 * screen off, and the start of the launcher, show the finished screen with no
 * animation. The bolt pulses while the level is below 100 %. Touches are
 * swallowed, nothing swipes it away (the crown does, in KeyRouter).
 *
 * Power (M1): every animation runs only while the display is on (`awake`: the
 * display on and not in the always-on screen) and the screen is up. The intro
 * is one NumberAnimation of `introT`; every value of it is a function of that
 * time (charging.js). The minute timer is armed only while up and awake, one
 * shot at a time; in the always-on screen the AP's own minute update
 * (displayAmbientUpdate) redraws the clock. No polling.
 *
 * Instantiated once in compositor.qml as `chargingScreen`, fed by the
 * ChargingController (shown, plugIntro, fade); reads the battery level, the
 * next alarm and the time itself. */
Item {
    id: screen
    objectName: "eosChargingScreen"

    // the screen is up (ChargingController.shown)
    property bool shown: false
    // the display is on (not off, not the always-on screen)
    property bool awake: true
    // this launch is a plug-in: play the intro (the controller says so before `shown`)
    property bool plugIntro: false
    // a hide fades out (the unplug) instead of going at once
    property bool fade: false

    // the battery level in per cent; the time; 12 or 24 h; unread notifications (the dot); the next alarm
    property int level: Charging.clampLevel(battery.percent)
    property date now: new Date()
    property bool use12h: !TimeFormat.use24h
    property bool unread: false
    property real nextAlarmMs: alarms ? alarms.nextAlarmMs : 0

    // the intro: time in ms; at rest it stands at its end
    property real introT: Charging.INTRO_END
    property bool introActive: false
    signal introFinished()
    // the bolt's pulse, 0.3..1
    property real pulse: 1

    readonly property bool low: Charging.isLow(level)
    readonly property var rl: Charging.roles(low)
    readonly property var st: Charging.introAt(introT)

    readonly property real wDp: width / Theme.density
    readonly property real hDp: height / Theme.density
    readonly property real pillW: Theme.dp(Charging.pillWidthDp(wDp))
    readonly property real pillH: Theme.dp(Charging.pillHeightDp(hDp))
    readonly property real pillTop: (height - pillH) / 2
    // the bottom slot: its bottom 14 dp above the edge; 5 dp tall with the unread dot, else 0 px
    readonly property real slotBottom: height - Theme.dp(Charging.slotBottomDp(Math.min(wDp, hDp)))
    readonly property real slotTop: slotBottom - Theme.dp(Charging.slotHeightDp(unread))
    readonly property var parts: Charging.clockParts(now, use12h)
    readonly property string localeName: currentLocale()
    readonly property var chipInfo: Charging.chip(now, nextAlarmMs, use12h, Qt.locale(localeName).amText,
                                                  Qt.locale(localeName).pmText, formatDate)

    function currentLocale() {
        // the language changed: the locale's words and the date pattern are read again (locale-formats-02)
        void localeManager.localeRevision
        return Qt.locale().name
    }
    // a date in ICU's best pattern for a skeleton, in the screen's locale (the chip: "EEE d")
    function formatDate(d, skeleton) {
        return DateFormat.format(d, skeleton, localeName)
    }
    function roleColor(r) {
        var c = Theme.color[r[0]]
        return Qt.rgba(c.r, c.g, c.b, c.a * r[1])
    }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    // the finished screen
    function finishIntro() {
        introAnim.stop()
        introT = Charging.INTRO_END
        if (introActive) {
            introActive = false
            introFinished()
        }
    }
    onShownChanged: {
        if (shown) {
            // the alarms are read (timed, over D-Bus) from the first time the screen is up on
            if (alarms === null)
                alarms = alarmsComponent.createObject(screen)
            refreshTime()
            if (plugIntro && Motion.animationScale > 0) {
                introT = 0
                introActive = true
            } else {
                finishIntro()
            }
        } else {
            finishIntro()
        }
    }
    // the display went dark in the middle of the intro: it is over (stock relaunches it without)
    onAwakeChanged: {
        if (awake) {
            refreshTime()
        } else if (introActive && introT > 0) {
            finishIntro()
        }
    }

    MceBatteryLevel { id: battery }
    // the next alarm of timed (the source of the alarm complication: read when it starts and when
    // the alarms change, no timer); made when the screen is first up, so that a watch that never sits
    // on the charger holds no alarm model for it
    property var alarms: null
    Component { id: alarmsComponent; ClockSource { active: true } }

    function refreshTime() {
        now = new Date()
        if (alarms) {
            alarms.now = now
            alarms.refresh()
        }
    }
    // up to the minute: one shot that re-arms itself in the handler, only while the screen is up on
    // the awake display; the AP's own minute update draws it in the always-on screen. (A one-shot
    // Timer clears its own running when it fires and the bound 'running' has nothing to re-evaluate,
    // hence the explicit restart.)
    Timer {
        id: minuteTimer
        objectName: "eosChargingMinute"
        running: screen.shown && screen.awake
        repeat: false
        interval: 60000 - (screen.now.getTime() % 60000) + 20
        onTriggered: {
            screen.refreshTime()
            if (screen.shown && screen.awake)
                minuteTimer.restart()
        }
    }
    Connections {
        target: Lipstick.compositor
        function onDisplayAmbientUpdate() { screen.refreshTime() }
        function onDisplayAboutToBeOn() { screen.refreshTime() }
    }

    // the intro
    NumberAnimation {
        id: introAnim
        objectName: "eosChargingIntro"
        target: screen
        property: "introT"
        from: 0
        to: Charging.INTRO_END
        duration: Charging.INTRO_END
        running: screen.introActive && screen.awake && screen.shown
        onFinished: screen.finishIntro()
    }

    // the bolt's pulse: 1.0 for 1 s, 0.3 in 1 s, back to 1.0 in 1 s, on cubic-bezier(0.2, 0, 0, 1);
    // only on the awake screen, below 100 %
    SequentialAnimation {
        id: pulseAnim
        objectName: "eosChargingPulse"
        loops: Animation.Infinite
        running: Charging.pulseRuns(screen.level, screen.awake, screen.shown && screen.visible) && !screen.introActive
        onRunningChanged: if (!running) screen.pulse = 1
        PauseAnimation { duration: Charging.PULSE.holdMs }
        NumberAnimation {
            target: screen; property: "pulse"; to: Charging.PULSE.low; duration: Charging.PULSE.holdMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [Charging.PULSE.curve[0], Charging.PULSE.curve[1], Charging.PULSE.curve[2], Charging.PULSE.curve[3], 1, 1]
        }
        NumberAnimation {
            target: screen; property: "pulse"; to: 1; duration: Charging.PULSE.holdMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [Charging.PULSE.curve[0], Charging.PULSE.curve[1], Charging.PULSE.curve[2], Charging.PULSE.curve[3], 1, 1]
        }
    }

    /* Up at once. Away at once (the crown), or (the unplug: the activity finishes
     * 1000 ms later) with the framework task close, motion A6: scale to 0.75 and
     * fade out, 250 ms on (0.4, 0, 0.2, 1) (windowmotion.js EXIT) */
    opacity: shown ? 1 : 0
    visible: opacity > 0
    scale: shown || !fade ? 1 : WM.EXIT.toScale
    Behavior on opacity {
        enabled: screen.fade
        NumberAnimation {
            duration: Motion.duration(WM.EXIT.durationMs)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: WM.EXIT.bezier
        }
    }
    Behavior on scale {
        enabled: screen.fade
        NumberAnimation {
            duration: Motion.duration(WM.EXIT.durationMs)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: WM.EXIT.bezier
        }
    }

    // the colours of the two sets (normal, low), changing over 300 ms
    property color ringColor: roleColor(rl.ring)
    property color trackColor: roleColor(rl.track)
    property color pillColor: roleColor(rl.pill)
    property color digitColor: roleColor(rl.digit)
    property color chipColor: roleColor(rl.chip)
    property color chipTextColor: roleColor(rl.chipText)
    property color percentColor: roleColor(rl.percent)
    property color boltColor: roleColor(rl.bolt)
    Behavior on ringColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on trackColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on pillColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on digitColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on chipColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on chipTextColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on percentColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }
    Behavior on boltColor { ColorAnimation { duration: Motion.duration(Charging.COLOR_MS) } }

    Accessible.role: Accessible.Pane
    //% "Charging"
    Accessible.name: qsTrId("id-status-charging") + ", " + percentText
    //% "%1%"
    readonly property string percentText: qsTrId("id-charging-percent").arg(level)

    // black, and the touches end here
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }
    MouseArea {
        anchors.fill: parent
        enabled: screen.visible
        onPressed: (mouse) => mouse.accepted = true
        onReleased: (mouse) => mouse.accepted = true
    }

    // the ring: progress 0 -> level (the intro) and then at the pace of the default effects spring
    // (written by the spring below, which sets the first value as it is: no binding here)
    property real shownLevel: 0
    // a level change on the default effects spring itself, 1.0/500 (motion F3); during the intro and
    // while hidden it follows at once
    WearSpring {
        target: screen
        property: "shownLevel"
        to: screen.introActive ? (screen.level / 100) * screen.st.ring : screen.level / 100
        enabled: !screen.introActive && screen.shown
        stiffness: Motion.standard.defaultEffects.stiffness
        dampingRatio: 1.0
        visibilityThreshold: 0.0005
    }
    Item {
        id: ring
        objectName: "eosChargingRing"
        anchors.fill: parent
        rotation: screen.st.ringRotation
        scale: screen.st.ringScale
        visible: !screen.introActive || screen.introT >= Charging.INTRO.ringAt

        readonly property real stroke: Theme.dp(Charging.LAYOUT.ringStrokeDp)
        readonly property real gap: Theme.dp(Charging.LAYOUT.ringGapDp)
        readonly property real radius: Math.min(width, height) / 2 - Theme.dp(Charging.LAYOUT.ringInsetDp) - stroke / 2
        readonly property real gapDeg: radius > 0 ? gap / radius * 180 / Math.PI : 0
        readonly property real fraction: Math.max(0, Math.min(1, screen.shownLevel))

        ProgressArc {
            id: track
            objectName: "eosChargingTrack"
            anchors.fill: parent
            radius: ring.radius
            strokeWidth: ring.stroke
            color: screen.trackColor
            startAngle: ring.fraction > 0 ? 270 + ring.fraction * 360 + ring.gapDeg : 270
            sweepAngle: ring.fraction > 0 ? Math.max(0, 360 * (1 - ring.fraction) - 2 * ring.gapDeg) : 360
        }
        ProgressArc {
            id: bar
            objectName: "eosChargingBar"
            anchors.fill: parent
            radius: ring.radius
            strokeWidth: ring.stroke
            color: screen.ringColor
            startAngle: 270
            sweepAngle: 360 * ring.fraction
        }
    }

    Label {
        id: percent
        objectName: "eosChargingPercent"
        role: "arcSmall"
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.dp(Charging.LAYOUT.percentTopDp)
        text: screen.percentText
        color: screen.percentColor
        opacity: screen.st.percent
        font.weight: Charging.LAYOUT.percentWeight
        font.features: Theme.tabularNumerals
    }

    // the digits' ink ('0') middle digitRiseDp above the pill's middle, whatever the font's ascent and
    // descent (a Label with its own pixel size has Qt's text box, not the role's line box)
    FontMetrics {
        id: digitMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sp(Charging.LAYOUT.digitSp)
        font.weight: Charging.LAYOUT.digitWeight
    }
    function digitOffset(boxHeight) {
        var r = digitMetrics.tightBoundingRect("0")
        return -Theme.dp(Charging.LAYOUT.digitRiseDp) - (digitMetrics.ascent + r.y + r.height / 2 - boxHeight / 2)
    }

    // the clock: hours and minutes in two pills
    Row {
        id: clockRow
        objectName: "eosChargingClock"
        spacing: Theme.dp(Charging.LAYOUT.pillGapDp)
        layoutDirection: Theme.rtl ? Qt.RightToLeft : Qt.LeftToRight
        x: (screen.width - width) / 2
        y: screen.pillTop + Theme.dp(Charging.INTRO.riseDp) * (1 - screen.st.clockRise)
        opacity: screen.st.clockFade

        Rectangle {
            objectName: "eosChargingHours"
            width: screen.pillW
            height: screen.pillH
            radius: Theme.dp(Charging.LAYOUT.hoursCornerDp)
            color: screen.pillColor
            Label {
                objectName: "eosChargingHoursText"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: screen.digitOffset(height)
                role: "numeralLarge"
                text: screen.parts.hours
                color: screen.digitColor
                font.pixelSize: Theme.sp(Charging.LAYOUT.digitSp)
                font.weight: Charging.LAYOUT.digitWeight
                font.features: Theme.tabularNumerals
            }
        }
        Rectangle {
            objectName: "eosChargingMinutes"
            width: screen.pillW
            height: screen.pillH
            radius: Theme.dp(Charging.LAYOUT.minutesCornerDp)
            color: screen.pillColor
            Label {
                objectName: "eosChargingMinutesText"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: screen.digitOffset(height)
                role: "numeralLarge"
                text: screen.parts.minutes
                color: screen.digitColor
                font.pixelSize: Theme.sp(Charging.LAYOUT.digitSp)
                font.weight: Charging.LAYOUT.digitWeight
                font.features: Theme.tabularNumerals
            }
        }
    }

    // the date, or the next alarm within 24 h
    Rectangle {
        id: chip
        objectName: "eosChargingChip"
        readonly property bool alarm: screen.chipInfo.kind === "alarm"
        width: chipRow.width + 2 * Theme.dp(Charging.LAYOUT.chipPadXDp)
        // the labelSmall line (16 sp), not the label's own box (taller with Noto's metrics)
        height: Theme.type.labelSmall.lineHeight + 2 * Theme.dp(Charging.LAYOUT.chipPadYDp)
        radius: height / 2
        color: screen.chipColor
        x: (screen.width - width) / 2
        // centred between the clock's bottom and the bottom slot (imm.java:64)
        y: Charging.chipTop(screen.pillTop + screen.pillH, screen.slotTop, height)
           + Theme.dp(Charging.INTRO.riseDp) * (1 - screen.st.chipRise)
        opacity: screen.st.chipFade
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.dp(Charging.LAYOUT.chipIconGapDp)
            Icon {
                objectName: "eosChargingChipIcon"
                visible: chip.alarm
                name: "ios-alarm"
                width: visible ? Theme.dp(Charging.LAYOUT.chipIconDp) : 0
                height: Theme.dp(Charging.LAYOUT.chipIconDp)
                color: screen.chipTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                objectName: "eosChargingChipText"
                role: "labelSmall"
                text: screen.chipInfo.text
                color: screen.chipTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // the bolt: from the middle of the intro to its place, 24 dp, 6 dp above the clock
    Bolt {
        id: bolt
        readonly property real m: screen.st.boltMove
        readonly property real introSize: Theme.dp(Charging.INTRO.boltBoxPx / 2) * screen.st.boltScale
        readonly property real restSize: Theme.dp(Charging.LAYOUT.boltDp)
        readonly property real restCentreY: screen.pillTop - Theme.dp(Charging.LAYOUT.boltGapDp) - restSize / 2
        size: introSize + (restSize - introSize) * m
        x: (screen.width - width) / 2
        y: (screen.height / 2 + (restCentreY - screen.height / 2) * m) - height / 2
        trace: screen.st.trace
        stroke: screen.st.stroke * Charging.BOLT.box / Charging.INTRO.boltBoxPx
        outlineOpacity: screen.st.outline
        fillOpacity: screen.st.fill
        outlineColor: Theme.color.onBackground
        fillColor: screen.mix(screen.roleColor(Charging.introBoltRole(screen.low)), screen.boltColor, m)
        opacity: screen.pulse
    }

    // the unread dot in the bottom slot (bae.java:172-215): the emulator's 5 dp primary dot (S03-c,
    // x 187-196, y 346-355); CP3A's composable draws nothing there (ini.java:2498-2508)
    Rectangle {
        objectName: "eosChargingDot"
        visible: screen.unread
        width: Theme.dp(Charging.LAYOUT.unreadDp)
        height: width
        radius: width / 2
        color: Theme.color.primary
        antialiasing: true
        x: (screen.width - width) / 2
        y: screen.slotBottom - height
        opacity: screen.st.dot
    }
}
