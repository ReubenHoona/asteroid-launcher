// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "eos"
import "eos/facekit.js" as Kit

/*
 * Bold numerals: the layout of Wear OS's Analog Bold face (watch_face_analogbold.xml),
 * our own artwork (watchface-catalogue-35, the audit's F6). Three very large rounded
 * numerals 12, 9 and 6, a date window at 3 o'clock, a thin seconds hand. Styles No
 * Dashes (default), Dashes & Dots, Dashes; Fonts Standard or Rounded (default);
 * Layout Numerals, Date (default), Info I (one bulb low centre), Info II (bulbs left
 * and right) or Info IV (four arcs on the rim); Seconds on; Color Flamingo.
 * Always-on: the numerals go light and dim, the window and the seconds hand are
 * hidden; the AP draws the minute (the hands are not hub-drawn yet: eosHubDrawn false).
 */
EosFace {
    id: face

    eosHubDrawn: false
    readonly property bool eosUsesSeconds: true

    eosOptions: [
        Kit.colorOption("flamingo"),
        Kit.listOption("styles", Kit.BOLD_STYLES, Kit.BOLD_STYLE_NAMES, "nodashes"),
        Kit.listOption("fonts", Kit.BOLD_FONTS, Kit.BOLD_FONT_NAMES, "rounded"),
        Kit.listOption("layout", Kit.BOLD_LAYOUTS, Kit.BOLD_LAYOUT_NAMES, "date"),
        Kit.boolOption("seconds", true)
    ]
    readonly property var g: Kit.bold(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.bold
    readonly property bool rounded: opt("fonts") === "rounded"
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // the dashes and dots of the style
    Repeater {
        model: Kit.boldTicks(opt("styles"))
        delegate: Item {
            objectName: "eosTick"
            x: face.cx
            y: face.cy
            width: 0
            height: 0
            rotation: modelData.angle
            Rectangle {
                x: -width / 2
                y: -(face.width / 2 - 4 * face.k)
                width: modelData.width * face.k
                height: modelData.length * face.k
                radius: modelData.round ? width / 2 : 0
                color: face.blend > 0.5 ? face.whiteAmbient : face.white
            }
        }
    }

    // the three numerals
    Repeater {
        model: Kit.BOLD_NUMERALS
        delegate: Text {
            objectName: "eosNumeral"
            readonly property real px: Kit.BOLD_NUMERAL_SIZE * face.k
            text: modelData.text
            color: face.blend > 0.5 ? face.accentAmbient : face.accent
            renderType: Text.NativeRendering
            font.family: face.rounded ? "Outfit" : Kit.FONT
            font.weight: face.blend > 0.5 ? Font.Light : (face.rounded ? Font.DemiBold : Font.Bold)
            font.pixelSize: Math.round(px)
            x: modelData.cx * face.k - width / 2
            y: modelData.cy * face.k - Kit.DIGIT_CENTER * px
        }
    }

    // the date window at 3 o'clock (the day of the month; nothing in always-on)
    Rectangle {
        objectName: "eosDateWindow"
        visible: face.g.window !== null && face.blend < 1
        x: Kit.DATE_WINDOW.x * face.k
        y: Kit.DATE_WINDOW.y * face.k
        width: Kit.DATE_WINDOW.w * face.k
        height: Kit.DATE_WINDOW.h * face.k
        radius: height / 4
        color: "#2b2b2b"
        Text {
            anchors.centerIn: parent
            text: String(face.now.getDate())
            color: face.white
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.weight: Font.Medium
            font.pixelSize: Math.round(28 * face.k)
        }
    }

    EosSlot {
        owner: face; slotId: "bottom"; shape: "bulb"; defaultSource: face.d.bottom
        spec: face.g.bulbs.length === 1 ? face.g.bulbs[0] : null
        eosActive: opt("layout") === "info1"
    }
    EosSlot {
        owner: face; slotId: "left"; shape: "bulb"; defaultSource: face.d.left
        spec: face.g.bulbs.length === 2 ? face.g.bulbs[0] : null
        eosActive: opt("layout") === "info2"
    }
    EosSlot {
        owner: face; slotId: "right"; shape: "bulb"; defaultSource: face.d.right
        spec: face.g.bulbs.length === 2 ? face.g.bulbs[1] : null
        eosActive: opt("layout") === "info2"
    }
    // the four arcs of Info IV: each is the whole face with its quarter of the rim
    EosSlot {
        owner: face; slotId: "topright"; shape: "arc"; defaultSource: face.d.topright
        arcStart: -90; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: opt("layout") === "info4"
    }
    EosSlot {
        owner: face; slotId: "bottomright"; shape: "arc"; defaultSource: face.d.bottomright
        arcStart: 0; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: opt("layout") === "info4"
    }
    EosSlot {
        owner: face; slotId: "bottomleft"; shape: "arc"; defaultSource: face.d.bottomleft
        arcStart: 90; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: opt("layout") === "info4"
    }
    EosSlot {
        owner: face; slotId: "topleft"; shape: "arc"; defaultSource: face.d.topleft
        arcStart: 180; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: opt("layout") === "info4"
    }

    EosHands {
        owner: face
        hourColor: face.white
        minuteColor: face.white
        secondColor: face.accent
    }
}
