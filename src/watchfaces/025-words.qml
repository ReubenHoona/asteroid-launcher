// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Words: the layout of Wear OS's Prime face (watch_face_wordclock.xml), our own
 * artwork (watchface-catalogue-37, the audit's F8). The time in three lines of
 * 64 px words: the hour in the accent at the left, "Oh" or the tens at the left
 * under it, the minutes' units in white at the right ("Ten / Oh / Nine" is 10:09);
 * one empty top line slot. English words (the other languages fall back to them).
 * Color Pomelo.
 * Always-on: the words are drawn by the AP once a minute (they change every
 * minute, nothing the hub can draw): eosHubDrawn is false and the picker says so.
 * They are thin and dim in the always-on screen.
 */
EosFace {
    id: face

    eosHubDrawn: false

    eosOptions: [ Kit.colorOption("pomelo") ]
    readonly property var g: Kit.WORDS
    readonly property var d: Kit.SLOT_DEFAULTS.words
    readonly property var lines: Kit.words(hour24, minute, use12)
    readonly property real px: g.size * k

    Repeater {
        model: 3
        delegate: Text {
            objectName: "eosWord" + index
            readonly property var line: face.g.lines[index]
            text: face.lines[index]
            color: index === 0 ? (face.blend > 0.5 ? face.accentAmbient : face.accent)
                               : (face.blend > 0.5 ? face.whiteAmbient : face.white)
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.weight: face.blend > 0.5 ? Font.Thin : Font.Light
            font.pixelSize: Math.round(face.px)
            // the first two lines are set at the left, the third at the right
            x: index < 2 ? face.g.left * face.k : face.width - face.g.right * face.k - width
            y: Kit.digitTop((line.y + line.h / 2) * face.k, face.px)
        }
    }

    EosSlot {
        owner: face; slotId: "top"; shape: "text"; defaultSource: face.d.top; spec: face.g.top
    }
}
