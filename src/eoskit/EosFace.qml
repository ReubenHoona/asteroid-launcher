/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * The root of the eos watch faces (W3-launcher-faces): what every face of the
 * Wear OS layouts shares.
 *
 *  - Options (watchface-catalogue-10): the face sets `eosOptions` (a list of
 *    Kit.colorOption / listOption / boolOption); the launcher's editor shows a
 *    page per entry and writes the favourite's choices into `eosStyle`
 *    ({id: value}); `opt(id)` is the value in force (the choice, else the
 *    default). Two favourites of the same face are two instances with two
 *    `eosStyle`s (watchface-catalogue-28).
 *  - The time (watchface-catalogue-26): "h:mm" in 12 h, "HH:mm" in 24 h, no
 *    AM/PM, no leading zero in 12 h (hourStr, minuteStr); it follows
 *    use12H and wallClock of the home screen.
 *  - The face picker's picture (N61-35): with `eosPreviewTime` set (a Date)
 *    the face shows that time, interactive, instead of the wall clock: the
 *    launcher draws each favourite once at 10:09 (FacePreviewRenderer).
 *  - The always-on look (watchface-catalogue-25, ambient-aod-21): the face owns
 *    it (`ambientOwnStyle`: the launcher does not dim the whole panel), a
 *    thinner time weight and dimmer colours through `blend`, which steps 0 to 1
 *    in one frame when the display goes always-on and back at once at the wake
 *    (the Wear OS 6 emulator, motion M13: no frame in between; A-02). Nothing
 *    here animates or has a timer.
 *  - The sensor hub (M1): a digital face names its time Text items eosHubHour
 *    and eosHubMinute (EosNumber does) so the hub draws the always-on time;
 *    `eosHubDrawn` says so. An analog or word face sets it false: the AP draws
 *    its always-on minute (the picker marks it).
 */
Item {
    id: face
    anchors.fill: parent

    // the options the face has, and the favourite's values
    property var eosOptions: []
    property var eosStyle: ({})
    // the face draws its own always-on look
    property bool ambientOwnStyle: true
    // the sensor hub draws the always-on time of this face
    property bool eosHubDrawn: true
    // the face's colour for the system theme (face-interaction-31)
    readonly property string seedColor: String(accent)

    // the time of a picture (a Date), or null: the wall clock
    property var eosPreviewTime: null
    readonly property bool previewing: eosPreviewTime !== null && eosPreviewTime !== undefined

    // ---- the clock of the home screen ----
    readonly property bool ambient: !previewing && typeof displayAmbient !== "undefined" && displayAmbient === true
    readonly property bool use12: typeof use12H !== "undefined" && use12H !== null && use12H.value === true
    readonly property date now: previewing ? eosPreviewTime
                                : typeof wallClock !== "undefined" && wallClock !== null ? wallClock.time : new Date(2026, 0, 1, 10, 8, 0)
    readonly property int hour24: now.getHours()
    readonly property int minute: now.getMinutes()
    readonly property int second: now.getSeconds()
    readonly property string hourStr: Kit.hourText(hour24, use12)
    readonly property string minuteStr: Kit.minuteText(minute)

    // ---- options ----
    function opt(id) { return Kit.optionValue(eosOptions, eosStyle, id) }
    readonly property color accent: Kit.accentColor(opt("color"), "cloud")
    readonly property color accentAmbient: Kit.ambientColor(accent)
    // the colourway's other roles (Kit.colorRole): the text colour, the second tone of a two-tone one ("c"),
    // and the light ramp ("e")
    readonly property color accent2: Kit.colorRole(opt("color"), "c", "cloud")
    readonly property color accentLight: Kit.colorRole(opt("color"), "e", "cloud")
    readonly property color white: "#ffffff"
    readonly property color whiteAmbient: Kit.ambientColor("#ffffff")
    readonly property bool boldTime: opt("boldTime") === true
    // one px of the 384 px design on this screen
    readonly property real k: width / Kit.BASE

    // ---- the always-on blend: 0 interactive, 1 always-on ----
    // both ways in one frame (Kit.AMBIENT_MS 0: the Wear OS 6 emulator steps, motion M13; A-02)
    property real blend: 0
    Component.onCompleted: blend = ambient ? 1 : 0
    onAmbientChanged: blend = ambient ? 1 : 0
}
