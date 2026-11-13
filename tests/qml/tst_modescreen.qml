/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The mode transition screens (src/qml/misc/ModeScreen.qml, modes-dnd-07,
 * -08, -16) and Bedtime's colour filter (src/qml/compositor/NightLight.qml,
 * modes-dnd-09) on a stand-in for the modes engine (src/modes.h): the
 * stock layout in px (160 px container, 48 px corners, 72 px glyph, 32 px
 * text, 52 px padding), the entry timeline (1000 in, 2000 held, 1000
 * content out, 1000 black, then the face), the exit screen ("Turning off
 * Bedtime mode…", 1000 in, 2000 held, two 150 ms steps, no face), Theater's
 * overlay (225 ms after 225 ms, the face at 450 ms, away at 1000 ms), the
 * cut-short and skipped cases, the calls and alarms that keep it away, the
 * colour matrix handed to the shader. Screenshots go to /tmp/w2lm-shots.
 * Run by pkg/W2-launcher-modes/run-qml-tests.sh (qemu-aarch64, offscreen,
 * software Qt Quick).
 */

import QtQuick
import QtTest
import "LauncherQml/desktop.js" as Desktop
import LauncherQml

Item {
    id: root
    width: 384
    height: 384

    // the modes engine's API (modes.h)
    QtObject {
        id: modes
        property string displayFilter: ""
        property var filterMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1]
        signal bedtimeStarting()
        signal bedtimeSkipped()
        signal bedtimeEnding()
        signal transitionCancelled()
        signal theaterStarting()
    }
    // the overlay arbiter's interrupting flag (a call, a phone alarm, an alert up)
    QtObject {
        id: arbiter
        property bool interrupting: false
    }

    Rectangle { anchors.fill: parent; color: "#303040" }
    ModeScreen { id: screen }
    NightLight { id: nightLight }

    TestCase {
        name: "ModeScreen"
        when: windowShown

        readonly property string shots: "/tmp/w2lm-shots"

        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) {
                var r = find(kids[i], name)
                if (r)
                    return r
            }
            return null
        }
        function view() { return find(screen, "modeView") }
        function overlay() { return find(screen, "theaterOverlay") }
        function label() { return find(screen, "bedtimeStarting") }
        // wait until ms after t0 (a Date.now() of the signal)
        function until(t0, ms) {
            var d = t0 + ms - Date.now()
            if (d > 0)
                wait(d)
        }
        function shot(name) {
            wait(50)
            grabImage(root).save(shots + "/" + name + ".png")
        }
        function init() {
            arbiter.interrupting = false
            Desktop.compositorRoot = undefined
            screen.reset()
            modes.displayFilter = ""
            modes.filterMatrix = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        }

        SignalSpy { id: faceSpy; target: screen; signalName: "showingFace" }

        function test_00_stock_numbers() {
            var t = screen.timing
            compare(t.fadeIn, 1000)
            compare(t.hold, 2000)
            compare(t.fadeOut, 1000)
            compare(t.black, 1000)
            compare(t.exitStep, 150)
            compare(t.exitStepContent, 0.1)
            compare(t.exitStepView, 0.9)
            compare(t.theaterDelay, 225)
            compare(t.theaterFade, 225)
            compare(t.theaterOverlayMs, 1000)
            // bedtime_entry_screen_v2.xml at 2 px per dp
            compare(screen.containerSize, 160)
            compare(screen.containerRadius, 48)
            compare(screen.glyphSize, 72)
            compare(screen.iconMarginBottom, 16)
            compare(screen.contentPadding, 52)
            compare(screen.messagePaddingBottom, 16)
            compare(screen.containerColor.toString().toLowerCase(), "#dbe2f9")
            compare(screen.glyphColor.toString().toLowerCase(), "#404759")
        }

        function test_01_layout() {
            modes.bedtimeStarting()
            wait(1200)
            verify(screen.visible)
            var box = find(screen, "modeContainer")
            compare(box.width, 160)
            compare(box.height, 160)
            compare(box.radius, 48)
            compare(box.color.toString().toLowerCase(), "#dbe2f9")
            var glyph = find(screen, "modeGlyph")
            compare(glyph.width, 72)
            var text = label()
            compare(text.text, "Starting Bedtime mode…")
            compare(text.font.pixelSize, 32)
            compare(text.color.toString().toLowerCase(), "#ffffff")
            compare(text.horizontalAlignment, Text.AlignHCenter)
            // 52 px either side of the screen
            compare(text.width, 384 - 2 * 52)
            // the container sits centred above the text, 16 px between
            var p = box.mapToItem(root, 0, 0)
            compare(p.x, (384 - 160) / 2)
            var tp = text.mapToItem(root, 0, 0)
            compare(Math.round(tp.y - (p.y + 160)), 16)
            shot("modescreen-01-entry")
            screen.reset()
        }

        function test_02_entry_timeline() {
            faceSpy.clear()
            var t0 = Date.now()
            modes.bedtimeStarting()
            compare(screen.kind, "entry")
            verify(screen.playing)
            until(t0, 500)
            verify(view().opacity > 0.2 && view().opacity < 0.8, "fading in: " + view().opacity)
            until(t0, 1250)
            compare(view().opacity, 1)
            compare(screen.contentOpacity, 1)
            until(t0, 2800)
            compare(screen.contentOpacity, 1)   // held to 3000
            until(t0, 3500)
            verify(screen.contentOpacity > 0.2 && screen.contentOpacity < 0.8, "content out: " + screen.contentOpacity)
            until(t0, 4300)
            compare(screen.contentOpacity, 0)
            compare(view().opacity, 1)          // black, still covering
            verify(screen.visible)
            compare(faceSpy.count, 0)
            shot("modescreen-02-entry-black")
            until(t0, 5400)
            compare(faceSpy.count, 1)           // the face, then it is gone
            verify(!screen.visible)
            compare(screen.kind, "")
        }

        function test_03_exit() {
            faceSpy.clear()
            var t0 = Date.now()
            modes.bedtimeEnding()
            compare(screen.kind, "exit")
            compare(label().text, "Turning off Bedtime mode…")
            until(t0, 1250)
            compare(view().opacity, 1)
            compare(screen.contentOpacity, 1)
            shot("modescreen-03-exit")
            until(t0, 2800)
            compare(view().opacity, 1)
            // two 150 ms steps after 3000: content 1 -> 0.1 / view 1 -> 0.9, then both to 0
            until(t0, 3700)
            verify(!screen.visible, "gone by 3.7 s")
            compare(faceSpy.count, 0)           // no jump to the face and no sleep
            compare(screen.kind, "")
        }

        function test_04_exit_steps_values() {
            // the steps are the stock numbers
            var steps = screen.timing
            compare(steps.exitStepContent, 0.1)
            compare(steps.exitStepView, 0.9)
            compare(steps.exitStep * 2, 300)
            compare(steps.fadeIn + steps.hold + steps.exitStep * 2, 3300)
        }

        function test_05_exit_only_with_home_on_top() {
            Desktop.compositorRoot = ({ lifecycle: ({ homeActive: false }) })
            modes.bedtimeEnding()
            wait(200)
            verify(!screen.visible)
            compare(screen.kind, "")
            Desktop.compositorRoot = ({ lifecycle: ({ homeActive: true }) })
            modes.bedtimeEnding()
            wait(200)
            compare(screen.kind, "exit")
            screen.reset()
        }

        function test_06_calls_and_alarms_keep_it_away() {
            faceSpy.clear()
            arbiter.interrupting = true
            modes.bedtimeStarting()
            modes.bedtimeEnding()
            modes.theaterStarting()
            modes.bedtimeSkipped()
            wait(300)
            verify(!screen.visible)
            compare(faceSpy.count, 0)
            arbiter.interrupting = false
        }

        function test_07_cut_short() {
            faceSpy.clear()
            modes.bedtimeStarting()
            wait(1500)
            verify(screen.visible)
            modes.transitionCancelled()
            verify(!screen.visible)
            compare(faceSpy.count, 1)
            wait(300)
            compare(faceSpy.count, 1)
            // an exit cut short: nothing to finalize
            modes.bedtimeEnding()
            wait(500)
            modes.transitionCancelled()
            verify(!screen.visible)
            compare(faceSpy.count, 1)
        }

        function test_08_skipped() {
            faceSpy.clear()
            modes.bedtimeSkipped()
            compare(faceSpy.count, 1)
            verify(!screen.visible)
        }

        function test_09_theater_overlay() {
            faceSpy.clear()
            var t0 = Date.now()
            modes.theaterStarting()
            until(t0, 100)
            compare(overlay().opacity, 0)       // 225 ms of nothing
            until(t0, 340)
            verify(overlay().opacity > 0.15 && overlay().opacity < 0.9, "fading: " + overlay().opacity)
            verify(screen.visible)
            until(t0, 560)
            compare(overlay().opacity, 1)
            compare(faceSpy.count, 1)           // the face under it
            shot("modescreen-04-theater-black")
            until(t0, 800)
            compare(overlay().opacity, 1)
            until(t0, 1400)
            compare(overlay().opacity, 0)       // away at 1000 ms
            verify(!screen.visible)
        }

        function test_10_night_light_matrix() {
            // off
            verify(!nightLight.active)
            compare(nightLight.filter, "")
            compare(nightLight.colorMatrix.m11, 1)
            compare(nightLight.colorMatrix.m22, 1)
            compare(nightLight.colorMatrix.m33, 1)
            // Bedtime's Night light at 2596 K (modescore.cpp filterMatrix)
            modes.displayFilter = "nightlight"
            modes.filterMatrix = [1, 0, 0, 0, 0.7232, 0, 0, 0, 0.4588]
            verify(nightLight.active)
            compare(nightLight.colorMatrix.m11, 1)
            compare(nightLight.colorMatrix.m22, 0.7232)
            compare(nightLight.colorMatrix.m33, 0.4588)
            compare(nightLight.colorMatrix.m44, 1)
            compare(nightLight.colorMatrix.m12, 0)
            // grayscale: luma rows
            modes.displayFilter = "grayscale"
            modes.filterMatrix = [0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722]
            verify(nightLight.active)
            compare(nightLight.colorMatrix.m11, 0.2126)
            compare(nightLight.colorMatrix.m12, 0.7152)
            compare(nightLight.colorMatrix.m13, 0.0722)
            compare(nightLight.colorMatrix.m21, 0.2126)
            compare(nightLight.colorMatrix.m33, 0.0722)
            // a matrix of the wrong size is not used
            modes.filterMatrix = [1, 2, 3]
            compare(nightLight.colorMatrix.m11, 1)
            compare(nightLight.colorMatrix.m12, 0)
            // none again
            modes.displayFilter = ""
            verify(!nightLight.active)
            compare(typeof nightLight.effect, "object")
        }
    }
}
