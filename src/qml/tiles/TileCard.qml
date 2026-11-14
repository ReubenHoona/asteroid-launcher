/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../pager.js" as Pager

/*
 * A card or button inside a tile, its own click target (tiles-individual-32).
 * Stock's tile layout has no catch-all click: the alarm card, a timer button,
 * an assistant chip each is a clickable of its own and a tap on empty black
 * does nothing (hnw.java:37-56, PrimaryLayout.kt: onClick optional). The
 * touch area is at least 48 dp (96 px) on each side: a card smaller than
 * that takes the missing part from its surroundings, at most hitSlop (half
 * the gap to its neighbours) so two cards never share a press. No haptic on
 * a tap (haptics-sounds E25). A long press still opens the carousel's
 * editor, as it does on the rest of the tile (400 ms, the platform's
 * long-press timeout).
 *
 * Draw the content inside it; it is clipped to nothing, the container
 * has the corners.
 */
Item {
    id: card

    property color containerColor: Theme.color.primary
    // the content's colour: the ripple's (stock draws it at 10 % in it)
    property color contentColor: Theme.color.onPrimary
    // stadium by default
    property real radius: Math.min(width, height) / 2
    // how much a press may take from the surroundings, per side (px)
    property real hitSlop: Theme.dp(2)
    // the screen reader's text
    property string accessibleName: ""
    // drawn small as a picture of itself (the tiles editor): no press
    property bool preview: false
    default property alias content: contentArea.data
    readonly property alias container: box
    readonly property alias ripple: ripple
    readonly property alias touchArea: area
    readonly property bool pressed: area.pressed
    // the part of the touch area outside the card, per side
    readonly property real slopX: Math.min(hitSlop, Math.max(0, (Theme.dp(48) - width) / 2))
    readonly property real slopY: Math.min(hitSlop, Math.max(0, (Theme.dp(48) - height) / 2))

    // a long press opens the carousel's editor (as on the rest of the tile);
    // a card with an editor of its own turns that off and listens to longPressed()
    property bool opensCarouselEditor: true

    signal clicked()
    signal longPressed()

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName

    Rectangle {
        id: box
        anchors.fill: parent
        radius: card.radius
        color: card.containerColor

        // the bounded ripple, in the content colour
        Ripple {
            id: ripple
            radius: box.radius
            color: card.contentColor
            pressed: area.pressed && !card.preview
            pressX: area.mouseX + area.x
            pressY: area.mouseY + area.y
        }
    }

    Item {
        id: contentArea
        anchors.fill: parent
    }

    MouseArea {
        id: area
        x: -card.slopX
        y: -card.slopY
        width: card.width + 2 * card.slopX
        height: card.height + 2 * card.slopY
        enabled: !card.preview
        pressAndHoldInterval: Pager.LONG_PRESS_MS
        onClicked: card.clicked()
        onPressAndHold: {
            Haptics.longPress()
            card.longPressed()
            if (card.opensCarouselEditor && typeof desktop !== "undefined" && desktop.openTilesEditor)
                desktop.openTilesEditor()
        }
    }
}
