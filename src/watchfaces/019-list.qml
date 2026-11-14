// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * List: the layout of Wear OS's Index face (watch_face_utilita.xml), our own
 * artwork (watchface-catalogue-31, the audit's F2). Day and date on top, hours
 * over minutes stacked at the left (bold by default), four line slots at the
 * right (Next event, Steps, Weather, Heart rate). Color Limoncello; Bold Time
 * on; Seconds off (when on, small seconds under the minutes, interactive only).
 * Always-on: the same, the digits drawn by the sensor hub.
 */
EosFace {
    id: face

    // the launcher ticks every second only while the seconds show
    readonly property bool eosUsesSeconds: true

    eosOptions: [
        Kit.colorOption("limoncello"),
        Kit.boolOption("boldTime", true),
        Kit.boolOption("seconds", false)
    ]
    readonly property var g: Kit.list()
    readonly property var d: Kit.SLOT_DEFAULTS.list

    EosTimeStack {
        objectName: "eosTime"
        owner: face
        hourBox: face.g.hour
        minuteBox: face.g.minute
        size: face.g.size
    }

    // small seconds under the minutes (the launcher hides it when Seconds is off and in always-on)
    Text {
        id: secondsText
        objectName: "eosSecondsText"
        x: (face.g.minute.x + face.g.minute.w / 2) * face.k - width / 2
        y: (face.g.minute.y + face.g.minute.h + 4) * face.k
        text: Kit.pad2(face.second)
        color: face.white
        opacity: 0.8
        renderType: Text.NativeRendering
        font.family: Kit.FONT
        font.weight: Font.Light
        font.pixelSize: Math.round(26 * face.k)
        visible: face.blend < 1
    }

    EosSlot {
        owner: face; slotId: "top"; shape: "text"; defaultSource: face.d.top; spec: face.g.top
    }
    EosSlot {
        owner: face; slotId: "one"; shape: "text"; defaultSource: face.d.one; spec: face.g.lines[0]
    }
    EosSlot {
        owner: face; slotId: "two"; shape: "text"; defaultSource: face.d.two; spec: face.g.lines[1]
    }
    EosSlot {
        owner: face; slotId: "three"; shape: "text"; defaultSource: face.d.three; spec: face.g.lines[2]
    }
    EosSlot {
        owner: face; slotId: "four"; shape: "text"; defaultSource: face.d.four; spec: face.g.lines[3]
    }
}
