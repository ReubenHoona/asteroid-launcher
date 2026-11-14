/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import "facepicker.js" as FP

/*
 * The style options of one favourite (face-interaction-20): the date, the
 * seconds and the always-on look, stored per favourite id in dconf
 * /org/asteroidos/watchface/style/<id> as a JSON object. A favourite that
 * has no value of its own yet reads today's global keys
 * (/org/asteroidos/watchface/show-date, show-seconds, ambient-style), which
 * is how the values the watch had before the favourites are carried into
 * every existing favourite; the first change writes all three, so from then
 * on the favourite is its own.
 *
 * W3-launcher-faces (watchface-catalogue-10): a face with a schema (its eosOptions,
 * watchfaces/eos/facekit.js) has more options (Color, Layout, Styles, Fonts, Bold
 * Time, Seconds ...): they live in the same JSON object under their ids, `values`
 * hands them to the face (its eosStyle), and `set` keeps every other key. The
 * schema's "seconds" option is the old "show-seconds" key; its default (a face that
 * has the option) is the face's own, not the global key's.
 */
Item {
    id: style
    visible: false
    width: 0
    height: 0

    // the favourite (empty: the globals)
    property string faceId: ""
    // the face's option schema (its eosOptions; empty for a face without one)
    property var schema: []

    ConfigurationValue {
        id: own
        key: FP.styleKey(style.faceId)
        defaultValue: ""
    }
    ConfigurationValue { id: globalDate; key: "/org/asteroidos/watchface/show-date"; defaultValue: true }
    ConfigurationValue { id: globalSeconds; key: "/org/asteroidos/watchface/show-seconds"; defaultValue: true }
    ConfigurationValue { id: globalAmbient; key: "/org/asteroidos/watchface/ambient-style"; defaultValue: "dim" }

    readonly property var _own: style.faceId === "" ? ({}) : FP.parseStyle(own.value)
    readonly property bool hasOwn: _own["show-date"] !== undefined

    readonly property bool showDate: _own["show-date"] !== undefined ? _own["show-date"] === true : globalDate.value === true
    readonly property var _secondsDefault: FP.secondsDefault(schema)
    readonly property bool showSeconds: _own["show-seconds"] !== undefined ? _own["show-seconds"] === true
                                        : (_secondsDefault !== undefined ? _secondsDefault : globalSeconds.value === true)
    // the choices the face reads (eosStyle): every stored key, and "seconds" as it is in force
    readonly property var values: {
        var o = {}
        for (var k in _own)
            o[k] = _own[k]
        o["seconds"] = showSeconds
        return o
    }
    readonly property string ambientStyle: _own["ambient-style"] !== undefined ? String(_own["ambient-style"]) : String(globalAmbient.value)

    // one option changed: "show-date", "show-seconds", "ambient-style" or the id of a schema option
    function set(name, value) {
        if (style.faceId === "")
            return
        var o = {}
        for (var k in _own)
            o[k] = _own[k]
        o["show-date"] = showDate
        o["show-seconds"] = showSeconds
        o["ambient-style"] = ambientStyle
        o[name] = value
        own.value = JSON.stringify(o)
    }
}
