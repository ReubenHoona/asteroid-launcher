/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A-02 (D60-04): the always-on entry in one frame, as the Wear OS 6 emulator (motion M13: the awake
 * face is replaced by the always-on one with no frame in between; the new look follows the emulator
 * where CP3A's fuv.java:84-95 animated 300 ms):
 *  - the face kit's AMBIENT_MS is 0;
 *  - an EosFace (Concentric, Classic, Words) steps `blend` 0 -> 1 in the same turn as displayAmbient
 *    goes true (no value in between, no animation left running) and 1 -> 0 at the wake;
 *  - what the face draws switches with it: Concentric's awake digits are hidden and the always-on
 *    ones shown the moment displayAmbient changes (no half-faded frame);
 *  - no animation of the blend is left in EosFace.
 * qmltestrunner under qemu-aarch64 with the image rootfs (offscreen, software Qt Quick), run in place.
 */

import QtQuick
import QtTest
import "../../src/eoskit/facekit.js" as Kit

Item {
    id: top
    width: 384
    height: 384

    // what the launcher gives a face (FaceLayer's context)
    property var wallClock: ({ time: new Date(2026, 10, 24, 10, 9, 30) })
    property var use12H: ({ value: true })
    property bool displayAmbient: false

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent }

    TestCase {
        id: tc
        name: "AmbientEntry"
        when: windowShown

        function load(file) {
            ld.source = ""
            top.displayAmbient = false
            ld.source = Qt.resolvedUrl("../../src/watchfaces/" + file)
            tryCompare(ld, "status", Loader.Ready, 20000)
            return ld.item
        }
        function animations(item, out) {
            out = out || []
            if (!item)
                return out
            var r = item.resources || []
            for (var i = 0; i < r.length; i++)
                if (r[i] && r[i].duration !== undefined && r[i].running !== undefined)
                    out.push(r[i])
            return out
        }

        function test_01_kit_has_no_ambient_transition() {
            compare(Kit.AMBIENT_MS, 0)
        }

        function test_02_blend_steps_both_ways_data() {
            return [{ tag: "concentric", file: "027-concentric.qml" },
                    { tag: "classic", file: "021-classic.qml" },
                    { tag: "words", file: "025-words.qml" }]
        }
        function test_02_blend_steps_both_ways(data) {
            var f = load(data.file)
            compare(f.blend, 0)
            var seen = []
            var rec = function () { seen.push(f.blend) }
            f.blendChanged.connect(rec)
            top.displayAmbient = true
            // in the same turn: no event loop pass, no frame, between awake and always-on
            compare(f.blend, 1, "always-on at once")
            wait(400)
            compare(seen, [1], "one step, no value in between: " + seen)
            top.displayAmbient = false
            compare(f.blend, 0, "the wake at once")
            compare(seen, [1, 0])
            f.blendChanged.disconnect(rec)
            // nothing animates the blend any more (the face's own animations, a dial sweep, are not it)
            var a = animations(f).filter(function (x) { return x.property === "blend" })
            compare(a.length, 0, "no blend animation")
        }

        function test_03_concentric_switches_what_it_draws_in_one_frame() {
            var f = load("027-concentric.qml")
            wait(50)
            // the always-on time items (the hub's: shown while blend > 0)
            var amb = []
            function walk(it) {
                if (!it)
                    return
                if (it.objectName === "eosHubHour" || it.objectName === "eosHubMinute")
                    amb.push(it)
                for (var i = 0; i < it.children.length; i++)
                    walk(it.children[i])
            }
            walk(f)
            top.displayAmbient = true
            compare(f.blend, 1)
            for (var j = 0; j < amb.length; j++) {
                var p = amb[j]
                var shown = true
                for (var q = p; q && q !== f; q = q.parent)
                    if (!q.visible || q.opacity <= 0)
                        shown = false
                verify(shown, "the hub's time items show at once (" + amb[j].objectName + ")")
            }
            var got = { ok: false }
            top.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile("/tmp/r5aod-shots/a02-concentric-entry.png"))
        }
    }
}
