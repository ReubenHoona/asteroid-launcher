/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
 * W2-launcher-calls: the call screens as stock CP3A (Phone 164.0): geometry and
 * colours of the ringing and in-call layout (calls-01, -02, -06, -07), the swipe
 * (calls-03, -08), the answer transition (calls-05), More options and the quick
 * replies (calls-04, -11), the call volume (calls-09), Mute (calls-10), the
 * confirmation (calls-18), "Call ended" (calls-19), "Calling..." (calls-20),
 * unknown callers (calls-21) and no work in ambient (calls-29).
 * Under qmltestrunner with the mocked lipstick, D-Bus and settings
 * (tests/qml/mocks); the controls are the real ones.
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

    QtObject {
        id: localeManager
        property string changesObserver: ""
    }

    // what lipstick keeps for the notification server
    QtObject {
        id: lipstickSettings
        property int callState: 0
    }

    Component {
        id: cardComponent
        QtObject {
            property int replacesId: 0
            property string summary: "Caller"
            property string body: ""
            property var hints: ({})
            property date timestamp: new Date()
            function actionInvoked(key) { Backend.record("notification", "actionInvoked", [replacesId, key]) }
        }
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: IncomingCall {}
    }

    TestCase {
        name: "Calls"
        when: windowShown
        property var view: null
        property var model: null

        readonly property string btsyncd: "org.asteroidos.btsyncd"
        readonly property string notif: "org.asteroidos.btsyncd.Notifications."
        readonly property string audioIface: "org.asteroidos.btsyncd.CallAudio."

        function init() {
            Backend.reset()
            Lipstick.notificationModel = null
            loader.active = false
            loader.active = true
            tryCompare(loader, "status", Loader.Ready)
            view = loader.item
            model = Lipstick.notificationModel
            verify(model !== null)
            model.populated = true
        }

        function card(id, actions, ageMs, summary, body) {
            return cardComponent.createObject(root, {
                "replacesId": id,
                "summary": summary === undefined ? "Alice" : summary,
                "body": body === undefined ? "+1 555 0100" : body,
                "hints": { "x-asteroid-phone-actions": actions },
                "timestamp": new Date(new Date().getTime() - (ageMs || 0))
            })
        }
        function ring(id, actions) {
            var n = card(id, actions || "answer,reject,silence", 0)
            model.add(n)
            verify(view.call === n)
            return n
        }
        function inCall(id, ageMs, summary) {
            var n = card(id, "end", ageMs || 0, summary)
            model.add(n)
            verify(view.call === n)
            return n
        }
        function find(item, name) {
            if (item.objectName === name)
                return item
            var kids = item.children
            for (var i = 0; i < kids.length; i++) {
                var f = find(kids[i], name)
                if (f)
                    return f
            }
            return null
        }
        function screen() { return find(view, "inCallScreen") }
        function part(name) { return find(view, name) }
        function settle(s) {
            // the answer animation (400 ms) and the edge button spring
            tryVerify(function () { return Math.abs(s.mix - (s.inCall ? 1 : 0)) < 0.001 }, 3000)
            tryVerify(function () { return Math.abs(s.bottomButton.shownHeight - s.bottomButton.preferredHeight) < 0.5 }, 3000)
        }
        function near(a, b, tol, msg) {
            verify(Math.abs(a - b) <= (tol === undefined ? 0.51 : tol), (msg || "") + " " + a + " != " + b)
        }
        function same(color, hex, msg) {
            verify(Qt.colorEqual(color, hex), (msg || "") + " " + color + " != " + hex)
        }
        function calls(target, method) {
            var out = []
            for (var i = 0; i < Backend.calls.length; i++)
                if (Backend.calls[i].target === target && Backend.calls[i].method === method)
                    out.push(Backend.calls[i])
            return out
        }
        function actions() {
            return calls("notification", "actionInvoked").map(function (c) { return c.args.join(":") })
        }
        // a left to right swipe over the screen: fast (a flick) or slow
        function swipe(fast) {
            mousePress(root, 200, 100)
            var to = fast ? 360 : 260
            for (var x = 200; x <= to; x += 20) {
                mouseMove(root, x, 100, fast ? 0 : 40)
            }
            mouseRelease(root, to, 100, Qt.LeftButton, Qt.NoModifier, fast ? 0 : 200)
        }
        // scroll the list of the open menu so that the chip is on the screen
        function reveal(chip) {
            var list = part("moreList")
            var max = list.contentHeight + list.bottomMargin - list.height
            list.contentY = Math.max(-list.topMargin, Math.min(max, chip.parent.y + chip.y + chip.height / 2 - 192))
        }
        function texts(item, out) {
            if (item.text !== undefined && item.visible && String(item.text) !== "")
                out.push(String(item.text))
            for (var i = 0; i < item.children.length; i++)
                texts(item.children[i], out)
            return out
        }

        /* ---- calls-01, -02: the ringing screen ---- */

        function test_01_ringing_geometry_and_colours() {
            ring(1, "answer,reject,silence,reply")
            var s = screen()
            verify(s !== null)
            settle(s)
            compare(s.inCall, false)
            // Decline: 52 dp = 104 px, 4 px from the left edge, centred at y 192, #EC928E
            var d = s.declineButton
            compare(d.visible, true)
            compare(d.width, 104); compare(d.height, 104)
            compare(d.x, 4)
            near(d.y + d.height / 2, 192)
            same(d.containerColor, "#EC928E", "decline fill")
            // the call-end glyph: the handset turned 135 degrees, 48 px, #410E0B
            var g = part("callDeclineGlyph")
            compare(g.width, 48); compare(g.rotation, 135)
            same(g.color, "#410E0B", "decline glyph")
            compare(d.Accessible.name, "Reject incoming call")
            // More options: filled tonal, right end, surfaceContainer, icon primary
            var m = s.moreButton
            compare(m.visible, true)
            compare(m.width, 104)
            compare(m.x, 384 - 4 - 104)
            near(m.y + m.height / 2, 192)
            same(m.containerColor, Theme.color.surfaceContainer, "more fill")
            same(m.glyphColor, Theme.color.primary, "more icon")
            compare(m.glyphItem.width, 52)
            compare(m.Accessible.name, "More options")
            // Answer: the EdgeButton, 56 dp = 112 px, #93E5C3, handset 64 px #003828
            var b = s.bottomButton
            compare(b.visible, true)
            compare(b.preferredHeight, 112)
            near(b.height, 112)
            same(b.containerColor, "#93E5C3", "answer fill")
            same(b.contentColor, "#003828", "answer glyph colour")
            var bg = s.bottomIcon
            compare(bg.width, 64); compare(bg.rotation, 0)
            compare(b.Accessible.name, "Answer incoming call")
            // no Mute, no status line, no Hide, no Silence, no labels
            compare(s.muteButton.visible, false)
            compare(s.statusLabel.visible, false)
            var all = texts(view, [])
            compare(all.indexOf("Hide"), -1)
            compare(all.indexOf("Silence"), -1)
            compare(all.indexOf("Decline"), -1)
            compare(all.indexOf("Answer"), -1)
            compare(all.indexOf("Incoming call"), -1)
            compare(all.indexOf("Silenced"), -1)
        }

        function test_02_name_monogram_and_time_text() {
            ring(2)
            var s = screen()
            settle(s)
            // the name: 24 sp = 48 px, weight 550, line 52 px, box 33 px from the top, 18 px each side
            var box = part("callName")
            compare(box.x, 18); compare(box.y, 33)
            compare(box.width, 384 - 36); compare(box.height, 52)
            compare(s.nameLabel.font.pixelSize, 48)
            compare(s.nameLabel.font.weight, 550)
            compare(s.nameLabel.text, "Alice")
            compare(s.nameLabel.maximumLineCount, 2147483647)
            // the number is not shown, nor "Incoming call"
            compare(texts(view, []).indexOf("+1 555 0100"), -1)
            // the monogram: 56 dp = 112 px circle centred on the screen, the first letter
            var mono = s.monogram
            compare(mono.width, 112)
            near(mono.x + mono.width / 2, 192)
            near(mono.y + mono.height / 2, 192)
            verify(texts(mono, []).indexOf("A") >= 0)
            // a TimeText at the top
            var hasTime = false
            var queue = [view]
            while (queue.length) {
                var it = queue.shift()
                if (String(it).indexOf("TimeText") === 0)
                    hasTime = true
                for (var i = 0; i < it.children.length; i++)
                    queue.push(it.children[i])
            }
            verify(hasTime, "TimeText")
        }

        function test_03_unknown_caller_names() {
            // a number and no name: the number is the name, no letter
            var n = card(3, "answer,reject", 0, "", "+64 21 555 0100")
            model.add(n)
            var s = screen()
            compare(s.name, "+64 21 555 0100")
            compare(s.initial, "")
            model.remove(n)
            // neither: Unknown (stock remote_end_display_name_unknown)
            var u = card(4, "answer,reject", 0, "", "")
            model.add(u)
            compare(s.name, "Unknown")
            compare(s.initial, "")
            model.remove(u)
            // a name: its first letter in capitals
            var a = card(5, "answer,reject", 0, "bob", "")
            model.add(a)
            compare(s.name, "bob")
            compare(s.initial, "B")
        }

        function test_04_long_name_scrolls_as_a_marquee() {
            ring(6)
            var s = screen()
            settle(s)
            // short names do not scroll
            verify(!s.marqueeRunning)
            compare(part("callName").scrolls, false)
            var n2 = card(7, "answer,reject", 0, "Alexandria Constantinople-Montgomery the Third", "")
            model.add(n2)
            compare(s.name, "Alexandria Constantinople-Montgomery the Third")
            compare(part("callName").scrolls, true)
            // 3 runs, 1200 ms delays, 30 dp/s = 60 px/s, gap 14.93 % of the width
            compare(s.marqueeRuns, 3)
            compare(s.marqueeDelayMs, 1200)
            compare(s.marqueeSpeed, 60)
            near(s.marqueeGap, 0.1493 * 348, 0.01)
            tryVerify(function () { return s.marqueeRunning }, 2000)
            // nothing animates with the display off
            Lipstick.compositor.displayOff()
            tryVerify(function () { return !s.marqueeRunning }, 2000)
            Lipstick.compositor.displayOn()
            tryVerify(function () { return s.marqueeRunning }, 2000)
        }

        /* ---- calls-03, -08: the swipe ---- */

        function test_05_swipe_right_silences_and_closes_the_ringing_screen() {
            var n = ring(10, "answer,reject,silence")
            verify(view.keepOn)
            swipe(true)
            tryVerify(function () { return view.call === null }, 3000)
            compare(view.visible, false)
            // the ringer is silenced through btsyncd, the call is neither answered nor declined
            compare(calls(btsyncd, notif + "Silence").length, 1)
            compare(calls(btsyncd, notif + "Silence")[0].args[0], 10)
            compare(actions().length, 0)
            // the card stays, so the chip and the card can bring the call back
            compare(model.itemCount, 1)
            verify(view.handled[10] === true)
            verify(Backend.find("com.nokia.mce", "com.nokia.mce.request.notification_end_req") !== null)
            verify(view.reopen(n))
            verify(view.call === n)
        }

        function test_06_short_swipe_stays() {
            ring(11)
            swipe(false)
            // a slow 60 px drag of 384 is below the commit distance (0.33 W)
            wait(300)
            verify(view.call !== null)
            compare(calls(btsyncd, notif + "Silence").length, 0)
        }

        function test_07_swipe_right_hides_the_call_in_progress_without_silencing() {
            var n = inCall(12, 5000)
            var s = screen()
            settle(s)
            swipe(true)
            tryVerify(function () { return view.call === null }, 3000)
            compare(calls(btsyncd, notif + "Silence").length, 0)
            compare(actions().length, 0)
            compare(model.itemCount, 1)
            // the call goes on and its state stays 2 for the notification server
            compare(lipstickSettings.callState, 2)
            verify(view.reopen(n))
            verify(view.ongoing)
        }

        /* ---- calls-06, -07: the in-call screen ---- */

        function test_08_in_call_layout() {
            inCall(20, 42000)
            var s = screen()
            settle(s)
            compare(s.inCall, true)
            // the monogram spans y 92..204, the status line ends at y 244 (140 px above the bottom)
            near(s.monogram.y, 92); compare(s.monogram.height, 112)
            near(s.statusLabel.y + s.statusLabel.height, 244)
            // 112 px side padding, labelSmall 13 sp = 26 px, line 32 px, weight 500, tabular figures
            near(s.statusLabel.x, 112); near(s.statusLabel.width, 384 - 224)
            compare(s.statusLabel.font.pixelSize, 26)
            compare(s.statusLabel.height, 32)
            compare(s.statusLabel.font.weight, 500)
            compare(s.statusLabel.font.features["tnum"], 1)
            same(s.statusLabel.color, Theme.color.tertiaryDim, "status colour")
            compare(s.statusLabel.horizontalAlignment, Text.AlignHCenter)
            verify(/^00:4[2-5]$/.test(s.statusLabel.text), s.statusLabel.text)
            // End call: the EdgeButton, #EC928E, the handset turned 135 degrees, 64 px, #410E0B
            var b = s.bottomButton
            same(b.containerColor, "#EC928E", "end fill")
            same(b.contentColor, "#410E0B", "end glyph colour")
            compare(s.bottomIcon.rotation, 135)
            compare(s.bottomIcon.width, 64)
            compare(b.Accessible.name, "End call")
            compare(b.preferredHeight, 112)
            // More at the right end, 104 px, centred at y 192; no Decline, no Mute (no call audio), no Hide
            var m = s.moreButton
            compare(m.visible, true); compare(m.x, 276); near(m.y + 52, 192)
            compare(s.declineButton.visible, false)
            compare(s.muteButton.visible, false)
            var all = texts(view, [])
            compare(all.indexOf("Hide"), -1)
            compare(all.indexOf("End call"), -1)
            compare(all.indexOf("+1 555 0100"), -1)
            // the End button ends the call: "Hanging up" until the card goes
            mouseClick(b)
            compare(view.hangingUp, true)
            compare(actions().join(","), "20:end")
            compare(s.statusLabel.text, "Hanging up")
            compare(s.buttonsEnabled, false)
            compare(b.enabled, false)
        }

        function test_09_elapsed_format() {
            // DateUtils.formatElapsedTime: 00:42, 1:02:03
            compare(view.formatElapsed(0), "00:00")
            compare(view.formatElapsed(42), "00:42")
            compare(view.formatElapsed(59 * 60 + 59), "59:59")
            compare(view.formatElapsed(3723), "1:02:03")
            compare(view.formatElapsed(10 * 3600 + 5), "10:00:05")
            inCall(21, 3723000)
            verify(/^1:02:0[3-6]$/.test(screen().statusLabel.text), screen().statusLabel.text)
        }

        /* ---- calls-05: Answer becomes End call ---- */

        function test_10_answer_keeps_the_view_and_moves_into_the_in_call_layout() {
            var n = ring(30)
            var s = screen()
            settle(s)
            mouseClick(s.bottomButton)
            compare(view.answering, true)
            verify(view.visible)
            verify(view.call === n)
            compare(actions().join(","), "30:answer")
            compare(lipstickSettings.callState, 2)
            // the in-call layout at once, status empty, buttons off until the card comes
            compare(s.inCall, true)
            compare(s.statusLabel.text, "")
            // End and Decline do nothing until the phone's card is here
            mouseClick(s.bottomButton)
            mouseClick(s.declineButton)
            compare(actions().join(","), "30:answer")
            // 400 ms, linear: half way after 200 ms
            wait(200)
            verify(s.mix > 0.15 && s.mix < 0.95, "mix " + s.mix)
            // the turn and the fill are one step of the same mix
            near(s.bottomIcon.rotation, 135 * s.mix, 0.001)
            var mid = s.bottomButton.containerColor
            verify(mid.r > 0.58 && mid.r < 0.92, "fill " + mid)
            tryVerify(function () { return s.mix === 1 }, 2000)
            same(s.bottomButton.containerColor, "#EC928E", "end fill")
            compare(s.bottomIcon.rotation, 135)
            // the phone replaces the ringing card by the call's: the view stays, then takes it over
            model.remove(n)
            verify(view.visible)
            compare(view.call, null)
            compare(s.name, "Alice")
            var o = card(31, "end", 0)
            model.add(o)
            verify(view.call === o)
            compare(view.answering, false)
            compare(view.liveOngoing, true)
            compare(s.buttonsEnabled, true)
            compare(s.bottomButton.enabled, true)
            tryVerify(function () { return /^00:0[0-3]$/.test(s.statusLabel.text) }, 3000)
        }

        function test_11_answer_without_a_call_card_closes_after_the_wait() {
            var n = ring(32)
            view.answerWaitMs = 200
            view.answer()
            model.remove(n)
            verify(view.visible)
            tryVerify(function () { return !view.visible }, 3000)
            compare(view.answering, false)
            // a late call card after the user left is not shown
            var n2 = ring(33)
            view.answer()
            view.hide()
            compare(view.visible, false)
            var o = card(34, "end", 0)
            model.add(o)
            compare(view.visible, false)
            verify(view.handled[34] === true)
        }

        /* ---- calls-19: Call ended ---- */

        function test_12_call_ended_shows_three_seconds() {
            var n = inCall(40, 5000)
            var s = screen()
            settle(s)
            compare(view.endedMs, 3000)
            model.remove(n)
            compare(view.callEnded, true)
            verify(view.visible)
            compare(s.statusLabel.text, "Call ended")
            compare(s.buttonsEnabled, false)
            compare(s.name, "Alice")
            compare(lipstickSettings.callState, 0, "the call is over for the notification server")
            wait(2000)
            verify(view.visible)
            tryVerify(function () { return !view.visible }, 3000)
            compare(view.callEnded, false)
            compare(lipstickSettings.callState, 0)
        }

        function test_13_end_call_by_the_user() {
            var n = inCall(41, 5000)
            var s = screen()
            settle(s)
            view.hangWaitMs = 300
            view.act("end")
            compare(view.hangingUp, true)
            compare(s.statusLabel.text, "Hanging up")
            // the phone removes the card: "Call ended"
            model.remove(n)
            compare(view.callEnded, true)
            compare(s.statusLabel.text, "Call ended")
            view.endedMs = 100
            tryVerify(function () { return !view.visible }, 3000)
            // a phone that never removes the card: the view leaves after the wait
            var m = inCall(42, 1000)
            view.act("end")
            verify(view.visible)
            tryVerify(function () { return !view.visible }, 3000)
        }

        function test_14_a_new_ringing_call_replaces_call_ended() {
            var n = inCall(43, 1000)
            model.remove(n)
            compare(view.callEnded, true)
            var r = ring(44)
            compare(view.callEnded, false)
            compare(screen().inCall, false)
        }

        // The glyphs are dimmed with their item's opacity: org.asteroid.controls Icon
        // multiplies the alpha of its tint at each colour change and never gets it
        // back, so a button dimmed by "Call ended" must still draw whole afterwards.
        function test_14b_glyphs_draw_whole_after_call_ended() {
            var r = ring(45, "answer,reject,silence,reply")
            settle(screen())
            wait(100)
            var before = grabImage(root).pixel(324, 192)
            model.remove(r)
            model.populated = true
            var o = inCall(46, 1000)
            model.remove(o)
            compare(view.callEnded, true)
            wait(100)
            var dim = grabImage(root).pixel(324, 192)
            view.hide()
            ring(47, "answer,reject,silence,reply")
            settle(screen())
            wait(100)
            var after = grabImage(root).pixel(324, 192)
            verify(Math.abs(after.r - before.r) < 0.02 && Math.abs(after.g - before.g) < 0.02
                   && Math.abs(after.b - before.b) < 0.02, "after " + after + " before " + before + " dim " + dim)
        }

        /* ---- calls-18: the confirmation ---- */

        function test_15_second_call_asks_before_ending_the_first() {
            var cur = inCall(50, 3000)
            var r = ring(51)
            view.answer()
            compare(view.confirmingAnswer, true)
            var box = part("confirmAnswer")
            tryVerify(function () { return box.visible }, 1000)
            compare(part("confirmTitle").text, "End current call?")
            compare(part("confirmMessage").text, "Answering new call will end current call")
            compare(actions().length, 0)
            // Cancel leaves everything as it was
            mouseClick(part("confirmCancel"))
            compare(view.confirmingAnswer, false)
            compare(actions().length, 0)
            tryVerify(function () { return !box.visible }, 3000)
            // Confirm ends the call in progress, then answers the new one
            view.answer()
            tryVerify(function () { return box.visible }, 1000)
            mouseClick(part("confirmAnswerButton"))
            compare(actions().join(","), "50:end,51:answer")
            compare(view.confirmingAnswer, false)
            compare(view.answering, true)
        }

        function test_16_no_confirmation_without_a_call_in_progress() {
            ring(52)
            view.answer()
            compare(view.confirmingAnswer, false)
            compare(actions().join(","), "52:answer")
        }

        /* ---- calls-04: More options on a ringing call ---- */

        function test_17_more_silences_and_offers_quick_replies() {
            var n = ring(60, "answer,reject,silence,reply")
            var s = screen()
            settle(s)
            compare(s.moreButton.visible, true)
            mouseClick(s.moreButton)
            // opening it silences the ringer
            compare(calls(btsyncd, notif + "Silence").length, 1)
            compare(view.moreOpen, true)
            var menu = part("incomingCallMore")
            verify(menu !== null)
            // paddings: top 9.38 %, sides 5.2 %, bottom 27.08 %
            compare(menu.list.topMargin, 36)
            compare(menu.list.bottomMargin, 104)
            compare(menu.sidePadding, 20)
            compare(menu.chipGap, 8)
            // the header and the three chips, centred text, 4 dp apart
            var header = part("sendHeader")
            compare(header.height, 88)
            var all = texts(menu, [])
            verify(all.indexOf("Send a message") >= 0)
            var c0 = part("reply0"), c1 = part("reply1"), c2 = part("reply2")
            compare(c0.text, "On my way!")
            compare(c1.text, "I'll call you back")
            compare(c2.text, "Running late")
            compare(c0.width, 384 - 40)
            compare(c1.y - (c0.y + c0.height), 8)
            compare(c0.centered, true)
            // a chip declines the call with that text and closes the view
            mouseClick(c1)
            var r = calls(btsyncd, notif + "Reply")
            compare(r.length, 1)
            compare(r[0].args[0], 60)
            compare(r[0].args[1], "I'll call you back")
            compare(view.call, null)
            compare(view.visible, false)
            compare(view.moreOpen, false)
            compare(model.itemCount, 1)
        }

        function test_18_no_more_button_when_the_phone_offers_no_reply() {
            ring(61, "answer,reject,silence")
            var s = screen()
            compare(s.moreButton.visible, false)
            compare(s.canMore, false)
        }

        function test_19_more_menu_swipes_away() {
            ring(62, "answer,reject,silence,reply")
            view.openMore()
            compare(view.moreOpen, true)
            swipe(true)
            tryVerify(function () { return !view.moreOpen }, 3000)
            // the call screen is still up
            verify(view.call !== null)
        }

        /* ---- calls-09: the crown is the call volume ---- */

        function test_20_crown_steps_the_call_volume_with_an_arc() {
            inCall(70, 1000)
            var s = screen()
            settle(s)
            var arc = part("crownArc")
            compare(arc.shown, false)
            // one crown detent is 24 counts of 120: a clockwise detent raises the volume by one step
            mouseWheel(root, 192, 192, 0, -120 * 24)
            var up = calls(btsyncd, audioIface + "AdjustVolume")
            compare(up.length, 1)
            compare(up[0].args[0], 1)
            compare(view.arcShown, true)
            compare(arc.shown, true)
            same(arc.color, "#FDE293", "arc colour")
            // counter-clockwise: one step down; a part of a detent does nothing yet
            mouseWheel(root, 192, 192, 0, 120 * 12)
            compare(calls(btsyncd, audioIface + "AdjustVolume").length, 1)
            mouseWheel(root, 192, 192, 0, 120 * 12)
            var all = calls(btsyncd, audioIface + "AdjustVolume")
            compare(all.length, 2)
            compare(all[1].args[0], -1)
            // the arc: 51 degrees on the left edge, 6 dp thick, 5 dp from the edge, filled from the bottom
            compare(arc.sweep, 51)
            compare(arc.stroke, 12)
            compare(arc.padding, 10)
            near(arc.radius, 192 - 10 - 6)
            compare(arc.startAngle, 154.5)
            // 2.5 s after the last change the arc goes
            view.arcHideMs = 200
            mouseWheel(root, 192, 192, 0, -120 * 24)
            tryVerify(function () { return !view.arcShown }, 3000)
        }

        // no call audio object in btsyncd: no crown volume, no More, no Mute
        function test_20b_without_the_call_audio_service_there_is_no_volume() {
            inCall(75, 1000)
            var s = screen()
            settle(s)
            compare(s.moreButton.visible, true)
            view.audio.reset()
            compare(view.audio.present, false)
            compare(s.moreButton.visible, false)
            mouseWheel(root, 192, 192, 0, -120 * 24)
            compare(calls(btsyncd, audioIface + "AdjustVolume").length, 0)
            compare(s.muteButton.visible, false)
            // State() answers: it is all there again
            view.audio.refresh()
            compare(view.audio.present, true)
            compare(s.moreButton.visible, true)
        }

        function test_21_volume_level_from_the_phone() {
            inCall(71, 1000)
            var arc = part("crownArc")
            view.audio.take({ "volume": 3, "volumeMax": 6 })
            near(view.volumeLevel, 0.5, 0.0001)
            near(arc.levelSweep, 25.5, 0.0001)
            // unknown level: one step is 1/7 from the middle
            view.audio.take({ "volume": -1, "volumeMax": 0 })
            near(view.volumeLevel, 0.5, 0.0001)
            mouseWheel(root, 192, 192, 0, -120 * 24)
            near(view.volumeLevel, 0.5 + 1 / 7, 0.0001)
        }

        function test_22_crown_inverted_setting_and_ringing() {
            // the crown does nothing to a ringing call (a press silences it)
            ring(72)
            mouseWheel(root, 192, 192, 0, -120 * 24)
            compare(calls(btsyncd, audioIface + "AdjustVolume").length, 0)
            view.hide()
            var n = inCall(73, 1000)
            Backend.confSet("/org/asteroidos/ux/rotary-invert", true)
            mouseWheel(root, 192, 192, 0, -120 * 24)
            var a = calls(btsyncd, audioIface + "AdjustVolume")
            compare(a.length, 1)
            compare(a[0].args[0], -1)
        }

        function test_23_volume_screen() {
            inCall(74, 1000)
            settle(screen())
            mouseClick(screen().moreButton)
            var menu = part("inCallMore")
            verify(menu !== null)
            // the crown scrolls the menu, it is not the volume now
            mouseWheel(root, 192, 192, 0, -120 * 24)
            compare(calls(btsyncd, audioIface + "AdjustVolume").length, 0)
            // no call audio: Volume only
            compare(part("chipVolume").visible, true)
            compare(part("chipKeypad").visible, false)
            compare(part("chipSpeaker").visible, false)
            compare(part("chipPull").visible, false)
            compare(part("audioHeader").visible, false)
            compare(part("chipVolume").text, "Volume")
            mouseClick(part("chipVolume"))
            compare(view.volumeOpen, true)
            var v = part("callVolume")
            verify(v !== null)
            // a round + 4.75 % from the top, a round - 4.75 % from the bottom, small (96 px)
            compare(v.upButton.width, 96)
            near(v.upButton.y, 0.0475 * 384, 0.51)
            near(v.downButton.y + v.downButton.height, 384 - 0.0475 * 384, 0.51)
            compare(v.arc.shown, true)
            mouseClick(v.upButton)
            mouseClick(v.downButton)
            var a = calls(btsyncd, audioIface + "AdjustVolume")
            compare(a.length, 2)
            compare(a[0].args[0], 1)
            compare(a[1].args[0], -1)
            // the crown works on this screen too
            mouseWheel(root, 192, 192, 0, -120 * 24)
            compare(calls(btsyncd, audioIface + "AdjustVolume").length, 3)
            // a swipe closes it, back to the menu
            swipe(true)
            tryVerify(function () { return !view.volumeOpen }, 3000)
            compare(view.moreOpen, true)
        }

        /* ---- calls-10: Mute ---- */

        function test_24_mute_with_call_audio_on_the_watch() {
            inCall(80, 1000)
            var s = screen()
            settle(s)
            compare(s.muteButton.visible, false)
            view.audio.take({ "available": true, "muted": false, "route": "watch" })
            compare(s.muteButton.visible, true)
            var m = s.muteButton
            compare(m.width, 104); compare(m.x, 4); near(m.y + 52, 192)
            same(m.containerColor, Theme.color.surfaceContainer, "mute off fill")
            same(m.glyphColor, Theme.color.onSurfaceVariant, "mute off icon")
            compare(m.Accessible.name, "Mute")
            mouseClick(m)
            var c = calls(btsyncd, audioIface + "SetMuted")
            compare(c.length, 1)
            compare(c[0].args[0], true)
            // the state comes back from btsyncd
            view.audio.take({ "muted": true })
            same(m.containerColor, Theme.color.primary, "mute on fill")
            same(m.glyphColor, Theme.color.onPrimary, "mute on icon")
            mouseClick(m)
            compare(calls(btsyncd, audioIface + "SetMuted")[1].args[0], false)
        }

        /* ---- calls-11: Keypad, Audio ---- */

        function test_25_more_options_with_call_audio() {
            inCall(81, 1000)
            settle(screen())
            view.audio.take({ "available": true, "muted": false, "route": "phone" })
            mouseClick(screen().moreButton)
            compare(part("chipVolume").visible, true)
            compare(part("chipKeypad").visible, true)
            compare(part("audioHeader").visible, true)
            compare(part("chipSpeaker").visible, true)
            compare(part("chipPhone").visible, true)
            // the audio is on the phone: Pull call audio to watch
            compare(part("chipPull").visible, true)
            compare(part("chipPull").text, "Pull call audio to watch")
            reveal(part("chipPull"))
            mouseClick(part("chipPull"))
            compare(calls(btsyncd, audioIface + "PullToWatch").length, 1)
            reveal(part("chipSpeaker"))
            mouseClick(part("chipSpeaker"))
            compare(calls(btsyncd, audioIface + "SetRoute")[0].args[0], "watch")
            view.audio.take({ "route": "watch" })
            compare(part("chipPull").visible, false)
            // Keypad: digits sent as tones
            reveal(part("chipKeypad"))
            mouseClick(part("chipKeypad"))
            compare(view.keypadOpen, true)
            var pad = part("inCallKeypad")
            verify(pad !== null)
            var k5 = part("key5")
            compare(k5.width, 88); compare(k5.height, 72)
            near(pad.leftGuide, 0.156 * 384, 0.001)
            near(pad.rightGuide, 0.843 * 384, 0.001)
            near(k5.x + k5.parent.x, pad.leftGuide + (pad.rightGuide - pad.leftGuide - 3 * 88) / 2 + 88, 0.6)
            compare(pad.keys.length, 12)
            mouseClick(k5)
            mouseClick(part("key#"))
            var t = calls(btsyncd, audioIface + "SendTones")
            compare(t.length, 2)
            compare(t[0].args[0], "5")
            compare(t[1].args[0], "#")
            compare(part("keypadDigits").text, "5#")
            compare(part("keypadDigits").elide, Text.ElideLeft)
            swipe(true)
            tryVerify(function () { return !view.keypadOpen }, 3000)
        }

        /* ---- calls-20: Calling... ---- */

        function test_26_calling_until_the_far_end_answers() {
            inCall(90, 20000)
            var s = screen()
            settle(s)
            verify(/^00:2/.test(s.statusLabel.text), s.statusLabel.text)
            view.audio.take({ "callState": "dialing" })
            compare(s.statusLabel.text, "Calling...")
            view.audio.take({ "callState": "alerting" })
            compare(s.statusLabel.text, "Calling...")
            // answered: the timer counts from now, not from the dial
            view.audio.take({ "callState": "active" })
            verify(/^00:0[0-2]$/.test(s.statusLabel.text), s.statusLabel.text)
        }

        function test_27_without_call_states_the_timer_counts_from_the_dial() {
            inCall(91, 20000)
            view.audio.take({ "callState": "active" })
            verify(/^00:2/.test(screen().statusLabel.text), screen().statusLabel.text)
        }

        /* ---- calls-29: no work in ambient ---- */

        function test_28_nothing_ticks_with_the_display_off() {
            inCall(95, 5000)
            var s = screen()
            settle(s)
            wait(1100)
            var before = view.elapsed
            Lipstick.compositor.displayOff()
            compare(view.displayOff, true)
            compare(s.animate, false)
            compare(s.marqueePaused, true)
            wait(2300)
            // the 1 s timer is stopped: the text did not move
            compare(view.elapsed, before)
            // the screen is not removed (the face is drawn by the hub, not by this view)
            Lipstick.compositor.displayOn()
            tryVerify(function () { return view.elapsed !== before }, 2000)
        }

        function test_29_ended_in_ambient_leaves_at_once() {
            var n = inCall(96, 1000)
            Lipstick.compositor.displayOff()
            model.remove(n)
            compare(view.callEnded, false)
            compare(view.visible, false)
        }

        /* ---- the call state for the notification server ---- */

        function test_30_call_state_ringing_in_call_and_after() {
            var r = ring(100)
            compare(lipstickSettings.callState, 1)
            view.answer()
            compare(lipstickSettings.callState, 2)
            model.remove(r)
            compare(lipstickSettings.callState, 2)
            var o = card(101, "end", 0)
            model.add(o)
            compare(lipstickSettings.callState, 2)
            model.remove(o)
            compare(view.callEnded, true)
            view.endedMs = 50
            tryVerify(function () { return lipstickSettings.callState === 0 }, 3000)
        }
    }
}
