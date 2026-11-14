/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick

/*
 * The fallback face (watchface-catalogue-27): what the home screen shows when the
 * chosen face cannot load, as SysUI's hidden "Simple" face. White "HH:MM" at 100 px
 * (time_font_size 50 dp), the digits 13.1 px each side of the middle
 * (time_digits_center_offset 6.55 dp), the colon two dots of radius 4 px
 * (delimiter_radius 2 dp) 16.7 px above and below the middle
 * (delimiter_spacing_from_center 8.37 dp), black background, ambient text #808080
 * (default_watch_face_ambient_text): SYSUI iqp.java:75-97,131-155, VALUES.tsv. The
 * numbers are px of a 384 px screen; the face scales them. 12 h: "h", no leading zero.
 *
 * The sensor hub draws the always-on time (eosHubHour, eosHubMinute: Roboto, tabular
 * digits, NativeRendering): no AP wake per minute; nothing here has a timer.
 */
Item {
    id: simple
    objectName: "eosSimpleFace"
    anchors.fill: parent

    property bool ambientOwnStyle: true
    property bool eosHubDrawn: true

    readonly property real k: width / 384
    readonly property bool ambient: typeof displayAmbient !== "undefined" && displayAmbient === true
    readonly property bool use12: typeof use12H !== "undefined" && use12H !== null && use12H.value === true
    readonly property date now: typeof wallClock !== "undefined" && wallClock !== null ? wallClock.time : new Date(2026, 0, 1, 10, 8, 0)
    readonly property int hour24: now.getHours()
    readonly property int minute: now.getMinutes()
    readonly property color ink: ambient ? "#808080" : "#ffffff"

    readonly property real size: 100 * k
    readonly property real offset: 13.1 * k
    readonly property real dotRadius: 4 * k
    readonly property real dotOffset: 16.7 * k
    // the digits' middle at the middle of the screen (Roboto of the image: the digits' middle is 0.688 em from the line's top)
    readonly property real digitsTop: height / 2 - 0.688 * size

    Text {
        id: hourText
        objectName: "eosHubHour"
        x: simple.width / 2 - simple.offset - implicitWidth
        y: simple.digitsTop
        text: simple.use12 ? String(simple.hour24 % 12 === 0 ? 12 : simple.hour24 % 12)
                           : (simple.hour24 < 10 ? "0" : "") + simple.hour24
        color: simple.ink
        renderType: Text.NativeRendering
        font.family: "Roboto"
        font.weight: Font.Normal
        font.pixelSize: Math.round(simple.size)
    }
    Text {
        id: minuteText
        objectName: "eosHubMinute"
        x: simple.width / 2 + simple.offset
        y: simple.digitsTop
        text: (simple.minute < 10 ? "0" : "") + simple.minute
        color: simple.ink
        renderType: Text.NativeRendering
        font.family: "Roboto"
        font.weight: Font.Normal
        font.pixelSize: Math.round(simple.size)
    }
    Rectangle {
        objectName: "eosSimpleDotTop"
        width: 2 * simple.dotRadius
        height: width
        radius: simple.dotRadius
        color: simple.ink
        x: simple.width / 2 - simple.dotRadius
        y: simple.height / 2 - simple.dotOffset - simple.dotRadius
    }
    Rectangle {
        objectName: "eosSimpleDotBottom"
        width: 2 * simple.dotRadius
        height: width
        radius: simple.dotRadius
        color: simple.ink
        x: simple.width / 2 - simple.dotRadius
        y: simple.height / 2 + simple.dotOffset - simple.dotRadius
    }
}
