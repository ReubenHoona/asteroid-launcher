/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 K-08: the tile editor's carousel opts in to RotaryInput's crown-speed mode (qml-asteroid crownspeed.h,
// FP-Q2), as stock's ManagementView RecyclerView with its snap helper scrolls with the crown and snaps
// (tiles-framework E38, face-interaction-22/-32): a third of a detent (8 counts) moves the cards by pixels (the
// stepping mode needs a whole detent, 24 counts, before anything moves), and once the crown rests they glide to
// the nearest card. The crown events are wheel events, as the PAT9126 crown reaches Qt; RotaryInput is the image 72
// org.asteroid.controls plugin's. MODE=tiles (the tree as its qrc lays it out, module LauncherQml).
import QtQuick
import QtTest
import org.asteroid.controls
import Nemo.Alarms
import LauncherQml

Item {
    id: top
    width: 384
    height: 384

    Rectangle { anchors.fill: parent; color: "black" }

    Component { id: editorComp; TilesEditor { idleEnabled: false } }

    TestCase {
        name: "CrownSpeed"
        when: windowShown

        readonly property var registry: ({
            timer: { file: "tiles/TimerTile.qml", name: "Timer", icon: "ios-timer-outline" },
            alarm: { file: "tiles/AlarmTile.qml", name: "Next Alarm", icon: "ios-alarm-outline" },
            favorites: { file: "tiles/FavoritesTile.qml", name: "Favorites", icon: "ms-contacts" }
        })

        function openEditor(list, at) {
            var ed = createTemporaryObject(editorComp, top, { registry: registry })
            verify(ed)
            ed.open(list, at)
            tryCompare(ed, "arrived", true, 3000)
            tryCompare(ed, "zoom", 1, 3000)
            return ed
        }
        function turn(counts) {
            for (var i = 0; i < Math.abs(counts); i++) {
                mouseWheel(top, 192, 192, 0, counts > 0 ? -120 : 120)
                wait(10)
            }
        }

        function test_01_the_editor_carousel_scrolls_freely_and_snaps() {
            var ed = openEditor(["timer", "alarm", "favorites"], 0)
            var c = ed.carousel
            compare(c.rotaryCrownSpeed, true)
            wait(200)
            var x0 = c.contentX
            compare(c.currentIndex, 0)
            // a third of a detent: the cards move by pixels, no whole step
            turn(8)
            tryVerify(function () { return Math.abs(c.contentX - x0) > 4 }, 1000, "moved with the crown")
            verify(Math.abs(c.contentX - x0) < ed.pitch / 2, "less than half a card: " + (c.contentX - x0))
            // the crown rests: back to the nearest card, the first
            tryVerify(function () { return Math.abs(c.contentX - x0) < 0.5 }, 3000, "snapped back")
            compare(c.currentIndex, 0)
            // a turn of about a card: on to the next one once it rests
            var moved = 0
            for (var n = 0; n < 200 && moved < ed.pitch * 0.6; n++) {
                turn(4)
                moved = c.contentX - x0
            }
            verify(moved >= ed.pitch * 0.6, "the crown took it past the middle: " + moved)
            tryCompare(c, "currentIndex", 1, 3000)
            tryVerify(function () { return !c.moving && !c.flicking }, 3000)
        }
    }
}
