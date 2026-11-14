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
 */
Item {
    id: style
    visible: false
    width: 0
    height: 0

    // the favourite (empty: the globals)
    property string faceId: ""

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
    readonly property bool showSeconds: _own["show-seconds"] !== undefined ? _own["show-seconds"] === true : globalSeconds.value === true
    readonly property string ambientStyle: _own["ambient-style"] !== undefined ? String(_own["ambient-style"]) : String(globalAmbient.value)

    // one option changed: "show-date", "show-seconds" or "ambient-style"
    function set(name, value) {
        if (style.faceId === "")
            return
        var o = { "show-date": showDate, "show-seconds": showSeconds, "ambient-style": ambientStyle }
        o[name] = value
        own.value = JSON.stringify(o)
    }
}
