// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import org.asteroid.controls
import "../eoskit"
import "../eoskit/facekit.js" as Kit
import "../eoskit/concentric.js" as C

/*
 * Concentric: stock Wear OS's default face (rwf "orbita", watch_face_orbita.xml; the catalogue
 * audit's row 15, D60-48), in the look of the Wear OS 6 emulator (BP2A). Our own drawing from
 * measurements; the numbers live in eoskit/concentric.js. In 384 px design units:
 *
 *   what                        stock evidence                                   here
 *   hour "06"                   S01 ink 144..239 x 161..226, 10 px stroke;       Roboto 90 px Medium, ink left 144,
 *                               S02 the same box, 6 px stroke (wght 440 / 300)    digits' middle 193.5; Light always-on
 *   minute "33"                 S01 ink 267..306 x 179..207, 4 px stroke;        Roboto 40 px Regular, ink left 266.5,
 *                               S02 266..306, 3 px stroke                         middle 193; Light always-on
 *   pill                        S01 2 px stroke, y 157..158 / 225..226, left     Rectangle 251,157, height 70, radius 35,
 *                               edge 251..252: radius 34 round (286, 192),        border 2, running off the right edge
 *                               off the right edge (fio.D)                        (width 170)
 *   always-on circle            S02 the same circle, radius 34, 2 px             the pill's right end moves in (width 70)
 *   outer dial (seconds)        numerals at r 160.0, white (Cloud's text         Roboto 23 px Regular, 17 px digits,
 *                               colour), 17 px tall, 31 px wide                   colour option's text colour
 *   inner dial (minutes)        numerals at r 106.1, #767a80 (S01 max 128)       the same font, #767a80
 *   tick rings                  60 ticks, 2 px, #5f6368: outer 182..189 and      Rectangles, the same radii
 *                               176..190 (long), inner 130.5..137.5, 124..138
 *   scrims                      awake a black rect 262..311 x 158.5..225.5 over  the same
 *                               the inner numerals in the pill; always-on a
 *                               black disk r 34 at (288, 192) under the circle
 *   motion (M13)                outer dial sweeps 6 degrees/s at every frame,    one 1 s linear animation per tick of
 *                               inner 0.1 degree/s; always-on: whole minute       the wall clock (ends when the clock
 *                                                                                 stops); always-on: the whole minute
 *   always-on (S02)             outer numerals gone, outer ticks still (at 0),   the same; the switch over EosFace's
 *                               thin digits, circle; the switch is a cut (M13)    blend (300 ms in, at once out)
 *
 * Options: Color (default Cloud: white dial and pill), Layout: Dial I (default) and Dial II (no tick
 * rings). Stock's Half Dial (the face moved left, three complications) is not built.
 * The hour has two digits in 12 h too ("06", stock); the minute is in the pill.
 *
 * The sensor hub draws the always-on face (huboffload.cpp): the hour and the minute are
 * eosHubHour and eosHubMinute (12 h with a leading zero: eosHubZeroPad); the inner dial is
 * eosHubDial: its numerals and long ticks are sprites on 60 fixed slots whose glyph the hub picks
 * from its minute (slot j shows value (minute + j) % 60 when that is a multiple of 5). The rest is
 * the background, which the AP draws once: the outer ticks, the inner short ticks (a ring that
 * stands still always-on) and what lies over the dial, the black disk and the circle (eosHubCover):
 * the hub cuts their part out of the slots' cells, so it never draws a sprite over anything but
 * black. So the AP sleeps through the minutes.
 */
EosFace {
    id: face

    // the seconds dial: the home screen's clock ticks every second while the face shows
    readonly property bool eosUsesSeconds: true

    eosOptions: [
        Kit.colorOption("cloud"),
        Kit.listOption("layout", C.LAYOUTS, C.LAYOUT_NAMES, "dial1")
    ]
    readonly property bool ticksShown: opt("layout") !== "dial2"
    // the dial's and the pill's colour: the colorway's text colour (white for Cloud)
    readonly property color ringColor: C.textColor(opt("color"))
    readonly property int numeralPx: Math.round(C.NUMERAL_PX * k)

    // ---- the sweep: seconds of the day, moving on between the clock's ticks ----
    property real sweep: 0
    readonly property bool sweeping: !ambient && Motion.animationScale > 0
    readonly property real secondsT: C.secondsT(sweep)
    readonly property real minutesT: ambient ? minute : C.minutesT(sweep)
    NumberAnimation {
        id: sweepAnim
        target: face
        property: "sweep"
        duration: 1000
        easing.type: Easing.Linear
    }
    // at every tick of the clock: from now to a second later (when the clock stops, so does this)
    function syncSweep() {
        var s = C.secondsOfDay(now)
        sweepAnim.stop()
        sweep = s
        if (sweeping) {
            sweepAnim.from = s
            sweepAnim.to = s + 1
            sweepAnim.start()
        }
    }
    onNowChanged: syncSweep()
    onSweepingChanged: syncSweep()
    Component.onCompleted: syncSweep()

    // ---- parts ----
    // a ring of 60 ticks round the middle, turned clockwise by `turn` degrees; the long ones at
    // every fifth (the numerals); the short ones under them too (showMinor, showMajor: one kind only)
    component TickRing: Item {
        id: ring
        property var spec: C.SECONDS_TICKS
        property real turn: 0
        property string majorName: ""
        property bool showMinor: true
        property bool showMajor: true
        x: face.width / 2
        y: face.height / 2
        width: 0
        height: 0
        rotation: turn
        Repeater {
            model: 60
            delegate: Item {
                rotation: -index * 6
                Rectangle {
                    visible: ring.showMinor
                    x: ring.spec.minor[0] * face.k
                    y: -height / 2
                    width: (ring.spec.minor[1] - ring.spec.minor[0]) * face.k
                    height: C.TICK_WIDTH * face.k
                    color: C.TICK_COLOR
                    antialiasing: true
                }
                Rectangle {
                    objectName: ring.majorName
                    visible: ring.showMajor && index % 5 === 0
                    x: ring.spec.major[0] * face.k
                    y: -height / 2
                    width: (ring.spec.major[1] - ring.spec.major[0]) * face.k
                    height: C.TICK_WIDTH * face.k
                    color: C.TICK_COLOR
                    antialiasing: true
                }
            }
        }
    }
    // a dial numeral (00 ... 55) upright at its angle: value v at (v - t) * 6 degrees
    component Numeral: Text {
        property real radius: C.SECONDS_RADIUS
        property real t: 0
        property int value: 0
        readonly property var at: C.numeralTopLeft(radius, C.numeralAngle(value, t), implicitWidth, face.k,
                                                   font.pixelSize, Kit.DIGIT_CENTER, face.ambient)
        x: at.x
        y: at.y
        text: C.pad2(value)
        renderType: Text.NativeRendering
        font.family: Kit.FONT
        font.pixelSize: face.numeralPx
        font.weight: Font.Normal
    }
    // the hour or the minute: the awake weight and the always-on weight (the hub's item), cross-faded
    // by the blend; left aligned, as stock's boxes (the first digit's ink at inkLeft)
    component DigitsText: Item {
        id: tt
        property string text: ""
        property real px: 90
        property int liveWeight: Font.Medium
        property int ambientWeight: Font.Light
        property string hubName: ""
        property real inkLeft: 0
        property real centerY: 0
        readonly property Item hubItem: amb
        FontMetrics { id: liveMetrics; font: live.font }
        FontMetrics { id: ambMetrics; font: amb.font }
        Text {
            id: live
            x: Math.round(tt.inkLeft - liveMetrics.tightBoundingRect("0").x)
            y: Math.round(Kit.digitTop(tt.centerY, font.pixelSize))
            visible: face.blend < 1
            opacity: 1 - face.blend
            text: tt.text
            color: "white"
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.pixelSize: Math.round(tt.px)
            font.weight: tt.liveWeight
        }
        Text {
            id: amb
            objectName: tt.hubName
            // the hour keeps its leading zero in 12 h: the hub's layout has it too (huboffload.cpp)
            property bool eosHubZeroPad: true
            x: Math.round(tt.inkLeft - ambMetrics.tightBoundingRect("0").x)
            y: Math.round(Kit.digitTop(tt.centerY, font.pixelSize))
            visible: face.blend > 0
            opacity: face.blend
            text: tt.text
            color: "white"
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.pixelSize: Math.round(tt.px)
            font.weight: tt.ambientWeight
        }
    }

    // ---- the outer tick ring: turning with the seconds awake, still (at 0) always-on ----
    TickRing {
        objectName: "eosConcentricSecondsTicks"
        spec: C.SECONDS_TICKS
        turn: C.ringTurn(face.secondsT)
        visible: face.ticksShown && face.blend < 1
        opacity: 1 - face.blend
    }
    TickRing {
        objectName: "eosConcentricAmbientTicks"
        spec: C.SECONDS_TICKS
        turn: 0
        visible: face.ticksShown && face.blend > 0
        opacity: face.blend
    }

    // ---- the inner dial: the minutes (the sensor hub draws it always-on) ----
    Item {
        id: minutesDial
        objectName: "eosHubDial"
        anchors.fill: parent

        // for the sensor hub (huboffload.cpp): the minute shown, where a numeral Text's top-left is
        // at slot j at a whole minute, and where the long tick of slot j runs (this item's px)
        readonly property int eosHubMinute: face.minute
        readonly property real eosHubTickWidth: C.TICK_WIDTH * face.k
        readonly property color eosHubTickColor: C.TICK_COLOR
        function eosHubSlotOrigin(j) {
            var p = C.numeralTopLeft(C.MINUTES_RADIUS, j * 6, minuteNumerals.itemAt(0).implicitWidth, face.k,
                                     face.numeralPx, Kit.DIGIT_CENTER, true)
            return Qt.point(p.x, p.y)
        }
        function eosHubTick(j) {
            var l = C.tickLine(j * 6, C.MINUTES_TICKS.major[0], C.MINUTES_TICKS.major[1])
            return { x1: l.x1 * face.k, y1: l.y1 * face.k, x2: l.x2 * face.k, y2: l.y2 * face.k }
        }

        // awake: one ring of short and long ticks turning with the minutes (and the seconds)
        TickRing {
            objectName: "eosConcentricMinutesTicks"
            spec: C.MINUTES_TICKS
            turn: C.ringTurn(face.minutesT)
            visible: face.ticksShown && !face.ambient
        }
        // always-on: the short ticks stand still, so they are the same pixels at every minute (the
        // hub's background has them), and only the long ones turn with the minute (the hub's slots).
        // The rings change at the switch (the turn is on the whole minute from then on), not over
        // the blend: the same ticks, so no cross-fade of two copies
        TickRing {
            objectName: "eosConcentricMinutesShortTicks"
            spec: C.MINUTES_TICKS
            turn: 0
            showMajor: false
            visible: face.ticksShown && face.ambient
        }
        TickRing {
            objectName: "eosConcentricMinutesLongTicks"
            spec: C.MINUTES_TICKS
            turn: C.ringTurn(face.minutesT)
            showMinor: false
            majorName: "eosHubDialTick"
            visible: face.ticksShown && face.ambient
        }
        Repeater {
            id: minuteNumerals
            model: 12
            delegate: Numeral {
                objectName: "eosHubDialNumeral"
                radius: C.MINUTES_RADIUS
                t: face.minutesT
                value: index * 5
                color: C.MINUTES_COLOR
            }
        }
    }

    // ---- the black under the pill: awake a box over the inner numerals in it, always-on a disk ----
    Rectangle {
        objectName: "eosConcentricScrim"
        visible: face.blend < 1
        opacity: 1 - face.blend
        x: C.SCRIM_RECT.x * face.k
        y: C.SCRIM_RECT.y * face.k
        width: C.SCRIM_RECT.w * face.k
        height: C.SCRIM_RECT.h * face.k
        color: "black"
    }
    Rectangle {
        objectName: "eosHubCover"
        visible: face.blend > 0
        opacity: face.blend
        x: (C.SCRIM_DISK.cx - C.SCRIM_DISK.r) * face.k
        y: (C.SCRIM_DISK.cy - C.SCRIM_DISK.r) * face.k
        width: 2 * C.SCRIM_DISK.r * face.k
        height: width
        radius: width / 2
        color: "black"
        // a cover is a fill or a border (huboffload.cpp): no border
        border.width: 0
        antialiasing: true
    }

    // ---- the outer dial: the seconds, awake only ----
    Item {
        objectName: "eosConcentricSecondsDial"
        anchors.fill: parent
        visible: face.blend < 1
        opacity: 1 - face.blend
        Repeater {
            model: 12
            delegate: Numeral {
                objectName: "eosConcentricSecond"
                radius: C.SECONDS_RADIUS
                t: face.secondsT
                value: index * 5
                color: face.ringColor
            }
        }
    }

    // ---- the pill, a circle always-on ----
    Rectangle {
        objectName: "eosHubCover"
        readonly property real outer: C.PILL.r + C.PILL.stroke / 2
        x: (C.PILL.cx - outer) * face.k
        y: (C.PILL.cy - outer) * face.k
        width: C.pillWidth(face.blend) * face.k
        height: 2 * outer * face.k
        radius: height / 2
        color: "transparent"
        border.width: C.PILL.stroke * face.k
        border.color: face.ringColor
        antialiasing: true
    }

    // ---- the time ----
    DigitsText {
        objectName: "eosConcentricHour"
        text: C.hourText(face.hour24, face.use12)
        px: C.HOUR.px * face.k
        liveWeight: Font.Medium
        ambientWeight: Font.Light
        hubName: "eosHubHour"
        inkLeft: C.HOUR.inkLeft * face.k
        centerY: C.HOUR.centerY * face.k
    }
    DigitsText {
        objectName: "eosConcentricMinute"
        text: face.minuteStr
        px: C.MINUTE.px * face.k
        liveWeight: Font.Normal
        ambientWeight: Font.Light
        hubName: "eosHubMinute"
        inkLeft: C.MINUTE.inkLeft * face.k
        centerY: C.MINUTE.centerY * face.k
    }
}
