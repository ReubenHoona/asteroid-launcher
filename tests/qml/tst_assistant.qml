/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The assistant overlay (src/qml/assistant: AssistantOverlay, AssistantGlow,
 * AssistantSpark) on the mocks of tests/qml/mocks, as module LauncherQml
 * (the real AssistantActions is replaced by tests/qml/stage/assistant's stub).
 * The daemon's signals are fed through the overlay's daemon* functions, the
 * D-Bus mock records what the overlay calls. Stock numbers: see the gaps
 * assistant-voice-04 .. 26 (PLAN.md W2-launcher-assistant).
 * Run by agents/wearimpl/pkg/W2-launcher-assistant/run-assistant.sh
 * (qemu-aarch64, offscreen, software Qt Quick).
 */

import QtQuick
import QtTest
import LauncherTest
import LauncherQml
import org.asteroid.controls
import org.nemomobile.lipstick

Item {
    id: root
    width: 384
    height: 384

    property var played: []
    Connections {
        target: Haptics
        function onPlayed(event) {
            var l = root.played.slice()
            l.push(event)
            root.played = l
        }
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: AssistantOverlay {}
    }

    Component { id: ovComponent; AssistantOverlay {} }

    TestCase {
        name: "Assistant"
        when: windowShown
        property var ov: null
        readonly property string svc: "org.asteroidos.assistant"
        readonly property string iface: "org.asteroidos.assistant."

        function init() {
            Backend.reset()
            root.played = []
            loader.active = false
            loader.active = true
            tryCompare(loader, "status", Loader.Ready)
            ov = loader.item
            Backend.replies[iface + "Listen"] = 7
            Backend.replies[iface + "Ask"] = 7
            Backend.replies[iface + "Dictate"] = 7
        }
        function cleanup() {
            if (ov && ov.shown)
                ov.close()
        }
        function child(name) { return findChild(ov, name) }
        function calls(method) {
            var n = 0
            for (var i = 0; i < Backend.calls.length; i++)
                if (Backend.calls[i].target === svc && Backend.calls[i].method === iface + method)
                    n++
            return n
        }
        function blanking() {
            var l = -1
            for (var i = 0; i < Backend.calls.length; i++)
                if (Backend.calls[i].target === "keepalive")
                    l = Backend.calls[i].args[0] ? 1 : 0
            return l
        }
        // a turn up to the listening plate
        function listen() {
            ov.open("", true)
            ov.daemonState(7, "starting")
            ov.daemonState(7, "listening")
        }
        function result(r) { ov.daemonState(7, "thinking"); ov.handleResult(JSON.stringify(r)) }
        function near(a, b, tol, msg) { verify(Math.abs(a - b) <= tol, (msg || "") + " " + a + " vs " + b) }

        /* ---- the glow: stock values (assistant-voice-04, -14) ---- */

        function test_glow_spec() {
            var s = child("glow").spec
            compare(s.wideDegrees, 122.87)
            compare(s.narrowDegrees, 37.01)
            compare(s.beadDegrees, 62)
            compare(s.flourishTo, 1.7)
            compare(s.flourishMs, 800)
            compare(s.sweepOpenMs, 500)
            compare(s.sweepSettleMs, 1000)
            compare(s.flavorDelayMs, 600)
            compare(s.flavorMs, 300)
            compare(s.idleLoopMs, 1167)
            compare(s.narrowMs, 900)
            compare(s.springStiffness, 1500)
            compare(s.springDamping, 1.0)
            compare(s.beadMs, 1410)
            compare(s.fadeInMs, 500)
            compare(s.fadeOutMs, 160)
            compare(s.bandHeight, 0.14)
            compare(s.lineDp, 6)
        }
        function test_glow_closed_at_rest() {
            var g = child("glow")
            compare(g.mode, "closed")
            compare(g.visible, false)
            compare(g.sweepAngle, 0)
            compare(g.flavor, 1)
            compare(g.beadPosition, -1)
            compare(g.animating, false)
        }
        function test_glow_start_sequence() {
            var g = child("glow")
            ov.open("", false)
            compare(ov.glowMode, "idle")
            compare(g.flavor, 0, "flavor starts at the flourish")
            compare(g.flourishWidth, 0)
            compare(g.sweepAngle, 0)
            verify(g.animating)
            // the sweep opens to 122.87 in 500 ms, the flourish to 1.7 in 800 ms
            tryVerify(function () { return g.sweepAngle > 100 }, 1500)
            tryVerify(function () { return g.flourishWidth > 1.69 }, 2500)
            near(g.flourishWidth, 1.7, 0.02, "flourish")
            // flavor goes to the resting palette after 600 ms
            tryCompare(g, "flavor", 1, 3000)
            // the sweep settles at 37.01 and then breathes between 37.01 and 122.87
            tryVerify(function () { return g.sweepAngle < 80 }, 3000)
            var lo = 1000, hi = 0
            for (var i = 0; i < 14; i++) {
                wait(200)
                lo = Math.min(lo, g.sweepAngle)
                hi = Math.max(hi, g.sweepAngle)
            }
            verify(lo >= 36.9 && lo < 45, "idle loop low " + lo)
            verify(hi > 100 && hi <= 122.9, "idle loop high " + hi)
        }
        function test_glow_opacity_fades() {
            var g = child("glow")
            ov.open("", false)
            compare(g.opacity, 0)
            wait(120)
            verify(g.opacity > 0 && g.opacity < 1, "fading in 500 ms: " + g.opacity)
            tryCompare(g, "opacity", 1, 1500)
            ov.close()
            // out in 160 ms linear
            tryCompare(g, "opacity", 0, 600)
            compare(g.visible, false)
            tryCompare(g, "sweepAngle", 0, 600)
            compare(g.flavor, 1)
            compare(g.animating, false)
        }
        function test_glow_voice_wide_narrow() {
            var g = child("glow")
            listen()
            compare(ov.phase, "listening")
            ov.daemonLevel(0.2)
            compare(ov.glowMode, "idle", "below the threshold, nothing talked yet")
            ov.daemonLevel(0.5)
            compare(ov.glowMode, "wide")
            tryCompare(g, "flavor", 2, 1000)
            // the spring brings it to 122.87
            tryVerify(function () { return Math.abs(g.sweepAngle - 122.87) < 0.5 }, 3000)
            ov.daemonLevel(0.1)
            compare(ov.glowMode, "narrow")
            wait(450)
            var mid = g.sweepAngle
            verify(mid < 122 && mid > 37.1, "narrowing linearly over 900 ms: " + mid)
            tryVerify(function () { return Math.abs(g.sweepAngle - 37.01) < 0.3 }, 2500)
            compare(g.flavor, 2)
            // loud again: wide again
            ov.daemonLevel(0.9)
            compare(ov.glowMode, "wide")
            tryVerify(function () { return g.sweepAngle > 100 }, 2000)
        }
        function test_glow_processing_bead() {
            var g = child("glow")
            listen()
            ov.daemonLevel(0.8)
            tryCompare(g, "flavor", 2, 1000)
            ov.daemonTranscript(7, "what time is it")
            compare(ov.phase, "thinking")
            compare(ov.glowMode, "processing")
            tryCompare(g, "flavor", 1, 1000)
            tryVerify(function () { return Math.abs(g.sweepAngle - 122.87) < 0.5 }, 2000)
            // the bead runs -1 -> 1 in 1410 ms, then again
            var seen = []
            for (var i = 0; i < 12; i++) {
                seen.push(g.beadPosition)
                wait(250)
            }
            var rises = 0, wraps = 0
            for (var k = 1; k < seen.length; k++) {
                if (seen[k] > seen[k - 1]) rises++
                else wraps++
            }
            verify(rises >= 8, "the bead moves on " + seen)
            verify(wraps >= 1, "and starts again " + seen)
            verify(g.animating)
            // the answer: the glow closes and nothing moves any more
            result({ type: "answer", intent: "question", text: "x", via: "watch" })
            tryCompare(g, "opacity", 0, 800)
            compare(g.animating, false)
            compare(g.beadPosition, -1)
        }
        function test_glow_pauses_with_the_display() {
            var g = child("glow")
            ov.open("", false)
            verify(g.animating)
            ov.screenOn = false
            compare(g.animating, false)
            var a = g.sweepAngle
            wait(300)
            compare(g.sweepAngle, a, "paused")
            ov.screenOn = true
            verify(g.animating)
            tryVerify(function () { return g.sweepAngle !== a }, 1000)
        }

        /* ---- plate: mark, prompt, transcript (voice-05, -06, -07, -08) ---- */

        function test_plate_geometry() {
            listen()
            var spark = child("spark")
            compare(spark.width, 40)
            compare(spark.height, 40)
            compare(spark.y, 20, "10 dp from the top")
            compare(spark.x + spark.width / 2, 192)
            verify(spark.shown)
            var p = child("prompt")
            compare(p.text, "Ask Assistant")
            compare(p.y, Math.round(0.052 * 384) + 40, "5.2 % of the height under the 20 dp icon")
            compare(p.width, Math.round(384 * 0.8), "10 % each side")
            compare(p.font.pixelSize, 32, "titleMedium 16 sp")
            compare(p.horizontalAlignment, Text.AlignHCenter)
            compare(p.opacity, 1)
            verify(p.text.indexOf("Gemini") < 0 && p.text.indexOf("Google") < 0)
        }
        function test_transcript() {
            listen()
            var t = child("transcript")
            var h = child("heardText")
            verify(!t.visible, "nothing heard yet")
            ov.daemonPartial(7, "set")
            verify(t.visible)
            verify(!child("prompt").visible, "the prompt gives way to the words")
            compare(h.font.pixelSize, 32, "bodyLarge 16 sp")
            compare(h.font.weight, 450)
            compare(t.lineHeight, 36)
            tryCompare(t, "height", 36, 500)
            compare(t.y, Math.round((384 - 36) / 2), "in the middle")
            ov.daemonPartial(7, "set a timer for five minutes and then remind me to take the pizza out of the oven")
            tryVerify(function () { return t.height === 72 }, 1000)
            compare(t.y, Math.round((384 - 72) / 2))
            verify(h.lineCount >= 3 && h.y < 0, "older lines scroll up: " + h.lineCount + " lines, y " + h.y)
            verify(findChild(ov, "transcriptFade").visible, "the top line fades")
            compare(t.clip, true)
            verify(h.lineCount >= 3)
            // height follows in 50 ms linear
            ov.daemonPartial(7, "set")
            wait(20)
            verify(t.height > 36 && t.height < 72, "50 ms: " + t.height)
            tryCompare(t, "height", 36, 500)
            verify(!findChild(ov, "transcriptFade").visible)
        }
        function test_ellipsis() {
            ov.open("", true)
            ov.daemonState(7, "starting")
            ov.startFollowUp({ prompt: "", onText: function () {} })
            var p = child("prompt")
            verify(p.stepped)
            verify(p.visible)
            var seen = [p.text]
            for (var i = 0; i < 90; i++) {
                wait(20)
                if (p.text !== seen[seen.length - 1])
                    seen.push(p.text)
            }
            // '   ' -> '.  ' -> '.. ' -> '...' and round again
            compare(seen.slice(0, 5).join("|"), ["   ", ".  ", ".. ", "...", "   "].join("|"))
            // with a prompt, no ellipsis
            ov.startFollowUp({ prompt: "What's the message?", onText: function () {} })
            compare(child("prompt").text, "What's the message?")
            compare(child("prompt").stepped, false)
        }

        /* ---- haptics (voice-09, -11) ---- */

        function test_haptics() {
            ov.open("", true)
            compare(root.played.length, 0, "no haptic on the hold or on open")
            ov.daemonState(7, "starting")
            compare(root.played.length, 0)
            ov.daemonState(7, "listening")
            compare(root.played.join(","), "assistant_mic_open", "a thud when the microphone opens")
            ov.daemonState(7, "listening")
            compare(root.played.length, 1, "once")
            ov.daemonState(7, "thinking")
            ov.handleResult(JSON.stringify({ type: "answer", intent: "question", text: "Hello", via: "phone" }))
            compare(root.played.join(","), "assistant_mic_open,assistant_response", "two thuds (the response event) on the answer")
            // an error says nothing
            ov.listenAgain()
            ov.daemonState(7, "starting")
            ov.daemonState(7, "listening")
            root.played = []
            ov.daemonState(7, "thinking")
            ov.handleResult(JSON.stringify({ type: "error", code: "timeout", text: "x" }))
            compare(root.played.length, 0)
            compare(ov.phase, "error")
        }

        /* ---- tap (voice-12) ---- */

        function test_tap_while_listening_stops() {
            listen()
            compare(ov.phase, "listening")
            mouseClick(root, 192, 192)
            compare(calls("Stop"), 1, "a tap anywhere asks the daemon to stop")
            compare(calls("Cancel"), 0)
            verify(ov.shown, "and does not close")
            compare(ov.phase, "listening", "the daemon moves it on")
            ov.daemonState(7, "recognising")
            compare(ov.phase, "thinking")
            mouseClick(root, 192, 100)
            mouseClick(root, 192, 300)
            compare(calls("Stop"), 1, "a tap while it thinks does nothing")
            compare(calls("Cancel"), 0)
            verify(ov.shown)
        }
        function test_tap_on_answer_does_not_close() {
            listen()
            result({ type: "answer", intent: "question", text: "It is half past ten.", via: "phone" })
            compare(ov.phase, "card")
            mouseClick(root, 192, 150)
            mouseClick(root, 40, 192)
            verify(ov.shown, "a tap on an answer does not close it")
            compare(ov.phase, "card")
        }
        function test_swipe_and_display_off_still_close() {
            listen()
            ov.close()
            compare(ov.shown, false)
            compare(calls("Cancel"), 1)
            listen()
            Lipstick.compositor.displayOff()
            compare(ov.shown, false)
        }

        /* ---- idle plate (voice-13, -21) ---- */

        function test_no_speech_goes_idle() {
            listen()
            result({ type: "error", code: "no-speech", text: "Sorry, I didn't catch that." })
            compare(ov.phase, "idle")
            compare(ov.glowMode, "closed")
            var m = child("idleMic")
            verify(m.visible)
            compare(m.width, 96, "48 dp touch target")
            compare(m.height, 96)
            compare(m.iconSize, 48, "24 dp icon")
            compare(m.y + m.height, 384 - Math.round(0.04 * 384), "4 % of the height above the edge")
            compare(m.x + m.width / 2, 192)
            compare(child("prompt").text, "Ask Assistant")
            verify(child("prompt").visible)
            verify(!child("spark").shown, "the icon goes when the microphone button shows")
            tryCompare(child("spark"), "visible", false, 600)
            verify(child("errorLoader").item === null, "no error dialog and no error text")
            var texts = findChild(ov, "suggestions")
            verify(texts.visible)
            compare(texts.texts.length, 3, "3 tap-to-ask suggestions")
            // the microphone listens again
            Backend.clearCalls()
            m.clicked(null)
            compare(calls("Listen"), 1)
            compare(ov.phase, "starting")
        }
        function test_spark_fades_out_in_250_ms() {
            listen()
            var s = child("spark")
            compare(s.opacity, 1)
            result({ type: "error", code: "no-speech", text: "x" })
            wait(90)
            verify(s.opacity > 0 && s.opacity < 1, "fading: " + s.opacity)
            tryCompare(s, "opacity", 0, 700)
            compare(s.visible, false)
        }
        function test_idle_suggestion_asks() {
            listen()
            result({ type: "error", code: "no-speech", text: "x" })
            Backend.clearCalls()
            var s = child("suggestion1")
            verify(s !== null)
            s.clicked(null)
            compare(calls("Ask"), 1)
            compare(Backend.find(svc, iface + "Ask").args[0], "Set a timer for 5 minutes")
            compare(ov.phase, "thinking")
        }

        /* ---- answer (voice-15, -16, -18, -19) ---- */

        function test_answer_list() {
            listen()
            result({ type: "answer", intent: "question", text: "Fourteen hours.", via: "phone" })
            compare(ov.phase, "card")
            var l = child("answerList")
            verify(l.visible)
            var kinds = ov.answerItems.map(function (e) { return e.kind })
            compare(kinds.join(","), "icon,text,disclaimer,thumbs,mic")
            compare(l.count, 5)
            compare(child("glow").mode, "closed")
            var tx = child("answerText")
            verify(tx !== null)
            compare(tx.text, "Fourteen hours.")
            compare(tx.font.pixelSize, 32, "bodyLarge")
            // disclaimer: 12 sp grey
            var d = child("disclaimer")
            verify(d !== null)
            compare(d.font.pixelSize, 24, "12 sp")
            compare(String(d.color), "#747775")
            compare(d.y, 24, "12 dp above")
            compare(d.text, "The assistant can make mistakes, so double-check it")
            // the thumbs: 32 dp, 24 dp apart
            var up = child("thumbUp"), down = child("thumbDown")
            verify(up !== null && down !== null)
            compare(up.width, 64)
            compare(down.width, 64)
            compare(down.mapToItem(up, 0, 0).x - up.width, 48, "24 dp between them")
            compare(ov.rated, "")
            up.clicked(null)
            compare(ov.rated, "up")
            compare(up.iconName, "ios-thumbs-up")
            down.clicked(null)
            compare(ov.rated, "down")
            compare(up.iconName, "ios-thumbs-up-outline")
            down.clicked(null)
            compare(ov.rated, "", "the same again takes it back")
            // the microphone button is last
            var mic = child("answerMic")
            verify(mic !== null)
            compare(mic.width, 96)
            compare(mic.y, 24, "12 dp above the button")
        }
        function test_local_answer_has_no_disclaimer() {
            listen()
            result({ type: "answer", intent: "question", text: "It is ten.", via: "watch" })
            compare(ov.answerItems.map(function (e) { return e.kind }).join(","), "icon,text,mic")
            compare(child("disclaimer"), null)
            compare(child("thumbUp"), null)
        }
        function test_action_card_chips() {
            listen()
            ov.daemonState(7, "thinking")
            var ran = 0
            ov.done({ icon: "ios-call", title: "Sam", text: "Call?", chips: [{ label: "Call", icon: "ios-call", run: function (d) { ran++ } },
                                                                              { label: "Cancel", run: function (d) { ran += 10 } }] })
            compare(ov.phase, "card")
            compare(ov.answerItems.map(function (e) { return e.kind }).join(","), "icon,title,text,chip,chip,mic")
            var c0 = child("answerChip0")
            verify(c0 !== null)
            compare(c0.text, "Call")
            compare(c0.height >= 104, true, "an M3 button, 52 dp")
            c0.clicked(null)
            compare(ran, 1)
            child("answerChip1").clicked(null)
            compare(ran, 11)
            compare(root.played.indexOf("assistant_response") >= 0, true)
        }
        function test_follow_up_from_the_answer() {
            listen()
            result({ type: "answer", intent: "question", text: "Fourteen hours.", via: "phone" })
            Backend.clearCalls()
            root.played = []
            child("answerMic").clicked(null)
            compare(calls("Listen"), 1, "the mic button starts a new turn")
            compare(ov.phase, "starting")
            verify(ov.keepAnswer, "the answer stays")
            verify(child("answerList").visible)
            verify(!child("plate").visible)
            compare(ov.glowMode, "idle", "the glow opens over it")
            ov.daemonState(7, "listening")
            compare(root.played.join(","), "assistant_mic_open")
            verify(child("answerList").visible)
            // a tap stops it
            mouseClick(root, 192, 192)
            compare(calls("Stop"), 1)
            // the first words take the answer away
            ov.daemonPartial(7, "and in")
            verify(!ov.keepAnswer)
            verify(child("plate").visible)
            verify(!child("answerList").visible)
            compare(child("transcript").visible, true)
        }

        /* ---- errors (voice-17) ---- */

        function dialog() { return child("errorDialog") }
        function test_error_offline() {
            listen()
            result({ type: "error", code: "offline", text: "I can't answer that right now." })
            compare(ov.phase, "error")
            tryVerify(function () { return dialog() !== null }, 1000)
            var d = dialog()
            compare(d.text, "Your watch isn't connected to the internet. Please connect and try again.")
            compare(ov.errorData.icon, "ios-wifi-outline")
            verify(d.icon !== null, "the Wi-Fi icon struck through")
            compare(d.buttons, "none")
            compare(ov.glowMode, "closed")
            var x = child("errorClose")
            verify(x !== null)
            compare(x.preferredHeight, 140, "70 dp edge button")
            tryVerify(function () { return x.visible && x.width > 0 && x.shownHeight > 130 }, 2000)
            mouseClick(x)
            tryCompare(ov, "shown", false, 1000)
        }
        function test_error_unavailable_and_in_call() {
            var codes = ["timeout", "server", "auth", "off", ""]
            for (var i = 0; i < codes.length; i++) {
                listen()
                result({ type: "error", code: codes[i], text: "daemon text" })
                tryVerify(function () { return dialog() !== null }, 1000)
                compare(dialog().text, "The assistant is currently unavailable. Try again in a few minutes.", "code " + codes[i])
                ov.close()
                compare(ov.shown, false)
                tryVerify(function () { return dialog() === null }, 1000)
            }
            listen()
            result({ type: "error", code: "mic", text: "I can't hear you. The microphone isn't working." })
            tryVerify(function () { return dialog() !== null }, 1000)
            compare(dialog().text, "I can't hear you. The microphone isn't working.", "the daemon's own sentence")
            ov.close()
            // over a call: no listening, the call text
            Backend.clearCalls()
            ov.inCall = true
            ov.open("", false)
            compare(calls("Listen"), 0)
            compare(ov.phase, "error")
            tryVerify(function () { return dialog() !== null }, 1000)
            compare(dialog().text, "Sorry, I can't help with that when you're in a call.")
            compare(dialog().iconName, "ios-call")
            ov.close()
            ov.inCall = false
        }
        function test_refused_start_is_an_error() {
            Backend.replies[iface + "Listen"] = 0
            ov.open("", false)
            compare(ov.phase, "error")
            tryVerify(function () { return dialog() !== null }, 1000)
            compare(dialog().text, "The assistant is currently unavailable. Try again in a few minutes.")
        }

        /* ---- screen on (voice-23) ---- */

        function test_display_hold() {
            ov.holdMs = ({ tail: 300, cap: 500 })
            Backend.clearCalls()
            compare(blanking(), -1)
            ov.open("", false)
            compare(blanking(), 1, "held from the start")
            ov.daemonState(7, "starting")
            ov.daemonState(7, "listening")
            ov.daemonState(7, "thinking")
            compare(blanking(), 1, "while it thinks")
            ov.handleResult(JSON.stringify({ type: "answer", intent: "question", text: "x", via: "watch" }))
            compare(ov.phase, "card")
            compare(blanking(), 1, "and for a while after")
            tryCompare(ov, "tail", false, 1000)
            compare(blanking(), 0, "then the normal timeout")
            // thinking stops holding after the cap
            ov.open("", false)
            ov.daemonState(7, "starting")
            ov.daemonState(7, "thinking")
            compare(blanking(), 1)
            tryCompare(ov, "capped", true, 1500)
            compare(blanking(), 0, "not for ever")
            ov.close()
            compare(blanking(), 0)
            // the stock numbers
            ov.holdMs = ({ tail: 2000, cap: 18000 })
            compare(ov.holdMs.tail, 2000)
            compare(ov.holdMs.cap, 18000)
        }
        function test_hold_numbers_are_stock() {
            var o = createTemporaryObject(ovComponent, root)
            compare(o.holdMs.tail, 2000)
            compare(o.holdMs.cap, 18000)
        }

        /* ---- open transition (voice-25) ---- */

        function test_open_transition() {
            // the side button's hold: at once
            ov.open("", true)
            compare(ov.opacity, 1)
            compare(ov.scale, 1)
            ov.close()
            tryCompare(ov, "opacity", 0, 1000)
            // the app list and the tile: the shared fade and scale
            ov.open("", false)
            verify(ov.opacity < 1, "fading in: " + ov.opacity)
            verify(ov.scale < 1)
            tryCompare(ov, "opacity", 1, 1000)
            tryCompare(ov, "scale", 1, 1000)
            // closing is always the fade
            ov.close()
            verify(ov.opacity < 1 || ov.opacity === 1)
            tryCompare(ov, "opacity", 0, 1000)
        }
    }
}
