/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * Text along the top edge of the round screen, read left to right, centred
 * at 12 o'clock (stock CurvedTextView / CurvedLayout, anchor 270 degrees),
 * as the watch face picker names its faces. The letters' tops sit
 * `topMargin` from the screen edge; past `maxSweep` degrees the text ends in
 * an ellipsis. The mirror of qml-asteroid's CurvedText (bottom edge); fill
 * the screen with it (anchors.fill, or the size of the screen when it moves
 * with an item). `pixelSize` is in px and not scaled by the font size
 * setting (stock: a fixed 15 dp).
 */
Item {
    id: curved

    property string text: ""
    property color color: Theme.color.onBackground
    // a Theme type role for weight and width
    property string role: "labelMedium"
    property real pixelSize: Theme.dp(15)
    property real maxSweep: 90
    // the letters' top from the screen edge, px
    property real topMargin: 8
    // the colour of the 1 px shadow under the letters ("" none)
    property color shadow: "#dd000000"

    readonly property var _role: Theme.type[role] || Theme.type.labelMedium
    readonly property real lineHeight: pixelSize * _role.lineHeight / _role.pixelSize
    // the radius of the middle of the letters
    readonly property real radius: Math.min(width, height) / 2 - topMargin - lineHeight / 2
    readonly property var _chars: text.split("")
    readonly property string _styleName: {
        var names = { 100: "Thin", 200: "ExtraLight", 300: "Light", 400: "", 500: "Medium",
                      600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black" }
        var w = Math.max(100, Math.min(900, Math.round(_role.weight / 100) * 100))
        return (_role.width < 95 ? "SemiCondensed " + names[w] : names[w]).trim()
    }

    readonly property var _widths: {
        var widths = []
        for (var i = 0; i < _chars.length; i++) {
            var item = _letters.count > i ? _letters.itemAt(i) : null
            widths.push(item ? item.advance : 0)
        }
        return widths
    }
    readonly property real _maxLength: maxSweep * Math.PI / 180 * Math.max(1, radius)
    // the whole text along the arc, px
    readonly property real naturalLength: {
        var t = 0
        for (var i = 0; i < _widths.length; i++)
            t += _widths[i]
        return t
    }
    readonly property bool fits: naturalLength <= _maxLength
    readonly property int _shown: {
        if (fits)
            return _widths.length
        var room = _maxLength - _ellipsis.advance
        var t = 0, n = 0
        while (n < _widths.length && t + _widths[n] <= room) {
            t += _widths[n]
            n++
        }
        return n
    }
    readonly property bool _elided: _shown < _chars.length
    readonly property real _length: {
        var t = 0
        for (var i = 0; i < _shown; i++)
            t += _widths[i]
        return t + (_elided ? _ellipsis.advance : 0)
    }
    // the angle the drawn text spans, degrees
    readonly property real sweep: radius > 0 ? _length / radius * 180 / Math.PI : 0
    readonly property var _mids: {
        var mids = []
        var x = -_length / 2
        for (var j = 0; j < _shown; j++) {
            mids.push(x + _widths[j] / 2)
            x += _widths[j]
        }
        mids.push(x + _ellipsis.advance / 2)
        return mids
    }

    component Letter: Text {
        readonly property real advance: implicitWidth
        property real along: 0
        // radians from 12 o'clock, positive to the reader's right
        readonly property real angle: curved.radius > 0 ? along / curved.radius : 0
        color: curved.color
        style: curved.shadow.a > 0 ? Text.Raised : Text.Normal
        styleColor: curved.shadow
        font.family: Theme.fontFamily
        font.pixelSize: curved.pixelSize
        font.weight: curved._role.weight
        font.styleName: curved._styleName
        font.letterSpacing: curved._role.letterSpacing
        font.variableAxes: curved._role.axes
        x: curved.width / 2 + curved.radius * Math.sin(angle) - width / 2
        y: curved.height / 2 - curved.radius * Math.cos(angle) - height / 2
        rotation: angle * 180 / Math.PI
    }

    Repeater {
        id: _letters
        model: curved._chars.length
        delegate: Letter {
            visible: index < curved._shown
            text: curved._chars[index] !== undefined ? curved._chars[index] : ""
            along: curved._mids[index] !== undefined ? curved._mids[index] : 0
        }
    }
    Letter {
        id: _ellipsis
        visible: curved._elided
        text: "…"
        along: curved._mids.length > 0 ? curved._mids[curved._mids.length - 1] : 0
    }
}
